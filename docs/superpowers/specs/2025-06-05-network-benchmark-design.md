# TKE 网络方案压测脚本与报告设计

## 1. 概述

在 TKE Guide 中新增一篇 Cilium 附录下的压测报告（`networking/cilium/appendix/benchmark.md`），并配套一个一键压测脚本 `network-benchmark.sh`（`static/scripts/network-benchmark.sh`）。

脚本在 4 个预置集群上跑完全相同的测试，自动检测集群类型并加测组件特有指标。AI 读取脚本生成的 `benchmark-summary.json` 等结果文件，产出最终压测报告。

## 2. 测试集群

|  #  |   集群 ID    |               方案                |     节点     |
| :-: | :----------: | :-------------------------------: | :----------: |
|  1  | cls-pvkjl54v |       Cilium Native Routing       | SA5 4C8G × 3 |
|  2  | cls-cmkmm9pt | Cilium Overlay (BPF Host Routing) | SA5 4C8G × 3 |
|  3  | cls-pz914sxn |          kube-proxy IPVS          | SA5 4C8G × 3 |
|  4  | cls-cy85e2sx |        kube-proxy iptables        | SA5 4C8G × 3 |

所有集群均为 VPC-CNI 模式，TencentOS Server 4，kernel 6.6.117，同一 VPC。

## 3. 脚本架构

### 3.1 定位

- 一键全流程：部署 workload → 跑测试 → 收集结果 → 清理
- 独立自包含脚本，curl 即可运行
- 生成结构化结果供 AI 和人工查阅

### 3.2 自动检测逻辑

```
kubectl get ds -n kube-system cilium → 有且 Ready → Cilium 集群
  ├── cilium status 检查隧道模式 → overlay / native
  └── 只测 Cilium 特有指标（agent 资源、BPF map 等）

非 Cilium → 检查 kube-proxy
  └── 检查 kubeproxy configmap mode → iptables / ipvs
  └── 测 kube-proxy 特有指标（资源、规则数）
```

### 3.3 测试项与参数

所有通用测试时长 120s × 3 轮取平均，轮间间隔 15s。资源监控延后 60s 收尾。

#### 3.3.1 吞吐量（iperf3）

| 场景                      | 参数                    | 说明                      |
| ------------------------- | ----------------------- | ------------------------- |
| Node Level（hostNetwork） | -P 8, -t 120            | VPC 带宽上限基线          |
| Pod-to-Pod 单流           | -t 120                  | 单流吞吐                  |
| Pod-to-Pod 多流           | -P 8, -t 120            | 多流并发，核心对比项      |
| Via Service               | ClusterIP, -P 8, -t 120 | 经过 Service 转发后的吞吐 |

#### 3.3.2 HTTP RPS（fortio）

| 场景                    | 参数                           | 说明                       |
| ----------------------- | ------------------------------ | -------------------------- |
| Pod-to-Pod 长连接       | -c 64 -t 120, keep-alive       | 直连 Pod IP                |
| Via Service 长连接 64c  | -c 64 -t 120, keep-alive       | 经过 ClusterIP             |
| Via Service 长连接 256c | -c 256 -t 120, keep-alive      | 高并发长连接               |
| Via Service 短连接 64c  | -c 64 -t 120, -keepalive=false | **关键指标**，每次新建 TCP |

#### 3.3.3 延迟（netperf + fortio）

| 场景            | 参数                          | 说明                     |
| --------------- | ----------------------------- | ------------------------ |
| TCP_RR          | -t TCP_RR -l 120, -r 1,1      | 1B 请求-响应，测 P50/P99 |
| TCP_CRR         | -t TCP_CRR -l 120             | 每次新建连接的延迟       |
| HTTP @ 1000 QPS | fortio -qps 1000 -c 16 -t 120 | 应用负载下实际延迟       |

#### 3.3.4 Service 规模衰减

- 创建 1000 个 dummy Service + Endpoints（脚本内循环 kubectl apply）
- 等待 30s 同步
- 跑短连接 RPS（64c, no keep-alive, 120s × 3 轮）
- 与 RPS 测试阶段的短连接基线对比，计算衰减率
- 采集 iptables 规则数或 BPF map 条目数

#### 3.3.5 组件特有指标

**Cilium 集群：**

| 指标                | 方法                                               | 时机                         |
| ------------------- | -------------------------------------------------- | ---------------------------- |
| cilium agent CPU    | `kubectl top pod -n kube-system -l k8s-app=cilium` | 空载基线 + 各压力阶段每隔 5s |
| cilium agent 内存   | 同上                                               | 同上                         |
| BPF map 内存        | `kubectl exec ds/cilium -- bpftool map list -j`    | 测试后采集                   |
| LB/CT/Identity 条目 | `cilium bpf lb list` / `cilium bpf ct list global` | 测试后采集                   |

**kube-proxy 集群：**

| 指标            | 方法                                                      | 时机                         |
| --------------- | --------------------------------------------------------- | ---------------------------- |
| kube-proxy CPU  | `kubectl top pod -n kube-system -l k8s-app=kube-proxy`    | 空载基线 + 各压力阶段每隔 5s |
| kube-proxy 内存 | 同上                                                      | 同上                         |
| iptables 规则数 | `kubectl exec <kube-proxy-pod> -- iptables-save \| wc -l` | Service 测试后               |
| IPVS 规则数     | `kubectl exec <kube-proxy-pod> -- ipvsadm -ln \| wc -l`   | Service 测试后               |

### 3.4 结果输出

脚本在当前目录创建 `benchmark-results-<cluster>/`，结构：

```
benchmark-results-<cluster>/
├── benchmark-summary.json      # 结构化数据供 AI 生成报告
├── context.yaml                # 集群上下文
├── throughput/                 # iperf3 JSON 原始输出
├── rps/                        # fortio JSON 原始输出
├── latency/                    # netperf 文本 + fortio JSON
├── service-scale/              # 1000 Service 测试结果
└── resources/                  # 资源开销 CSV
```

## 4. 报告生成

AI 读取各集群的 `benchmark-summary.json`，合并生成 Markdown 报告，包含：

- 测试方法与脚本使用说明
- 测试环境（4 个集群的配置对比表）
- 核心指标对比表（吞吐 / RPS / 延迟 / 规模衰减）
- 组件开销对比（Cilium vs kube-proxy 资源占用）
- 关键结论与选型建议
- 各原始结果链接引用

## 5. 实施流程

1. 编写 `network-benchmark.sh`（基类测试函数 + 检测逻辑 + 结果聚合）
2. 在第一个集群（cls-pvkjl54v, cilium native）上调试至完全可用
3. 依次跑完其余 3 个集群
4. AI 读取所有结果文件，整理数据并生成压测报告
5. 提交脚本 + 报告到文档库

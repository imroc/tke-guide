# Cilium 网络性能 Benchmark

本文使用 [`network-benchmark.sh`](https://imroc.cc/tke/scripts/network-benchmark.sh) 一键脚本，在**完全相同的硬件、内核、VPC 环境**下对三种 TKE 网络方案做全方位性能对比：

- **Cluster A — VPC-CNI + kube-proxy iptables**：传统方案，作为性能基线
- **Cluster B — VPC-CNI + Cilium Native Routing**：Cilium 以 cni-chaining 接在 VPC-CNI 之上，Pod IP 仍是 VPC 合法 IP
- **Cluster C — VPC-CNI + Cilium Overlay (VXLAN)**：Cilium 独占 Pod CNI，Pod 走独立 overlay 网段

覆盖吞吐量、HTTP RPS、TCP 延迟、Service 规模化退化（0→5000→10000）、Hubble 开销、NetworkPolicy L3/L4 与 L7 开销、BPF 内存、组件资源消耗等维度。

:::tip[本文想回答的三个问题]

1. **iptables vs Cilium**：换成 Cilium 后性能是涨还是跌？代价在哪、收益在哪？
2. **Cilium Native vs Overlay**：两种 Cilium 部署形态性能差多少？怎么选？
3. **小规模 vs 大规模 Service**：Service 数量从 5000 涨到 10000，三种方案的退化曲线如何？

:::

:::note[与 cilium connectivity perf 的区别]

[Cilium 性能测试](./performance-test.md) 使用 `cilium connectivity perf`（基于 netperf）测 TCP_RR 延迟和 TCP_STREAM 吞吐。本文的 `network-benchmark.sh` 额外覆盖 HTTP 层 RPS、经 Service 路径、大规模 Service 退化、Hubble / NetworkPolicy 开销、BPF 内存等维度，并加入 iptables 基线对照。两篇互补，建议结合阅读。

:::

## 测试方法

### 一键运行

```bash
bash -c "$(curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/network-benchmark.sh)"
```

国内网络无法连接 GitHub 时改用站点镜像：

```bash
bash -c "$(curl -sfL https://imroc.cc/tke/scripts/network-benchmark.sh)"
```

:::note[前置条件]

- `KUBECONFIG` 指向目标集群（当前 context 可用）
- 本机需安装 `kubectl`、`python3`、`timeout`（macOS 需 `brew install coreutils`）
- 集群至少 2 个 worker 节点

:::

### 自定义参数

```bash
# 多轮测试（大规格实例无 QoS 顾虑时）
ROUNDS=3 IPERF_DURATION=120 FORTIO_DURATION=120 bash network-benchmark.sh --dir ./bench

# 自定义 Service 规模化测试档位
SVC_SCALE_STEPS="1000,5000,10000" SVC_CREATE_PARALLEL=8 bash network-benchmark.sh
```

| 环境变量              | 默认值     | 说明                                     |
| --------------------- | ---------- | ---------------------------------------- |
| `IPERF_DURATION`      | 30         | iperf3 每轮测试时长（秒）                |
| `FORTIO_DURATION`     | 60         | fortio / netperf 每轮测试时长（秒）      |
| `ROUNDS`              | 1          | 每个场景重复轮次                         |
| `ROUND_SLEEP`         | 30         | 轮间等待（秒），用于 burst credit 恢复   |
| `SVC_SCALE_STEPS`     | 5000,10000 | Service 规模化测试档位（逗号分隔，递增） |
| `SVC_ENDPOINTS`       | 10         | 每个 dummy Service 的 endpoint 数        |
| `SVC_CREATE_PARALLEL` | 4          | 并发创建 Service 的 worker 数            |

:::warning[大规模测试需调大 Cilium LB map 上限]

Cilium 的 Service 负载均衡 BPF map 默认上限是 `bpf-lb-map-max=65536`。每个 Service 约占用 `1 + endpoint 数` 个 LB 条目，因此 **10000 Service × 10 endpoint ≈ 11 万条目会超出默认上限导致 map 溢出**——表现为大规模下 RPS 异常暴跌（这是转发失败，不是 O(n) 退化，会污染测试结论）。

跑大规模测试前，先调大该上限并重启 cilium：

```bash
kubectl -n kube-system patch configmap cilium-config --type merge \
  -p '{"data":{"bpf-lb-map-max":"262144"}}'
kubectl -n kube-system rollout restart ds/cilium
```

脚本在 Service Scale 测试前会自动预检容量并在不足时打印 `LB MAP CAPACITY WARNING`。

:::

### 测试工具与指标

| 工具    | 测试内容                                            | 指标                  |
| ------- | --------------------------------------------------- | --------------------- |
| iperf3  | 跨节点 TCP 吞吐                                     | Gbps（1/8/16 并发流） |
| fortio  | HTTP RPS（长连接 / 短连接）                         | req/s                 |
| netperf | TCP_RR / TCP_CRR 延迟                               | p50 / p99 微秒        |
| fortio  | 多档 Service 规模（5000/10000）后 RPS 退化          | 退化百分比            |
| fortio  | Hubble on/off RPS 对比（仅 Cilium）                 | 开销百分比            |
| fortio  | NetworkPolicy L3/L4 + L7 前后 RPS 对比（仅 Cilium） | 开销百分比            |
| bpftool | BPF map 内存占用统计（仅 Cilium）                   | MB                    |

## 测试环境

| 项              | Cluster A (iptables)          | Cluster B (Cilium Native)                       | Cluster C (Cilium Overlay)           |
| --------------- | ----------------------------- | ----------------------------------------------- | ------------------------------------ |
| 网络方案        | VPC-CNI + kube-proxy iptables | VPC-CNI + Cilium cni-chaining（Native Routing） | Cilium VXLAN Overlay（独占 Pod CNI） |
| Kubernetes 版本 | v1.34.1-tke.5                 | v1.34.1-tke.5                                   | v1.34.1-tke.5                        |
| Cilium 版本     | N/A                           | v1.19.4                                         | v1.19.4                              |
| kube-proxy 替代 | 否（iptables 模式）           | 是（eBPF）                                      | 是（eBPF）                           |
| 节点 OS         | TencentOS Server 4            | TencentOS Server 4                              | TencentOS Server 4                   |
| 内核版本        | 6.6.117                       | 6.6.117                                         | 6.6.117                              |
| 节点规格        | SA5.LARGE8（4C 8G）           | SA5.LARGE8（4C 8G）                             | SA5.LARGE8（4C 8G）                  |
| 节点数量        | 3                             | 3                                               | 3                                    |

三个集群位于同一 VPC、相同规格硬件、相同内核版本，保证公平对比。所有 RPS / 延迟测试均为跨节点（不同 Worker）。

## 一图速览

| 维度                      | iptables   | Cilium Native | Cilium Overlay | 关键结论                          |
| ------------------------- | ---------- | ------------- | -------------- | --------------------------------- |
| Pod2Pod 吞吐（8 streams） | 10.43 Gbps | 10.43 Gbps    | 10.77 Gbps     | 三者均达突发上限，无差异          |
| RPS 长连接（c64）         | 90,164     | 74,684        | 76,384         | iptables 高 ~20%                  |
| RPS 短连接（c64）         | 22,313     | 10,258        | 10,537         | iptables 高 ~115%                 |
| TCP_RR p99                | 121 µs     | 135 µs        | 129 µs         | Cilium 高 ~10-15 µs               |
| HTTP p99 @1000 QPS        | 0.99 ms    | 0.99 ms       | 0.99 ms        | **真实负载下三者完全相同**        |
| 10000 svc 短连接退化      | **-37.3%** | **-9.0%**     | **-8.4%**      | **iptables O(n)，Cilium 近 O(1)** |
| L3/L4 NetworkPolicy 开销  | N/A        | -0.5%         | -0.1%          | 零开销                            |
| L7 NetworkPolicy 开销     | N/A        | -85.2%        | -86.3%         | Envoy 代理，需选择性启用          |
| Hubble L3/L4 开销         | N/A        | -0.4%         | -0.1%          | 零开销                            |
| BPF map 内存 / 节点       | N/A        | 92.8 MB       | 92.7 MB        | 预分配，不随 svc 增长             |
| 数据面组件内存 / 节点     | 31.5 MB    | 391 MB        | 321 MB         | Cilium 换来了能力                 |

下面分维度展开。

## 一、吞吐量（iperf3, 30s, 跨节点）

| 场景                      | iptables   | Cilium Native | Cilium Overlay |
| ------------------------- | ---------- | ------------- | -------------- |
| Node hostNet（8 streams） | 10.44 Gbps | 10.44 Gbps    | 10.82 Gbps     |
| Pod-to-Pod（single）      | 10.43 Gbps | 10.42 Gbps    | 10.76 Gbps     |
| Pod-to-Pod（8 streams）   | 10.43 Gbps | 10.43 Gbps    | 10.77 Gbps     |
| Pod-to-Pod（16 streams）  | 10.43 Gbps | 10.43 Gbps    | 10.77 Gbps     |
| Via Service（8 streams）  | 10.43 Gbps | 10.43 Gbps    | 10.60 Gbps     |

:::note[吞吐量三者等价]

三种方案均跑满 ~10.4-10.8 Gbps，逼近 SA5.LARGE8 实例的突发带宽上限——**吞吐量层面三者完全等价**。集群间的 ±4% 差异是 VPC 突发带宽波动和物理节点路径差异，不代表方案优劣。16 streams 与 8 streams 持平，说明 8 并发流已饱和网卡。

值得注意的是 Overlay 即使带 VXLAN 封装，大包吞吐反而略高——说明 50 字节封装头在大包（MTU 级别）场景下占比极小，对吞吐无实质影响。VXLAN 的代价主要体现在小包高频场景（见 RPS 章节）。

:::

## 二、RPS（fortio, 60s, max QPS, 跨节点）

这是本测试中差异最大的维度。

| 场景                   | iptables         | Cilium Native    | Cilium Overlay   |
| ---------------------- | ---------------- | ---------------- | ---------------- |
| Pod-to-Pod c64 长连接  | 90,097 req/s     | 74,454 req/s     | 76,341 req/s     |
| Via Svc c64 长连接     | 90,164 req/s     | 74,684 req/s     | 76,384 req/s     |
| Via Svc c256 长连接    | 91,649 req/s     | 76,534 req/s     | 77,768 req/s     |
| **Via Svc c64 短连接** | **22,313** req/s | **10,258** req/s | **10,537** req/s |

### 为什么 iptables 的 RPS 反而更高？

这是最反直觉的结论。Cilium 用 eBPF 替代 iptables，"应该更快"，但在小规模 Service 的极限 RPS 压测中 iptables 领先 ~20%（长连接）到 ~115%（短连接）。原因要分两种 Cilium 形态分别看：

**Cilium Native：cni-chaining + per-endpoint 路由**

VPC-CNI 是 Pod 网络的主 CNI（分配 VPC IP），Cilium 以 cni-chaining 方式接在其上提供策略与可观测能力。这种架构强制开启 per-endpoint 路由（`endpointRoutes=true`），Pod 流量走单独的 veth 路由、不经过 `cilium_host` 设备——既要走完整内核网络栈（netfilter + FIB lookup），又要叠加 eBPF 的 conntrack + Service 解析 + Policy 检查。每个包多了一层 eBPF 处理，却没省下内核栈那一层。

**Cilium Overlay：VXLAN encap/decap**

Overlay 模式下 Cilium 是唯一 Pod CNI，BPF Host Routing 可正常生效，跳过了部分内核栈。但每个跨节点包都要做 VXLAN encap（出口）+ decap（入口）：封包构造、UDP checksum、内层 metadata 维护构成主要开销。

**iptables 路径最短**

小规模 Service 下，iptables 模式每个包只走一次内核协议栈，kube-proxy 的 NAT 规则只是 PREROUTING/POSTROUTING 上的几条匹配，没有 eBPF 处理也没有封装。所以在小规模、极限压测下 iptables 取得绝对值领先。

:::tip[关键认知：这是局部最优，不是全局最优]

iptables 的小规模 RPS 优势只在"Service 数量少 + 极限压测"这个特定条件下成立。一旦 Service 数量增长，iptables 的 O(n) 退化会迅速吞掉这部分优势（见[第五节](#五service-规模化退化0--5000--10000)）。

而且——**这个差异对真实业务无感知**。所有三种方案的绝对 RPS（74K-90K）都远超典型微服务单 Pod 的负载需求（通常 < 10K）。在真实负载下（见下方延迟章节的 HTTP p99 @1000 QPS），三者表现完全一致。

:::

### Native vs Overlay：几乎持平

Native（74,684）和 Overlay（76,384）长连接 RPS 差异 < 3%，短连接（10,258 vs 10,537）差异 < 3%。两者数据面开销构成不同（一个是 cni-chaining 双层处理，一个是 VXLAN 封装），但量级恰好相当。

## 三、延迟（netperf TCP_RR / TCP_CRR + fortio HTTP, 跨节点）

| 指标               | iptables | Cilium Native | Cilium Overlay |
| ------------------ | -------- | ------------- | -------------- |
| TCP_RR p50         | 99 µs    | 106 µs        | 105 µs         |
| TCP_RR p99         | 121 µs   | 135 µs        | 129 µs         |
| TCP_CRR p99        | 467 µs   | 623 µs        | 608 µs         |
| HTTP p99 @1000 QPS | 0.99 ms  | 0.99 ms       | 0.99 ms        |

:::tip[延迟差异在真实负载下消失]

- **TCP_RR**（长连接请求-响应）：Cilium 比 iptables 多 ~10-15 µs，是 eBPF 数据面 conntrack lookup + policy check 的固有开销。亚毫秒级，应用层无感知。
- **TCP_CRR**（每次新建连接）：Cilium 比 iptables 多 ~140-155 µs，因新连接的 SYN 包要做 BPF conntrack 创建 + Service 解析 + 完整内核栈穿越。
- **HTTP p99 @1000 QPS**：在真实业务速率（1000 QPS）下，三者**完全相同**（0.99 ms）。微秒级差异被应用层处理时间彻底淹没。

**这是全文最重要的一张表**：极限压测暴露的 µs 级差异，只在 fortio/wrk 这种空响应、打满 CPU 的场景下才可见。一旦应用本身有任何处理逻辑（数据库查询、JSON 序列化、业务计算），网络层的微秒差异完全不可见。

:::

## 四、Cilium Native vs Overlay：怎么选

两者在所有 RPS、延迟、规模化退化指标上的差异都在 ±5% 噪声范围内。**选型应基于网络架构需求，而非性能**：

| 维度       | Cilium Native                              | Cilium Overlay                                  |
| ---------- | ------------------------------------------ | ----------------------------------------------- |
| Pod IP     | VPC 合法 IP，VPC 内直接可路由              | 独立 overlay 网段，与 VPC 解耦                  |
| 适用场景   | 直连 CLB、跨集群/跨 VPC 互通、传统监控直采 | IP 资源紧张、跨 VPC 复用 CIDR、Pod 数超弹性网卡 |
| 数据面 CPU | ~102 m                                     | ~89 m                                           |
| 跨节点延迟 | TCP_RR p99 135 µs                          | TCP_RR p99 129 µs                               |
| MTU        | 无额外开销                                 | VXLAN 占用 50 字节（建议开启巨型帧缓解）        |

实测两者性能基本一致，Native 数据面 CPU 反而略高（cni-chaining 双层处理），Overlay 略低（BPF Host Routing 生效）但需承担 VXLAN 封装的 MTU 开销。**核心判据是 Pod IP 是否需要在 VPC 内直接可路由。**

> 关于为什么 Native 模式下 BPF Host Routing 实际不命中、以及云厂商 Native IPAM 的共性，详见 [VPC-CNI Native Routing 模式详解](./native-routing.md)。

## 五、Service 规模化退化（0 → 5000 → 10000）

测试方法：创建 N 个 dummy ClusterIP Service（各含 endpoint），等待 60s 同步后，在相同负载下对比 RPS 退化。这是 Cilium 替换 kube-proxy 最核心的价值所在。

### 长连接：三者都几乎无退化

| Service 数 | iptables | Cilium Native | Cilium Overlay |
| ---------- | -------- | ------------- | -------------- |
| 基线（0）  | 90,164   | 74,684        | 76,384         |
| 5000       | -1.3%    | -0.2%         | -0.2%          |
| 10000      | -0.8%    | -0.6%         | -0.9%          |

长连接场景三者均无明显退化——conntrack 缓存了首包的转发决策，后续包直接命中，无需再遍历规则链或查 BPF map。**这就是为什么用了连接池或 HTTP keepalive 的生产业务，基本感受不到 Service 规模的影响。**

### 短连接：iptables 线性恶化，Cilium 近乎恒定

| Service 数      | iptables             | Cilium Native      | Cilium Overlay     |
| --------------- | -------------------- | ------------------ | ------------------ |
| 基线（0）       | 22,313 req/s         | 10,258 req/s       | 10,537 req/s       |
| 5000            | 17,336（-22.3%）     | 9,582（-6.6%）     | 9,915（-5.9%）     |
| 10000           | 13,994（**-37.3%**） | 9,331（**-9.0%**） | 9,653（**-8.4%**） |
| iptables 规则数 | 30136 → 60118        | -                  | -                  |

:::tip[O(1) vs O(n)：差距随规模放大]

**短连接才是真正的考验**：每个新 TCP 连接的 SYN 包都要重新完成 Service 选择，无法命中 conntrack 缓存。

- **iptables 是 O(n) 顺序遍历**：每个 SYN 包要顺序匹配 KUBE-SERVICES → KUBE-SVC-XXX → KUBE-SEP-XXX 规则链。5000 svc 时 30136 条规则、退化 22.3%；10000 svc 时 60118 条规则（翻倍）、退化 **37.3%**。退化随规则数近乎线性恶化。
- **Cilium 是 O(1) BPF hash map 查找**：无论多少 Service，单次查表耗时恒定。Native 从 -6.6%（5000）到 -9.0%（10000）、Overlay 从 -5.9% 到 -8.4%，均为亚线性增长。

**残余退化的来源不是查表本身**，而是 5000→10000 svc 同步过程中 cilium-agent 控制面的 BPF map 写入压力 + conntrack 表条目膨胀（短连接频繁创建/淘汰）的 datapath 副作用，与 Service 数量并非线性相关。

**注意绝对值**：本测试中即使到 10000 svc，iptables 短连接绝对 RPS（13,994）仍高于 Cilium（~9,500）——只是领先优势从基线的 2.1 倍缩小到 1.45 倍。**iptables 尚未被反超，但趋势已经非常清晰**：iptables 退化随规则数线性增长（每 5000 svc 退化加深约 15 个百分点），而 Cilium 稳定在 -10% 以内。按此斜率线性外推，约 15000-20000 svc 时两者交叉，之后 Cilium 反超。

:::

:::warning[关于 dummy Service 的简化]

本测试的每个 dummy Service 只挂 **1 个 Endpoint**。真实业务的 Service 往往有多个后端 Pod（多 Endpoint），而 iptables 模式下每个 Endpoint 会额外生成一条 KUBE-SEP 规则——**Endpoint 越多，iptables 规则链越长、O(n) 退化越严重**，交叉点会比本测试外推的 15000-20000 svc 更早到来。Cilium 的 BPF map 查找不受 Endpoint 数量影响，仍是 O(1)。

因此本测试对 iptables 大规模退化的估计是**偏保守的**：真实多 Endpoint 场景下，iptables 的劣势会更早、更明显地暴露。

:::

### 小规模 vs 大规模：一句话总结

- **小规模（千以下）**：iptables 绝对值领先，因为路径最短、没有 eBPF/封装开销。
- **大规模（数千~万）**：iptables 仍领先，但优势随规则数快速收窄（短连接领先优势从 2.1 倍降到 1.45 倍）。Cilium 的 O(1) 不随规模退化，iptables 的 O(n) 线性恶化，按斜率外推约 1.5-2 万 svc 后 Cilium 反超（真实多 Endpoint 场景会更早）。
- **长连接全程无感**：无论哪种方案、无论规模多大，长连接业务都不受影响。

## 六、Hubble 可观测性开销（仅 Cilium）

| 指标       | Cilium Native | Cilium Overlay |
| ---------- | ------------- | -------------- |
| Hubble ON  | 74,096 req/s  | 76,006 req/s   |
| Hubble OFF | 74,392 req/s  | 76,067 req/s   |
| **开销**   | **-0.4%**     | **-0.1%**      |

:::note

Hubble L3/L4 可观测性开销在 ±0.5% 噪声范围内，**实质为零**。Hubble 在 datapath 上仅做事件采样和 ring buffer 写入，不参与转发决策。可放心在生产环境全量启用 Hubble L3/L4 流量观测。

:::

## 七、NetworkPolicy 开销（仅 Cilium）

### L3/L4 策略：零开销

| 指标             | Cilium Native | Cilium Overlay |
| ---------------- | ------------- | -------------- |
| 无策略           | 74,576 req/s  | 76,132 req/s   |
| L3/L4 CNP 生效后 | 74,202 req/s  | 76,064 req/s   |
| **开销**         | **-0.5%**     | **-0.1%**      |

L3/L4 CiliumNetworkPolicy 的执行开销**为零**。Cilium 的 L3/L4 策略在 eBPF 程序中通过 identity lookup + bitmap 匹配实现，不引入额外的内存拷贝或上下文切换。**可放心对所有工作负载批量应用 L3/L4 NetworkPolicy。**

### L7 策略（HTTP）：开销巨大，需谨慎

| 指标          | Cilium Native | Cilium Overlay |
| ------------- | ------------- | -------------- |
| 无策略        | 74,576 req/s  | 76,132 req/s   |
| L7 CNP 生效后 | 11,048 req/s  | 10,439 req/s   |
| **开销**      | **-85.2%**    | **-86.3%**     |

:::warning[L7 策略只对必要的 Pod 启用]

L7 CiliumNetworkPolicy（如 HTTP path/method 过滤）会将流量重定向到 **Envoy 代理**做应用层解析，引入进程间通信和 HTTP 解析的巨大代价——实测 RPS 下降 **85%+**。

这不是 Cilium 的缺陷，而是 L7 可见性的固有成本（任何 L7 策略/Service Mesh 方案都有类似代价）。正确用法是：

- **L3/L4 策略**：覆盖绝大多数生产安全需求（按 IP、端口、命名空间标签 allow/deny），零开销，可全量启用。
- **L7 策略**：仅对确实需要应用层管控的 Pod 选择性启用（如对外入口网关、敏感 API 审计），不要全量铺开。

:::

## 八、资源占用

### CPU / 内存

| 组件                   | CPU avg | Memory avg |
| ---------------------- | ------- | ---------- |
| kube-proxy (iptables)  | 1.0 m   | 31.5 MiB   |
| Cilium Agent (Native)  | 102.5 m | 237.7 MiB  |
| Cilium Agent (Overlay) | 88.8 m  | 209.9 MiB  |

kube-proxy 仅做 Service 同步，CPU/内存极低；但它把 iptables 规则膨胀和扫描的开销转嫁到了 datapath（见第五节）。Cilium Agent 不仅替换 kube-proxy，还同时承担 NetworkPolicy 编译、Hubble 流量采集、Identity 分配、BPF map 维护等职责，资源消耗自然更高——**但换来的是与 Service 规模解耦的 datapath（O(1)）和一整套企业级能力**。

### BPF Map 内存：预分配，不随规模增长

| 指标             | Cilium Native | Cilium Overlay |
| ---------------- | ------------- | -------------- |
| BPF map 总内存   | 92.8 MB       | 92.7 MB        |
| BPF map 数量     | 76            | 47             |
| Cilium Agent RSS | 391 MB        | 321 MB         |

Top BPF map 内存消耗（两集群基本一致）：

| Map 名称（截断）  | Max Entries | 内存    |
| ----------------- | ----------- | ------- |
| cilium_ct4_global | 131,072     | 17.0 MB |
| cilium_snat_v4    | 131,072     | 15.0 MB |
| cilium_nodeport   | 131,072     | 10.0 MB |
| cilium_policymap  | 65,536      | 9.5 MB  |
| cilium_ct_any4    | 65,536      | 8.5 MB  |

:::note[BPF 内存不会与业务争抢]

**关键机制：BPF map 使用预分配**——创建时按 `max_entries` 一次性分配最大内存，后续增删 Service/Endpoint 只是填充已分配空间，不会动态增长。这就是为什么本测试中即使 Service 从 0 涨到 10000，BPF map 总内存始终稳定在 ~92.7 MB。

在 SA5.LARGE8（4C 8G）节点上的内存预算：

```text
节点总内存:           8,192 MB
  系统预留:           ~1,024 MB
  kubelet / 运行时:   ~512 MB
  Cilium Agent RSS:   ~320-390 MB
  BPF Maps (memlock): ~93 MB
  ────────────────────────────
  Cilium 合计:        ~410-480 MB（约 5-6% of 8G）
  业务 Pod 可用:      ~6,000+ MB（73%+）
```

即使叠加 10000 Services + NetworkPolicy + 活跃连接，Cilium 的内存占用对业务也无实质影响。Native 的 RSS（391 MB）略高于 Overlay（321 MB），来自 cni-chaining 下更多的 endpoint 路由状态。

:::

## 总结

### iptables vs Cilium

| 角度       | 结论                                                                                                       |
| ---------- | ---------------------------------------------------------------------------------------------------------- |
| 小规模 RPS | iptables 领先（路径最短，无 eBPF/封装开销），但这是局部最优                                                |
| 大规模 RPS | iptables 仍领先但优势快速收窄（短连接领先 2.1→1.45 倍）；O(1) vs O(n) 趋势下约 1.5-2 万 svc 后 Cilium 反超 |
| 真实负载   | **完全无差异**（HTTP p99 @1000 QPS 三者均 0.99 ms）                                                        |
| 附加能力   | Cilium 提供 NetworkPolicy、Hubble、Identity 安全策略、L7 等 iptables 不具备的能力                          |
| 资源       | Cilium 多耗 ~300 MB 内存/节点，但 BPF 预分配不随规模膨胀，对 8G 节点无压力                                 |

**换 Cilium 的代价**：小规模极限压测下 ~20% RPS、~15 µs 延迟（真实负载无感）+ ~300 MB 内存。**换来的收益**：大规模 Service 下的 O(1) 性能、零开销的 L3/L4 NetworkPolicy 与 Hubble 可观测性、Identity-based 安全策略。对中大规模或有安全合规需求的集群，这笔交易完全划算。

### Cilium Native vs Overlay

性能基本一致（差异 < 5%）。**选型看网络架构而非性能**：需要 Pod IP 在 VPC 内直接可路由选 Native，需要 Pod CIDR 与 VPC 解耦选 Overlay。

### 小规模 vs 大规模 Service

iptables 的性能与 Service 数量强相关（O(n)），从 5000 到 10000 svc 短连接退化从 22% 恶化到 37%；Cilium 与 Service 数量解耦（O(1)），全程稳定在 10% 以内。**这是大规模集群选择 Cilium 替换 kube-proxy 的最核心理由。**

详细选型建议参见 [Cilium 性能测试 - 选型建议](./performance-test.md#选型建议)。

## 相关链接

- [Cilium 性能测试（cilium connectivity perf）](./performance-test.md)
- [VPC-CNI Native Routing 模式详解](./native-routing.md)
- [安装 Cilium](../install.md)

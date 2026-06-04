# Cilium 性能测试

本文介绍如何对在 TKE 集群上安装的 cilium 做网络性能测试，并给出各推荐安装方案的实测结果。

cilium 官方提供了 [`cilium connectivity perf`](https://docs.cilium.io/en/stable/operations/performance/benchmark/) 性能测试工具，基于 netperf 在集群中实际下发 Pod 跑 TCP_RR（请求-响应延迟）/ TCP_STREAM（吞吐）等测试，覆盖 **同节点 / 跨节点** × **Pod 网络 / Host 网络** 共四种网络组合。

## 测试方法

### 一键脚本

[一键安装脚本](../install.md#一键安装脚本) `cilium.sh` 提供了 `perf` 子命令，会用 TKE 内网可拉取的镜像跑 `cilium connectivity perf`：

```bash
bash -c "$(curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh)" -- perf
```

国内网络无法连接 GitHub 时改用站点镜像：

```bash
bash -c "$(curl -sfL https://imroc.cc/tke/scripts/cilium.sh)" -- perf
```

性能测试默认跑约 1 分钟（每个测试持续 10 秒），最后输出汇总表格。脚本会在跑测前自动清理上次测试残留的 `cilium-test-*` namespace（详见 [常见问题](#为什么-perf-跑前要清理-cilium-test--namespace)）。

### 手动测试

需先安装 [cilium CLI](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli)：

```bash
cilium connectivity perf \
  --performance-image quay.tencentcloudcr.com/cilium/network-perf:3.20-1772622563-6fd6a90
```

`cilium connectivity perf` 默认行为：

- `--duration 10s`：每个 RR/STREAM 测试持续 10 秒
- `--samples 1`：每个测试跑 1 次（可调大跑多次取平均）
- `--rr / --throughput / --throughput-multi`：默认开启 TCP_RR、TCP_STREAM、TCP_STREAM_MULTI 测试
- `--pod-net / --host-net / --other-node / --same-node`：默认全开（覆盖 Pod 网络 + Host 网络 + 同/跨节点 4 种组合）
- 可加 `--udp` 测 UDP，`--crr` 测 TCP_CRR（每次连接都重建），`--bandwidth` 测带宽限速能力

更多参数详见 `cilium connectivity perf --help`。

### 测试模式说明

| Test 类型          | 含义                                            | 测什么                                      |
| ------------------ | ----------------------------------------------- | ------------------------------------------- |
| `TCP_RR`           | TCP Request-Response，反复发小请求等响应        | **延迟**（µs，越低越好）；OP/s 是每秒事务数 |
| `TCP_STREAM`       | TCP 单流持续发送                                | **单流吞吐**（Mb/s，越高越好）              |
| `TCP_STREAM_MULTI` | TCP 多流并发发送（默认 4 流，`--streams` 调整） | **多流并发吞吐**（Mb/s）                    |

### 网络组合说明

| Scenario       | Node       | 含义                                                 | 数据路径                                                                             |
| -------------- | ---------- | ---------------------------------------------------- | ------------------------------------------------------------------------------------ |
| `pod-to-pod`   | same-node  | client Pod → 同节点 server Pod                       | client veth → cilium ebpf → server veth                                              |
| `pod-to-pod`   | other-node | client Pod → 跨节点 server Pod                       | client veth → cilium ebpf → 网卡出 → underlay → 对端网卡 → cilium ebpf → server veth |
| `host-to-host` | same-node  | client（hostNetwork） → 同节点 server（hostNetwork） | host stack → host stack（不经过 cilium veth 路径）                                   |
| `host-to-host` | other-node | client（hostNetwork） → 跨节点 server（hostNetwork） | host stack → 网卡 → underlay → 对端网卡 → host stack                                 |

:::tip[结果解读注意事项]

性能数据**强依赖节点机型 / VPC 带宽 / 内核版本 / 同时运行的其它负载**。本文给出的是空载新建集群的实测值，仅作为不同 cilium 安装方案之间的横向对比参考，不能作为生产环境性能基线。

`S5.LARGE8` 单流跨节点带宽典型在 1.5-1.7 Gbps，已是该机型本身的网卡限速，不是 cilium 瓶颈。生产建议根据实际业务流量选择带宽更大的机型。

:::

## Native Routing (VPC-CNI) 测试结果

### 测试环境

| 项              | 值                                                                                           |
| --------------- | -------------------------------------------------------------------------------------------- |
| Kubernetes 版本 | v1.34.1（containerd 1.7.28）                                                                 |
| Cilium 版本     | v1.19.4                                                                                      |
| Cilium CLI 版本 | v0.19.4                                                                                      |
| 节点 OS         | TencentOS Server 4 (kernel 6.6.117-45.7.3.tl4.x86_64)                                        |
| 节点机型        | S5.LARGE8（4C8G）                                                                            |
| 节点数量        | 3 个节点                                                                                     |
| 节点公网        | 节点绑 EIP（性能测试不依赖公网）                                                             |
| 安装方式        | [一键安装脚本](../install.md#一键安装脚本) `cilium.sh install`，启用 Egress Gateway          |
| Host Routing    | Legacy（Native + endpointRoutes 必然走 legacy，详见 [host-routing 附录](./host-routing.md)） |

### 测试结果

```text
🔥 Network Performance Test Summary [cilium-test-1]:
📋 Scenario        | Node       | Test            | Min     | Mean      | P50    | P90    | P99    | OP/s
📋 pod-to-pod      | same-node  | TCP_RR          | 21µs    | 46.81µs   | 45µs   | 52µs   | 66µs   | 21267.51
📋 host-to-host    | same-node  | TCP_RR          | 17µs    | 41.19µs   | 40µs   | 47µs   | 59µs   | 24168.99
📋 pod-to-pod      | other-node | TCP_RR          | 107µs   | 136.56µs  | 135µs  | 149µs  | 177µs  | 7310.98
📋 host-to-host    | other-node | TCP_RR          | 101µs   | 129.64µs  | 129µs  | 140µs  | 164µs  | 7701.61

📋 Scenario        | Node       | Test               | Throughput Mb/s
📋 pod-to-pod      | same-node  | TCP_STREAM         | 26585.24
📋 pod-to-pod      | same-node  | TCP_STREAM_MULTI   | 37535.25
📋 host-to-host    | same-node  | TCP_STREAM         | 28790.54
📋 host-to-host    | same-node  | TCP_STREAM_MULTI   | 41499.79
📋 pod-to-pod      | other-node | TCP_STREAM         | 1601.10
📋 pod-to-pod      | other-node | TCP_STREAM_MULTI   | 1627.11
📋 host-to-host    | other-node | TCP_STREAM         | 1590.50
📋 host-to-host    | other-node | TCP_STREAM_MULTI   | 1604.75

✅ All 1 tests (12 actions) successful, 0 tests skipped, 0 scenarios skipped.
```

耗时约 2 分 44 秒。

#### TCP_RR（请求-响应延迟）

| #   | Scenario       | Node       | Min | Mean   | P50 | P90 | P99 | Transactions/s |
| --- | -------------- | ---------- | --- | ------ | --- | --- | --- | -------------- |
| 1   | `pod-to-pod`   | same-node  | 21  | 46.81  | 45  | 52  | 66  | **21268**      |
| 2   | `host-to-host` | same-node  | 17  | 41.19  | 40  | 47  | 59  | **24169**      |
| 3   | `pod-to-pod`   | other-node | 107 | 136.56 | 135 | 149 | 177 | **7311**       |
| 4   | `host-to-host` | other-node | 101 | 129.64 | 129 | 140 | 164 | **7702**       |

#### TCP_STREAM / TCP_STREAM_MULTI（吞吐，单位 Mb/s）

| #   | Scenario       | Node       | TCP_STREAM (单流) | TCP_STREAM_MULTI (4 流并发) |
| --- | -------------- | ---------- | ----------------- | --------------------------- |
| 5   | `pod-to-pod`   | same-node  | **26585.24**      | **37535.25**                |
| 6   | `host-to-host` | same-node  | **28790.54**      | **41499.79**                |
| 7   | `pod-to-pod`   | other-node | **1601.10**       | **1627.11**                 |
| 8   | `host-to-host` | other-node | **1590.50**       | **1604.75**                 |

#### 解读

- **同节点 vs 跨节点**：吞吐差 ~16 倍（同节点单流 ~26 Gbps，跨节点 ~1.6 Gbps），延迟差 ~3 倍（46µs vs 137µs）——跨节点流量经过物理网卡 + VPC underlay，是 S5.LARGE8 机型本身网卡带宽（约 1.5-1.7 Gbps）的限速结果，不是 cilium 开销
- **Pod 网络 vs Host 网络**：差距很小（同节点 26 vs 28 Gbps，~7%；跨节点几乎无差距）——Native Routing 模式下 Pod IP 就是 VPC IP，cilium ebpf 不做 SNAT/封装，Pod 流量直接走 host 同样的路径
- **单流 vs 多流（同节点）**：4 流并发能跑到 37-41 Gbps，是单流的 1.4-1.5 倍——内核 lo 设备 + cilium ebpf 在多流下能更好利用 CPU
- **跨节点单流 ≈ 多流**（1601 vs 1627）——单流已跑满网卡带宽，多流没有增益

## Overlay (VPC-CNI) 测试结果

### 测试环境

| 项              | 值                                                                                         |
| --------------- | ------------------------------------------------------------------------------------------ |
| Kubernetes 版本 | v1.34.1（containerd 1.7.28）                                                               |
| Cilium 版本     | v1.19.4                                                                                    |
| Cilium CLI 版本 | v0.19.4                                                                                    |
| 节点 OS         | TencentOS Server 4 (kernel 6.6.117-45.7.3.tl4.x86_64)                                      |
| 节点机型        | S5.LARGE8（4C8G）                                                                          |
| 节点数量        | 3 个节点                                                                                   |
| 节点公网        | 节点绑 EIP（性能测试不依赖公网）                                                           |
| 安装方式        | [一键安装脚本](../install.md#一键安装脚本) `cilium.sh install`                             |
| Host Routing    | BPF（一键脚本默认开启 `bpf.masquerade=true`，详见 [host-routing 附录](./host-routing.md)） |

### 测试结果

```text
🔥 Network Performance Test Summary [cilium-test-1]:
📋 Scenario        | Node       | Test            | Min     | Mean      | P50    | P90    | P99    | OP/s
📋 pod-to-pod      | same-node  | TCP_RR          | 15µs    | 39.47µs   | 38µs   | 45µs   | 62µs   | 25219.91
📋 host-to-host    | same-node  | TCP_RR          | 17µs    | 41.86µs   | 40µs   | 47µs   | 65µs   | 23786.68
📋 pod-to-pod      | other-node | TCP_RR          | 91µs    | 119.83µs  | 118µs  | 132µs  | 169µs  | 8331.06
📋 host-to-host    | other-node | TCP_RR          | 84µs    | 112.66µs  | 112µs  | 125µs  | 154µs  | 8861.62

📋 Scenario        | Node       | Test               | Throughput Mb/s
📋 pod-to-pod      | same-node  | TCP_STREAM         | 30466.54
📋 pod-to-pod      | same-node  | TCP_STREAM_MULTI   | 41079.43
📋 host-to-host    | same-node  | TCP_STREAM         | 27857.19
📋 host-to-host    | same-node  | TCP_STREAM_MULTI   | 39825.38
📋 pod-to-pod      | other-node | TCP_STREAM         | 1557.48
📋 pod-to-pod      | other-node | TCP_STREAM_MULTI   | 1559.26
📋 host-to-host    | other-node | TCP_STREAM         | 1587.03
📋 host-to-host    | other-node | TCP_STREAM_MULTI   | 1618.91

✅ All 1 tests (12 actions) successful, 0 tests skipped, 0 scenarios skipped.
```

耗时约 2 分 38 秒。

#### TCP_RR（请求-响应延迟）

| #   | Scenario       | Node       | Min | Mean   | P50 | P90 | P99 | Transactions/s |
| --- | -------------- | ---------- | --- | ------ | --- | --- | --- | -------------- |
| 1   | `pod-to-pod`   | same-node  | 15  | 39.47  | 38  | 45  | 62  | **25220**      |
| 2   | `host-to-host` | same-node  | 17  | 41.86  | 40  | 47  | 65  | **23787**      |
| 3   | `pod-to-pod`   | other-node | 91  | 119.83 | 118 | 132 | 169 | **8331**       |
| 4   | `host-to-host` | other-node | 84  | 112.66 | 112 | 125 | 154 | **8862**       |

#### TCP_STREAM / TCP_STREAM_MULTI（吞吐，单位 Mb/s）

| #   | Scenario       | Node       | TCP_STREAM (单流) | TCP_STREAM_MULTI (4 流并发) |
| --- | -------------- | ---------- | ----------------- | --------------------------- |
| 5   | `pod-to-pod`   | same-node  | **30466.54**      | **41079.43**                |
| 6   | `host-to-host` | same-node  | **27857.19**      | **39825.38**                |
| 7   | `pod-to-pod`   | other-node | **1557.48**       | **1559.26**                 |
| 8   | `host-to-host` | other-node | **1587.03**       | **1618.91**                 |

#### 解读

- **同节点 pod-to-pod 比 host-to-host 还略快**（39.47µs vs 41.86µs，30.4 Gbps vs 27.8 Gbps）——cilium BPF host routing 在 cilium_host 设备 ingress 完成 endpoint 查找 + redirect，比 host netns → host netns 的内核 routing 路径还要短
- **跨节点 pod-to-pod ~1.56 Gbps**：相比 Native（1601 Mbps）略低 ~3%，对应 vxlan 8 字节包头封装的开销；与机型本身的网卡带宽限速相比，可忽略
- **跨节点 RR 比 Native 快**（120µs vs 137µs）——BPF host routing 的延迟优势盖过了 vxlan 封装/解封装开销

## 性能差异对比分析

把上面两组数据放在一起对比，先给结论再拆解原因。

### 关键指标对照

| 指标                              | Native (Legacy host routing) | Overlay (BPF host routing) | 差异               |
| --------------------------------- | ---------------------------- | -------------------------- | ------------------ |
| **同节点 pod-to-pod TCP_RR Mean** | 46.81µs                      | 39.47µs                    | Overlay **快 16%** |
| **同节点 pod-to-pod TCP_RR P99**  | 66µs                         | 62µs                       | Overlay 快 6%      |
| **同节点 pod-to-pod 单流吞吐**    | 26585 Mbps                   | 30467 Mbps                 | Overlay **高 15%** |
| **同节点 pod-to-pod 多流吞吐**    | 37535 Mbps                   | 41079 Mbps                 | Overlay **高 9%**  |
| **跨节点 pod-to-pod TCP_RR Mean** | 136.56µs                     | 119.83µs                   | Overlay **快 12%** |
| **跨节点 pod-to-pod TCP_RR P99**  | 177µs                        | 169µs                      | Overlay 快 5%      |
| **跨节点 pod-to-pod 单流吞吐**    | 1601 Mbps                    | 1557 Mbps                  | Overlay 略低 ~3%   |
| **跨节点 host-to-host 单流吞吐**  | 1590 Mbps                    | 1587 Mbps                  | 几乎一致           |

### 一句话结论

**Overlay 多了 vxlan 封装，但因为走 BPF host routing，整体延迟和吞吐反而比 Native 更好。** 唯一例外是跨节点单流吞吐 Overlay 略低 ~3%（vxlan 包头开销），但被网卡限速掩盖，实际可忽略。

### 为什么 Overlay 反而更快？因果链 A→B→C

这一节是理解上面数据的关键。**关键变量不是"是否封装 vxlan"，而是"数据包是否经过 cilium_host 设备"**——这决定了走的是 BPF host routing 还是 Legacy host routing。

A. **Native 必须开 `endpointRoutes.enabled=true`**：cilium chained CNI 模式下，每个 Pod 在节点内核路由表里有独立的一条路由（`ip route` 直接指向 lxc 设备），数据包**不经过** `cilium_host` 设备。

B. **`bpf/bpf_host.c` 的 `ENABLE_HOST_ROUTING` 分支只在 `cilium_host` 设备的 tc-bpf 程序里执行**——包不经过 `cilium_host`，BPF host routing 这段代码就**不会被命中**，cilium 自动 fallback 到 **Legacy host routing**。

C. Legacy host routing 每个包**额外**经过：

- 5 个 netfilter 钩子（PREROUTING / FORWARD / INPUT / OUTPUT / POSTROUTING）
- conntrack 表 lookup 与 update（即使没规则也会走 connection tracking 状态机）
- 内核 FIB（路由表）lookup

对小包 RR 延迟和高 PPS 场景的开销很明显——这就是 Native 同节点 RR Mean 比 Overlay 慢 16%、单流吞吐低 15% 的根本原因。

完整机制（含两个独立条件 + 各部署模式实际命中哪条）见 [Cilium Host Routing：legacy vs BPF](./host-routing.md)。

### 按场景拆解

#### 同节点（client Pod 与 server Pod 在同一节点）

数据路径：`client veth → cilium ebpf → server veth`，**不出网卡**。

- **TCP_RR**：Overlay 39.47µs vs Native 46.81µs，**快 16%**——BPF host routing 在 `cilium_host` ingress 直接 redirect 到 server lxc，省掉了 Native 的 netfilter/conntrack/FIB 全套
- **TCP_STREAM 单流**：Overlay 30.5 Gbps vs Native 26.6 Gbps，**高 15%**——同一台机内 lo 设备的吞吐取决于内核栈处理速度，Legacy 多走的几跳累积起来明显
- **TCP_STREAM_MULTI 4 流**：差距收窄到 9%（41 vs 37.5 Gbps）——多流并发能更好利用 CPU，掩盖部分 Legacy 路径开销
- **`pod-to-pod` 同节点 RR ≈ `host-to-host` 同节点 RR**：Overlay 下 39.47µs vs 41.86µs，Pod 路径甚至**比 host netns 直连还快**——cilium BPF 在 cilium_host 设备直接 redirect 比内核 host stack 路由还短

#### 跨节点（client Pod 与 server Pod 在不同节点）

数据路径：`client veth → cilium ebpf → 网卡 → underlay → 对端网卡 → cilium ebpf → server veth`，**经过物理网卡**。

- **TCP_RR**：Overlay 119.83µs vs Native 136.56µs，**快 12%**——延迟差比同节点小，因为大部分时间花在网卡 + underlay 传输（约 80-100µs），cilium 处理只占少数
- **TCP_STREAM 单流**：Overlay 1557 Mbps vs Native 1601 Mbps，**Overlay 略低 ~3%**——这是 vxlan 包头封装的代价（每个 1500B MTU 包额外 50B vxlan 头），对吞吐影响 ~3%
- **跨节点带宽统一被网卡限速到 1.5-1.7 Gbps**：S5.LARGE8 单流网卡带宽就是这个量级，cilium 不是瓶颈
- **Pod 网络 vs Host 网络**：跨节点几乎一致——跨节点流量 cilium ebpf 处理的部分占比小，封装与否对吞吐的影响远小于网卡本身的限速

### 选型建议

| 场景                                                                         | 推荐                        | 原因                                                                                          |
| ---------------------------------------------------------------------------- | --------------------------- | --------------------------------------------------------------------------------------------- |
| **追求极致 RTT、高 PPS**                                                     | Overlay (VPC-CNI) ⭐        | BPF host routing 的延迟优势在小包场景明显（同节点 RR ~16%，跨节点 RR ~12%）                   |
| **追求 Pod IP 与 VPC IP 一致**（VPC 路由 / CLB / 安全组 / CCN 原生识别 Pod） | Native Routing (VPC-CNI) ⭐ | 性能损失主要是小包 RR 延迟 12-16%，生产业务通常可接受；Pod IP 直通 VPC 才是 Native 的核心价值 |
| **跨节点大流量**                                                             | 两者无差别                  | 都被节点网卡带宽限速，3% vxlan 开销可忽略                                                     |
| **东西向 NetworkPolicy / Hubble / KPR / Egress Gateway**                     | 两者无差别                  | 这些是 cilium 的应用层能力，与 host routing 路径无关                                          |

具体延伸阅读：

- 想深入理解 host routing 与命中条件，看 [Cilium Host Routing：legacy vs BPF](./host-routing.md)
- 想知道 Native 是否值得为 BPF host routing 切到 Overlay，看 host-routing 附录里的"是否需要切换"小节

## 常见问题

### 为什么 perf 跑前要清理 cilium-test-\* namespace？

`cilium connectivity perf` 启动时第一步是 `kubectl delete ns cilium-test-1`。但 TKE 集群启用了 gatekeeper 策略 `baseline.gatekeeper.sh / block-namespace-deletion-rule`，**禁止 namespace 内还有 Pod 时删除 namespace**：

```text
admission webhook "baseline.gatekeeper.sh" denied the request:
[block-namespace-deletion-rule] The Namespace cilium-test-1 is not allowed
to be deleted. Reason: It is not allowed to delete a namespace when it
includes any pod resource.
```

如果上次跑 `cilium connectivity test` 有失败的用例（例如 Native 下 LRP 边缘场景必失败），cilium-cli 默认**保留**测试资源（namespace + Deployment + Pod）方便排障——这些 Pod 直接卡死后续 perf 的 namespace 删除步骤，表现为：

```text
🔥 [cls-cluster] Deleting connectivity check deployments...
⌛ [cls-cluster] Waiting for namespace cilium-test-1 to disappear
（永远卡住）
```

`cilium.sh perf` 会在主流程开始前自动清理：先删 Deployment / DaemonSet / StatefulSet / ReplicaSet / Job / CronJob 等持有 Pod 的资源 → 等 Pod 真正消失（必要时 `--grace-period=0 --force`）→ 再删 namespace。这样能绕过 gatekeeper 的限制，避免脚本卡住。

如果是手工跑 `cilium connectivity perf` 卡住，可以手工执行下列命令清理后再跑：

```bash
for ns in cilium-test-1 cilium-test-ccnp1 cilium-test-ccnp2; do
  kubectl -n $ns delete deployment,daemonset,statefulset,replicaset,job,cronjob --all --wait=false --ignore-not-found
done
sleep 30  # 等 Pod 真正消失
for ns in cilium-test-1 cilium-test-ccnp1 cilium-test-ccnp2; do
  kubectl delete ns $ns --ignore-not-found
done
```

## 相关链接

- [安装 Cilium](../install.md)
- [Cilium 功能测试](./connectivity-test.md)
- [Cilium Host Routing：legacy vs BPF](./host-routing.md)
- [Cilium Performance Documentation](https://docs.cilium.io/en/stable/operations/performance/)

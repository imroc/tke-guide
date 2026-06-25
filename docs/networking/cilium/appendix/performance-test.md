# Cilium 性能测试

本文介绍如何对在 TKE 集群上安装的 cilium 做网络性能测试，并给出各推荐安装方案的实测结果。

cilium 官方提供了 [`cilium connectivity perf`](https://docs.cilium.io/en/stable/operations/performance/benchmark/) 性能测试工具，基于 netperf 在集群中实际下发 Pod 跑 TCP_RR（请求-响应延迟）/ TCP_STREAM（吞吐）等测试，覆盖 **同节点 / 跨节点** × **Pod 网络 / Host 网络** 共四种网络组合。

## 测试方法

### 一键脚本

[一键安装脚本](../install.md#一键安装脚本) `cilium.sh` 提供了 `perf` 子命令，封装 `cilium connectivity perf`：

```bash
bash -c "$(curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh)" -- perf
```

国内网络无法连接 GitHub 时改用站点镜像：

```bash
bash -c "$(curl -sfL https://imroc.cc/tke/scripts/cilium.sh)" -- perf
```

:::tip[关于并发流数]

SA5 等支持突发带宽的机型，默认 4 流可能无法触发突发，建议调为 8 流：

```bash
# 直接使用 cilium CLI
cilium connectivity perf --streams 8

# 或通过一键脚本
bash -c "$(curl -sfL ...)" -- perf --streams 8
```

8 流在 SA5 各规格上经实测均可稳定填满突发带宽，能更准确地反映吞吐上限。

:::

脚本相比直接跑 `cilium connectivity perf` 多做这几件事：

- **替换镜像**：netperf 镜像替换成 TKE 内网可拉取的 mirror 地址（`quay.tencentcloudcr.com/cilium/network-perf`），节点无需公网即可拉镜像
- **自动清理上次残留**：跑前清理上次测试遗留的 `cilium-test-*` namespace。`cilium connectivity perf` 启动时会 `kubectl delete ns cilium-test-1`，但 TKE gatekeeper 禁止 ns 内有 Pod 时删 ns，所以不预清理脚本会卡住（详见 [常见问题](#为什么-perf-跑前要清理-cilium-test--namespace)）
- **耗时统计**：测试结束打印总耗时

### 手动测试

需先安装 [cilium CLI](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli)：

```bash
cilium connectivity perf \
  --streams 8 \
  --performance-image quay.tencentcloudcr.com/cilium/network-perf:3.20-1772622563-6fd6a90
```

`cilium connectivity perf` 常用参数：

- `--duration 10s`：每个 RR/STREAM 测试持续 10 秒
- `--samples 1`：每个测试跑 1 次（可调大跑多次取平均）
- `--streams`：TCP_STREAM_MULTI 并发流数（默认 4，推荐 8）
- `--rr / --throughput / --throughput-multi`：默认开启 TCP_RR、TCP_STREAM、TCP_STREAM_MULTI 测试
- `--pod-net / --host-net / --other-node / --same-node`：默认全开（覆盖 Pod 网络 + Host 网络 + 同/跨节点 4 种组合）
- 可加 `--udp` 测 UDP，`--crr` 测 TCP_CRR（每次连接都重建），`--bandwidth` 测带宽限速能力

更多参数详见 `cilium connectivity perf --help`。

### 测试模式说明

| Test 类型          | 含义                                     | 测什么                                      |
| ------------------ | ---------------------------------------- | ------------------------------------------- |
| `TCP_RR`           | TCP Request-Response，反复发小请求等响应 | **延迟**（µs，越低越好）；OP/s 是每秒事务数 |
| `TCP_STREAM`       | TCP 单流持续发送                         | **单流吞吐**（Mb/s，越高越好）              |
| `TCP_STREAM_MULTI` | TCP 多流并发发送（`--streams` 调整流数） | **多流并发吞吐**（Mb/s）                    |

### 网络组合说明

| Scenario       | Node       | 含义                                                 | 数据路径                                                                             |
| -------------- | ---------- | ---------------------------------------------------- | ------------------------------------------------------------------------------------ |
| `pod-to-pod`   | same-node  | client Pod → 同节点 server Pod                       | client veth → cilium ebpf → server veth                                              |
| `pod-to-pod`   | other-node | client Pod → 跨节点 server Pod                       | client veth → cilium ebpf → 网卡出 → underlay → 对端网卡 → cilium ebpf → server veth |
| `host-to-host` | same-node  | client（hostNetwork） → 同节点 server（hostNetwork） | host stack → host stack（不经过 cilium veth 路径）                                   |
| `host-to-host` | other-node | client（hostNetwork） → 跨节点 server（hostNetwork） | host stack → 网卡 → underlay → 对端网卡 → host stack                                 |

:::tip[结果解读注意事项]

性能数据**强依赖节点机型 / VPC 带宽 / 内核版本 / 同时运行的其它负载**。本文给出的是空载新建集群的实测值，仅作为不同 cilium 安装方案之间的横向对比参考，不能作为生产环境性能基线。

本文所用 `cilium connectivity perf` 的 TCP_STREAM 测试（基于 netperf）因默认 buffer 较大、单连接 PPS 有限，较难触发腾讯云机型特有的突发带宽机制。多流场景下（`--streams 8`）跨节点吞吐基本能反映机型的基准带宽，但突发上限需用 iperf3 等工具才能准确测量。本文重点放在不同模式间的**相对差异**而非绝对值。

:::

## 测试环境

| 项              | 值                                                                 |
| --------------- | ------------------------------------------------------------------ |
| Kubernetes 版本 | v1.34.1（containerd 1.7.28）                                       |
| Cilium 版本     | v1.19.5                                                            |
| Cilium CLI 版本 | v0.19.4                                                            |
| 节点 OS         | TencentOS Server 4 (kernel 6.6.117-45.7.3.tl4.x86_64)              |
| 节点数量        | 3 个节点                                                           |
| 安装方式        | [一键安装脚本](../install.md#一键安装脚本) `cilium.sh install`     |
| perf 参数       | `--streams 8`（多流并发 8 条）                                     |
| Native 模式     | Legacy Host Routing（详见 [Native Routing 模式详解](./native-routing.md)） |
| Overlay 模式    | BPF Host Routing（详见 [Native Routing 模式详解](./native-routing.md)）    |

### 测试机型

| 规格                | vCPU | 内存 | 基准/突发带宽 | 队列数 | 选择理由                 |
| ------------------- | ---- | ---- | ------------- | ------ | ------------------------ |
| SA5.LARGE8（4C）    | 4    | 8G   | 1.5 / 10 Gbps | 4      | TKE 最常见的入门规格     |
| SA5.2XLARGE16（8C） | 8    | 16G  | 3 / 10 Gbps   | 8      | 常用升级规格，队列数翻倍 |

## 测试结果总览

### TCP_RR（请求-响应延迟，µs）

| 机型 | 模式    | Scenario   | Node       | Mean       | P50 | P90 | P99 | OP/s  |
| ---- | ------- | ---------- | ---------- | ---------- | --- | --- | --- | ----- |
| 4C   | Overlay | pod-to-pod | same-node  | **31.27**  | 31  | 34  | 44  | 31736 |
| 4C   | Native  | pod-to-pod | same-node  | **37.62**  | 37  | 41  | 53  | 26409 |
| 4C   | Overlay | pod-to-pod | other-node | **94.29**  | 94  | 100 | 116 | 10576 |
| 4C   | Native  | pod-to-pod | other-node | **112.83** | 113 | 119 | 138 | 8843  |
| 8C   | Overlay | pod-to-pod | same-node  | **31.94**  | 32  | 34  | 43  | 31092 |
| 8C   | Native  | pod-to-pod | same-node  | **38.03**  | 37  | 41  | 51  | 26135 |
| 8C   | Overlay | pod-to-pod | other-node | **106.21** | 105 | 114 | 127 | 9394  |
| 8C   | Native  | pod-to-pod | other-node | **94.13**  | 93  | 99  | 109 | 10598 |

### TCP_STREAM / TCP_STREAM_MULTI（吞吐，单位 Mb/s）

| 机型 | 模式    | Scenario   | Node       | 单流       | 多流（8 流并发） |
| ---- | ------- | ---------- | ---------- | ---------- | ---------------- |
| 4C   | Overlay | pod-to-pod | same-node  | **22,997** | **75,623**       |
| 4C   | Native  | pod-to-pod | same-node  | **29,329** | **64,128**       |
| 4C   | Overlay | pod-to-pod | other-node | **11,116** | **11,721**       |
| 4C   | Native  | pod-to-pod | other-node | **10,767** | **11,296**       |
| 8C   | Overlay | pod-to-pod | same-node  | **25,537** | **94,666**       |
| 8C   | Native  | pod-to-pod | same-node  | **21,410** | **88,831**       |
| 8C   | Overlay | pod-to-pod | other-node | **11,113** | **11,148**       |
| 8C   | Native  | pod-to-pod | other-node | **10,768** | **10,776**       |

> 同节点多流吞吐远超网卡带宽上限是因为数据在本地回环（loopback）设备上传输，不经过物理网卡，受 CPU 和内核栈性能影响。

## 对比分析

### 关键指标对照

| 指标                              | Overlay vs Native（4C） | Overlay vs Native（8C） | 趋势一致性 |
| --------------------------------- | ----------------------- | ----------------------- | ---------- |
| **同节点 pod-to-pod TCP_RR Mean** | Overlay **快 17%**      | Overlay **快 16%**      | ✅ 一致    |
| **同节点 pod-to-pod TCP_RR P99**  | Overlay 快 17%          | Overlay 快 16%          | ✅ 一致    |
| **同节点多流吞吐**                | Overlay 高 15%          | Overlay 高 7%           | ✅ 一致    |
| **跨节点多流吞吐**                | 几乎一致（~11.5 Gbps）  | 几乎一致（~11 Gbps）    | ✅ 一致    |
| **跨节点 pod-to-pod TCP_RR**      | 波动较大，不定          | 波动较大，不定          | ❌ 见下文  |

### 核心发现

#### 同节点延迟：Overlay 优势明确且稳定

Overlay 的 BPF host routing 在 `cilium_host` 设备入口完成 endpoint 查找 + redirect，跳过 native 模式下 Legacy host routing 必经的 netfilter / conntrack / FIB 全套开销。这个优势不受 vCPU 数和 VPC 拓扑影响，**多次实测偏差 < 1%，结论可靠**。

| 指标           | Overlay   | Native    | 差距               |
| -------------- | --------- | --------- | ------------------ |
| 同节点 RR Mean | 31.27µs   | 37.62µs   | Overlay **快 17%** |
| 同节点 RR P99  | 44µs      | 53µs      | Overlay 快 17%     |
| 同节点多流吞吐 | 75.6 Gbps | 64.1 Gbps | Overlay **高 15%** |

> 同节点多流吞吐（loopback）远超物理网卡上限，衡量的是 CPU/内核栈处理能力。Overlay 稳定高出 7-15%，但均属于"本地数据拷贝"，不能作为跨节点性能的参考。

#### 跨节点延迟：波动较大，无稳定结论

跨节点延迟受 **VPC 物理拓扑（两节点间的交换机跳数/物理距离）** 影响很大，同一组节点对在不同集群、不同 VPC 子网下的延迟基线不同。三次测试中每次趋势不一（有时 Overlay 快，有时 Native 快），说明差值在统计噪声范围内。

实际结论：**跨节点延迟不是选型的决定因素**——两者的差距（约 10-20µs）远小于应用层延迟波动，生产业务无感知。

#### 跨节点多流吞吐：无差异

两机型的多流吞吐都稳定在 ~**11 Gbps**，Native 与 Overlay 无实质差异。这个值接近 SA5 各规格实际可用的 VPC 带宽上限（SA5 突发带宽 10 Gbps），说明在此粒度下 cilium 数据面不是瓶颈。

:::note[关于吞吐稳定性]
跨节点多流吞吐在多次测试中偶有落在基准带宽附近（~1.7 Gbps）的情况，这是因为 SA5 的突发带宽基于积分机制，需满足特定条件才能触发。**Run-to-run 波动不是 Native 与 Overlay 的模式差异，而是 netperf 测试栈 PPS 不够高，有时无法消耗突发积分。** 建议跑 2-3 次取最能反映峰值的数据。
:::

#### 跨节点单流吞吐：不稳定，不做对比指标

单流基本落在基准带宽或其附近（1.5-3 Gbps），偶有触发突发的情况。不能据此得出任何模式差异结论。

## 选型建议

| 场景                                                              | 推荐                        | 原因                                                                                              |
| ----------------------------------------------------------------- | --------------------------- | ------------------------------------------------------------------------------------------------- |
| **同节点高频小包（RPC / KV 数据库 / MQ broker）**                 | Overlay (VPC-CNI) ⭐        | BPF host routing 在同节点小包场景有稳定 ~17% 的延迟优势，这是最可靠的差异结论                     |
| **追求 Pod IP 与 VPC IP 一致**（VPC 路由 / CLB / 安全组 / CCN）   | Native Routing (VPC-CNI) ⭐ | Pod IP 直通 VPC 是 Native 的核心价值；跨节点吞吐与 Overlay 无差异                                 |
| **跨节点大流量**（流数 ≥ 8）                                      | 两者无差别                  | 多流并发下两者都能跑满 VPC 带宽上限                                                               |
| **跨节点分布式服务**                                              | 两者无差别                  | 跨节点延迟受 VPC 拓扑影响 > 模式差异，差值在 10-20µs 内，应用层无感                               |
| **东西向 NetworkPolicy / Hubble / KPR / Egress Gateway**          | 两者无差别                  | 这些是 cilium 的应用层能力，与 host routing 路径无关                                              |
| **运维简单性**（不依赖 VPC-CNI chaining / 不受 TKE VPC-CNI 限制） | Overlay (VPC-CNI) ⭐        | Overlay 下 cilium 完全接管 Pod 网络，不依赖 VPC-CNI 的 CNI chaining，配置更简洁，排查问题也更直接 |

### 一句话总结

**唯一的可靠差异在同节点延迟：Overlay 比 Native 快约 17%。** 跨节点无稳定差异。如果你的业务主要是跨节点调用，性能不是选型依据——两者的跨节点多流吞吐完全一致，核心能力（NetworkPolicy / Hubble / KPR）完整可用，按运维偏好和环境条件选即可。

延伸阅读：[VPC-CNI Native Routing 模式详解](./native-routing.md) 深入解释两种 host routing 的原理与命中条件。

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

### 为什么 `--streams` 建议设为 8？

SA5 各规格的队列数 = vCPU 数（48 封顶）。实测表明：

| 机型 | 队列数 | `--streams=4` | `--streams=8`  | `--streams=16` |
| ---- | ------ | ------------- | -------------- | -------------- |
| 4C   | 4      | ~1.7 Gbps     | **~11.8 Gbps** | —              |
| 8C   | 8      | ~1.7 Gbps     | **~11.1 Gbps** | ~3.4 Gbps      |

8 流在两款机型上都能填满突发上限；16 流反而下降（单流带宽被摊薄，PPS 不足以消耗突发积分）。因此推荐 `--streams 8` 作为通用值。如果切换到不同机型规格，可根据规格的队列数适当调整——规则是：设为目标机型队列数的 2 倍（上限 64），通常能填满突发带宽。

## 相关链接

- [安装 Cilium](../install.md)
- [Cilium 功能测试](./connectivity-test.md)
- [VPC-CNI Native Routing 模式详解](./native-routing.md)
- [Cilium Performance Documentation](https://docs.cilium.io/en/stable/operations/performance/)

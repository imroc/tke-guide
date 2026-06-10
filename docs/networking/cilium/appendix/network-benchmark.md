# Cilium 网络性能 Benchmark

本文使用 [`network-benchmark.sh`](https://imroc.cc/tke/scripts/network-benchmark.sh) 一键脚本对 **iptables/kube-proxy**、**Cilium Native Routing** 和 **Cilium Overlay** 三种网络方案进行全方位性能对比，覆盖吞吐量、HTTP RPS、TCP 延迟、Service 规模、Hubble 开销、NetworkPolicy 开销等维度。

:::tip[与 cilium connectivity perf 的区别]

[Cilium 性能测试](./performance-test.md) 使用 `cilium connectivity perf`（基于 netperf）测试 TCP_RR 延迟和 TCP_STREAM 吞吐。本文的 `network-benchmark.sh` 脚本额外覆盖：

- **HTTP 层面**：fortio 全速压测 RPS（长连接 / 短连接）
- **Service 路径**：经 ClusterIP Service 的吞吐和 RPS
- **Service 规模影响**：1000 Services 后的 RPS 退化对比（O(1) vs O(n)）
- **Hubble / NetworkPolicy 开销**：量化可观测性和策略执行的性能影响
- **iptables 基线**：加入无 Cilium 的 kube-proxy iptables 模式作为参照

两篇文档互补，建议结合阅读。

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

# 指定输出目录和 namespace
bash network-benchmark.sh --dir ./my-results --ns my-bench
```

| 环境变量          | 默认值 | 说明                                   |
| ----------------- | ------ | -------------------------------------- |
| `IPERF_DURATION`  | 30     | iperf3 每轮测试时长（秒）              |
| `FORTIO_DURATION` | 60     | fortio / netperf 每轮测试时长（秒）    |
| `ROUNDS`          | 1      | 每个场景重复轮次                       |
| `ROUND_SLEEP`     | 30     | 轮间等待（秒），用于 burst credit 恢复 |

### 测试指标说明

| 工具    | 测试内容                          | 指标                |
| ------- | --------------------------------- | ------------------- |
| iperf3  | 跨节点 TCP 吞吐                   | Gbps（8/16 并发流） |
| fortio  | HTTP RPS（长连接 / 短连接）       | req/s               |
| netperf | TCP_RR / TCP_CRR 延迟             | p50 / p99 微秒      |
| fortio  | 1000 Services 后 RPS 退化         | 退化百分比          |
| fortio  | Hubble on/off RPS 对比            | 开销百分比          |
| fortio  | NetworkPolicy L3/L4 前后 RPS 对比 | 开销百分比          |

## 测试环境

| 项              | Cluster A (iptables)          | Cluster B (Cilium Native)                             | Cluster C (Cilium Overlay)                        |
| --------------- | ----------------------------- | ----------------------------------------------------- | ------------------------------------------------- |
| 网络方案        | VPC-CNI + kube-proxy iptables | VPC-CNI + Cilium Native Routing (Legacy Host Routing) | VPC-CNI + Cilium VXLAN Overlay (BPF Host Routing) |
| Kubernetes 版本 | v1.34.1                       | v1.34.1                                               | v1.34.1                                           |
| Cilium 版本     | N/A                           | v1.19.4                                               | v1.19.4                                           |
| 节点 OS         | TencentOS Server 4            | TencentOS Server 4                                    | TencentOS Server 4                                |
| 内核版本        | 6.6.117                       | 6.6.117                                               | 6.6.117                                           |
| 节点规格        | SA5.LARGE8（4C 8G）           | SA5.LARGE8（4C 8G）                                   | SA5.LARGE8（4C 8G）                               |
| 节点数量        | 3                             | 3                                                     | 3                                                 |

三个集群位于同一 VPC、相同规格硬件、相同内核版本，确保公平对比。

## 测试结果

### 吞吐量（iperf3, 30s, 跨节点）

| 场景                      | iptables   | Cilium Native | Cilium Overlay |
| ------------------------- | ---------- | ------------- | -------------- |
| Node hostNet（8 streams） | 10.88 Gbps | 10.44 Gbps    | 10.82 Gbps     |
| Pod-to-Pod（single）      | 10.90 Gbps | 10.43 Gbps    | 10.54 Gbps     |
| Pod-to-Pod（8 streams）   | 10.88 Gbps | 10.43 Gbps    | 10.77 Gbps     |
| Pod-to-Pod（16 streams）  | 10.86 Gbps | 10.43 Gbps    | 10.77 Gbps     |
| Via Service（8 streams）  | 10.88 Gbps | 10.43 Gbps    | 10.77 Gbps     |

:::note

三者均跑满 10+ Gbps 接近 VPC 突发带宽上限，吞吐量无差异。不同集群间的 ±4% 差异属于 VPC 带宽波动和不同物理节点间的网络路径差异，不代表方案差异。16 streams 与 8 streams 吞吐一致，说明 8 并发流已足够饱和网卡。

:::

### RPS（fortio, 60s, max QPS, 跨节点）

| 场景                     | iptables         | Cilium Native    | Cilium Overlay   | Cilium vs iptables |
| ------------------------ | ---------------- | ---------------- | ---------------- | ------------------ |
| Pod-to-Pod c64 keepalive | 90,257 req/s     | 78,354 req/s     | 77,377 req/s     | -13% ~ -14%        |
| Via Svc c64 keepalive    | 90,013 req/s     | 78,374 req/s     | 77,185 req/s     | -13% ~ -14%        |
| Via Svc c256 keepalive   | 90,461 req/s     | 79,145 req/s     | 78,084 req/s     | -13% ~ -14%        |
| Via Svc c64 短连接       | **22,845** req/s | **10,667** req/s | **10,695** req/s | **-53%**           |

:::tip[RPS 差异解读]

**iptables vs Cilium（-13%~14%）**：

Cilium 在 VPC-CNI Native 模式下需设置 `endpointRoutes=true`，导致数据包绕过 `cilium_host` 设备，无法启用 BPF Host Routing，回退为 Legacy Host Routing。数据包经 Cilium eBPF 处理（conntrack + Service 解析 + Policy 检查）后，仍需再次穿越完整的内核网络栈（netfilter + conntrack + FIB），产生约 10-15% 的双重处理开销。

**短连接 iptables 22K vs Cilium 10K（-53%）**：

短连接场景差异更大，原因同上——每个新 TCP 连接都需要走完整的 Cilium BPF 处理 + 内核栈双重路径。但此差异对实际业务**无感知**——典型微服务单 Pod QPS 通常 < 10K，且 Service Mesh / 连接池等机制会自动启用长连接复用。

**注意**：所有三种方案的绝对 RPS 值都远超典型生产负载需求。差异仅在极限压力下可见，在真实应用负载下（如 HTTP p99 @1000 QPS）三者延迟完全相同（0.99 ms）。

:::

### 延迟（netperf TCP_RR / TCP_CRR + fortio HTTP, 跨节点）

| 指标               | iptables | Cilium Native | Cilium Overlay | Cilium vs iptables |
| ------------------ | -------- | ------------- | -------------- | ------------------ |
| TCP_RR p50         | 89 µs    | 106 µs        | 104 µs         | +15~17 µs          |
| TCP_RR p99         | 113 µs   | 130 µs        | 128 µs         | +15~17 µs          |
| TCP_CRR p99        | 469 µs   | 611 µs        | 607 µs         | +138~142 µs        |
| HTTP p99 @1000 QPS | 0.99 ms  | 0.99 ms       | 0.99 ms        | **0 ms**           |

:::tip[延迟差异解读]

- **TCP_RR**（keep-alive 请求-响应）：Cilium 比 iptables 多 ~15-17 µs，这是 eBPF 数据面处理的固有开销（conntrack lookup + policy check）。在亚毫秒量级，对应用层完全无感知。
- **TCP_CRR**（每次新建连接）：Cilium 比 iptables 多 ~140 µs，因为新连接时 Cilium 需要额外做 SYN 包的 BPF conntrack 创建和 Service 解析。
- **HTTP p99 @1000 QPS**：在真实应用负载（1000 QPS）下，三者延迟**完全相同**——微秒级的差异被应用层处理时间完全淹没。
- **Cilium Native vs Overlay**：两者延迟几乎一致（差异 < 3 µs），跨节点场景下 VXLAN 封装的额外延迟可忽略。

:::

### Service Scale（1000 Services 后 RPS 退化）

| 指标                     | iptables     | Cilium Native | Cilium Overlay |
| ------------------------ | ------------ | ------------- | -------------- |
| iptables 规则 / BPF 条目 | 6,142 rules  | 3,043 entries | 3,049 entries  |
| keepalive RPS (1000 svc) | 89,626 req/s | 78,195 req/s  | 77,194 req/s   |
| keepalive 退化           | -0.4%        | -0.2%         | 0.0%           |
| 短连接 RPS (1000 svc)    | 21,486 req/s | 10,492 req/s  | 10,256 req/s   |
| **短连接退化**           | **-5.9%**    | **-1.6%**     | **-4.1%**      |

:::tip[O(1) vs O(n) Service 查找]

**keepalive 场景**：三者均无退化——conntrack 缓存了连接状态，后续包无需再遍历规则链 / BPF map。

**短连接场景**（核心差异）：每个新 TCP 连接的 SYN 包必须遍历完整的 KUBE-SERVICES 链或查询 BPF map：

- **iptables -5.9%**：1000 Services = 6,142 条规则顺序遍历（O(n)），引入可测量的性能退化
- **Cilium Native -1.6%**：BPF hash map O(1) 查找，1000 Services 后几乎无影响
- **Cilium Overlay -4.1%**：退化略高于 Native，可能因为 VXLAN 封装路径上的 CT 表条目更多

在更大规模（如 5,000+ Services）下，iptables 退化将按比例增长，而 Cilium 保持恒定。这是 Cilium 替换 kube-proxy 最核心的价值之一。

:::

### Hubble 可观测性开销（仅 Cilium 集群）

| 指标       | Cilium Native | Cilium Overlay |
| ---------- | ------------- | -------------- |
| Hubble ON  | 78,209 req/s  | 76,917 req/s   |
| Hubble OFF | 78,004 req/s  | 76,928 req/s   |
| **开销**   | **+0.3%**     | **-0.0%**      |

:::note

Hubble L3/L4 可观测性的性能开销**可以忽略**（< 0.5%）。Hubble 在 datapath 上仅做事件采样和 ring buffer 写入，不参与转发决策，对吞吐量几乎没有影响。可以放心在生产环境开启 Hubble L3/L4 模式。

:::

### NetworkPolicy L3/L4 开销（仅 Cilium 集群）

| 指标             | Cilium Native | Cilium Overlay |
| ---------------- | ------------- | -------------- |
| 无策略           | 78,401 req/s  | 76,944 req/s   |
| L3/L4 CNP 生效后 | 77,880 req/s  | 77,220 req/s   |
| **开销**         | **-0.7%**     | **+0.4%**      |

:::note

L3/L4 CiliumNetworkPolicy 的执行开销**为零**（差异在 ±1% 噪声范围内）。Cilium 的 L3/L4 策略在 eBPF 程序中通过 identity lookup + bitmap 匹配实现，不引入额外的内存拷贝或上下文切换，性能与无策略时完全一致。可以放心对所有工作负载批量应用 L3/L4 NetworkPolicy。

:::

### 资源占用

| 组件                   | CPU avg | Memory avg |
| ---------------------- | ------- | ---------- |
| kube-proxy (iptables)  | ~1m     | ~13 MiB    |
| Cilium Agent (Native)  | 106m    | 194 MiB    |
| Cilium Agent (Overlay) | 181m    | 192 MiB    |

:::note

Cilium 不仅替换 kube-proxy，还同时提供 NetworkPolicy、Hubble 可观测性、Identity-based 安全策略等能力。如果这些功能通过 sidecar 方式单独部署，总体开销会更大。内存差异（~180 MiB）来自这些额外能力的运行时状态。

:::

## 对比分析

### 汇总

| 维度                         | 结论                             | 量化差异                                       |
| ---------------------------- | -------------------------------- | ---------------------------------------------- |
| **吞吐量**                   | 三者无差异                       | 均达 10G+ 线速                                 |
| **RPS（长连接）**            | Cilium 比 iptables 低 ~13%       | 78K vs 90K（Legacy Host Routing 双重处理开销） |
| **RPS（短连接）**            | Cilium 比 iptables 低 ~53%       | 10K vs 22K（同上，但绝对值远超生产需求）       |
| **延迟 p99**                 | Cilium 比 iptables 高 ~17 µs     | 130 vs 113 µs（应用层无感知）                  |
| **HTTP p99 @1000 QPS**       | **三者完全相同**                 | 均为 0.99 ms                                   |
| **1000 Svc 短连接退化**      | **iptables O(n) vs Cilium O(1)** | iptables -5.9%，Cilium -1.6%~-4.1%             |
| **Hubble L3/L4 开销**        | 可忽略                           | < 0.5%                                         |
| **NetworkPolicy L3/L4 开销** | 零开销                           | ±0.7%（噪声范围）                              |
| **Cilium Native vs Overlay** | 无显著差异                       | RPS ±2%，延迟 ±3 µs                            |

### 核心结论

1. **真实负载下无性能差异**：在典型应用负载（HTTP p99 @1000 QPS）下，三种方案延迟完全相同（0.99 ms）。微秒级的差异只在极限压力测试中可见。

2. **Cilium 的代价**：相比 iptables，Cilium 在极限 RPS 场景下有 ~13% 开销（VPC-CNI Native 模式下 Legacy Host Routing 双重处理），但换来了 NetworkPolicy、Hubble 可观测性、eBPF 安全策略等企业级能力。

3. **Cilium 的优势**：
   - Service 查找 O(1)——1000 Services 短连接退化仅 1.6%，而 iptables 退化 5.9%，规模越大差距越大
   - Hubble L3/L4 可观测性零开销（< 0.5%），可放心全量开启
   - L3/L4 NetworkPolicy 零开销，可放心批量应用

4. **Native vs Overlay**：两者性能几乎一致。选型应基于网络架构需求（Pod IP 是否需要 VPC 可路由）而非性能。

详细选型建议参见 [Cilium 性能测试 - 选型建议](./performance-test.md#选型建议)。

## 相关链接

- [Cilium 性能测试（cilium connectivity perf）](./performance-test.md)
- [VPC-CNI Native Routing 模式详解](./native-routing.md)
- [安装 Cilium](../install.md)

# Cilium 网络性能 Benchmark

本文使用 [`network-benchmark.sh`](https://imroc.cc/tke/scripts/network-benchmark.sh) 一键脚本对 **iptables/kube-proxy**、**Cilium Native Routing** 和 **Cilium Overlay** 三种网络方案进行全方位性能对比，覆盖吞吐量、HTTP RPS、TCP 延迟、Service 规模化退化、Hubble 开销、NetworkPolicy 开销、组件资源消耗等维度。

:::tip[与 cilium connectivity perf 的区别]

[Cilium 性能测试](./performance-test.md) 使用 `cilium connectivity perf`（基于 netperf）测试 TCP_RR 延迟和 TCP_STREAM 吞吐。本文的 `network-benchmark.sh` 脚本额外覆盖：

- **HTTP 层面**：fortio 全速压测 RPS（长连接 / 短连接）
- **Service 路径**：经 ClusterIP Service 的吞吐和 RPS
- **大规模 Service 退化**：5000 Services 后的 RPS 退化对比（O(1) vs O(n)）
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

# 调整 Service 规模化测试的 Service 数量与并发创建度
SVC_SCALE_COUNT=10000 SVC_CREATE_PARALLEL=8 bash network-benchmark.sh
```

| 环境变量              | 默认值 | 说明                                   |
| --------------------- | ------ | -------------------------------------- |
| `IPERF_DURATION`      | 30     | iperf3 每轮测试时长（秒）              |
| `FORTIO_DURATION`     | 60     | fortio / netperf 每轮测试时长（秒）    |
| `ROUNDS`              | 1      | 每个场景重复轮次                       |
| `ROUND_SLEEP`         | 30     | 轮间等待（秒），用于 burst credit 恢复 |
| `SVC_SCALE_COUNT`     | 5000   | Service 规模化测试创建的 Service 数量  |
| `SVC_CREATE_PARALLEL` | 4      | 并发创建 Service 的 worker 数          |

### 测试指标说明

| 工具    | 测试内容                                       | 指标                  |
| ------- | ---------------------------------------------- | --------------------- |
| iperf3  | 跨节点 TCP 吞吐                                | Gbps（1/8/16 并发流） |
| fortio  | HTTP RPS（长连接 / 短连接）                    | req/s                 |
| netperf | TCP_RR / TCP_CRR 延迟                          | p50 / p99 微秒        |
| fortio  | 5000 Services 后 RPS 退化                      | 退化百分比            |
| fortio  | Hubble on/off RPS 对比（仅 Cilium）            | 开销百分比            |
| fortio  | NetworkPolicy L3/L4 前后 RPS 对比（仅 Cilium） | 开销百分比            |

## 测试环境

| 项              | Cluster A (iptables)          | Cluster B (Cilium Native)                       | Cluster C (Cilium Overlay)           |
| --------------- | ----------------------------- | ----------------------------------------------- | ------------------------------------ |
| 网络方案        | VPC-CNI + kube-proxy iptables | VPC-CNI + Cilium cni-chaining（Native Routing） | Cilium VXLAN Overlay（独占 Pod CNI） |
| Kubernetes 版本 | v1.34.1                       | v1.34.1                                         | v1.34.1                              |
| Cilium 版本     | N/A                           | v1.19.4                                         | v1.19.4                              |
| 节点 OS         | TencentOS Server 4            | TencentOS Server 4                              | TencentOS Server 4                   |
| 内核版本        | 6.6.117                       | 6.6.117                                         | 6.6.117                              |
| 节点规格        | SA5.LARGE8（4C 8G）           | SA5.LARGE8（4C 8G）                             | SA5.LARGE8（4C 8G）                  |
| 节点数量        | 3                             | 3                                               | 3                                    |

三个集群位于同一 VPC、相同规格硬件、相同内核版本，保证公平对比。

## 测试结果

### 吞吐量（iperf3, 30s, 跨节点）

| 场景                      | iptables   | Cilium Native | Cilium Overlay |
| ------------------------- | ---------- | ------------- | -------------- |
| Node hostNet（8 streams） | 10.44 Gbps | 10.44 Gbps    | 10.82 Gbps     |
| Pod-to-Pod（single）      | 10.43 Gbps | 10.43 Gbps    | 10.63 Gbps     |
| Pod-to-Pod（8 streams）   | 10.43 Gbps | 10.43 Gbps    | 10.77 Gbps     |
| Pod-to-Pod（16 streams）  | 10.43 Gbps | 10.43 Gbps    | 10.77 Gbps     |
| Via Service（8 streams）  | 10.38 Gbps | 10.43 Gbps    | 10.77 Gbps     |

:::note

三者均跑满 10 Gbps 接近 SA5.LARGE8 实例突发带宽上限，**吞吐量层面三种方案完全等价**。集群间 ±4% 差异属于 VPC 突发带宽波动和不同物理节点间网络路径差异，不代表方案差异。16 streams 与 8 streams 吞吐一致，说明 8 并发流已饱和网卡。Overlay 略高于 Native 是测试时段 VPC 带宽波动的偶然结果，与 VXLAN 封装无关。

:::

### RPS（fortio, 60s, max QPS, 跨节点）

| 场景                     | iptables         | Cilium Native    | Cilium Overlay   | Cilium vs iptables |
| ------------------------ | ---------------- | ---------------- | ---------------- | ------------------ |
| Pod-to-Pod c64 keepalive | 91,698 req/s     | 75,785 req/s     | 75,252 req/s     | -17% ~ -18%        |
| Via Svc c64 keepalive    | 91,896 req/s     | 75,272 req/s     | 75,191 req/s     | -18%               |
| Via Svc c256 keepalive   | 93,882 req/s     | 77,126 req/s     | 76,279 req/s     | -18%               |
| **Via Svc c64 短连接**   | **22,846** req/s | **10,194** req/s | **10,554** req/s | **-54% ~ -55%**    |

:::tip[RPS 差异解读：iptables 高于 Cilium 的根因]

**Cilium Native：cni-chaining + per-endpoint 路由（-18% / -55%）**

VPC-CNI 是 Pod 网络的主 CNI（分配 VPC IP），Cilium 以 cni-chaining 方式接在其上提供策略与可观测性能力。这种架构下 Pod 流量必须走 per-endpoint 路由（`endpointRoutes=true`），数据包绕过 `cilium_host` 设备，进入 Pod 前后都要穿越内核网络栈（netfilter + FIB lookup）；Cilium eBPF 也要做 conntrack + Service 解析 + Policy 检查。这就是测试中 Native 长连接 RPS 比 iptables 低 ~18%、短连接低 ~55% 的根本原因——每个包多走了一层 eBPF 处理但内核栈没省下来。

**Cilium Overlay：Cilium 是唯一 Pod CNI，VXLAN encap/decap 是主要代价**

Overlay 模式下 Cilium 自己分配 Pod IP（独立 PodCIDR），节点间通过 VXLAN 隧道互通——Cilium 是唯一 Pod CNI，不存在 cni-chaining。Pod 流量走 `cilium_host` 与 `cilium_vxlan` 设备，BPF Host Routing 可正常生效（满足 `kubeProxyReplacement=true` + `bpf.masquerade=true`）。但跨节点包必须做 VXLAN encap（出口）+ decap（入口），50 字节封包构造、UDP checksum、内层 metadata 维护构成主要开销。

测试结果上 Native 和 Overlay RPS 几乎持平（差异 &lt; 1%），但路径与代价完全不同：

| 集群                                  | Pod CNI 关系           | 主要开销来源               |
| ------------------------------------- | ---------------------- | -------------------------- |
| Cilium Native（VPC-CNI cni-chaining） | VPC-CNI 主 + Cilium 链 | per-endpoint 路由 + 内核栈 |
| Cilium Overlay                        | Cilium 独占            | VXLAN encap/decap          |

**为什么 iptables 反而更高？**

iptables 模式在小规模 Service 下数据路径最短：每个包只走一次内核协议栈，kube-proxy 的 NAT 规则只是 PREROUTING/POSTROUTING 链上的几条规则匹配，没有额外的 eBPF 处理或封装代价。Cilium 无论 Native 还是 Overlay，都引入了一层不可省的处理，因此在小规模、极限压测场景下 iptables 取得绝对值领先。

**关键认知**：iptables 的小规模 RPS 优势只是 ClusterIP Service 在简单架构下的局部最优。一旦 Service 数量增长，iptables 的 O(n) 退化（见后续 Service Scale 章节）会迅速吞噬这部分优势。本测试中 Cilium 与云厂商 VPC-CNI 集成，是 TKE 客户最常见的部署形态；只有当 Cilium 完全自管 Pod CIDR（如 Overlay 模式或纯 Cilium 自建集群的 Cluster Pool IPAM + auto-direct-node-routes/BGP）才能避免 cni-chaining，但相应也不再继承 VPC-CNI 的 VPC 直接可路由优势。

:::

### 延迟（netperf TCP_RR / TCP_CRR + fortio HTTP, 跨节点）

| 指标               | iptables | Cilium Native | Cilium Overlay |
| ------------------ | -------- | ------------- | -------------- |
| TCP_RR p50         | 92 µs    | 114 µs        | 105 µs         |
| TCP_RR p99         | 112 µs   | 136 µs        | 130 µs         |
| TCP_CRR p99        | 427 µs   | 641 µs        | 605 µs         |
| HTTP p99 @1000 QPS | 0.99 ms  | 0.99 ms       | 0.99 ms        |

:::tip[延迟差异解读]

- **TCP_RR**（keepalive 请求-响应）：Cilium 比 iptables 多 ~18-22 µs，是 eBPF 数据面 conntrack lookup + policy check 的固有开销。亚毫秒级，应用层无感知。
- **TCP_CRR**（每次新建连接）：Cilium 比 iptables 多 ~180-210 µs，新连接的 SYN 包需要做 BPF conntrack 创建 + Service 解析 + 完整内核栈穿越。
- **HTTP p99 @1000 QPS**：在真实业务负载下，三者**完全相同**（0.99 ms）—— 微秒级差异被应用层处理时间淹没。
- **Native vs Overlay**：跨节点延迟差异 < 10 µs。两者 datapath 不同（Native 是 cni-chaining 下的 per-endpoint 路由 + 内核栈，Overlay 是 BPF Host Routing + VXLAN encap/decap），但延迟代价数值上恰好相当。

**关键结论**：极限压测的延迟差异（µs 级）只在 wrk/fortio 这种空 HTTP 响应场景下可见。一旦应用本身有任何处理逻辑（数据库查询、JSON 序列化等），网络层的 µs 差异完全被掩盖。

:::

### Service 规模化（5000 Services 后 RPS 退化）

测试方法：先创建 5000 个 dummy ClusterIP Service（每个含 5 个 endpoint），等待 60s 同步完成后，在相同负载下对比退化幅度。

#### 5000 Services 全量结果

| 指标                    | iptables      | Cilium Native | Cilium Overlay |
| ----------------------- | ------------- | ------------- | -------------- |
| iptables 规则总数       | **30,142 条** | -             | -              |
| keepalive RPS 基线      | 91,896 req/s  | 75,272 req/s  | 75,191 req/s   |
| keepalive RPS @5000 svc | 91,528 req/s  | 76,341 req/s  | 75,181 req/s   |
| **keepalive 退化**      | -0.4%         | +1.4%         | -0.0%          |
| 短连接 RPS 基线         | 22,846 req/s  | 10,194 req/s  | 10,554 req/s   |
| 短连接 RPS @5000 svc    | 17,528 req/s  | 9,738 req/s   | 9,897 req/s    |
| **短连接退化**          | **-23.3%**    | **-4.5%**     | **-6.2%**      |

#### 小规模 vs 大规模：iptables 退化加速 vs Cilium 保持恒定

将本次 5000 svc 数据与早期同环境的 1000 svc 数据放在一起，能直观看到规模放大后两套架构的差异：

| 指标                   | iptables（1000→5000）    | Cilium Native（1000→5000） | Cilium Overlay（1000→5000） |
| ---------------------- | ------------------------ | -------------------------- | --------------------------- |
| iptables 规则总数      | 6,142 → **30,142**（×5） | -                          | -                           |
| keepalive 退化         | -0.4% → -0.4%            | -0.2% → +1.4%              | 0.0% → -0.0%                |
| **短连接退化**         | **-5.9% → -23.3%**       | **-1.6% → -4.5%**          | **-4.1% → -6.2%**           |
| 短连接退化随规模增长比 | **× 4** （线性放大）     | × 2.8 （亚线性，含噪声）   | × 1.5 （亚线性）            |

:::tip[O(1) vs O(n)：核心差异随规模放大]

**keepalive 场景三方均无退化**：conntrack 缓存了首包决策，后续包直接命中，无需再遍历规则链或查询 BPF map。这是为什么大多数生产负载（用了连接池或 HTTP keepalive）感受不到 Service 规模带来的性能影响。

**短连接场景才是真正的考验**：每个新 TCP 连接的 SYN 包都必须重新完成 Service 选择：

- **iptables O(n) 顺序遍历**：1000 svc 时退化 5.9%，5000 svc 时退化 23.3%，**规则数 ×5 → 退化 ×4**，几乎线性恶化。这是 KUBE-SERVICES → KUBE-SVC-XXX → KUBE-SEP-XXX 三层链表顺序匹配的固有代价，规模越大代价越明显。
- **Cilium BPF hash map O(1) 查找**：1000 svc 时退化 1.6%，5000 svc 时退化 4.5%，规模 ×5 但退化仅放大 ~3 倍。**残余退化的来源不是查表本身**，而是 5000 svc 同步过程中 cilium-agent 控制面的 BPF map 写入压力 + conntrack 表条目膨胀（5000 svc × 多 endpoint × 短连接频繁创建/淘汰）的 datapath 副作用，与 Service 数量并非线性相关。
- **Overlay 略高于 Native**：因为 VXLAN encap/decap 的代码路径上 conntrack 表条目维护更密集，但量级仍远低于 iptables。

**外推 10000+ Services 场景**：iptables 短连接退化将逼近 50%（线性），而 Cilium 仍保持在 10% 以内。这是 Cilium 替换 kube-proxy 在大规模集群下最核心的价值。

:::

### Hubble 可观测性开销（仅 Cilium）

| 指标       | Cilium Native | Cilium Overlay |
| ---------- | ------------- | -------------- |
| Hubble ON  | 75,604 req/s  | 74,913 req/s   |
| Hubble OFF | 75,676 req/s  | 74,621 req/s   |
| **开销**   | **-0.1%**     | **+0.4%**      |

:::note

Hubble L3/L4 可观测性的性能开销在 ±0.5% 噪声范围内，**实质为零**。Hubble 在 datapath 上仅做事件采样和 ring buffer 写入，不参与转发决策。可放心在生产环境全量启用 Hubble L3/L4 模式。

:::

### NetworkPolicy L3/L4 开销（仅 Cilium）

| 指标             | Cilium Native | Cilium Overlay |
| ---------------- | ------------- | -------------- |
| 无策略           | 75,573 req/s  | 74,900 req/s   |
| L3/L4 CNP 生效后 | 75,675 req/s  | 74,910 req/s   |
| **开销**         | **+0.1%**     | **+0.0%**      |

:::note

L3/L4 CiliumNetworkPolicy 的执行开销**为零**。Cilium 的 L3/L4 策略在 eBPF 程序中通过 identity lookup + bitmap 匹配实现，不引入额外的内存拷贝或上下文切换。可放心对所有工作负载批量应用 L3/L4 NetworkPolicy。

:::

### 资源占用

| 组件                   | CPU avg | Memory avg |
| ---------------------- | ------- | ---------- |
| kube-proxy (iptables)  | 1.0 m   | 31.1 MiB   |
| Cilium Agent (Native)  | 67.9 m  | 188.1 MiB  |
| Cilium Agent (Overlay) | 96.8 m  | 192.0 MiB  |

:::note

- **kube-proxy 仅做 Service 同步**，CPU/内存极低；但带来的 iptables 规则膨胀和扫描开销转嫁到了 datapath。
- **Cilium Agent 不仅替换 kube-proxy**，还同时承担 NetworkPolicy 编译、Hubble 流量采集、Identity 分配、BPF map 维护等职责，资源消耗自然更高。但 datapath 性能与 Service 规模解耦（O(1)）。
- **Overlay 比 Native CPU 高 ~30m**：来自 VXLAN encap/decap 在 BPF 程序中的额外计算。

如果 NetworkPolicy、可观测性等能力通过 sidecar 方式单独实现，总开销远高于 Cilium Agent 的 ~190 MiB。

:::

## 对比分析

### 三方差异汇总

| 维度                         | 结论                                     | 量化差异                                  |
| ---------------------------- | ---------------------------------------- | ----------------------------------------- |
| **吞吐量**                   | 三者无差异                               | 均达 10 Gbps 突发上限                     |
| **RPS 长连接**               | iptables 比 Cilium 高 ~18%               | 92K vs 75K（cni-chaining/VXLAN 额外开销） |
| **RPS 短连接**               | iptables 比 Cilium 高 ~55%               | 23K vs 10K（同上，绝对值仍远超生产需求）  |
| **TCP_RR p99**               | Cilium 比 iptables 高 ~20 µs             | 应用层无感知                              |
| **HTTP p99 @1000 QPS**       | **三者完全相同**                         | 均为 0.99 ms                              |
| **5000 svc 短连接退化**      | **iptables -23.3% vs Cilium -4.5/-6.2%** | **规模差距随 Service 数量放大**           |
| **Hubble L3/L4 开销**        | 可忽略                                   | < 0.5%                                    |
| **NetworkPolicy L3/L4 开销** | 零                                       | < 0.5%                                    |
| **Cilium Native vs Overlay** | RPS 与延迟基本一致，Overlay CPU 略高     | RPS ±1%，延迟 ±10 µs，CPU +30m            |

### 核心结论

#### 1. 真实业务负载下三方完全等价

HTTP p99 @1000 QPS 三者都是 0.99 ms。极限压测的差异只在 fortio/wrk 这类空响应场景下才能复现，对生产应用无感知。

#### 2. iptables 在小规模下 RPS 更高，在大规模下显著退化

iptables 在小规模 Service（千以下）的极限 RPS 测试中**绝对值领先 Cilium ~18%**。Native 的差距来自 cni-chaining + per-endpoint 路由让每个包走完整内核栈、外加 eBPF 处理；Overlay 的差距来自 VXLAN encap/decap。两种集成方式都让 Cilium 比小规模 iptables 多一层处理，这是架构代价而非 Cilium 缺陷。

但代价是 iptables 的 datapath 性能与 Service 数量强相关：

- 1000 svc 短连接退化 5.9%
- **5000 svc 短连接退化 23.3%**（线性放大约 4 倍）
- 外推 10000 svc 将逼近 50%

而 Cilium 的退化曲线远缓于线性增长（5000 svc 仅 4.5%~6.2%）。**集群 Service 数 ≥ 数千时，Cilium 反超 iptables。**

#### 3. Cilium Native vs Overlay 性能几乎一致

两者在所有 RPS、延迟、规模化退化指标上的差异都在 ±5% 噪声范围内。**选型应基于网络架构而非性能**：

- 需要 Pod IP 在 VPC 内可路由（直连 ELB、跨集群通信、传统监控直接访问 Pod）→ **Native**
- 需要 Pod CIDR 与 VPC 解耦（IP 资源紧张、跨 VPC 复用 CIDR、Pod 数量远超弹性网卡上限）→ **Overlay**

Overlay 在 CPU 上比 Native 略高 ~30m（VXLAN 封解包），但内存几乎一致。

#### 4. Hubble 与 NetworkPolicy 零开销

L3/L4 层面的 Hubble 和 NetworkPolicy 都不引入可测量的性能损失（< 0.5%）。生产环境可放心全量启用。L7 策略的开销另当别论（涉及 Envoy 代理），不在本测试范围。

#### 5. 资源占用：Cilium 换来了能力

Cilium Agent 占用 ~70-100m CPU + ~190 MiB 内存，相比 kube-proxy 的 ~1m + 31MiB 多一个数量级。但获得了 NetworkPolicy（含 Identity-based）、Hubble、L7 策略支持、与 Service 数量解耦的 datapath 等能力。在大规模或安全合规要求高的集群中，这部分代价完全值得。

详细选型建议参见 [Cilium 性能测试 - 选型建议](./performance-test.md#选型建议)。

## 相关链接

- [Cilium 性能测试（cilium connectivity perf）](./performance-test.md)
- [VPC-CNI Native Routing 模式详解](./native-routing.md)
- [安装 Cilium](../install.md)

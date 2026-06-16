# Cilium 网络性能 Benchmark

本文用 [`network-benchmark.sh`](https://imroc.cc/tke/scripts/network-benchmark.sh) 一键脚本，在**完全相同的硬件、内核、VPC 环境**下横向压测三种 TKE 网络方案，回答一个 TKE 用户在选型时最关心的问题：**把 kube-proxy 换成 Cilium，性能到底是赚还是亏？**

测试的三套集群：

- **Cluster A — VPC-CNI + kube-proxy iptables**：传统方案，性能基线
- **Cluster B — VPC-CNI + Cilium Native Routing**：Cilium 以 cni-chaining 接在 VPC-CNI 之上，Pod IP 仍是 VPC 合法 IP
- **Cluster C — VPC-CNI + Cilium Overlay (VXLAN)**：Cilium 独占 Pod CNI，Pod 走独立 overlay 网段

覆盖吞吐、HTTP RPS（长/短连接）、TCP 延迟、Service 规模化退化（5000→30000，每 Service 4 个 Endpoint）、Hubble 开销、NetworkPolicy L3/L4 与 L7 开销、BPF 内存、组件资源。

:::tip[先看结论]

- **吞吐、真实业务延迟（HTTP p99 @1000 QPS）三者完全一致**——网络方案的差异在真实负载下不可见。
- **小规模极限压测**：iptables 的 RPS 领先 Cilium（长连接约 15%，短连接约 2.2 倍），因为它数据路径最短。
- **大规模 Service 是分水岭**：iptables 短连接性能随 Service 数**线性崩塌**，在约 **2 万 Service** 时被 Cilium 反超；到 **3 万 Service** 时 iptables 短连接 RPS 已跌到 Cilium 的 70%~88%。规模越大，天平越向 Cilium 倾斜。
- **L7 NetworkPolicy 是唯一的性能悬崖**：开销约 86~89%，需谨慎按需启用；L3/L4 策略与 Hubble 则是零开销。

:::

## 术语表

第一次看网络压测的读者可以先扫一眼这些术语，后面的表格会反复用到。

| 术语                    | 含义                                               | 通俗解释                                                                                             |
| ----------------------- | -------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| **RPS**                 | Requests Per Second，每秒请求数                    | 一秒内能处理多少个 HTTP 请求，越高越好。本文用 fortio 打满 CPU 测极限 RPS。                          |
| **长连接 / keepalive**  | 一条 TCP 连接建立后**反复复用**发多个请求          | 类似"打一次电话聊很多事"。连接池、HTTP keepalive、gRPC 都是这种。                                    |
| **短连接 / short-conn** | **每个请求都新建一条 TCP 连接**，用完即关          | 类似"每说一句话都重新拨一次号"。无连接池的老式客户端、部分 PHP/CGI 场景。                            |
| **c64 / c256**          | concurrency，并发连接数 = 64 / 256                 | 同时有多少条连接在压测。c256 比 c64 压力更大。                                                       |
| **TCP_RR**              | TCP Request/Response 延迟测试                      | 在**一条已建好的连接**上反复来回，测单次往返延迟。对应"长连接"场景。                                 |
| **TCP_CRR**             | TCP Connect/Request/Response 延迟测试              | **每次都新建连接**再来回一次，测"建连+往返+断连"的完整延迟。对应"短连接"场景。                       |
| **p50 / p99**           | 延迟的 50 / 99 分位数                              | p99=99% 的请求快于这个值。p99 是衡量"尾延迟/最差体验"的关键 SLO 指标。                               |
| **Gbps**                | Gigabits per second，吞吐带宽                      | 每秒传输多少 Gb 数据，衡量大流量传输能力。                                                           |
| **Endpoint**            | Service 背后的一个后端 Pod（IP:Port）              | 一个有 4 副本的 Deployment，其 Service 就有 4 个 Endpoint。                                          |
| **conntrack**           | 内核连接跟踪表                                     | 记录每条连接的转发决策；连接建立后续包直接查表命中，无需重新选路。这是长连接不退化的根本原因。       |
| **KUBE-SERVICES 链**    | kube-proxy 在 iptables 里为所有 Service 建的规则链 | 新连接首包要在这条链里**线性查找**自己的 Service，链长 ≈ Service 数量，是 iptables O(n) 退化的根源。 |
| **BPF map**             | Cilium 在内核里存 Service/Endpoint 的哈希表        | Cilium 用它做 O(1) 查找，速度与 Service 数量无关。                                                   |
| **O(n) / O(1)**         | 算法复杂度                                         | O(n)：耗时随规模线性增长（iptables 查 Service）；O(1)：耗时恒定，与规模无关（Cilium 查 BPF map）。   |
| **VXLAN**               | 一种 Overlay 隧道封装协议                          | Overlay 模式下跨节点流量被封装进 VXLAN 包（多 50 字节头），实现 Pod 网络与底层 VPC 解耦。            |

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
- 跑万级 Service 规模测试时，集群规格要够（如 TKE L500），否则 Service 总数会被集群上限卡住

:::

### 自定义参数

```bash
# 多轮测试（大规格实例无 QoS 顾虑时）
ROUNDS=3 IPERF_DURATION=120 FORTIO_DURATION=120 bash network-benchmark.sh --dir ./bench

# 自定义 Service 规模化测试档位与每 svc 的 endpoint 数
SVC_SCALE_STEPS="5000,10000,20000,30000" SVC_ENDPOINTS=4 bash network-benchmark.sh
```

| 环境变量              | 默认值                 | 说明                                     |
| --------------------- | ---------------------- | ---------------------------------------- |
| `IPERF_DURATION`      | 30                     | iperf3 每轮测试时长（秒）                |
| `FORTIO_DURATION`     | 60                     | fortio / netperf 每轮测试时长（秒）      |
| `ROUNDS`              | 1                      | 每个场景重复轮次                         |
| `ROUND_SLEEP`         | 30                     | 轮间等待（秒），用于 burst credit 恢复   |
| `SVC_SCALE_STEPS`     | 5000,10000,20000,30000 | Service 规模化测试档位（逗号分隔，递增） |
| `SVC_ENDPOINTS`       | 4                      | 每个 dummy Service 的 endpoint 数        |
| `SVC_CREATE_PARALLEL` | 4                      | 并发创建 Service 的 worker 数            |
| `AUTO_FIX_LB_MAP`     | （交互询问）           | `true` 时不询问、自动调大 Cilium LB map  |

:::tip[关于 dummy Service 的 Endpoint 数]

压测只打**一个** fronting Service，它的新连接首包扫的是 `KUBE-SERVICES` 链（长度 = **Service 数量**），与每个 dummy svc 挂多少 Endpoint 无关。Endpoint 只会撑大总规则数 / BPF LB map / 创建耗时，对热路径无贡献。因此本文用 4 个 Endpoint（贴近真实多副本），**靠 Service 数量驱动退化**。

:::

:::warning[大规模测试需调大 Cilium LB map 上限]

Cilium 的 Service 负载均衡 BPF map 默认上限是 `bpf-lb-map-max=65536`。每个 Service 约占用 `1 + endpoint 数` 个 LB 条目，**3 万 Service × (4+1) ≈ 15 万条目会超出默认上限导致 map 溢出**——表现为大规模下 RPS 异常暴跌（这是转发失败，不是 O(n) 退化，会污染结论）。

脚本在 Service Scale 测试前会**自动预检**容量，不足时交互式询问是否自动调大并重启 cilium（`AUTO_FIX_LB_MAP=true` 可免询问）。也可手动设置：

```bash
kubectl -n kube-system patch configmap cilium-config --type merge \
  -p '{"data":{"bpf-lb-map-max":"1048576"}}'
kubectl -n kube-system rollout restart ds/cilium
```

:::

### 测试工具与指标

| 工具    | 测试内容                                            | 指标                  |
| ------- | --------------------------------------------------- | --------------------- |
| iperf3  | 跨节点 TCP 吞吐                                     | Gbps（1/8/16 并发流） |
| fortio  | HTTP RPS（长连接 / 短连接）                         | req/s                 |
| netperf | TCP_RR / TCP_CRR 延迟                               | p50 / p99 微秒        |
| fortio  | 多档 Service 规模（5000→30000）后 RPS 退化          | 退化百分比            |
| fortio  | Hubble on/off RPS 对比（仅 Cilium）                 | 开销百分比            |
| fortio  | NetworkPolicy L3/L4 + L7 前后 RPS 对比（仅 Cilium） | 开销百分比            |
| bpftool | BPF map 内存占用统计（仅 Cilium）                   | MB                    |

## 测试环境

| 项              | Cluster A (iptables)          | Cluster B (Cilium Native)                       | Cluster C (Cilium Overlay)           |
| --------------- | ----------------------------- | ----------------------------------------------- | ------------------------------------ |
| 网络方案        | VPC-CNI + kube-proxy iptables | VPC-CNI + Cilium cni-chaining（Native Routing） | Cilium VXLAN Overlay（独占 Pod CNI） |
| Kubernetes 版本 | v1.34.1-tke.5                 | v1.34.1-tke.5                                   | v1.34.1-tke.5                        |
| 集群规格        | L500                          | L500                                            | L500                                 |
| Cilium 版本     | N/A                           | v1.19.4                                         | v1.19.4                              |
| kube-proxy 替代 | 否（iptables 模式）           | 是（eBPF）                                      | 是（eBPF）                           |
| 节点 OS         | TencentOS Server 4            | TencentOS Server 4                              | TencentOS Server 4                   |
| 内核版本        | 6.6.117-45.11.2               | 6.6.117-45.11.2                                 | 6.6.117-45.11.2                      |
| 节点规格        | SA5.LARGE8（4C 8G）           | SA5.LARGE8（4C 8G）                             | SA5.LARGE8（4C 8G）                  |
| 节点数量        | 3                             | 3                                               | 3                                    |

三个集群同 VPC、同规格硬件、同内核版本（6.6.117-45.11.2）、同集群规格（L500，支撑 3 万级 Service）。Service Scale 测试每个 Service 挂 4 个 Endpoint。所有 RPS / 延迟测试均为跨节点（不同 Worker）。

## 一图速览

| 维度                      | iptables   | Cilium Native | Cilium Overlay | 谁更优                   |
| ------------------------- | ---------- | ------------- | -------------- | ------------------------ |
| Pod2Pod 吞吐（8 streams） | 10.43 Gbps | 10.43 Gbps    | 10.77 Gbps     | 平                       |
| RPS 长连接（c64）         | 115,434    | 100,416       | 100,955        | iptables（+14%）         |
| RPS 短连接（c64，小规模） | 31,365     | 13,826        | 14,193         | iptables（+2.2x）        |
| TCP_RR p99（基线）        | 107 µs     | 103 µs        | 118 µs         | 噪声带内，无显著差异     |
| HTTP p99 @1000 QPS        | 0.99 ms    | 0.99 ms       | 0.99 ms        | 平                       |
| **短连接 RPS @20000 svc** | 12,916     | 11,815        | **13,080**     | **交叉点：Overlay 反超** |
| **短连接 RPS @30000 svc** | **9,057**  | **10,286**    | **12,879**     | **Cilium 全面领先**      |
| L3/L4 NetworkPolicy 开销  | N/A        | -0.0%         | -2.2%          | 零开销                   |
| L7 NetworkPolicy 开销     | N/A        | -86.1%        | -88.7%         | 性能悬崖，按需启用       |
| Hubble L3/L4 开销         | N/A        | -0.3%         | -0.2%          | 零开销                   |
| BPF map 内存 / 节点       | N/A        | 289.7 MB      | 289.7 MB       | 预分配，不随 svc 增长    |
| 数据面组件内存 / 节点     | 926 MB     | 1111 MB       | 1104 MB        | 见[第六节](#六资源占用)  |

下面分维度展开，并对几个反直觉的点做深入分析。

## 一、吞吐量：三者等价

| 场景                      | iptables   | Cilium Native | Cilium Overlay |
| ------------------------- | ---------- | ------------- | -------------- |
| Node hostNet（8 streams） | 10.44 Gbps | 10.44 Gbps    | 10.82 Gbps     |
| Pod-to-Pod（single）      | 10.43 Gbps | 10.43 Gbps    | 10.75 Gbps     |
| Pod-to-Pod（8 streams）   | 10.43 Gbps | 10.43 Gbps    | 10.77 Gbps     |
| Pod-to-Pod（16 streams）  | 10.43 Gbps | 10.43 Gbps    | 10.77 Gbps     |
| Via Service（8 streams）  | 10.43 Gbps | 10.43 Gbps    | 10.77 Gbps     |

三种方案均跑满 ~10.4-10.8 Gbps，逼近 SA5.LARGE8 的突发带宽上限——**吞吐量层面三者完全等价**。集群间 ±4% 差异是 VPC 突发带宽波动。16 streams 与 8 streams 持平，说明 8 并发流已饱和网卡。

Overlay 即使带 VXLAN 封装，大包吞吐反而略高——50 字节封装头在 MTU 级大包场景下占比极小，对吞吐无实质影响。VXLAN 的代价只体现在小包高频场景（见 RPS）。

## 二、RPS：iptables 小规模领先，但这是路径最短的红利

| 场景                   | iptables         | Cilium Native    | Cilium Overlay   |
| ---------------------- | ---------------- | ---------------- | ---------------- |
| Pod-to-Pod c64 长连接  | 115,903 req/s    | 100,338 req/s    | 93,159 req/s     |
| Via Svc c64 长连接     | 115,434 req/s    | 100,416 req/s    | 100,955 req/s    |
| Via Svc c256 长连接    | 119,434 req/s    | 102,827 req/s    | 94,148 req/s     |
| **Via Svc c64 短连接** | **31,365** req/s | **13,826** req/s | **14,193** req/s |

### 长连接：iptables 领先约 14%

iptables（115K）> Native（100K）≈ Overlay（101K）。差距不大但稳定，原因是**路径长度不同**：

- **iptables 路径最短**：每个包只走一次内核协议栈，kube-proxy 的 DNAT 只是 conntrack 命中后的几条规则匹配，没有额外处理。
- **Cilium Native**：VPC-CNI cni-chaining 强制 per-endpoint 路由，Pod 流量绕过 `cilium_host`，既走内核栈又叠加 eBPF 的 conntrack + Service + Policy 处理，每个包多一层。
- **Cilium Overlay**：BPF Host Routing 生效、跳过部分内核栈，但每个跨节点包要做 VXLAN encap/decap，封装开销与 Native 的双层处理量级相当。

（注：Overlay 的 c256 / pod2pod 单项偏低是单轮测试噪声，svc keepalive c64 的 100,955 与 Native 基本持平更具代表性。）

### 短连接：iptables 领先 2.2 倍——为什么差距这么大？

短连接基线 iptables（31,365）是 Cilium（~14,000）的 **2.2 倍**，远大于长连接的差距。根因在于**长短连接命中的代码路径完全不同**：

- **长连接**：连接建好后，每个请求复用同一条 TCP 连接，转发决策被 conntrack 缓存，后续包直接命中缓存——三种方案此时都只是"查 conntrack + 转发"，差异只来自那一层固定开销。
- **短连接**：每个请求都新建 TCP 连接，每个 SYN 包都要**完整重做一次 Service 选择 + conntrack 表项创建**。这里 Cilium 的劣势被放大：
  - Native 每个新连接都要走 eBPF（创建 BPF conntrack 条目 + Service 后端选择）**叠加**内核栈的连接建立，是真正的"双份开销"；
  - iptables 新建连接虽然也要遍历规则，但在**小规模（基线几乎无 dummy svc）**时规则链极短，开销很低。

换句话说：短连接基线的 2.2 倍差距，是 iptables 在"规则链短"前提下的红利。**这个前提随 Service 规模增长会迅速消失**——见第四节，这正是全文的转折点。

:::tip[但这些差异对真实业务无感知]

三种方案的绝对 RPS（短连接 14K-31K、长连接 100K-115K）都**远超**典型微服务单 Pod 的负载（通常 < 10K req/s）。差异只在 fortio 打满 CPU 的极限压测下可见。真实业务负载下三者表现一致（见下方 HTTP p99 @1000 QPS）。

:::

## 三、延迟：真实负载下完全一致

| 指标               | iptables | Cilium Native | Cilium Overlay |
| ------------------ | -------- | ------------- | -------------- |
| TCP_RR p50         | 84 µs    | 85 µs         | 95 µs          |
| TCP_RR p99         | 107 µs   | 103 µs        | 118 µs         |
| TCP_CRR p99        | 487 µs   | 546 µs        | 558 µs         |
| HTTP p99 @1000 QPS | 0.99 ms  | 0.99 ms       | 0.99 ms        |

:::tip[延迟差异在真实负载下消失]

- **HTTP p99 @1000 QPS：三者 0.99 ms，完全一致**。这是全文最重要的一行。在真实业务速率（1000 QPS）下，三种方案的 p99 延迟完全相同。前面 RPS 章节那些 14%、2.2 倍的差距，一旦应用本身有处理逻辑（数据库查询、序列化、业务计算），就被彻底淹没。**网络方案的选择不会影响真实应用的延迟。**
- **TCP_RR p99（长连接往返）**：三者都在 ~100-120 µs 噪声带内，方向不稳定（这次 Native 甚至略低于 iptables）。亚毫秒级差异对应用层不可见，不构成方案优劣判断。
- **TCP_CRR p99（新建连接往返）**：iptables（487 µs）略低于 Cilium（546-558 µs），与短连接 RPS 一致——新建连接时 Cilium 多一层 eBPF 处理。同样地，这个差距会随 Service 规模增长而逆转（每个新连接的扫链成本随 svc 数上升）。

:::

:::note[关于延迟随规模的退化]

延迟和 RPS 是同一现象的两面（满压下 `RPS ≈ 并发 / 延迟`）。理论上 iptables 的 TCP_CRR p99 会随 Service 数线性抬升、Cilium 保持恒定，与下面短连接 RPS 退化曲线平行。本轮的延迟随规模数据存在采集时序噪声，暂不纳入，后续补测干净数据后再补充本节。

:::

## 四、Service 规模化退化：全文的核心转折点

这是 Cilium 替换 kube-proxy 最有价值的一环。测试方法：阶梯式创建 5000 → 30000 个 dummy Service（**每个挂 4 个 Endpoint**），每档等待同步后压测，对比相对基线的退化。

### 长连接：三者全程几乎零退化

| Service 数 | iptables | Cilium Native | Cilium Overlay |
| ---------- | -------- | ------------- | -------------- |
| 5000       | -0.2%    | 0.0%          | -0.1%          |
| 10000      | -2.1%    | -0.7%         | 0.1%           |
| 20000      | -0.3%    | -1.5%         | 0.2%           |
| 30000      | -0.7%    | -9.2%         | 0.5%           |

长连接场景几乎不退化——conntrack 缓存了首包决策，后续包不再查规则链 / BPF map。**用了连接池或 HTTP keepalive 的生产业务，基本不受 Service 规模影响。**（Native 在 30000 svc 的 -9.2% 是单轮测试中 agent 同步压力导致的离群点，与同规模 Overlay 的 +0.5% 对比可见并非 datapath 退化。）

### 短连接：iptables 线性崩塌，Cilium 稳如磐石，约 2 万 svc 反超

| Service 数                   | iptables             | Cilium Native        | Cilium Overlay      |
| ---------------------------- | -------------------- | -------------------- | ------------------- |
| 基线（小规模）               | 31,365 req/s         | 13,826 req/s         | 14,193 req/s        |
| 5000                         | 22,237（-29.1%）     | 12,774（-7.6%）      | 13,122（-7.5%）     |
| 10000                        | 17,261（-45.0%）     | 11,895（-14.0%）     | 12,746（-10.2%）    |
| **20000**                    | **12,916（-58.8%）** | 11,815（-14.5%）     | **13,080（-7.8%）** |
| **30000**                    | **9,057（-71.1%）**  | **10,286（-25.6%）** | **12,879（-9.3%）** |
| KUBE-SERVICES 链长 / LB 条目 | 5011→30003           | 30018→179946         | 30042→179988        |

:::tip[O(n) vs O(1)：交叉点出现在约 2 万 Service]

短连接是真正的考验——每个新连接的 SYN 包都要重做 Service 选择，无法命中 conntrack 缓存。

- **iptables 是 O(n) 顺序遍历**：每个 SYN 包顺序匹配 `KUBE-SERVICES` 链（长度 = Service 数量）。Service 越多，扫链越久。短连接 RPS 从基线 31K 一路跌到 30000 svc 的 9K（**退化 71%**），随 Service 数近乎线性崩塌。
- **Cilium 是 O(1) BPF hash map 查找**：查表耗时与 Service 数量无关。Native 退化到 -25.6%、Overlay 仅 -9.3%，远比 iptables 平缓。

**交叉点清晰可见**：

- **约 2 万 Service**：iptables（12,916）已被 Overlay（13,080）反超，与 Native（11,815）基本持平。
- **3 万 Service**：iptables（9,057）跌到明显低于 Native（10,286）和 Overlay（12,879）——**Cilium 两种模式全面领先**，iptables 短连接 RPS 只剩 Overlay 的 70%。

一句话：**小规模 iptables 凭"路径短"领先，约 2 万 Service 时被 Cilium 反超，之后差距持续拉大。** 长连接业务则全程无所谓。

:::

:::note[为什么 endpoint 数不影响这条曲线]

退化由 `KUBE-SERVICES` 链长（≈Service 数量）驱动，而非每个 svc 的 Endpoint 数——压测只打单个 fronting Service，新连接首包扫的是这条链，扫到自己那条就跳走，不会进入各 dummy svc 的后端规则。所以无论每个 dummy svc 挂 4 个还是 50 个 Endpoint，退化曲线一致。真实业务里 **Service 数量**才是 iptables 短连接退化的关键变量。

:::

## 五、Hubble 与 NetworkPolicy：L3/L4 零开销，L7 是性能悬崖

### Hubble 可观测性（仅 Cilium）

| 指标       | Cilium Native | Cilium Overlay |
| ---------- | ------------- | -------------- |
| Hubble ON  | 100,007 req/s | 101,434 req/s  |
| Hubble OFF | 100,271 req/s | 101,675 req/s  |
| **开销**   | **-0.3%**     | **-0.2%**      |

Hubble L3/L4 可观测性开销在 ±0.5% 噪声范围内，**实质为零**。Hubble 只在 datapath 做事件采样写 ring buffer，不参与转发决策。可放心在生产全量启用 L3/L4 流量观测。

### NetworkPolicy L3/L4：零开销

| 指标             | Cilium Native | Cilium Overlay |
| ---------------- | ------------- | -------------- |
| 无策略           | 99,985 req/s  | 101,514 req/s  |
| L3/L4 CNP 生效后 | 99,965 req/s  | 99,249 req/s   |
| **开销**         | **-0.0%**     | **-2.2%**      |

L3/L4 CiliumNetworkPolicy 通过 eBPF 的 identity lookup + bitmap 匹配实现，无额外内存拷贝或上下文切换，**开销为零**（Overlay 的 -2.2% 在单轮噪声范围内）。可放心对所有工作负载批量应用。

### NetworkPolicy L7：性能悬崖，按需启用

| 指标          | Cilium Native | Cilium Overlay |
| ------------- | ------------- | -------------- |
| 无策略        | 99,985 req/s  | 101,514 req/s  |
| L7 CNP 生效后 | 13,883 req/s  | 11,483 req/s   |
| **开销**      | **-86.1%**    | **-88.7%**     |

:::warning[L7 策略只对必要的 Pod 启用]

L7 CiliumNetworkPolicy（如 HTTP path/method 过滤）会把流量重定向到 **Envoy 代理**做应用层解析，RPS 暴跌 **86~89%**。这不是 Cilium 的缺陷，而是 L7 可见性的固有成本（任何 L7 策略 / Service Mesh 都有类似代价）。

正确用法：

- **L3/L4 策略**：覆盖绝大多数生产安全需求（按 IP、端口、命名空间标签 allow/deny），零开销，全量启用。
- **L7 策略**：仅对确实需要应用层管控的 Pod 选择性启用（对外入口网关、敏感 API 审计），不要全量铺开。

:::

## 六、资源占用

### CPU / 内存（满载 30000 svc × 4 ep，稳态采样）

| 组件                   | CPU avg / max | Memory avg / max |
| ---------------------- | ------------- | ---------------- |
| kube-proxy (iptables)  | 8.2m / 16m    | 926 / 928 MiB    |
| Cilium Agent (Native)  | 25.8m / 43m   | 1111 / 1216 MiB  |
| Cilium Agent (Overlay) | 25.4m / 33m   | 1104 / 1228 MiB  |

:::note[满载下 kube-proxy 内存也接近 1 GB]

满载（30000 svc × 4 ep）下三个组件的内存都到了 GB 级。kube-proxy（926 MiB）要在用户态维护 **54 万条 iptables 规则**的完整表示，并在每次 Service/Endpoint 变更时做规则 diff 与全量刷新——规则越多，kube-proxy 内存越高。CPU 则很低（8m），因为规则匹配发生在内核态。

Cilium Agent（~1.1 GiB）的内存主要是 BPF map（预分配，见下）+ endpoint/identity 状态。CPU（~25m）也很低且稳定。

要强调：这是 **3 万 Service 的极端规模**，绝大多数集群远达不到。在常规规模（数百到数千 Service）下，三者组件内存都在百 MiB 量级。

:::

### BPF Map 内存：预分配，不随规模增长

| 指标             | Cilium Native | Cilium Overlay |
| ---------------- | ------------- | -------------- |
| BPF map 总内存   | 289.7 MB      | 289.7 MB       |
| BPF map 数量     | 64            | 63             |
| Cilium Agent RSS | 870 MB        | 1014 MB        |

Top BPF map 内存消耗（两集群一致；LB map 上限已调到 1020000 以支撑 3 万 svc）：

| Map 名称（截断）    | Max Entries | 内存    |
| ------------------- | ----------- | ------- |
| cilium_lb4_affinity | 1,020,000   | 93.8 MB |
| cilium_lb4_services | 1,020,000   | 31.1 MB |
| cilium_lb4_backends | 1,020,000   | 25.2 MB |
| cilium_lb4_reverse  | 1,020,000   | 18.1 MB |
| cilium_ct4_global   | 131,072     | 17.0 MB |

:::note[BPF map 预分配机制]

**BPF map 在创建时按 `max_entries` 一次性分配最大内存**，后续增删 Service/Endpoint 只填充已分配空间，不动态增长。本测试中 Service 从 0 涨到 30000，BPF map 总内存始终稳定在 ~289.7 MB。

注意：这里的 289.7 MB 是把 LB map 上限**调到 102 万**（为支撑 3 万 svc）后的预分配值——上限越大，预分配越多。在默认 `bpf-lb-map-max=65536` 下，BPF map 总内存约 90 MB。**所以这个数字是"为极端规模预留"的结果，不是常规集群的占用。** 按需设置 `bpf-lb-map-max` 即可控制这部分内存。

:::

## 总结与选型

### iptables vs Cilium：换不换？

| 你的情况                                             | 建议                                                                     |
| ---------------------------------------------------- | ------------------------------------------------------------------------ |
| Service 数量少（数千以下）、追求极限 RPS             | iptables 小规模 RPS 领先，可继续用；但差异真实负载无感                   |
| Service 数量大（≥2 万）、有大量短连接业务            | **Cilium**：约 2 万 svc 起 Cilium 短连接 RPS 反超，iptables 持续线性崩塌 |
| 需要 NetworkPolicy / Hubble 可观测性 / Identity 安全 | **Cilium**：L3/L4 策略与 Hubble 零开销，iptables 不具备                  |
| 只跑长连接业务（连接池 / keepalive）                 | 都行：长连接对规模和方案都不敏感                                         |

核心权衡：**换 Cilium 在小规模极限压测下损失约 14% 长连接 RPS（真实负载无感），换来大规模下不崩塌的短连接性能 + 零开销的安全与可观测能力。** 对中大规模或有安全合规需求的集群，这笔交易划算。

### Cilium Native vs Overlay：看架构不看性能

两者所有性能指标差异都在噪声范围内（基线 RPS/延迟基本持平；规模化退化 Overlay 略优于 Native，但都远好于 iptables）。**选型应基于网络架构**：

- 需要 Pod IP 在 VPC 内直接可路由（直连 CLB、跨集群 / 跨 VPC 互通、传统监控直采 Pod）→ **Native**
- 需要 Pod CIDR 与 VPC 解耦（IP 资源紧张、跨 VPC 复用 CIDR、Pod 数远超弹性网卡上限）→ **Overlay**

> 关于 Native 模式下 BPF Host Routing 为何实际不命中、以及云厂商 Native IPAM 的共性，详见 [VPC-CNI Native Routing 模式详解](./native-routing.md)。

### 小规模 vs 大规模 Service

iptables 的短连接性能与 Service 数量强相关（O(n)）：从 5000 svc 的 -29% 一路崩到 30000 svc 的 -71%；Cilium 与 Service 数量解耦（O(1)），全程平缓。**交叉点在约 2 万 Service——这是大规模集群选择 Cilium 替换 kube-proxy 的量化依据。**

详细选型建议参见 [Cilium 性能测试 - 选型建议](./performance-test.md#选型建议)。

## 相关链接

- [Cilium 性能测试（cilium connectivity perf）](./performance-test.md)
- [VPC-CNI Native Routing 模式详解](./native-routing.md)
- [安装 Cilium](../install.md)

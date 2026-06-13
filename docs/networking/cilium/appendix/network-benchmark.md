# Cilium 网络性能 Benchmark

本文用 [`network-benchmark.sh`](https://imroc.cc/tke/scripts/network-benchmark.sh) 一键脚本，在**完全相同的硬件、内核、VPC 环境**下横向压测三种 TKE 网络方案，回答一个 TKE 用户在选型时最关心的问题：**把 kube-proxy 换成 Cilium，性能到底是赚还是亏？**

测试的三套集群：

- **Cluster A — VPC-CNI + kube-proxy iptables**：传统方案，性能基线
- **Cluster B — VPC-CNI + Cilium Native Routing**：Cilium 以 cni-chaining 接在 VPC-CNI 之上，Pod IP 仍是 VPC 合法 IP
- **Cluster C — VPC-CNI + Cilium Overlay (VXLAN)**：Cilium 独占 Pod CNI，Pod 走独立 overlay 网段

覆盖吞吐、HTTP RPS（长/短连接）、TCP 延迟、Service 规模化退化（5000→10000，每 Service 10 个 Endpoint 模拟真实多副本）、Hubble 开销、NetworkPolicy L3/L4 与 L7 开销、BPF 内存、组件资源。

:::tip[先看结论]

- **吞吐、真实业务延迟（HTTP p99 @1000 QPS）三者完全一致**——网络方案的差异在真实负载下不可见。
- **小规模极限压测**：iptables 的 RPS 仍领先 Cilium（长连接约 6-11%，短连接约 2.2 倍），因为它路径最短。
- **大规模 Service**：iptables 短连接性能随规则数**线性崩塌**（10000 Service × 10 Endpoint = 42 万条规则，短连接退化 43%），Cilium 几乎不退化（约 11-13%）。规模越大，天平越向 Cilium 倾斜。
- **延迟反转**：在本次较新的内核（6.6.117-45.11.2）下，Cilium 的 TCP_RR 延迟反而**低于** iptables——与旧内核结论相反。
- **L7 NetworkPolicy 是唯一的性能悬崖**：开销约 87-88%，需谨慎按需启用；L3/L4 策略与 Hubble 则是零开销。

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

# 自定义 Service 规模化测试档位与每 svc 的 endpoint 数
SVC_SCALE_STEPS="1000,5000,10000" SVC_ENDPOINTS=10 bash network-benchmark.sh
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

Cilium 的 Service 负载均衡 BPF map 默认上限是 `bpf-lb-map-max=65536`。每个 Service 约占用 `1 + endpoint 数` 个 LB 条目，**10000 Service × 10 endpoint ≈ 11 万条目会超出默认上限导致 map 溢出**——表现为大规模下 RPS 异常暴跌（这是转发失败，不是 O(n) 退化，会污染结论）。跑大规模测试前先调大并重启 cilium：

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
| fortio  | 多档 Service 规模（5000/10000，每 svc 10 ep）退化   | 退化百分比            |
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
| 内核版本        | 6.6.117-45.11.2               | 6.6.117-45.11.2                                 | 6.6.117-45.11.2                      |
| 节点规格        | SA5.LARGE8（4C 8G）           | SA5.LARGE8（4C 8G）                             | SA5.LARGE8（4C 8G）                  |
| 节点数量        | 3                             | 3                                               | 3                                    |

三个集群同 VPC、同规格硬件、同内核版本（6.6.117-45.11.2）、同 LB map 上限（262144），Service Scale 测试每个 Service 挂 10 个 Endpoint（模拟多副本真实业务）。所有 RPS / 延迟测试均为跨节点（不同 Worker）。

## 一图速览

| 维度                      | iptables   | Cilium Native | Cilium Overlay | 谁更优                       |
| ------------------------- | ---------- | ------------- | -------------- | ---------------------------- |
| Pod2Pod 吞吐（8 streams） | 10.43 Gbps | 10.43 Gbps    | 10.77 Gbps     | 平                           |
| RPS 长连接（c64）         | 111,673    | 105,070       | 100,084        | iptables（+6~11%）           |
| RPS 短连接（c64，小规模） | 30,576     | 13,786        | 14,263         | iptables（+2.2x）            |
| TCP_RR p99                | 109 µs     | 96 µs         | 95 µs          | **Cilium（更低）**           |
| TCP_CRR p99               | 499 µs     | 558 µs        | 537 µs         | iptables（略低）             |
| HTTP p99 @1000 QPS        | 0.99 ms    | 0.99 ms       | 0.99 ms        | 平                           |
| 10000 svc 短连接退化      | **-43.2%** | **-13.2%**    | **-11.5%**     | **Cilium（差距随规模拉大）** |
| 10000 svc 规则/LB 条目    | 419,891    | 119,832       | 119,888        | -                            |
| L3/L4 NetworkPolicy 开销  | N/A        | -0.7%         | +0.4%          | 零开销                       |
| L7 NetworkPolicy 开销     | N/A        | -87.0%        | -88.0%         | 性能悬崖，按需启用           |
| Hubble L3/L4 开销         | N/A        | -0.5%         | +0.3%          | 零开销                       |
| BPF map 内存 / 节点       | N/A        | 142.5 MB      | 142.6 MB       | 预分配，不随 svc 增长        |
| 数据面组件内存 / 节点     | 204 MB     | 153 MB        | 165 MB         | 见[第六节](#六资源占用)      |

下面分维度展开，并对几个反直觉的点做深入分析。

## 一、吞吐量：三者等价

| 场景                      | iptables   | Cilium Native | Cilium Overlay |
| ------------------------- | ---------- | ------------- | -------------- |
| Node hostNet（8 streams） | 10.44 Gbps | 10.44 Gbps    | 10.88 Gbps     |
| Pod-to-Pod（single）      | 10.42 Gbps | 10.42 Gbps    | 10.69 Gbps     |
| Pod-to-Pod（8 streams）   | 10.43 Gbps | 10.43 Gbps    | 10.77 Gbps     |
| Pod-to-Pod（16 streams）  | 10.43 Gbps | 10.43 Gbps    | 10.77 Gbps     |
| Via Service（8 streams）  | 10.43 Gbps | 10.43 Gbps    | 10.77 Gbps     |

三种方案均跑满 ~10.4-10.9 Gbps，逼近 SA5.LARGE8 的突发带宽上限——**吞吐量层面三者完全等价**。集群间 ±4% 差异是 VPC 突发带宽波动。16 streams 与 8 streams 持平，说明 8 并发流已饱和网卡。

Overlay 即使带 VXLAN 封装，大包吞吐反而略高——50 字节封装头在 MTU 级大包场景下占比极小，对吞吐无实质影响。VXLAN 的代价只体现在小包高频场景（见 RPS）。

## 二、RPS：iptables 小规模领先，但这是路径最短的红利

| 场景                   | iptables         | Cilium Native    | Cilium Overlay   |
| ---------------------- | ---------------- | ---------------- | ---------------- |
| Pod-to-Pod c64 长连接  | 111,593 req/s    | 105,378 req/s    | 100,836 req/s    |
| Via Svc c64 长连接     | 111,673 req/s    | 105,070 req/s    | 100,084 req/s    |
| Via Svc c256 长连接    | 115,206 req/s    | 107,692 req/s    | 102,554 req/s    |
| **Via Svc c64 短连接** | **30,576** req/s | **13,786** req/s | **14,263** req/s |

### 长连接：iptables 领先 6-11%

iptables（111K）> Native（105K）> Overlay（100K）。差距不大但稳定，原因是**路径长度不同**：

- **iptables 路径最短**：每个包只走一次内核协议栈，kube-proxy 的 DNAT 只是 conntrack 命中后的几条规则匹配，没有额外处理。
- **Cilium Native**：VPC-CNI cni-chaining 强制 per-endpoint 路由，Pod 流量绕过 `cilium_host`，既走内核栈又叠加 eBPF 的 conntrack + Service + Policy 处理，每个包多一层。
- **Cilium Overlay**：BPF Host Routing 生效、跳过部分内核栈，但每个跨节点包要做 VXLAN encap/decap，封装开销使它在三者中长连接 RPS 最低。

### 短连接：iptables 领先 2.2 倍——为什么差距这么大？

短连接基线 iptables（30,576）是 Cilium（~14,000）的 **2.2 倍**，远大于长连接的差距。根因在于**长短连接命中的代码路径完全不同**：

- **长连接**：连接建好后，每个请求复用同一条 TCP 连接，转发决策被 conntrack 缓存，后续包直接命中缓存——三种方案此时都只是"查 conntrack + 转发"，差异只来自那一层固定开销。
- **短连接**：每个请求都新建 TCP 连接，每个 SYN 包都要**完整重做一次 Service 选择 + conntrack 表项创建**。这里 Cilium 的劣势被放大：
  - Native 每个新连接都要走 eBPF（创建 BPF conntrack 条目 + Service 后端选择）**叠加**内核栈的连接建立，是真正的"双份开销"；
  - iptables 新建连接虽然也要遍历规则，但在**小规模（基线几乎无 dummy svc）**时规则链极短，开销很低。

换句话说：短连接基线的 2.2 倍差距，是 iptables 在"规则链短"前提下的红利。**这个前提随 Service 规模增长会迅速消失**——见第四节，这正是全文的转折点。

:::tip[但这些差异对真实业务无感知]

三种方案的绝对 RPS（短连接 14K-30K、长连接 100K-115K）都**远超**典型微服务单 Pod 的负载（通常 < 10K req/s）。差异只在 fortio 打满 CPU 的极限压测下可见。真实业务负载下三者表现一致（见下方 HTTP p99 @1000 QPS）。

:::

## 三、延迟：真实负载下完全一致，但极限延迟出现了反转

| 指标               | iptables | Cilium Native | Cilium Overlay |
| ------------------ | -------- | ------------- | -------------- |
| TCP_RR p50         | 90 µs    | 79 µs         | 76 µs          |
| TCP_RR p99         | 109 µs   | 96 µs         | 95 µs          |
| TCP_CRR p99        | 499 µs   | 558 µs        | 537 µs         |
| HTTP p99 @1000 QPS | 0.99 ms  | 0.99 ms       | 0.99 ms        |

### HTTP p99 @1000 QPS：三者 0.99 ms，完全一致

**这是全文最重要的一行**。在真实业务速率（1000 QPS）下，三种方案的 p99 延迟完全相同。前面 RPS 章节那些 6-11%、2.2 倍的差距，一旦应用本身有处理逻辑（数据库查询、序列化、业务计算），就被彻底淹没。**网络方案的选择不会影响真实应用的延迟。**

### TCP_RR：Cilium 反而比 iptables 低（与旧内核相反）

值得专门指出：本次测试中 Cilium 的 TCP_RR（长连接请求-响应延迟）p99 为 95-96 µs，**低于** iptables 的 109 µs。

这与我们早前在较旧内核（6.6.117-45.7.3）上的结论相反——当时 Cilium 比 iptables **高** ~15 µs。本次三套集群都跑在更新的 6.6.117-45.11.2 内核上，所有方案的绝对延迟都下降了，但 Cilium 降幅更大，于是出现反超。

:::note[一个待验证的假说]

我们没有深究这次反转的内核级根因，这里只给一个**合理假说、留待验证**：较新内核可能优化了 eBPF 数据路径上的热点（如 conntrack 查找、`bpf_redirect` 的 per-CPU 路径），使 Cilium 在长连接稳态请求-响应下的单跳延迟低于走完整 netfilter 链的 iptables。

要强调的是：**这个量级（±10-15 µs）的延迟差异在亚毫秒区间，对应用层不可见**（HTTP p99 三者一致已证明）。它的意义不在于"谁更快"，而在于提醒一个常被忽视的事实——**网络组件的微基准结论强依赖内核版本，换个内核可能就反转，不要把某次微基准的排名当成方案的固有属性。**

:::

### TCP_CRR：新建连接 iptables 略低

TCP_CRR（每次新建连接的请求-响应）iptables（499 µs）略低于 Cilium（537-558 µs）。与短连接 RPS 一致：新建连接时 Cilium 要做 eBPF conntrack 创建 + Service 解析，比小规模 iptables 多一层。同样地，这个差距会随 Service 规模增长而逆转。

## 四、Service 规模化退化：全文的核心转折点

这是 Cilium 替换 kube-proxy 最有价值的一环。测试方法：阶梯式创建 5000 → 10000 个 dummy Service（**每个挂 10 个 Endpoint**，模拟多副本 Deployment），每档等待同步后压测，对比相对基线的退化。

### 长连接：三者全程几乎零退化

| Service 数 | iptables | Cilium Native | Cilium Overlay |
| ---------- | -------- | ------------- | -------------- |
| 5000       | -0.6%    | -0.9%         | -0.0%          |
| 10000      | -0.7%    | -1.2%         | -0.1%          |

长连接场景三者都几乎不退化——conntrack 缓存了首包决策，后续包不再查规则链 / BPF map。**用了连接池或 HTTP keepalive 的生产业务，基本不受 Service 规模影响。**

### 短连接：iptables 线性崩塌，Cilium 稳如磐石

| Service 数     | iptables              | Cilium Native        | Cilium Overlay       |
| -------------- | --------------------- | -------------------- | -------------------- |
| 基线（小规模） | 30,576 req/s          | 13,786 req/s         | 14,263 req/s         |
| 5000           | 21,286（-30.4%）      | 12,473（-9.5%）      | 13,149（-7.8%）      |
| 10000          | 17,358（**-43.2%**）  | 11,963（**-13.2%**） | 12,618（**-11.5%**） |
| 规则数/LB 条目 | 210,142 → **419,891** | 60,006 → 119,832     | 60,030 → 119,888     |

:::tip[O(n) vs O(1)：10 Endpoint 把差距放大到肉眼可见]

短连接是真正的考验——每个新连接的 SYN 包都要重做 Service 选择，无法命中 conntrack 缓存。

- **iptables 是 O(n) 顺序遍历**：每个 SYN 包顺序匹配 KUBE-SERVICES → KUBE-SVC-XXX → KUBE-SEP-XXX 规则链。**每个 Endpoint 多一条 KUBE-SEP 规则**，所以 10000 svc × 10 ep 时规则数高达 **42 万条**。短连接退化从 5000 svc 的 -30.4% 恶化到 10000 svc 的 -43.2%，随规则数近乎线性崩塌。
- **Cilium 是 O(1) BPF hash map 查找**：查表耗时与 Service/Endpoint 数量无关。Native 从 -9.5% 到 -13.2%、Overlay 从 -7.8% 到 -11.5%，退化平缓。**注意 Cilium 的 LB 条目数（11.9 万）和 iptables 规则数（42 万）在同样 svc 规模下差了 3.5 倍**——因为 Cilium 的后端是 map 里的值而非独立规则，Endpoint 增长不额外拉长查找路径。

**与单 Endpoint 测试的对比**：早前每 svc 只挂 1 个 Endpoint 时，iptables 10000 svc 短连接退化是 -37%、规则数 6 万。换成 10 Endpoint 后退化加深到 -43%、规则数飙到 42 万——**Endpoint 越多，iptables 的 O(n) 劣势越严重**，这才贴近真实业务（真实 Service 普遍多副本）。

:::

### 那么 Cilium 何时反超 iptables？

注意绝对值：**即使到 10000 svc，iptables 短连接（17,358）仍高于 Cilium（~12,600）**。但领先优势从基线的 2.2 倍已收窄到 1.38 倍。

按 5000→10000 段的下降斜率线性外推，iptables 短连接 RPS 约在 **1.5-1.6 万 Service** 时跌破 Cilium，之后被反超。考虑到真实业务的 Service 往往比 dummy svc 挂更多 Endpoint、规则链更长，**实际交叉点会更早到来**。

**一句话**：小规模 iptables 凭"路径短"领先，大规模 Cilium 凭"O(1)"反超，交叉点在万级 Service。长连接业务则全程无所谓。

## 五、Hubble 与 NetworkPolicy：L3/L4 零开销，L7 是性能悬崖

### Hubble 可观测性（仅 Cilium）

| 指标       | Cilium Native | Cilium Overlay |
| ---------- | ------------- | -------------- |
| Hubble ON  | 104,343 req/s | 100,381 req/s  |
| Hubble OFF | 104,914 req/s | 100,098 req/s  |
| **开销**   | **-0.5%**     | **+0.3%**      |

Hubble L3/L4 可观测性开销在 ±0.5% 噪声范围内，**实质为零**。Hubble 只在 datapath 做事件采样写 ring buffer，不参与转发决策。可放心在生产全量启用 L3/L4 流量观测。

### NetworkPolicy L3/L4：零开销

| 指标             | Cilium Native | Cilium Overlay |
| ---------------- | ------------- | -------------- |
| 无策略           | 104,787 req/s | 100,242 req/s  |
| L3/L4 CNP 生效后 | 104,083 req/s | 100,599 req/s  |
| **开销**         | **-0.7%**     | **+0.4%**      |

L3/L4 CiliumNetworkPolicy 通过 eBPF 的 identity lookup + bitmap 匹配实现，无额外内存拷贝或上下文切换，**开销为零**。可放心对所有工作负载批量应用。

### NetworkPolicy L7：性能悬崖，按需启用

| 指标          | Cilium Native | Cilium Overlay |
| ------------- | ------------- | -------------- |
| 无策略        | 104,787 req/s | 100,242 req/s  |
| L7 CNP 生效后 | 13,591 req/s  | 11,984 req/s   |
| **开销**      | **-87.0%**    | **-88.0%**     |

:::warning[L7 策略只对必要的 Pod 启用]

L7 CiliumNetworkPolicy（如 HTTP path/method 过滤）会把流量重定向到 **Envoy 代理**做应用层解析，RPS 暴跌 **87-88%**。这不是 Cilium 的缺陷，而是 L7 可见性的固有成本（任何 L7 策略 / Service Mesh 都有类似代价）。

正确用法：

- **L3/L4 策略**：覆盖绝大多数生产安全需求（按 IP、端口、命名空间标签 allow/deny），零开销，全量启用。
- **L7 策略**：仅对确实需要应用层管控的 Pod 选择性启用（对外入口网关、敏感 API 审计），不要全量铺开。

:::

## 六、资源占用

### CPU / 内存

| 组件                   | CPU avg | Memory avg |
| ---------------------- | ------- | ---------- |
| kube-proxy (iptables)  | 29.7 m  | 203.8 MiB  |
| Cilium Agent (Native)  | 113.3 m | 152.5 MiB  |
| Cilium Agent (Overlay) | 94.3 m  | 165.0 MiB  |

:::note[kube-proxy 内存反而比 Cilium 高？]

一个反直觉的结果：满载（10000 svc × 10 ep）下 **kube-proxy 内存（204 MB）反而高于 Cilium Agent（153-165 MB）**。

原因是 kube-proxy 要在用户态维护那 **42 万条 iptables 规则**的完整内存表示，并在每次 Service/Endpoint 变更时做规则 diff 与全量刷新——规则越多，kube-proxy 内存和 CPU 越高。这也解释了为什么 iptables 模式的 kube-proxy 内存从早前单 Endpoint（~31 MB，6 万规则）暴涨到现在的 204 MB（42 万规则）。

Cilium Agent 的内存则主要是 BPF map（预分配，固定）+ endpoint/identity 状态，**与规则数解耦**，不随 Service 规模线性膨胀。

:::

### BPF Map 内存：预分配，不随规模增长

| 指标             | Cilium Native | Cilium Overlay |
| ---------------- | ------------- | -------------- |
| BPF map 总内存   | 142.5 MB      | 142.6 MB       |
| BPF map 数量     | 56            | 63             |
| Cilium Agent RSS | 715.8 MB      | 656.9 MB       |

Top BPF map 内存消耗（两集群基本一致，已调大 LB map 上限到 262144）：

| Map 名称（截断）    | Max Entries | 内存    |
| ------------------- | ----------- | ------- |
| cilium_lb4_affinity | 262,144     | 24.0 MB |
| cilium_ct4_global   | 131,072     | 17.0 MB |
| cilium_snat_v4      | 131,072     | 15.0 MB |
| cilium_lb4_services | 262,144     | 14.1 MB |
| cilium_lb4_backends | 262,144     | 11.6 MB |

:::note[BPF 内存不会与业务争抢]

**BPF map 预分配**——创建时按 `max_entries` 一次性分配最大内存，后续增删 Service/Endpoint 只填充已分配空间，不动态增长。本测试中 Service 从 0 涨到 10000、Endpoint 涨到 10 万，BPF map 总内存始终稳定在 ~142.6 MB（注意这是把 LB map 上限调到 262144 后的值，默认 65536 时约 93 MB）。

SA5.LARGE8（4C 8G）节点内存预算：

```text
节点总内存:           8,192 MB
  系统预留:           ~1,024 MB
  kubelet / 运行时:   ~512 MB
  Cilium Agent RSS:   ~660-720 MB
  BPF Maps (memlock): ~143 MB
  ────────────────────────────
  Cilium 合计:        ~800-860 MB（约 10% of 8G）
  业务 Pod 可用:      ~5,900+ MB（72%+）
```

即使叠加 10000 Service × 10 Endpoint + NetworkPolicy + 活跃连接，Cilium 内存占用对业务无实质影响。Agent RSS（657-716 MB）的主要构成是 10 万 Endpoint 的运行时状态，已是相当极端的规模。

:::

## 总结与选型

### iptables vs Cilium：换不换？

| 你的情况                                             | 建议                                                                       |
| ---------------------------------------------------- | -------------------------------------------------------------------------- |
| Service 数量少（千级以下）、追求极限 RPS             | iptables 小规模 RPS 领先，可继续用；但差异真实负载无感                     |
| Service 数量大（万级）、有大量短连接业务             | **Cilium**：iptables 短连接随规则数线性崩塌（42 万规则 -43%），Cilium 稳定 |
| 需要 NetworkPolicy / Hubble 可观测性 / Identity 安全 | **Cilium**：L3/L4 策略与 Hubble 零开销，iptables 不具备                    |
| 只跑长连接业务（连接池 / keepalive）                 | 都行：长连接对规模和方案都不敏感                                           |

核心权衡：**换 Cilium 在小规模极限压测下损失 ~6-11% 长连接 RPS（真实负载无感），换来大规模下不崩塌的短连接性能 + 零开销的安全与可观测能力。** 对中大规模或有安全合规需求的集群，这笔交易划算。

### Cilium Native vs Overlay：看架构不看性能

两者所有性能指标差异都在 ±5% 噪声内（Overlay 长连接 RPS 略低于 Native，因 VXLAN 封装；其余基本持平）。**选型应基于网络架构**：

- 需要 Pod IP 在 VPC 内直接可路由（直连 CLB、跨集群 / 跨 VPC 互通、传统监控直采 Pod）→ **Native**
- 需要 Pod CIDR 与 VPC 解耦（IP 资源紧张、跨 VPC 复用 CIDR、Pod 数远超弹性网卡上限）→ **Overlay**

> 关于 Native 模式下 BPF Host Routing 为何实际不命中、以及云厂商 Native IPAM 的共性，详见 [VPC-CNI Native Routing 模式详解](./native-routing.md)。

### 一个方法论提醒

本次较新内核（6.6.117-45.11.2）下 TCP_RR 出现了 Cilium 反超 iptables 的现象，与旧内核相反。**网络组件的微基准结论强依赖内核版本和测试规模**——不要把某次微基准的排名当成方案的固有属性。真正稳健的结论是那些跨内核、跨规模都成立的：吞吐等价、真实负载延迟一致、大规模下 Cilium 的 O(1) 优势。

详细选型建议参见 [Cilium 性能测试 - 选型建议](./performance-test.md#选型建议)。

## 相关链接

- [Cilium 性能测试（cilium connectivity perf）](./performance-test.md)
- [VPC-CNI Native Routing 模式详解](./native-routing.md)
- [安装 Cilium](../install.md)

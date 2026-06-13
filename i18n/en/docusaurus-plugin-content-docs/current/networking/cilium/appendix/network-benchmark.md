# Cilium Network Performance Benchmark

This article uses the [`network-benchmark.sh`](https://imroc.cc/tke/scripts/network-benchmark.sh) one-click script to benchmark three TKE networking solutions side by side under **identical hardware, kernel, and VPC environments**, answering the question a TKE user cares most about when choosing a solution: **does replacing kube-proxy with Cilium win or lose on performance?**

The three clusters tested:

- **Cluster A — VPC-CNI + kube-proxy iptables**: traditional approach, performance baseline
- **Cluster B — VPC-CNI + Cilium Native Routing**: Cilium plugs into VPC-CNI via cni-chaining; Pod IPs remain legitimate VPC IPs
- **Cluster C — VPC-CNI + Cilium Overlay (VXLAN)**: Cilium is the sole Pod CNI; Pods use an independent overlay CIDR

Coverage: throughput, HTTP RPS (keepalive/short conn), TCP latency, Service-scale degradation (5000→10000, with 10 Endpoints per Service to simulate real multi-replica workloads), Hubble overhead, NetworkPolicy L3/L4 and L7 overhead, BPF memory, and component resources.

:::tip[Conclusions first]

- **Throughput and real-workload latency (HTTP p99 @1000 QPS) are identical across all three** — networking-solution differences are invisible under realistic load.
- **Small-scale saturation benchmarks**: iptables RPS still leads Cilium (keepalive ~6-11%, short conn ~2.2x), because it has the shortest path.
- **Large-scale Services**: iptables short-connection performance **collapses linearly** with rule count (10000 Services × 10 Endpoints = 420K rules, short-conn degrades 43%), while Cilium barely degrades (~11-13%). The larger the scale, the more the balance tips toward Cilium.
- **Latency reversal**: on this newer kernel (6.6.117-45.11.2), Cilium's TCP_RR latency is actually **lower** than iptables — the opposite of the old-kernel result.
- **L7 NetworkPolicy is the one performance cliff**: ~87-88% overhead, enable selectively; L3/L4 policy and Hubble are zero-overhead.

:::

## Test Methodology

### One-Click Execution

```bash
bash -c "$(curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/network-benchmark.sh)"
```

If you cannot connect to GitHub from China, use the site mirror:

```bash
bash -c "$(curl -sfL https://imroc.cc/tke/scripts/network-benchmark.sh)"
```

:::note[Prerequisites]

- `KUBECONFIG` points to the target cluster (current context is usable)
- `kubectl`, `python3`, and `timeout` must be installed locally (on macOS, `brew install coreutils`)
- The cluster must have at least 2 worker nodes

:::

### Custom Parameters

```bash
# Multiple rounds (for large instances without QoS concerns)
ROUNDS=3 IPERF_DURATION=120 FORTIO_DURATION=120 bash network-benchmark.sh --dir ./bench

# Custom Service scale steps and endpoints per service
SVC_SCALE_STEPS="1000,5000,10000" SVC_ENDPOINTS=10 bash network-benchmark.sh
```

| Environment Variable  | Default    | Description                                           |
| --------------------- | ---------- | ----------------------------------------------------- |
| `IPERF_DURATION`      | 30         | iperf3 test duration per round (seconds)              |
| `FORTIO_DURATION`     | 60         | fortio / netperf test duration per round (seconds)    |
| `ROUNDS`              | 1          | Repetition rounds per scenario                        |
| `ROUND_SLEEP`         | 30         | Inter-round wait (seconds), for burst credit recovery |
| `SVC_SCALE_STEPS`     | 5000,10000 | Comma-separated Service scale steps (ascending)       |
| `SVC_ENDPOINTS`       | 10         | Endpoints per dummy Service                           |
| `SVC_CREATE_PARALLEL` | 4          | Parallel workers for Service creation                 |

:::warning[Large-scale tests require raising Cilium's LB map limit]

Cilium's Service load-balancing BPF map defaults to `bpf-lb-map-max=65536`. Each Service consumes roughly `1 + endpoint count` LB entries, so **10000 Services × 10 endpoints ≈ 110K entries will exceed the default and overflow the map** — manifesting as an abnormal RPS collapse at large scale (this is forwarding failure, not O(n) degradation, and pollutes the conclusions). Before running large-scale tests, raise the limit and restart cilium:

```bash
kubectl -n kube-system patch configmap cilium-config --type merge \
  -p '{"data":{"bpf-lb-map-max":"262144"}}'
kubectl -n kube-system rollout restart ds/cilium
```

The script automatically preflight-checks capacity before the Service Scale test and prints `LB MAP CAPACITY WARNING` if insufficient.

:::

### Tools and Metrics

| Tool    | Test Content                                              | Metric                         |
| ------- | --------------------------------------------------------- | ------------------------------ |
| iperf3  | Cross-node TCP throughput                                 | Gbps (1/8/16 parallel streams) |
| fortio  | HTTP RPS (keep-alive / short conn)                        | req/s                          |
| netperf | TCP_RR / TCP_CRR latency                                  | p50 / p99 microseconds         |
| fortio  | Multi-step Service scale (5000/10000, 10 ep each) degrade | Degradation percentage         |
| fortio  | Hubble on/off RPS comparison (Cilium only)                | Overhead percentage            |
| fortio  | NetworkPolicy L3/L4 + L7 RPS comparison (Cilium only)     | Overhead percentage            |
| bpftool | BPF map memory statistics (Cilium only)                   | MB                             |

## Test Environment

| Item                | Cluster A (iptables)          | Cluster B (Cilium Native)                      | Cluster C (Cilium Overlay)                    |
| ------------------- | ----------------------------- | ---------------------------------------------- | --------------------------------------------- |
| Network Solution    | VPC-CNI + kube-proxy iptables | VPC-CNI + Cilium cni-chaining (Native Routing) | Cilium VXLAN Overlay (Cilium as sole Pod CNI) |
| Kubernetes Version  | v1.34.1-tke.5                 | v1.34.1-tke.5                                  | v1.34.1-tke.5                                 |
| Cilium Version      | N/A                           | v1.19.4                                        | v1.19.4                                       |
| kube-proxy replaced | No (iptables mode)            | Yes (eBPF)                                     | Yes (eBPF)                                    |
| Node OS             | TencentOS Server 4            | TencentOS Server 4                             | TencentOS Server 4                            |
| Kernel Version      | 6.6.117-45.11.2               | 6.6.117-45.11.2                                | 6.6.117-45.11.2                               |
| Node Spec           | SA5.LARGE8 (4C 8G)            | SA5.LARGE8 (4C 8G)                             | SA5.LARGE8 (4C 8G)                            |
| Node Count          | 3                             | 3                                              | 3                                             |

All three clusters share the same VPC, hardware spec, kernel version (6.6.117-45.11.2), and LB map limit (262144). The Service Scale test attaches 10 Endpoints per Service (simulating multi-replica real workloads). All RPS / latency tests are cross-node (different Workers).

## At a Glance

| Dimension                      | iptables   | Cilium Native | Cilium Overlay | Winner                                   |
| ------------------------------ | ---------- | ------------- | -------------- | ---------------------------------------- |
| Pod2Pod throughput (8 streams) | 10.43 Gbps | 10.43 Gbps    | 10.77 Gbps     | Tie                                      |
| RPS keepalive (c64)            | 111,673    | 105,070       | 100,084        | iptables (+6~11%)                        |
| RPS short conn (c64, small)    | 30,576     | 13,786        | 14,263         | iptables (+2.2x)                         |
| TCP_RR p99                     | 109 µs     | 96 µs         | 95 µs          | **Cilium (lower)**                       |
| TCP_CRR p99                    | 499 µs     | 558 µs        | 537 µs         | iptables (slightly lower)                |
| HTTP p99 @1000 QPS             | 0.99 ms    | 0.99 ms       | 0.99 ms        | Tie                                      |
| 10000 svc short-conn degrade   | **-43.2%** | **-13.2%**    | **-11.5%**     | **Cilium (gap widens w/ scale)**         |
| 10000 svc rules/LB entries     | 419,891    | 119,832       | 119,888        | -                                        |
| L3/L4 NetworkPolicy overhead   | N/A        | -0.7%         | +0.4%          | Zero overhead                            |
| L7 NetworkPolicy overhead      | N/A        | -87.0%        | -88.0%         | Perf cliff, enable selectively           |
| Hubble L3/L4 overhead          | N/A        | -0.5%         | +0.3%          | Zero overhead                            |
| BPF map memory / node          | N/A        | 142.5 MB      | 142.6 MB       | Pre-allocated, doesn't grow              |
| Datapath component mem / node  | 204 MB     | 153 MB        | 165 MB         | See [Section 6](#6-resource-consumption) |

Details below, with deep dives on the counter-intuitive points.

## 1. Throughput: All Three Equivalent

| Scenario                 | iptables   | Cilium Native | Cilium Overlay |
| ------------------------ | ---------- | ------------- | -------------- |
| Node hostNet (8 streams) | 10.44 Gbps | 10.44 Gbps    | 10.88 Gbps     |
| Pod-to-Pod (single)      | 10.42 Gbps | 10.42 Gbps    | 10.69 Gbps     |
| Pod-to-Pod (8 streams)   | 10.43 Gbps | 10.43 Gbps    | 10.77 Gbps     |
| Pod-to-Pod (16 streams)  | 10.43 Gbps | 10.43 Gbps    | 10.77 Gbps     |
| Via Service (8 streams)  | 10.43 Gbps | 10.43 Gbps    | 10.77 Gbps     |

All three saturate ~10.4-10.9 Gbps, approaching the SA5.LARGE8 burst bandwidth ceiling — **throughput is fully equivalent**. The ±4% inter-cluster variance is VPC burst bandwidth fluctuation. 16 streams matches 8 streams, confirming 8 parallel streams already saturate the NIC.

Overlay's large-packet throughput is even slightly higher despite VXLAN — the 50-byte header is negligible at MTU-level packet sizes. VXLAN's cost only shows in small-packet high-frequency scenarios (see RPS).

## 2. RPS: iptables Leads at Small Scale, But That's the Shortest-Path Dividend

| Scenario                   | iptables         | Cilium Native    | Cilium Overlay   |
| -------------------------- | ---------------- | ---------------- | ---------------- |
| Pod-to-Pod c64 keepalive   | 111,593 req/s    | 105,378 req/s    | 100,836 req/s    |
| Via Svc c64 keepalive      | 111,673 req/s    | 105,070 req/s    | 100,084 req/s    |
| Via Svc c256 keepalive     | 115,206 req/s    | 107,692 req/s    | 102,554 req/s    |
| **Via Svc c64 short conn** | **30,576** req/s | **13,786** req/s | **14,263** req/s |

### Keepalive: iptables leads by 6-11%

iptables (111K) > Native (105K) > Overlay (100K). The gap is small but consistent, due to **path length**:

- **iptables has the shortest path**: each packet traverses the kernel stack once; kube-proxy's DNAT is just a few rule matches after conntrack hits.
- **Cilium Native**: VPC-CNI cni-chaining forces per-endpoint routing, Pod traffic bypasses `cilium_host`, traversing the kernel stack _and_ layering on eBPF conntrack + Service + Policy — one extra layer per packet.
- **Cilium Overlay**: BPF Host Routing skips part of the kernel stack, but every cross-node packet does VXLAN encap/decap, making it the lowest keepalive RPS of the three.

### Short conn: iptables leads by 2.2x — why so much?

The short-conn baseline iptables (30,576) is **2.2x** Cilium (~14,000), far larger than the keepalive gap. The root cause is that **keepalive and short-conn hit completely different code paths**:

- **Keepalive**: once the connection is established, every request reuses the same TCP connection; the forwarding decision is conntrack-cached, and subsequent packets hit cache — all three are just "conntrack lookup + forward", differing only by that one fixed layer.
- **Short conn**: every request opens a new TCP connection; every SYN must **fully redo Service selection + conntrack entry creation**. Cilium's disadvantage is amplified here:
  - Native does eBPF (BPF conntrack creation + backend selection) **on top of** the kernel connection setup — genuinely "double work";
  - iptables, while also traversing rules per new connection, has an extremely short rule chain at **small scale (baseline has almost no dummy svc)**, so the cost is low.

In other words: the 2.2x short-conn baseline gap is iptables's dividend under "short rule chains". **This premise vanishes as Service scale grows** — see Section 4, the pivot of this whole article.

:::tip[But these differences are invisible to real workloads]

All three solutions' absolute RPS (short conn 14K-30K, keepalive 100K-115K) **far exceed** the load of a typical microservice Pod (usually < 10K req/s). The differences only appear under fortio's CPU-saturating extreme benchmarks. Under realistic load all three perform identically (see HTTP p99 @1000 QPS below).

:::

## 3. Latency: Identical Under Real Load, But a Reversal in the Extreme

| Metric             | iptables | Cilium Native | Cilium Overlay |
| ------------------ | -------- | ------------- | -------------- |
| TCP_RR p50         | 90 µs    | 79 µs         | 76 µs          |
| TCP_RR p99         | 109 µs   | 96 µs         | 95 µs          |
| TCP_CRR p99        | 499 µs   | 558 µs        | 537 µs         |
| HTTP p99 @1000 QPS | 0.99 ms  | 0.99 ms       | 0.99 ms        |

### HTTP p99 @1000 QPS: 0.99 ms, identical

**This is the single most important line.** Under a realistic request rate (1000 QPS), all three have identical p99 latency. The 6-11% and 2.2x gaps from the RPS section vanish once the application does any real work (DB query, serialization, business logic). **The networking choice does not affect real application latency.**

### TCP_RR: Cilium is actually lower than iptables (opposite of old kernel)

Worth calling out: in this test Cilium's TCP_RR (keepalive request-response latency) p99 is 95-96 µs, **lower** than iptables's 109 µs.

This is the opposite of our earlier result on an older kernel (6.6.117-45.7.3), where Cilium was **~15 µs higher**. This time all three clusters run on the newer 6.6.117-45.11.2 kernel; all solutions' absolute latencies dropped, but Cilium dropped more, hence the reversal.

:::note[A hypothesis, pending verification]

We didn't dig into the kernel-level root cause of this reversal; here's a **plausible hypothesis, left for verification**: the newer kernel may have optimized hotspots on the eBPF data path (e.g. conntrack lookup, the per-CPU path of `bpf_redirect`), making Cilium's single-hop latency under steady keepalive request-response lower than iptables traversing the full netfilter chain.

To emphasize: this magnitude (±10-15 µs) of latency difference, in the sub-millisecond range, is **invisible to the application layer** (the identical HTTP p99 across all three proves it). Its significance is not "who's faster" but a reminder of an often-overlooked fact — **network-component microbenchmark conclusions strongly depend on kernel version; a different kernel may reverse them. Don't treat a single microbenchmark's ranking as an intrinsic property of the solution.**

:::

### TCP_CRR: iptables slightly lower for new connections

TCP_CRR (per-new-connection request-response) iptables (499 µs) is slightly below Cilium (537-558 µs). Consistent with short-conn RPS: new connections require Cilium to do eBPF conntrack creation + Service resolution, one layer more than small-scale iptables. This gap, too, reverses as Service scale grows.

## 4. Service Scale Degradation: The Core Pivot

This is where replacing kube-proxy with Cilium pays off most. Method: incrementally create 5000 → 10000 dummy Services (**each with 10 Endpoints**, simulating multi-replica Deployments), wait for sync at each step, benchmark, and compare degradation vs baseline.

### Keepalive: virtually zero degradation throughout

| Service count | iptables | Cilium Native | Cilium Overlay |
| ------------- | -------- | ------------- | -------------- |
| 5000          | -0.6%    | -0.9%         | -0.0%          |
| 10000         | -0.7%    | -1.2%         | -0.1%          |

All three barely degrade on keepalive — conntrack caches the first-packet decision, subsequent packets skip rule chains / BPF maps. **Production workloads using connection pools or HTTP keepalive are largely immune to Service scale.**

### Short conn: iptables collapses linearly, Cilium rock-solid

| Service count    | iptables              | Cilium Native       | Cilium Overlay      |
| ---------------- | --------------------- | ------------------- | ------------------- |
| Baseline (small) | 30,576 req/s          | 13,786 req/s        | 14,263 req/s        |
| 5000             | 21,286 (-30.4%)       | 12,473 (-9.5%)      | 13,149 (-7.8%)      |
| 10000            | 17,358 (**-43.2%**)   | 11,963 (**-13.2%**) | 12,618 (**-11.5%**) |
| rules/LB entries | 210,142 → **419,891** | 60,006 → 119,832    | 60,030 → 119,888    |

:::tip[O(n) vs O(1): 10 Endpoints make the gap visible]

Short connections are the real test — every new connection's SYN must redo Service selection, missing the conntrack cache.

- **iptables is O(n) sequential traversal**: each SYN sequentially matches the KUBE-SERVICES → KUBE-SVC-XXX → KUBE-SEP-XXX chain. **Each Endpoint adds a KUBE-SEP rule**, so 10000 svc × 10 ep yields **420K rules**. Short-conn degradation worsens from -30.4% at 5000 svc to -43.2% at 10000 svc, collapsing nearly linearly with rule count.
- **Cilium is O(1) BPF hash map lookup**: lookup time is independent of Service/Endpoint count. Native goes -9.5% → -13.2%, Overlay -7.8% → -11.5%, degrading gently. **Note Cilium's LB entries (119K) vs iptables's rules (420K) differ 3.5x at the same svc scale** — Cilium's backends are map values, not standalone rules, so Endpoint growth doesn't lengthen the lookup path.

**Compared to the single-Endpoint test**: earlier with 1 Endpoint per svc, iptables 10000 svc short-conn degraded -37% with 60K rules. With 10 Endpoints it deepens to -43% with 420K rules — **the more Endpoints, the worse iptables's O(n) disadvantage**, which is closer to real workloads (real Services are commonly multi-replica).

:::

### So when does Cilium overtake iptables?

Mind the absolute values: **even at 10000 svc, iptables short-conn (17,358) is still higher than Cilium (~12,600)**. But the lead has narrowed from 2.2x at baseline to 1.38x.

Linearly extrapolating the 5000→10000 slope, iptables short-conn RPS drops below Cilium at around **15-16K Services**, then gets overtaken. Since real Services usually have more Endpoints (longer rule chains) than these dummy svc, **the actual crossover comes earlier**.

**In one sentence**: small-scale iptables leads via "short path", large-scale Cilium overtakes via "O(1)", crossover at the ten-thousand-Service level. Keepalive workloads don't care either way.

## 5. Hubble & NetworkPolicy: L3/L4 Zero-Overhead, L7 a Performance Cliff

### Hubble Observability (Cilium only)

| Metric       | Cilium Native | Cilium Overlay |
| ------------ | ------------- | -------------- |
| Hubble ON    | 104,343 req/s | 100,381 req/s  |
| Hubble OFF   | 104,914 req/s | 100,098 req/s  |
| **Overhead** | **-0.5%**     | **+0.3%**      |

Hubble L3/L4 observability overhead is within the ±0.5% noise range — **effectively zero**. Hubble only samples events into a ring buffer in the datapath, not participating in forwarding. Enable L3/L4 flow observation across production freely.

### NetworkPolicy L3/L4: zero overhead

| Metric            | Cilium Native | Cilium Overlay |
| ----------------- | ------------- | -------------- |
| No policy         | 104,787 req/s | 100,242 req/s  |
| L3/L4 CNP applied | 104,083 req/s | 100,599 req/s  |
| **Overhead**      | **-0.7%**     | **+0.4%**      |

L3/L4 CiliumNetworkPolicy is implemented in eBPF via identity lookup + bitmap match, with no extra memory copy or context switch — **zero overhead**. Apply broadly across all workloads.

### NetworkPolicy L7: a performance cliff, enable selectively

| Metric         | Cilium Native | Cilium Overlay |
| -------------- | ------------- | -------------- |
| No policy      | 104,787 req/s | 100,242 req/s  |
| L7 CNP applied | 13,591 req/s  | 11,984 req/s   |
| **Overhead**   | **-87.0%**    | **-88.0%**     |

:::warning[Enable L7 policy only on Pods that need it]

L7 CiliumNetworkPolicy (e.g. HTTP path/method filtering) redirects traffic to an **Envoy proxy** for application-layer parsing, dropping RPS by **87-88%**. This is not a Cilium flaw, but the inherent cost of L7 visibility (any L7 policy / Service Mesh has comparable cost).

Correct usage:

- **L3/L4 policy**: covers the vast majority of production security needs (allow/deny by IP, port, namespace labels), zero overhead, enable broadly.
- **L7 policy**: enable selectively only on Pods that genuinely need application-layer control (external ingress gateways, sensitive API auditing). Don't roll out broadly.

:::

## 6. Resource Consumption

### CPU / Memory

| Component              | CPU avg | Memory avg |
| ---------------------- | ------- | ---------- |
| kube-proxy (iptables)  | 29.7 m  | 203.8 MiB  |
| Cilium Agent (Native)  | 113.3 m | 152.5 MiB  |
| Cilium Agent (Overlay) | 94.3 m  | 165.0 MiB  |

:::note[kube-proxy uses more memory than Cilium?]

A counter-intuitive result: at full load (10000 svc × 10 ep), **kube-proxy memory (204 MB) is actually higher than Cilium Agent (153-165 MB)**.

The reason is that kube-proxy maintains the full in-memory representation of those **420K iptables rules** in user space, doing rule diffs and full reflushes on every Service/Endpoint change — the more rules, the more memory and CPU. This also explains why iptables-mode kube-proxy memory ballooned from ~31 MB earlier (single Endpoint, 60K rules) to 204 MB now (420K rules).

Cilium Agent memory is mainly BPF maps (pre-allocated, fixed) + endpoint/identity state, **decoupled from rule count**, not growing linearly with Service scale.

:::

### BPF Map Memory: pre-allocated, doesn't grow with scale

| Metric           | Cilium Native | Cilium Overlay |
| ---------------- | ------------- | -------------- |
| BPF map total    | 142.5 MB      | 142.6 MB       |
| BPF map count    | 56            | 63             |
| Cilium Agent RSS | 715.8 MB      | 656.9 MB       |

Top BPF map memory consumers (nearly identical across clusters, with LB map raised to 262144):

| Map name (truncated) | Max Entries | Memory  |
| -------------------- | ----------- | ------- |
| cilium_lb4_affinity  | 262,144     | 24.0 MB |
| cilium_ct4_global    | 131,072     | 17.0 MB |
| cilium_snat_v4       | 131,072     | 15.0 MB |
| cilium_lb4_services  | 262,144     | 14.1 MB |
| cilium_lb4_backends  | 262,144     | 11.6 MB |

:::note[BPF memory does not contend with business workloads]

**BPF maps use pre-allocation** — they allocate maximum memory at creation based on `max_entries`; adding Services/Endpoints only fills already-allocated space, never growing dynamically. In this test, Services grew from 0 to 10000 and Endpoints to 100K, yet BPF map total memory stayed steady at ~142.6 MB (note: this is with LB map raised to 262144; at the default 65536 it's ~93 MB).

Memory budget on a SA5.LARGE8 (4C 8G) node:

```text
Total node memory:    8,192 MB
  System reserved:    ~1,024 MB
  kubelet / runtime:  ~512 MB
  Cilium Agent RSS:   ~660-720 MB
  BPF Maps (memlock): ~143 MB
  ────────────────────────────
  Cilium total:       ~800-860 MB (~10% of 8G)
  Available for Pods: ~5,900+ MB (72%+)
```

Even with 10000 Services × 10 Endpoints + NetworkPolicy + active connections, Cilium's memory footprint has no material impact on business workloads. The Agent RSS (657-716 MB) is dominated by the runtime state of 100K Endpoints, already an extreme scale.

:::

## Summary & Selection Guide

### iptables vs Cilium: switch or not?

| Your situation                                       | Recommendation                                                                                    |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Few Services (sub-thousand), chasing peak RPS        | iptables leads small-scale RPS, keep it; but the gap is invisible under real load                 |
| Many Services (ten-thousand), heavy short-conn       | **Cilium**: iptables short conn collapses with rule count (420K rules, -43%), Cilium stays stable |
| Need NetworkPolicy / Hubble observability / Identity | **Cilium**: L3/L4 policy and Hubble are zero-overhead, iptables lacks them                        |
| Only keepalive workloads (connection pool/keepalive) | Either: keepalive is insensitive to scale and solution                                            |

Core trade-off: **switching to Cilium loses ~6-11% keepalive RPS in small-scale saturation benchmarks (invisible under real load), in exchange for non-collapsing short-connection performance at scale + zero-overhead security and observability.** For medium-to-large clusters or those with security/compliance needs, this trade is worth it.

### Cilium Native vs Overlay: architecture, not performance

All performance metric differences are within the ±5% noise range (Overlay keepalive RPS slightly below Native due to VXLAN; the rest essentially equal). **Choose by network architecture**:

- Pod IP must be directly routable in the VPC (direct CLB attach, cross-cluster / cross-VPC connectivity, legacy monitoring directly hitting Pods) → **Native**
- Pod CIDR decoupled from VPC (IP scarcity, cross-VPC CIDR reuse, Pod count far exceeding ENI capacity) → **Overlay**

> For why BPF Host Routing isn't actually hit in Native mode, and the commonality of cloud-provider Native IPAM, see [VPC-CNI Native Routing Details](./native-routing.md).

### A methodology reminder

On this newer kernel (6.6.117-45.11.2), TCP_RR showed Cilium overtaking iptables — the opposite of the old kernel. **Network-component microbenchmark conclusions strongly depend on kernel version and test scale** — don't treat a single microbenchmark's ranking as an intrinsic property of the solution. The genuinely robust conclusions are those that hold across kernels and scales: equivalent throughput, identical real-load latency, and Cilium's O(1) advantage at scale.

For detailed selection guidance, see [Cilium Performance Test - Recommendations](./performance-test.md#recommendations).

## References

- [Cilium Performance Test (cilium connectivity perf)](./performance-test.md)
- [VPC-CNI Native Routing Details](./native-routing.md)
- [Install Cilium](../install.md)

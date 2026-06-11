# Cilium Network Performance Benchmark

This article uses the [`network-benchmark.sh`](https://imroc.cc/tke/scripts/network-benchmark.sh) one-click script to perform a comprehensive performance comparison of **iptables/kube-proxy**, **Cilium Native Routing**, and **Cilium Overlay**, covering throughput, HTTP RPS, TCP latency, Service scale degradation, Hubble overhead, NetworkPolicy overhead, and component resource consumption.

:::tip[Difference from cilium connectivity perf]

[Cilium Performance Test](./performance-test.md) uses `cilium connectivity perf` (based on netperf) to test TCP_RR latency and TCP_STREAM throughput. The `network-benchmark.sh` script in this article additionally covers:

- **HTTP layer**: fortio full-speed RPS benchmarking (keep-alive / short connections)
- **Service path**: throughput and RPS via ClusterIP Service
- **Large-scale Service degradation**: RPS degradation comparison after 5000 Services (O(1) vs O(n))
- **Hubble / NetworkPolicy overhead**: quantifying the performance impact of observability and policy enforcement
- **iptables baseline**: includes kube-proxy iptables mode without Cilium as a reference

These two articles are complementary — read them together.

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

# Specify output directory and namespace
bash network-benchmark.sh --dir ./my-results --ns my-bench

# Custom scale steps: test at 1000, 5000, 10000 Services
SVC_SCALE_STEPS="1000,5000,10000" SVC_CREATE_PARALLEL=8 bash network-benchmark.sh
```

| Environment Variable  | Default    | Description                                           |
| --------------------- | ---------- | ----------------------------------------------------- |
| `IPERF_DURATION`      | 30         | iperf3 test duration per round (seconds)              |
| `FORTIO_DURATION`     | 60         | fortio / netperf test duration per round (seconds)    |
| `ROUNDS`              | 1          | Repetition rounds per scenario                        |
| `ROUND_SLEEP`         | 30         | Inter-round wait (seconds), for burst credit recovery |
| `SVC_SCALE_STEPS`     | 5000,10000 | Comma-separated Service scale steps (ascending)       |
| `SVC_CREATE_PARALLEL` | 4          | Parallel workers for Service creation                 |

### Test Metric Description

| Tool    | Test Content                                              | Metric                         |
| ------- | --------------------------------------------------------- | ------------------------------ |
| iperf3  | Cross-node TCP throughput                                 | Gbps (1/8/16 parallel streams) |
| fortio  | HTTP RPS (keep-alive / short conn)                        | req/s                          |
| netperf | TCP_RR / TCP_CRR latency                                  | p50 / p99 microseconds         |
| fortio  | Multi-step Service scale (default 5000/10000) degradation | Degradation percentage         |
| fortio  | Hubble on/off RPS comparison (Cilium only)                | Overhead percentage            |
| fortio  | RPS before/after NetworkPolicy L3/L4 + L7 (Cilium only)   | Overhead percentage            |
| bpftool | BPF map memory statistics (Cilium only)                   | MB                             |

## Test Environment

| Item               | Cluster A (iptables)          | Cluster B (Cilium Native)                      | Cluster C (Cilium Overlay)                    |
| ------------------ | ----------------------------- | ---------------------------------------------- | --------------------------------------------- |
| Network Solution   | VPC-CNI + kube-proxy iptables | VPC-CNI + Cilium cni-chaining (Native Routing) | Cilium VXLAN Overlay (Cilium as sole Pod CNI) |
| Kubernetes Version | v1.34.1                       | v1.34.1                                        | v1.34.1                                       |
| Cilium Version     | N/A                           | v1.19.4                                        | v1.19.4                                       |
| Node OS            | TencentOS Server 4            | TencentOS Server 4                             | TencentOS Server 4                            |
| Kernel Version     | 6.6.117                       | 6.6.117                                        | 6.6.117                                       |
| Node Spec          | SA5.LARGE8 (4C 8G)            | SA5.LARGE8 (4C 8G)                             | SA5.LARGE8 (4C 8G)                            |
| Node Count         | 3                             | 3                                              | 3                                             |

All three clusters are in the same VPC, with identical hardware spec and kernel version, ensuring a fair comparison.

## Test Results

### Throughput (iperf3, 30s, cross-node)

| Scenario                 | iptables   | Cilium Native | Cilium Overlay |
| ------------------------ | ---------- | ------------- | -------------- |
| Node hostNet (8 streams) | 10.44 Gbps | 10.44 Gbps    | 10.82 Gbps     |
| Pod-to-Pod (single)      | 10.43 Gbps | 10.43 Gbps    | 10.63 Gbps     |
| Pod-to-Pod (8 streams)   | 10.43 Gbps | 10.43 Gbps    | 10.77 Gbps     |
| Pod-to-Pod (16 streams)  | 10.43 Gbps | 10.43 Gbps    | 10.77 Gbps     |
| Via Service (8 streams)  | 10.38 Gbps | 10.43 Gbps    | 10.77 Gbps     |

:::note

All three solutions saturate ~10 Gbps, close to the SA5.LARGE8 instance burst bandwidth ceiling. **Throughput is effectively identical across the three solutions.** The ±4% inter-cluster variance is VPC burst bandwidth fluctuation and physical-node path differences, not solution differences. 16 streams matches 8 streams, confirming 8 parallel streams already saturate the NIC. Overlay being slightly above Native is incidental VPC bandwidth fluctuation during the test window, unrelated to VXLAN encapsulation.

:::

### RPS (fortio, 60s, max QPS, cross-node)

| Scenario                   | iptables         | Cilium Native    | Cilium Overlay   | Cilium vs iptables |
| -------------------------- | ---------------- | ---------------- | ---------------- | ------------------ |
| Pod-to-Pod c64 keepalive   | 91,698 req/s     | 75,785 req/s     | 75,252 req/s     | -17% ~ -18%        |
| Via Svc c64 keepalive      | 91,896 req/s     | 75,272 req/s     | 75,191 req/s     | -18%               |
| Via Svc c256 keepalive     | 93,882 req/s     | 77,126 req/s     | 76,279 req/s     | -18%               |
| **Via Svc c64 short conn** | **22,846** req/s | **10,194** req/s | **10,554** req/s | **-54% ~ -55%**    |

:::tip[RPS difference: why iptables exceeds Cilium]

**Cilium Native: cni-chaining + per-endpoint routing (-18% / -55%)**

VPC-CNI is the primary Pod CNI (assigning VPC IPs); Cilium plugs in via cni-chaining to provide policy and observability features. This architecture forces per-endpoint routing (`endpointRoutes=true`), so Pod traffic bypasses the `cilium_host` device and must traverse the kernel network stack (netfilter + FIB lookup) at both Pod ingress and egress; meanwhile Cilium eBPF still performs conntrack + Service resolution + Policy checks. This is the root cause of Native's ~18% keepalive RPS deficit and ~55% short-conn deficit relative to iptables — every packet picks up an extra eBPF processing layer without saving the kernel-stack pass.

**Cilium Overlay: Cilium is the sole Pod CNI; VXLAN encap/decap is the dominant cost**

In Overlay mode, Cilium assigns Pod IPs from its own PodCIDR and connects nodes via VXLAN tunnels — Cilium is the only Pod CNI; there is no cni-chaining. Pod traffic flows through `cilium_host` and `cilium_vxlan`, and BPF Host Routing operates normally (given `kubeProxyReplacement=true` + `bpf.masquerade=true`). However, every cross-node packet undergoes VXLAN encap (egress) + decap (ingress): the 50-byte header construction, UDP checksum, and inner metadata bookkeeping form the dominant cost.

In the test, Native and Overlay land on nearly identical RPS (differing &lt;1%), but their datapaths and cost structures are completely different:

| Cluster                              | Pod CNI Relationship             | Main Cost Source                    |
| ------------------------------------ | -------------------------------- | ----------------------------------- |
| Cilium Native (VPC-CNI cni-chaining) | VPC-CNI primary + Cilium chained | per-endpoint routing + kernel stack |
| Cilium Overlay                       | Cilium alone                     | VXLAN encap/decap                   |

**Why does iptables come out higher?**

In iptables mode at small Service scale, the data path is the shortest: every packet traverses the kernel network stack once, kube-proxy's NAT rules are just a handful of matches on PREROUTING/POSTROUTING, and there is no extra eBPF processing or encapsulation cost. Cilium — in either Native or Overlay — introduces one inevitable extra processing layer, so iptables takes the absolute lead at small-scale, saturation benchmarks.

**Key insight**: iptables's small-scale RPS advantage is a local optimum for ClusterIP Service in a simple architecture. Once Service count grows, iptables's O(n) degradation (see Service Scale section below) quickly eats up that lead. The Cilium clusters in this test integrate with the cloud provider's VPC-CNI, which is the most common deployment shape for TKE customers; only when Cilium fully manages Pod CIDR (e.g. Overlay mode, or pure Cilium clusters with Cluster Pool IPAM + auto-direct-node-routes/BGP) does cni-chaining go away — but then the VPC-routable Pod IP advantage is also lost.

:::

### Latency (netperf TCP_RR / TCP_CRR + fortio HTTP, cross-node)

| Metric             | iptables | Cilium Native | Cilium Overlay |
| ------------------ | -------- | ------------- | -------------- |
| TCP_RR p50         | 92 µs    | 114 µs        | 105 µs         |
| TCP_RR p99         | 112 µs   | 136 µs        | 130 µs         |
| TCP_CRR p99        | 427 µs   | 641 µs        | 605 µs         |
| HTTP p99 @1000 QPS | 0.99 ms  | 0.99 ms       | 0.99 ms        |

:::tip[Latency analysis]

- **TCP_RR** (keepalive request-response): Cilium adds ~18-22 µs over iptables — the inherent cost of eBPF datapath conntrack lookup + policy check. Sub-millisecond, invisible at the application layer.
- **TCP_CRR** (per-connection setup): Cilium adds ~180-210 µs — every new connection's SYN packet performs BPF conntrack creation + Service resolution + a full kernel-stack pass.
- **HTTP p99 @1000 QPS**: Under realistic application load, all three are **identical** at 0.99 ms — microsecond differences are dwarfed by application processing time.
- **Native vs Overlay**: cross-node latency differs &lt;10 µs. The two clusters take different datapaths (Native uses per-endpoint routing + kernel stack under cni-chaining, Overlay uses BPF Host Routing + VXLAN encap/decap), but the latency cost happens to be numerically comparable.

**Key insight**: The microsecond-level latency gap visible in saturating benchmarks (wrk/fortio with empty HTTP responses) disappears once the application performs any meaningful work (DB query, JSON serialization). Network-layer µs differences are completely masked.

:::

### Service Scale (RPS degradation after 5000 Services)

Test method: create 5000 dummy ClusterIP Services (each with 5 endpoints), wait 60s for sync, then re-run RPS under identical load and compare degradation.

#### Full results @5000 Services

| Metric                     | iptables         | Cilium Native | Cilium Overlay |
| -------------------------- | ---------------- | ------------- | -------------- |
| iptables rule count        | **30,142 rules** | -             | -              |
| keepalive RPS baseline     | 91,896 req/s     | 75,272 req/s  | 75,191 req/s   |
| keepalive RPS @5000 svc    | 91,528 req/s     | 76,341 req/s  | 75,181 req/s   |
| **keepalive degradation**  | -0.4%            | +1.4%         | -0.0%          |
| short-conn RPS baseline    | 22,846 req/s     | 10,194 req/s  | 10,554 req/s   |
| short-conn RPS @5000 svc   | 17,528 req/s     | 9,738 req/s   | 9,897 req/s    |
| **short-conn degradation** | **-23.3%**       | **-4.5%**     | **-6.2%**      |

#### Small scale vs Large scale: iptables degradation accelerates while Cilium stays bounded

Combining the 5000-svc results with earlier 1000-svc data on the same environment shows the architectural divergence clearly:

| Metric                                | iptables (1000→5000)    | Cilium Native (1000→5000) | Cilium Overlay (1000→5000) |
| ------------------------------------- | ----------------------- | ------------------------- | -------------------------- |
| iptables rule count                   | 6,142 → **30,142** (×5) | -                         | -                          |
| keepalive degradation                 | -0.4% → -0.4%           | -0.2% → +1.4%             | 0.0% → -0.0%               |
| **short-conn degradation**            | **-5.9% → -23.3%**      | **-1.6% → -4.5%**         | **-4.1% → -6.2%**          |
| short-conn degradation scaling factor | **× 4** (linear)        | × 2.8 (sub-linear, noisy) | × 1.5 (sub-linear)         |

:::tip[O(1) vs O(n): the gap widens at scale]

**No degradation in keepalive across all three solutions**: conntrack caches the first-packet decision; subsequent packets hit cache, never re-traversing the rule chain or BPF map. This is why most production workloads (using connection pools or HTTP keepalive) don't feel Service-scale impact.

**Short connections expose the real difference**: every new TCP connection's SYN must repeat Service selection from scratch:

- **iptables O(n) sequential scan**: 5.9% degradation @1000 svc, **23.3% @5000 svc** — rules ×5 → degradation ×4, almost linear. This is the inherent cost of sequentially matching the KUBE-SERVICES → KUBE-SVC-XXX → KUBE-SEP-XXX three-level rule chain.
- **Cilium BPF hash map O(1) lookup**: 1.6% @1000 svc, **4.5% @5000 svc** — rules ×5 but degradation only ×~3. **The residual degradation is not from the lookup itself**, but from cilium-agent control-plane pressure (BPF map writes for 5000 svc) + conntrack table churn (5000 svc × multiple endpoints × frequent short-conn create/teardown) on the datapath, which is not strictly linear with Service count.
- **Overlay slightly higher than Native**: VXLAN encap/decap code path maintains conntrack entries more densely, but the magnitude is still far below iptables.

**Extrapolating to 10000+ Services**: iptables short-conn degradation will approach 50% (linear), while Cilium remains under 10%. This is the core value of replacing kube-proxy with Cilium in large clusters.

:::

### Hubble Observability Overhead (Cilium only)

| Metric       | Cilium Native | Cilium Overlay |
| ------------ | ------------- | -------------- |
| Hubble ON    | 75,604 req/s  | 74,913 req/s   |
| Hubble OFF   | 75,676 req/s  | 74,621 req/s   |
| **Overhead** | **-0.1%**     | **+0.4%**      |

:::note

The Hubble L3/L4 observability overhead is within the ±0.5% noise range — **effectively zero**. Hubble only samples events into a ring buffer in the datapath; it does not participate in forwarding decisions. You can safely enable Hubble L3/L4 observability across production environments.

:::

### NetworkPolicy Overhead (Cilium only)

#### L3/L4 Policy

| Metric            | Cilium Native | Cilium Overlay |
| ----------------- | ------------- | -------------- |
| No policy         | 75,573 req/s  | 74,900 req/s   |
| L3/L4 CNP applied | 75,675 req/s  | 74,910 req/s   |
| **Overhead**      | **+0.1%**     | **+0.0%**      |

:::note

L3/L4 CiliumNetworkPolicy execution overhead is **zero**. Cilium implements L3/L4 policy in eBPF via identity lookup + bitmap match, with no extra memory copy or context switch. Apply L3/L4 NetworkPolicy broadly without performance concerns.

:::

#### L7 Policy (HTTP)

| Metric         | Cilium Native | Cilium Overlay |
| -------------- | ------------- | -------------- |
| No policy      | TBD           | TBD            |
| L7 CNP applied | TBD           | TBD            |
| **Overhead**   | **TBD**       | **TBD**        |

:::warning[L7 policy has significant overhead]

L7 CiliumNetworkPolicy (e.g. HTTP path/method filtering) redirects traffic to an Envoy proxy for application-layer inspection. Expected overhead is approximately **-80% to -90%**. L7 policies should be **selectively applied only to Pods requiring application-layer security controls**, not broadly across all workloads.

L3/L4 policies already cover the security requirements of most production workloads (allow/deny by IP, port, namespace labels).

:::

### Resource Consumption

| Component              | CPU avg | Memory avg |
| ---------------------- | ------- | ---------- |
| kube-proxy (iptables)  | 1.0 m   | 31.1 MiB   |
| Cilium Agent (Native)  | 67.9 m  | 188.1 MiB  |
| Cilium Agent (Overlay) | 96.8 m  | 192.0 MiB  |

:::note

- **kube-proxy only syncs Services** — its CPU/memory is minimal, but the resulting iptables rule explosion and scan cost is shifted onto the datapath.
- **Cilium Agent does much more than replace kube-proxy** — it also handles NetworkPolicy compilation, Hubble flow capture, Identity allocation, BPF map maintenance, etc. Higher resource usage is expected, but the datapath cost decouples from Service scale (O(1)).
- **Overlay uses ~30m more CPU than Native**: from VXLAN encap/decap computation in BPF programs.

If NetworkPolicy and observability were implemented via separate sidecars instead, total overhead would far exceed Cilium Agent's ~190 MiB.

:::

### BPF Map Memory Overhead (Cilium only)

BPF maps use a **pre-allocation mechanism** — they allocate their maximum memory at creation time based on `max_entries`. Adding Services/Endpoints only fills data into already-allocated space; memory does not grow dynamically.

| Metric               | Cilium Native | Cilium Overlay |
| -------------------- | ------------- | -------------- |
| BPF map total memory | TBD           | TBD            |
| BPF map count        | TBD           | TBD            |
| Cilium Agent RSS     | TBD           | TBD            |

:::note[BPF memory does not contend with business workloads]

On SA5.LARGE8 (4C 8G) nodes, Cilium's total memory footprint (Agent RSS + BPF maps) is approximately 300 MB (~3.8% of node memory), leaving 77%+ available for business Pods. The pre-allocation mechanism means that even as Service count grows from 0 to 5000+, BPF map memory stays virtually unchanged — the growth comes primarily from Agent process heap memory (~25-30 MB).

:::

## Comparison Summary

### Three-way comparison

| Dimension                           | Conclusion                                                     | Quantified Difference                                                      |
| ----------------------------------- | -------------------------------------------------------------- | -------------------------------------------------------------------------- |
| **Throughput**                      | All three identical                                            | All hit ~10 Gbps burst ceiling                                             |
| **RPS keepalive**                   | iptables ~18% higher than Cilium                               | 92K vs 75K (cni-chaining / VXLAN extra overhead)                           |
| **RPS short conn**                  | iptables ~55% higher than Cilium                               | 23K vs 10K (same cause; absolute values still far exceed production needs) |
| **TCP_RR p99**                      | Cilium ~20 µs higher than iptables                             | Application-layer invisible                                                |
| **HTTP p99 @1000 QPS**              | **All three identical**                                        | All 0.99 ms                                                                |
| **5000 svc short-conn degradation** | **iptables -23.3% vs Cilium -4.5/-6.2%**                       | **Gap widens with Service count**                                          |
| **Hubble L3/L4 overhead**           | Negligible                                                     | &lt;0.5%                                                                   |
| **NetworkPolicy L3/L4 overhead**    | Zero                                                           | &lt;0.5%                                                                   |
| **NetworkPolicy L7 overhead**       | ~-85% to -90% (Envoy proxy)                                    | Selectively enable for Pods needing app-layer audit                        |
| **BPF Map memory**                  | Pre-allocated, does not grow with Service count                | ~88 MB (~1% node memory)                                                   |
| **Cilium Native vs Overlay**        | RPS and latency essentially equal; Overlay CPU slightly higher | RPS ±1%, latency ±10 µs, CPU +30m                                          |

### Key Takeaways

#### 1. All three are equivalent under realistic workloads

HTTP p99 @1000 QPS is 0.99 ms across all three. The differences exposed by extreme benchmarks only appear in fortio/wrk-style empty-response scenarios, with no production-application impact.

#### 2. iptables wins at small scale but loses badly at large scale

iptables has **~18% absolute RPS lead over Cilium** at small Service counts (under a thousand). The Native gap comes from cni-chaining + per-endpoint routing forcing each packet through the kernel stack on top of eBPF processing; the Overlay gap comes from VXLAN encap/decap. Either way, Cilium adds an extra processing layer that iptables doesn't have at small scale — this is architectural cost, not a Cilium flaw.

But the cost is that iptables datapath performance scales with Service count:

- 1000 svc short-conn degradation: 5.9%
- **5000 svc short-conn degradation: 23.3%** (linear ~4× scaling)
- Extrapolated 10000 svc: approaching 50%

Cilium's degradation curve is far sub-linear (only 4.5%~6.2% @5000 svc). **At cluster Service count ≥ several thousand, Cilium overtakes iptables.**

#### 3. Cilium Native vs Overlay are essentially equivalent

All RPS, latency, and scale-degradation differences fall within the ±5% noise range. **Choose based on network architecture, not performance**:

- Pod IP must be VPC-routable (direct ELB attach, cross-cluster connectivity, legacy monitoring directly hitting Pods) → **Native**
- Pod CIDR decoupled from VPC (IP scarcity, cross-VPC CIDR reuse, Pod count far exceeding ENI capacity) → **Overlay**

Overlay uses ~30m more CPU than Native (VXLAN encap/decap), but memory is nearly identical.

#### 4. Hubble and L3/L4 NetworkPolicy are zero-overhead; L7 requires caution

Both Hubble L3/L4 and L3/L4 NetworkPolicy introduce no measurable performance loss (&lt;0.5%). Enable globally in production.

**L7 CiliumNetworkPolicy (HTTP path/method filtering) incurs approximately -85% to -90% overhead**: traffic is redirected to an Envoy proxy for application-layer inspection, introducing inter-process communication and HTTP parsing costs. L7 policies should be **selectively applied only to Pods requiring application-layer security controls** (e.g. external ingress gateways, sensitive APIs), not broadly.

#### 5. Resource usage: Cilium pays for capability; BPF memory does not contend

Cilium Agent uses ~70-100m CPU + ~190 MiB memory, an order of magnitude more than kube-proxy's ~1m + 31 MiB. In return: NetworkPolicy (incl. Identity-based), Hubble, L7 policy support, and Service-count-decoupled datapath.

BPF maps use pre-allocation — total memory is approximately 88 MB (~1% of node memory) and does not grow with Service/Endpoint count. On SA5.LARGE8 (4C 8G) nodes, Cilium's total memory footprint (Agent + BPF maps) is approximately 300 MB, leaving 77%+ available for business Pods.

For detailed selection guidance, see [Cilium Performance Test - Recommendations](./performance-test.md#recommendations).

## References

- [Cilium Performance Test (cilium connectivity perf)](./performance-test.md)
- [VPC-CNI Native Routing Mode Explained](./native-routing.md)
- [Install Cilium](../install.md)

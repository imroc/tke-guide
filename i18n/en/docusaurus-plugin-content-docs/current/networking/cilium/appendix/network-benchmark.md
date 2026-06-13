# Cilium Network Performance Benchmark

This article uses the [`network-benchmark.sh`](https://imroc.cc/tke/scripts/network-benchmark.sh) one-click script to perform a comprehensive performance comparison of three TKE networking solutions under **identical hardware, kernel, and VPC environments**:

- **Cluster A — VPC-CNI + kube-proxy iptables**: the traditional approach, used as the performance baseline
- **Cluster B — VPC-CNI + Cilium Native Routing**: Cilium plugs into VPC-CNI via cni-chaining; Pod IPs remain legitimate VPC IPs
- **Cluster C — VPC-CNI + Cilium Overlay (VXLAN)**: Cilium is the sole Pod CNI; Pods use an independent overlay CIDR

Coverage: throughput, HTTP RPS, TCP latency, Service-scale degradation (0→5000→10000), Hubble overhead, NetworkPolicy L3/L4 and L7 overhead, BPF memory, and component resource consumption.

:::tip[Three questions this article answers]

1. **iptables vs Cilium**: Does switching to Cilium improve or degrade performance? Where's the cost, where's the benefit?
2. **Cilium Native vs Overlay**: How much do the two Cilium deployment modes differ? How to choose?
3. **Small scale vs large scale Services**: As Service count grows from 5000 to 10000, how do the degradation curves compare?

:::

:::note[Difference from cilium connectivity perf]

[Cilium Performance Test](./performance-test.md) uses `cilium connectivity perf` (based on netperf) for TCP_RR latency and TCP_STREAM throughput. The `network-benchmark.sh` script here additionally covers HTTP-layer RPS, the Service path, large-scale Service degradation, Hubble / NetworkPolicy overhead, BPF memory, and adds an iptables baseline. The two articles are complementary — read them together.

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

# Custom Service scale steps
SVC_SCALE_STEPS="1000,5000,10000" SVC_CREATE_PARALLEL=8 bash network-benchmark.sh
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

Cilium's Service load-balancing BPF map defaults to `bpf-lb-map-max=65536`. Each Service consumes roughly `1 + endpoint count` LB entries, so **10000 Services × 10 endpoints ≈ 110K entries will exceed the default and overflow the map** — manifesting as an abnormal RPS collapse at large scale (this is forwarding failure, not O(n) degradation, and pollutes the conclusions).

Before running large-scale tests, raise the limit and restart cilium:

```bash
kubectl -n kube-system patch configmap cilium-config --type merge \
  -p '{"data":{"bpf-lb-map-max":"262144"}}'
kubectl -n kube-system rollout restart ds/cilium
```

The script automatically preflight-checks capacity before the Service Scale test and prints `LB MAP CAPACITY WARNING` if insufficient.

:::

### Tools and Metrics

| Tool    | Test Content                                          | Metric                         |
| ------- | ----------------------------------------------------- | ------------------------------ |
| iperf3  | Cross-node TCP throughput                             | Gbps (1/8/16 parallel streams) |
| fortio  | HTTP RPS (keep-alive / short conn)                    | req/s                          |
| netperf | TCP_RR / TCP_CRR latency                              | p50 / p99 microseconds         |
| fortio  | Multi-step Service scale (5000/10000) degradation     | Degradation percentage         |
| fortio  | Hubble on/off RPS comparison (Cilium only)            | Overhead percentage            |
| fortio  | NetworkPolicy L3/L4 + L7 RPS comparison (Cilium only) | Overhead percentage            |
| bpftool | BPF map memory statistics (Cilium only)               | MB                             |

## Test Environment

| Item                | Cluster A (iptables)          | Cluster B (Cilium Native)                      | Cluster C (Cilium Overlay)                    |
| ------------------- | ----------------------------- | ---------------------------------------------- | --------------------------------------------- |
| Network Solution    | VPC-CNI + kube-proxy iptables | VPC-CNI + Cilium cni-chaining (Native Routing) | Cilium VXLAN Overlay (Cilium as sole Pod CNI) |
| Kubernetes Version  | v1.34.1-tke.5                 | v1.34.1-tke.5                                  | v1.34.1-tke.5                                 |
| Cilium Version      | N/A                           | v1.19.4                                        | v1.19.4                                       |
| kube-proxy replaced | No (iptables mode)            | Yes (eBPF)                                     | Yes (eBPF)                                    |
| Node OS             | TencentOS Server 4            | TencentOS Server 4                             | TencentOS Server 4                            |
| Kernel Version      | 6.6.117                       | 6.6.117                                        | 6.6.117                                       |
| Node Spec           | SA5.LARGE8 (4C 8G)            | SA5.LARGE8 (4C 8G)                             | SA5.LARGE8 (4C 8G)                            |
| Node Count          | 3                             | 3                                              | 3                                             |

All three clusters are in the same VPC, with identical hardware spec and kernel version, ensuring a fair comparison. All RPS / latency tests are cross-node (different Workers).

## At a Glance

| Dimension                      | iptables   | Cilium Native | Cilium Overlay | Key Takeaway                         |
| ------------------------------ | ---------- | ------------- | -------------- | ------------------------------------ |
| Pod2Pod throughput (8 streams) | 10.43 Gbps | 10.43 Gbps    | 10.77 Gbps     | All hit burst ceiling, no difference |
| RPS keepalive (c64)            | 90,164     | 74,684        | 76,384         | iptables ~20% higher                 |
| RPS short conn (c64)           | 22,313     | 10,258        | 10,537         | iptables ~115% higher                |
| TCP_RR p99                     | 121 µs     | 135 µs        | 129 µs         | Cilium ~10-15 µs higher              |
| HTTP p99 @1000 QPS             | 0.99 ms    | 0.99 ms       | 0.99 ms        | **Identical under realistic load**   |
| 10000 svc short-conn degrade   | **-37.3%** | **-9.0%**     | **-8.4%**      | **iptables O(n), Cilium near O(1)**  |
| L3/L4 NetworkPolicy overhead   | N/A        | -0.5%         | -0.1%          | Zero overhead                        |
| L7 NetworkPolicy overhead      | N/A        | -85.2%        | -86.3%         | Envoy proxy; enable selectively      |
| Hubble L3/L4 overhead          | N/A        | -0.4%         | -0.1%          | Zero overhead                        |
| BPF map memory / node          | N/A        | 92.8 MB       | 92.7 MB        | Pre-allocated, doesn't grow with svc |
| Datapath component mem / node  | 31.5 MB    | 391 MB        | 321 MB         | Cilium pays for capability           |

Details below, by dimension.

## 1. Throughput (iperf3, 30s, cross-node)

| Scenario                 | iptables   | Cilium Native | Cilium Overlay |
| ------------------------ | ---------- | ------------- | -------------- |
| Node hostNet (8 streams) | 10.44 Gbps | 10.44 Gbps    | 10.82 Gbps     |
| Pod-to-Pod (single)      | 10.43 Gbps | 10.42 Gbps    | 10.76 Gbps     |
| Pod-to-Pod (8 streams)   | 10.43 Gbps | 10.43 Gbps    | 10.77 Gbps     |
| Pod-to-Pod (16 streams)  | 10.43 Gbps | 10.43 Gbps    | 10.77 Gbps     |
| Via Service (8 streams)  | 10.43 Gbps | 10.43 Gbps    | 10.60 Gbps     |

:::note[Throughput is equivalent across all three]

All three solutions saturate ~10.4-10.8 Gbps, approaching the SA5.LARGE8 instance burst bandwidth ceiling — **throughput is effectively equivalent**. The ±4% inter-cluster variance is VPC burst bandwidth fluctuation and physical-node path differences, not solution quality. 16 streams matches 8 streams, confirming 8 parallel streams already saturate the NIC.

Notably, Overlay (with VXLAN encapsulation) even shows slightly higher large-packet throughput — the 50-byte encapsulation header is negligible at MTU-level packet sizes. VXLAN's cost manifests mainly in small-packet, high-frequency scenarios (see RPS section).

:::

## 2. RPS (fortio, 60s, max QPS, cross-node)

This is the dimension with the largest differences.

| Scenario                   | iptables         | Cilium Native    | Cilium Overlay   |
| -------------------------- | ---------------- | ---------------- | ---------------- |
| Pod-to-Pod c64 keepalive   | 90,097 req/s     | 74,454 req/s     | 76,341 req/s     |
| Via Svc c64 keepalive      | 90,164 req/s     | 74,684 req/s     | 76,384 req/s     |
| Via Svc c256 keepalive     | 91,649 req/s     | 76,534 req/s     | 77,768 req/s     |
| **Via Svc c64 short conn** | **22,313** req/s | **10,258** req/s | **10,537** req/s |

### Why is iptables RPS actually higher?

This is the most counter-intuitive result. Cilium replaces iptables with eBPF and "should be faster," yet in small-scale Service saturation benchmarks iptables leads by ~20% (keepalive) to ~115% (short conn). The reason differs between the two Cilium modes:

**Cilium Native: cni-chaining + per-endpoint routing**

VPC-CNI is the primary Pod CNI (assigning VPC IPs); Cilium plugs in via cni-chaining to provide policy and observability. This architecture forces per-endpoint routing (`endpointRoutes=true`), so Pod traffic uses dedicated veth routes and bypasses the `cilium_host` device — it traverses the full kernel network stack (netfilter + FIB lookup) _and_ layers on eBPF's conntrack + Service resolution + Policy checks. Each packet picks up an extra eBPF processing layer without saving the kernel-stack pass.

**Cilium Overlay: VXLAN encap/decap**

In Overlay mode Cilium is the sole Pod CNI, BPF Host Routing works normally and skips part of the kernel stack. But every cross-node packet must do VXLAN encap (egress) + decap (ingress): header construction, UDP checksum, and inner metadata bookkeeping form the dominant cost.

**iptables has the shortest path**

At small Service scale, every packet in iptables mode traverses the kernel stack once, and kube-proxy's NAT rules are just a handful of matches on PREROUTING/POSTROUTING — no eBPF processing, no encapsulation. So iptables takes the absolute lead in small-scale saturation benchmarks.

:::tip[Key insight: this is a local optimum, not a global one]

iptables's small-scale RPS advantage only holds under the specific condition of "few Services + saturation benchmark." Once Service count grows, iptables's O(n) degradation quickly erodes this lead (see [Section 5](#5-service-scale-degradation-0--5000--10000)).

Moreover — **this difference is invisible to real workloads.** All three solutions' absolute RPS (74K-90K) far exceed the load needs of a typical microservice Pod (usually < 10K). Under realistic load (see HTTP p99 @1000 QPS in the latency section), all three perform identically.

:::

### Native vs Overlay: nearly identical

Native (74,684) and Overlay (76,384) differ by < 3% on keepalive RPS, and < 3% on short conn (10,258 vs 10,537). Their datapath cost structures differ (one is cni-chaining double-processing, the other is VXLAN encapsulation), but the magnitudes happen to match.

## 3. Latency (netperf TCP_RR / TCP_CRR + fortio HTTP, cross-node)

| Metric             | iptables | Cilium Native | Cilium Overlay |
| ------------------ | -------- | ------------- | -------------- |
| TCP_RR p50         | 99 µs    | 106 µs        | 105 µs         |
| TCP_RR p99         | 121 µs   | 135 µs        | 129 µs         |
| TCP_CRR p99        | 467 µs   | 623 µs        | 608 µs         |
| HTTP p99 @1000 QPS | 0.99 ms  | 0.99 ms       | 0.99 ms        |

:::tip[Latency differences vanish under realistic load]

- **TCP_RR** (keepalive request-response): Cilium adds ~10-15 µs over iptables — the inherent cost of eBPF datapath conntrack lookup + policy check. Sub-millisecond, invisible at the application layer.
- **TCP_CRR** (per-connection setup): Cilium adds ~140-155 µs because every new connection's SYN does BPF conntrack creation + Service resolution + a full kernel-stack pass.
- **HTTP p99 @1000 QPS**: under realistic request rates (1000 QPS), all three are **identical** at 0.99 ms. Microsecond differences are completely masked by application processing time.

**This is the single most important table in this article**: the µs-level differences exposed by saturation benchmarks only appear in fortio/wrk-style empty-response, CPU-saturating scenarios. Once the application does any real work (DB query, JSON serialization, business logic), network-layer microsecond differences are entirely invisible.

:::

## 4. Cilium Native vs Overlay: How to Choose

All RPS, latency, and scale-degradation differences fall within the ±5% noise range. **Choose based on network architecture, not performance**:

| Dimension      | Cilium Native                                    | Cilium Overlay                                         |
| -------------- | ------------------------------------------------ | ------------------------------------------------------ |
| Pod IP         | Legitimate VPC IP, directly routable in VPC      | Independent overlay CIDR, decoupled from VPC           |
| Best for       | Direct CLB, cross-cluster/VPC, legacy monitoring | IP scarcity, cross-VPC CIDR reuse, Pods > ENI capacity |
| Datapath CPU   | ~102 m                                           | ~89 m                                                  |
| Cross-node lat | TCP_RR p99 135 µs                                | TCP_RR p99 129 µs                                      |
| MTU            | No extra overhead                                | VXLAN takes 50 bytes (enable jumbo frames to mitigate) |

In practice both perform nearly identically. Native's datapath CPU is slightly higher (cni-chaining double-processing); Overlay is slightly lower (BPF Host Routing active) but bears the VXLAN MTU overhead. **The core criterion is whether Pod IP needs to be directly routable in the VPC.**

> For why BPF Host Routing isn't actually hit in Native mode, and the commonality of cloud-provider Native IPAM, see [VPC-CNI Native Routing Details](./native-routing.md).

## 5. Service Scale Degradation (0 → 5000 → 10000)

Test method: create N dummy ClusterIP Services (each with endpoints), wait 60s for sync, then compare RPS degradation under identical load. This is the core value of replacing kube-proxy with Cilium.

### Keepalive: virtually no degradation for any

| Service count | iptables | Cilium Native | Cilium Overlay |
| ------------- | -------- | ------------- | -------------- |
| Baseline (0)  | 90,164   | 74,684        | 76,384         |
| 5000          | -1.3%    | -0.2%         | -0.2%          |
| 10000         | -0.8%    | -0.6%         | -0.9%          |

In keepalive scenarios all three show no meaningful degradation — conntrack caches the first-packet forwarding decision; subsequent packets hit cache without re-traversing rule chains or BPF maps. **This is why production workloads using connection pools or HTTP keepalive barely feel Service-scale impact.**

### Short connections: iptables degrades linearly, Cilium stays near-constant

| Service count  | iptables            | Cilium Native     | Cilium Overlay    |
| -------------- | ------------------- | ----------------- | ----------------- |
| Baseline (0)   | 22,313 req/s        | 10,258 req/s      | 10,537 req/s      |
| 5000           | 17,336 (-22.3%)     | 9,582 (-6.6%)     | 9,915 (-5.9%)     |
| 10000          | 13,994 (**-37.3%**) | 9,331 (**-9.0%**) | 9,653 (**-8.4%**) |
| iptables rules | 30136 → 60118       | -                 | -                 |

:::tip[O(1) vs O(n): the gap widens with scale]

**Short connections are the real test**: every new TCP connection's SYN must redo Service selection and cannot hit the conntrack cache.

- **iptables is O(n) sequential traversal**: each SYN packet sequentially matches the KUBE-SERVICES → KUBE-SVC-XXX → KUBE-SEP-XXX rule chain. At 5000 svc: 30136 rules, -22.3%; at 10000 svc: 60118 rules (doubled), **-37.3%**. Degradation worsens almost linearly with rule count.
- **Cilium is O(1) BPF hash map lookup**: constant lookup time regardless of Service count. Native goes from -6.6% (5000) to -9.0% (10000); Overlay from -5.9% to -8.4% — both sub-linear.

**The residual degradation isn't from the lookup itself**, but from cilium-agent control-plane pressure (BPF map writes during 5000→10000 svc sync) + conntrack table churn (frequent short-conn create/teardown) on the datapath, which doesn't scale linearly with Service count.

**Mind the absolute values**: even at 10000 svc, iptables's absolute short-conn RPS (13,994) is still higher than Cilium's (~9,500) — the lead has merely narrowed from 2.1x at baseline to 1.45x. **iptables has not yet been overtaken, but the trend is unmistakable**: iptables degrades linearly with rule count (~15 percentage points deeper per 5000 svc), while Cilium stays under -10%. Linear extrapolation puts the crossover at roughly 15000-20000 svc, after which Cilium pulls ahead.

:::

:::warning[On the dummy Service simplification]

Each dummy Service in this test has only **1 Endpoint**. Real-world Services often have multiple backend Pods (multiple Endpoints), and in iptables mode each Endpoint generates an additional KUBE-SEP rule — **the more Endpoints, the longer the iptables rule chain and the worse the O(n) degradation**, so the crossover point arrives earlier than the 15000-20000 svc extrapolated here. Cilium's BPF map lookup is unaffected by Endpoint count and remains O(1).

This means our estimate of iptables's large-scale degradation is **conservative**: in real multi-Endpoint scenarios, iptables's disadvantage surfaces earlier and more sharply.

:::

### Small scale vs large scale: in one sentence

- **Small scale (under a thousand)**: iptables leads in absolute terms — shortest path, no eBPF/encapsulation overhead.
- **Large scale (thousands to tens of thousands)**: iptables still leads, but the lead narrows fast as rules grow (short-conn lead drops from 2.1x to 1.45x). Cilium's O(1) doesn't degrade while iptables's O(n) worsens linearly; extrapolating the slope, Cilium overtakes around 15000-20000 svc (earlier in real multi-Endpoint scenarios).
- **Keepalive is unaffected throughout**: regardless of solution or scale, keepalive workloads are immune.

## 6. Hubble Observability Overhead (Cilium only)

| Metric       | Cilium Native | Cilium Overlay |
| ------------ | ------------- | -------------- |
| Hubble ON    | 74,096 req/s  | 76,006 req/s   |
| Hubble OFF   | 74,392 req/s  | 76,067 req/s   |
| **Overhead** | **-0.4%**     | **-0.1%**      |

:::note

Hubble L3/L4 observability overhead is within the ±0.5% noise range — **effectively zero**. Hubble only samples events into a ring buffer in the datapath; it does not participate in forwarding decisions. You can safely enable Hubble L3/L4 flow observation across production.

:::

## 7. NetworkPolicy Overhead (Cilium only)

### L3/L4 policy: zero overhead

| Metric            | Cilium Native | Cilium Overlay |
| ----------------- | ------------- | -------------- |
| No policy         | 74,576 req/s  | 76,132 req/s   |
| L3/L4 CNP applied | 74,202 req/s  | 76,064 req/s   |
| **Overhead**      | **-0.5%**     | **-0.1%**      |

L3/L4 CiliumNetworkPolicy execution overhead is **zero**. Cilium implements L3/L4 policy in eBPF via identity lookup + bitmap match, with no extra memory copy or context switch. **Apply L3/L4 NetworkPolicy broadly across all workloads without concern.**

### L7 policy (HTTP): large overhead, use with caution

| Metric         | Cilium Native | Cilium Overlay |
| -------------- | ------------- | -------------- |
| No policy      | 74,576 req/s  | 76,132 req/s   |
| L7 CNP applied | 11,048 req/s  | 10,439 req/s   |
| **Overhead**   | **-85.2%**    | **-86.3%**     |

:::warning[Enable L7 policy only on Pods that need it]

L7 CiliumNetworkPolicy (e.g. HTTP path/method filtering) redirects traffic to an **Envoy proxy** for application-layer parsing, introducing inter-process communication and HTTP parsing costs — measured RPS drops by **85%+**.

This is not a Cilium flaw, but the inherent cost of L7 visibility (any L7 policy / Service Mesh solution has comparable cost). The correct usage:

- **L3/L4 policy**: covers the vast majority of production security needs (allow/deny by IP, port, namespace labels), zero overhead, enable broadly.
- **L7 policy**: enable selectively only on Pods that genuinely need application-layer control (e.g. external ingress gateways, sensitive API auditing). Don't roll it out broadly.

:::

## 8. Resource Consumption

### CPU / Memory

| Component              | CPU avg | Memory avg |
| ---------------------- | ------- | ---------- |
| kube-proxy (iptables)  | 1.0 m   | 31.5 MiB   |
| Cilium Agent (Native)  | 102.5 m | 237.7 MiB  |
| Cilium Agent (Overlay) | 88.8 m  | 209.9 MiB  |

kube-proxy only syncs Services, so its CPU/memory is minimal; but it shifts the iptables rule explosion and scan cost onto the datapath (see Section 5). Cilium Agent does much more than replace kube-proxy — it also handles NetworkPolicy compilation, Hubble flow capture, Identity allocation, BPF map maintenance, etc. Higher resource usage is expected — **but in return you get a Service-scale-decoupled datapath (O(1)) and a full set of enterprise capabilities.**

### BPF Map Memory: pre-allocated, doesn't grow with scale

| Metric           | Cilium Native | Cilium Overlay |
| ---------------- | ------------- | -------------- |
| BPF map total    | 92.8 MB       | 92.7 MB        |
| BPF map count    | 76            | 47             |
| Cilium Agent RSS | 391 MB        | 321 MB         |

Top BPF map memory consumers (nearly identical across clusters):

| Map name (truncated) | Max Entries | Memory  |
| -------------------- | ----------- | ------- |
| cilium_ct4_global    | 131,072     | 17.0 MB |
| cilium_snat_v4       | 131,072     | 15.0 MB |
| cilium_nodeport      | 131,072     | 10.0 MB |
| cilium_policymap     | 65,536      | 9.5 MB  |
| cilium_ct_any4       | 65,536      | 8.5 MB  |

:::note[BPF memory does not contend with business workloads]

**Key mechanism: BPF maps use pre-allocation** — they allocate maximum memory at creation based on `max_entries`. Adding Services/Endpoints only fills already-allocated space; memory doesn't grow dynamically. That's why even as Services grew from 0 to 10000 in this test, BPF map total memory stayed steady at ~92.7 MB.

Memory budget on a SA5.LARGE8 (4C 8G) node:

```text
Total node memory:    8,192 MB
  System reserved:    ~1,024 MB
  kubelet / runtime:  ~512 MB
  Cilium Agent RSS:   ~320-390 MB
  BPF Maps (memlock): ~93 MB
  ────────────────────────────
  Cilium total:       ~410-480 MB (~5-6% of 8G)
  Available for Pods: ~6,000+ MB (73%+)
```

Even with 10000 Services + NetworkPolicy + active connections, Cilium's memory footprint has no material impact on business workloads. Native's RSS (391 MB) is slightly above Overlay's (321 MB), due to more endpoint routing state under cni-chaining.

:::

## Summary

### iptables vs Cilium

| Angle           | Conclusion                                                                                                                          |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Small-scale RPS | iptables leads (shortest path, no eBPF/encap overhead), but this is a local optimum                                                 |
| Large-scale RPS | iptables still leads but the lead narrows fast (short-conn 2.1x→1.45x); under O(1) vs O(n), Cilium overtakes around 15000-20000 svc |
| Realistic load  | **No difference** (HTTP p99 @1000 QPS is 0.99 ms for all three)                                                                     |
| Capabilities    | Cilium provides NetworkPolicy, Hubble, Identity security, L7 — things iptables lacks                                                |
| Resources       | Cilium uses ~300 MB more memory/node, but BPF pre-allocation doesn't grow with scale                                                |

**The cost of switching to Cilium**: ~20% RPS and ~15 µs latency in small-scale saturation benchmarks (invisible under real load) + ~300 MB memory. **The benefit**: O(1) performance at large Service scale, zero-overhead L3/L4 NetworkPolicy and Hubble observability, Identity-based security policies. For medium-to-large clusters or those with security/compliance needs, this trade is well worth it.

### Cilium Native vs Overlay

Performance is essentially identical (< 5% difference). **Choose by network architecture, not performance**: pick Native if Pod IPs need to be directly routable in the VPC; pick Overlay if Pod CIDR needs to be decoupled from the VPC.

### Small scale vs large scale Services

iptables performance is strongly correlated with Service count (O(n)) — short-conn degradation worsens from 22% to 37% going from 5000 to 10000 svc. Cilium is decoupled from Service count (O(1)), staying under 10% throughout. **This is the core reason large-scale clusters choose Cilium to replace kube-proxy.**

For detailed selection guidance, see [Cilium Performance Test - Recommendations](./performance-test.md#recommendations).

## References

- [Cilium Performance Test (cilium connectivity perf)](./performance-test.md)
- [VPC-CNI Native Routing Details](./native-routing.md)
- [Install Cilium](../install.md)

# Cilium Network Performance Benchmark

This article uses the [`network-benchmark.sh`](https://imroc.cc/tke/scripts/network-benchmark.sh) one-click script to conduct a comprehensive performance comparison of **iptables/kube-proxy**, **Cilium Native Routing**, and **Cilium Overlay**, covering throughput, HTTP RPS, TCP latency, and Service scale dimensions.

:::tip[Difference from cilium connectivity perf]

[Cilium Performance Test](./performance-test.md) uses `cilium connectivity perf` (based on netperf) to test TCP_RR latency and TCP_STREAM throughput. The `network-benchmark.sh` script in this article additionally covers:

- **HTTP Layer**: fortio full-speed RPS stress test (keep-alive / short connections)
- **Service Path**: throughput and RPS via ClusterIP Service
- **Service Scale Impact**: RPS degradation comparison after 1000 Services (O(1) vs O(n))
- **iptables Baseline**: includes kube-proxy iptables mode without Cilium as a reference

The two articles complement each other — it is recommended to read them together.

:::

## Test Methodology

### One-Click Run

```bash
bash -c "$(curl -sfL https://imroc.cc/tke/scripts/network-benchmark.sh)"
```

:::note[Prerequisites]

- `KUBECONFIG` points to the target cluster (current context is usable)
- `kubectl`, `python3`, and `timeout` must be installed locally (on macOS, install via `brew install coreutils`)
- The cluster must have at least 2 worker nodes

:::

### Custom Parameters

```bash
# Multiple rounds (for large instances without QoS concerns)
ROUNDS=3 IPERF_DURATION=120 FORTIO_DURATION=120 bash network-benchmark.sh --dir ./bench

# Specify output directory and namespace
bash network-benchmark.sh --dir ./my-results --ns my-bench
```

| Environment Variable | Default | Description                                              |
| -------------------- | ------- | -------------------------------------------------------- |
| `IPERF_DURATION`     | 30      | Duration per iperf3 test round (seconds)                 |
| `FORTIO_DURATION`    | 60      | Duration per fortio / netperf test round (seconds)       |
| `ROUNDS`             | 1       | Number of repetitions per scenario                       |
| `ROUND_SLEEP`        | 30      | Wait between rounds (seconds), for burst credit recovery |

### Test Metrics Description

| Tool    | Test Content                              | Metrics                     |
| ------- | ----------------------------------------- | --------------------------- |
| iperf3  | Cross-node TCP throughput                 | Gbps (8 concurrent streams) |
| fortio  | HTTP RPS (keep-alive / short connections) | req/s, p99 latency          |
| netperf | TCP_RR / TCP_CRR latency                  | p50 / p99 microseconds      |
| fortio  | RPS degradation after 1000 Services       | Degradation percentage      |

## Test Environment

| Item               | Cluster A (iptables)          | Cluster B (Cilium Native)                             | Cluster C (Cilium Overlay)                        |
| ------------------ | ----------------------------- | ----------------------------------------------------- | ------------------------------------------------- |
| Network Solution   | VPC-CNI + kube-proxy iptables | VPC-CNI + Cilium Native Routing (Legacy Host Routing) | VPC-CNI + Cilium VXLAN Overlay (BPF Host Routing) |
| Kubernetes Version | v1.34.1                       | v1.34.1                                               | v1.34.1                                           |
| Cilium Version     | N/A                           | v1.19.4                                               | v1.19.4                                           |
| Node OS            | TencentOS Server 4            | TencentOS Server 4                                    | TencentOS Server 4                                |
| Kernel Version     | 6.6.117                       | 6.6.117                                               | 6.6.117                                           |
| Node Spec          | SA5.LARGE8 (4C 8G)            | SA5.LARGE8 (4C 8G)                                    | SA5.LARGE8 (4C 8G)                                |
| Node Count         | 3                             | 3                                                     | 3                                                 |

All three clusters are in the same VPC with identical hardware specs and kernel versions, ensuring a fair comparison.

## Test Results

### Throughput (iperf3, 30s, cross-node)

| Scenario                 | iptables   | Cilium Native | Cilium Overlay |
| ------------------------ | ---------- | ------------- | -------------- |
| Node hostNet (8 streams) | 10.43 Gbps | 10.44 Gbps    | 10.82 Gbps     |
| Pod-to-Pod (single)      | —          | 10.43 Gbps    | 10.76 Gbps     |
| Pod-to-Pod (8 streams)   | —          | 10.43 Gbps    | 10.77 Gbps     |
| Via Service (8 streams)  | —          | 10.43 Gbps    | 10.76 Gbps     |

:::note

- Node hostNet: all three saturate at ~10.4 Gbps (VPC burst bandwidth cap), confirming consistent hardware baselines
- Pod-to-Pod and Via Service throughput for the iptables cluster were invalid due to QoS burst credit exhaustion (dropped to baseline bandwidth of 1.6 Gbps). According to reference data in the PDF report: Pod-to-Pod 8 streams were all ~10.4 Gbps across all three solutions — no significant throughput difference
- Cilium Native and Overlay Pod-to-Pod / Via Service throughput are identical

:::

### RPS (fortio, 60s, max QPS, cross-node)

| Scenario                 | iptables         | Cilium Native    | Cilium Overlay | Cilium vs iptables |
| ------------------------ | ---------------- | ---------------- | -------------- | ------------------ |
| Pod-to-Pod c64 keepalive | 90,579 req/s     | 80,373 req/s     | 77,503 req/s   | -11% ~ -14%        |
| Via Svc c64 keepalive    | 89,965 req/s     | 80,231 req/s     | 77,342 req/s   | -11% ~ -14%        |
| Via Svc c256 keepalive   | 90,357 req/s     | 81,815 req/s     | 78,502 req/s   | -9% ~ -13%         |
| Via Svc c64 short conn   | **22,807** req/s | **10,721** req/s | —              | **-53%**           |

:::tip[RPS Difference Explained]

**iptables vs Cilium (-11%~14%)**:

In VPC-CNI Native mode, Cilium requires setting `endpointRoutes=true`, which causes packets to bypass the `cilium_host` device and prevents BPF Host Routing from being enabled, falling back to Legacy Host Routing. After eBPF processing (conntrack + Service resolution + Policy check), packets must still traverse the full kernel network stack (netfilter + conntrack + FIB), resulting in approximately 10-15% dual-processing overhead.

**Short connections: iptables 22K vs Cilium 10K (-53%)**:

The gap is larger for short connections for the same reason — every new TCP connection must go through the full Cilium BPF processing + kernel stack dual path. However, this difference is **imperceptible** to real workloads — typical microservice per-Pod QPS is usually < 10K, and Service Mesh / connection pooling mechanisms automatically enable keep-alive connection reuse.

**Note**: The absolute RPS values of all three solutions far exceed typical production workload requirements. The differences are only visible under extreme stress; under real application loads (e.g., HTTP p99 @1000 QPS), all three have identical latency (0.99 ms).

:::

### Latency (netperf TCP_RR / TCP_CRR + fortio HTTP, cross-node)

| Metric             | iptables | Cilium Native | Cilium Overlay | Cilium vs iptables |
| ------------------ | -------- | ------------- | -------------- | ------------------ |
| TCP_RR p50         | 89 µs    | 104 µs        | 105 µs         | +15~16 µs          |
| TCP_RR p99         | 109 µs   | 127 µs        | 129 µs         | +18~20 µs          |
| TCP_CRR p99        | 472 µs   | 628 µs        | 596 µs         | +124~156 µs        |
| HTTP p99 @1000 QPS | 0.99 ms  | 0.99 ms       | 0.99 ms        | **0 ms**           |

:::tip[Latency Difference Explained]

- **TCP_RR** (keep-alive request-response): Cilium adds ~15-20 µs compared to iptables — this is the inherent overhead of eBPF data plane processing (conntrack lookup + policy check). At sub-millisecond scale, this is completely imperceptible to the application layer.
- **TCP_CRR** (new connection per request): Cilium adds ~130 µs compared to iptables, because Cilium needs to perform additional BPF conntrack creation and Service resolution for SYN packets on new connections.
- **HTTP p99 @1000 QPS**: Under real application load (1000 QPS), all three solutions have **identical latency** — microsecond-level differences are completely drowned out by application-layer processing time.

:::

### Service Scale (RPS degradation after 1000 Services)

| Metric                       | iptables     | Cilium Native | Cilium Overlay |
| ---------------------------- | ------------ | ------------- | -------------- |
| iptables rules / BPF entries | 6,142 rules  | 3,043 entries | 3,049 entries  |
| keepalive RPS (1000 svc)     | 89,528 req/s | 80,195 req/s  | 76,087 req/s   |
| keepalive degradation        | **-0.5%**    | **-0.0%**     | **-1.6%**      |
| short conn RPS (1000 svc)    | 20,795 req/s | —             | —              |
| short conn degradation       | **-8.8%**    | —             | —              |

:::tip[O(1) vs O(n) Service Lookup]

**iptables**: The first SYN packet of every new TCP connection must **sequentially traverse** the entire `KUBE-SERVICES` iptables chain (O(n) complexity, where n = number of Services). The sequential traversal overhead from 6,142 rules causes 8.8% degradation in short connection scenarios. This degradation will increase linearly as Service count grows.

**Cilium eBPF**: Uses BPF hash map for O(1) constant-time lookup — whether there are 10 or 10,000 Services, lookup speed remains constant. Degradation after 1000 Services is < 2%, well within noise range.

**Scale Projection**: At larger scales (e.g., 5,000+ Services), iptables degradation will grow proportionally, while Cilium remains constant. This is one of the most core values of Cilium replacing kube-proxy.

:::

### Resource Consumption

| Component              | CPU avg | Memory avg |
| ---------------------- | ------- | ---------- |
| kube-proxy (iptables)  | ~1m     | ~13 MiB    |
| Cilium Agent (Native)  | 106m    | 194 MiB    |
| Cilium Agent (Overlay) | 181m    | 192 MiB    |

:::note

Cilium not only replaces kube-proxy but also simultaneously provides NetworkPolicy, Hubble observability, Identity-based security policies, and more. If these features were deployed separately via sidecars, the total overhead would be greater. The memory difference (~180 MiB) comes from the runtime state of these additional capabilities.

:::

## Comparative Analysis

### Summary

| Dimension                    | Conclusion                         | Quantified Difference                                                     |
| ---------------------------- | ---------------------------------- | ------------------------------------------------------------------------- |
| **Throughput**               | No difference among all three      | All reach 10G+ line rate                                                  |
| **RPS (keep-alive)**         | Cilium ~12% lower than iptables    | 80K vs 90K (Legacy Host Routing dual-processing overhead)                 |
| **RPS (short connections)**  | Cilium ~53% lower than iptables    | 10K vs 22K (same reason, but absolute values far exceed production needs) |
| **Latency p99**              | Cilium ~18 µs higher than iptables | 127 vs 109 µs (imperceptible at application layer)                        |
| **HTTP p99 @1000 QPS**       | **All three identical**            | All at 0.99 ms                                                            |
| **1000 Svc degradation**     | **iptables O(n) vs Cilium O(1)**   | iptables short conn degrades 8.8%, Cilium < 2%                            |
| **Cilium Native vs Overlay** | No significant difference          | RPS ±4%, latency ±2 µs                                                    |

### Key Conclusions

1. **No performance difference under real workloads**: Under typical application load (HTTP p99 @1000 QPS), all three solutions have identical latency (0.99 ms). Microsecond-level differences are only visible in extreme stress tests.

2. **Cilium's cost**: Compared to iptables, Cilium has ~12% overhead in extreme RPS scenarios (Legacy Host Routing dual-processing), but in exchange provides enterprise-grade capabilities such as NetworkPolicy, Hubble observability, and eBPF security policies.

3. **Cilium's advantage**: Service lookup is O(1) — as cluster Service count grows, iptables performance degrades linearly while Cilium remains constant. At 1000 Services, the gap is already visible (8.8% vs < 2%), and the advantage becomes more pronounced at larger scales.

4. **Native vs Overlay**: Performance is nearly identical between the two. Selection should be based on network architecture requirements (whether Pod IPs need to be VPC-routable) rather than performance.

For detailed selection recommendations, see [Cilium Performance Test - Recommendations](./performance-test.md#recommendations).

## Related Links

- [Cilium Performance Test (cilium connectivity perf)](./performance-test.md)
- [VPC-CNI Native Routing Mode Explained](./native-routing.md)
- [Install Cilium](../install.md)

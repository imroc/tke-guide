# Cilium Network Performance Benchmark

This article uses the [`network-benchmark.sh`](https://imroc.cc/tke/scripts/network-benchmark.sh) one-click script to perform a comprehensive performance comparison of **iptables/kube-proxy**, **Cilium Native Routing**, and **Cilium Overlay**, covering throughput, HTTP RPS, TCP latency, Service scale, Hubble overhead, NetworkPolicy overhead, and more.

:::tip[Difference from cilium connectivity perf]

[Cilium Performance Test](./performance-test.md) uses `cilium connectivity perf` (based on netperf) to test TCP_RR latency and TCP_STREAM throughput. The `network-benchmark.sh` script in this article additionally covers:

- **HTTP layer**: fortio full-speed RPS benchmarking (keep-alive / short connections)
- **Service path**: throughput and RPS via ClusterIP Service
- **Service scale impact**: RPS degradation comparison after 1000 Services (O(1) vs O(n))
- **Hubble / NetworkPolicy overhead**: quantifying the performance impact of observability and policy enforcement
- **iptables baseline**: includes kube-proxy iptables mode without Cilium as a reference

These two articles are complementary — it's recommended to read them together.

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
```

| Environment Variable | Default | Description                                              |
| -------------------- | ------- | -------------------------------------------------------- |
| `IPERF_DURATION`     | 30      | iperf3 test duration per round (seconds)                 |
| `FORTIO_DURATION`    | 60      | fortio / netperf test duration per round (seconds)       |
| `ROUNDS`             | 1       | Number of repetitions per scenario                       |
| `ROUND_SLEEP`        | 30      | Wait between rounds (seconds), for burst credit recovery |

### Test Metrics Description

| Tool    | Test Content                                    | Metric                 |
| ------- | ----------------------------------------------- | ---------------------- |
| iperf3  | Cross-node TCP throughput                       | Gbps (8/16 streams)    |
| fortio  | HTTP RPS (keep-alive / short connections)       | req/s                  |
| netperf | TCP_RR / TCP_CRR latency                        | p50 / p99 microseconds |
| fortio  | RPS degradation after 1000 Services             | Degradation percentage |
| fortio  | Hubble on/off RPS comparison                    | Overhead percentage    |
| fortio  | RPS comparison before/after NetworkPolicy L3/L4 | Overhead percentage    |

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

All three clusters are in the same VPC with identical hardware specs and kernel versions to ensure a fair comparison.

## Test Results

### Throughput (iperf3, 30s, Cross-Node)

| Scenario                 | iptables   | Cilium Native | Cilium Overlay |
| ------------------------ | ---------- | ------------- | -------------- |
| Node hostNet (8 streams) | 10.88 Gbps | 10.44 Gbps    | 10.82 Gbps     |
| Pod-to-Pod (single)      | 10.90 Gbps | 10.43 Gbps    | 10.54 Gbps     |
| Pod-to-Pod (8 streams)   | 10.88 Gbps | 10.43 Gbps    | 10.77 Gbps     |
| Pod-to-Pod (16 streams)  | 10.86 Gbps | 10.43 Gbps    | 10.77 Gbps     |
| Via Service (8 streams)  | 10.88 Gbps | 10.43 Gbps    | 10.77 Gbps     |

:::note

All three solutions saturate 10+ Gbps, approaching the VPC burst bandwidth limit — no throughput difference. The ±4% variation between clusters is due to VPC bandwidth fluctuation and network path differences between physical nodes, not solution differences. 16 streams and 8 streams show the same throughput, indicating that 8 concurrent streams are sufficient to saturate the NIC.

:::

### RPS (fortio, 60s, max QPS, Cross-Node)

| Scenario                 | iptables         | Cilium Native    | Cilium Overlay   | Cilium vs iptables |
| ------------------------ | ---------------- | ---------------- | ---------------- | ------------------ |
| Pod-to-Pod c64 keepalive | 90,257 req/s     | 78,354 req/s     | 77,377 req/s     | -13% ~ -14%        |
| Via Svc c64 keepalive    | 90,013 req/s     | 78,374 req/s     | 77,185 req/s     | -13% ~ -14%        |
| Via Svc c256 keepalive   | 90,461 req/s     | 79,145 req/s     | 78,084 req/s     | -13% ~ -14%        |
| Via Svc c64 short conn   | **22,845** req/s | **10,667** req/s | **10,695** req/s | **-53%**           |

:::tip[RPS Difference Explained]

**iptables vs Cilium (-13%~14%)**:

In VPC-CNI Native mode, Cilium requires `endpointRoutes=true`, causing packets to bypass the `cilium_host` device and preventing BPF Host Routing from being enabled — falling back to Legacy Host Routing. After Cilium eBPF processing (conntrack + Service resolution + Policy check), packets still traverse the full kernel network stack (netfilter + conntrack + FIB), resulting in approximately 10-15% dual-processing overhead.

**Short connections iptables 22K vs Cilium 10K (-53%)**:

The difference is larger for short connections due to the same reason — each new TCP connection must traverse the full Cilium BPF processing + kernel stack dual path. However, this difference is **imperceptible** for real workloads — typical microservice per-Pod QPS is usually < 10K, and Service Mesh / connection pools automatically enable keep-alive connection reuse.

**Note**: The absolute RPS values for all three solutions far exceed typical production workload requirements. The differences are only visible under extreme pressure — under real application load (e.g., HTTP p99 @1000 QPS), all three have identical latency (0.99 ms).

:::

### Latency (netperf TCP_RR / TCP_CRR + fortio HTTP, Cross-Node)

| Metric             | iptables | Cilium Native | Cilium Overlay | Cilium vs iptables |
| ------------------ | -------- | ------------- | -------------- | ------------------ |
| TCP_RR p50         | 89 µs    | 106 µs        | 104 µs         | +15~17 µs          |
| TCP_RR p99         | 113 µs   | 130 µs        | 128 µs         | +15~17 µs          |
| TCP_CRR p99        | 469 µs   | 611 µs        | 607 µs         | +138~142 µs        |
| HTTP p99 @1000 QPS | 0.99 ms  | 0.99 ms       | 0.99 ms        | **0 ms**           |

:::tip[Latency Difference Explained]

- **TCP_RR** (keep-alive request-response): Cilium adds ~15-17 µs compared to iptables, which is the inherent overhead of eBPF datapath processing (conntrack lookup + policy check). At the sub-millisecond scale, this is completely imperceptible to the application layer.
- **TCP_CRR** (new connection per request): Cilium adds ~140 µs compared to iptables because new connections require additional BPF conntrack creation and Service resolution for SYN packets.
- **HTTP p99 @1000 QPS**: Under real application load (1000 QPS), all three solutions have **identical latency** — the microsecond-level differences are completely overwhelmed by application-layer processing time.
- **Cilium Native vs Overlay**: Latency is nearly identical between the two (difference < 3 µs) — the additional latency from VXLAN encapsulation in cross-node scenarios is negligible.

:::

### Service Scale (RPS Degradation After 1000 Services)

| Metric                       | iptables     | Cilium Native | Cilium Overlay |
| ---------------------------- | ------------ | ------------- | -------------- |
| iptables rules / BPF entries | 6,142 rules  | 3,043 entries | 3,049 entries  |
| keepalive RPS (1000 svc)     | 89,626 req/s | 78,195 req/s  | 77,194 req/s   |
| keepalive degradation        | -0.4%        | -0.2%         | 0.0%           |
| short conn RPS (1000 svc)    | 21,486 req/s | 10,492 req/s  | 10,256 req/s   |
| **short conn degradation**   | **-5.9%**    | **-1.6%**     | **-4.1%**      |

:::tip[O(1) vs O(n) Service Lookup]

**Keep-alive scenario**: No degradation for any of the three — conntrack caches connection state, so subsequent packets don't need to traverse the rule chain / BPF map.

**Short connection scenario** (key difference): The SYN packet of each new TCP connection must traverse the complete KUBE-SERVICES chain or query the BPF map:

- **iptables -5.9%**: 1000 Services = 6,142 rules traversed sequentially (O(n)), introducing measurable performance degradation
- **Cilium Native -1.6%**: BPF hash map O(1) lookup, virtually unaffected by 1000 Services
- **Cilium Overlay -4.1%**: Slightly higher degradation than Native, possibly due to more CT table entries on the VXLAN encapsulation path

At larger scales (e.g., 5,000+ Services), iptables degradation will grow proportionally, while Cilium remains constant. This is one of the core values of Cilium replacing kube-proxy.

:::

### Hubble Observability Overhead (Cilium Clusters Only)

| Metric       | Cilium Native | Cilium Overlay |
| ------------ | ------------- | -------------- |
| Hubble ON    | 78,209 req/s  | 76,917 req/s   |
| Hubble OFF   | 78,004 req/s  | 76,928 req/s   |
| **Overhead** | **+0.3%**     | **-0.0%**      |

:::note

The performance overhead of Hubble L3/L4 observability is **negligible** (< 0.5%). Hubble only performs event sampling and ring buffer writes on the datapath without participating in forwarding decisions, resulting in virtually no impact on throughput. You can safely enable Hubble L3/L4 mode in production environments.

:::

### NetworkPolicy L3/L4 Overhead (Cilium Clusters Only)

| Metric          | Cilium Native | Cilium Overlay |
| --------------- | ------------- | -------------- |
| No policy       | 78,401 req/s  | 76,944 req/s   |
| After L3/L4 CNP | 77,880 req/s  | 77,220 req/s   |
| **Overhead**    | **-0.7%**     | **+0.4%**      |

:::note

The execution overhead of L3/L4 CiliumNetworkPolicy is **zero** (differences are within the ±1% noise range). Cilium's L3/L4 policies are implemented in eBPF programs via identity lookup + bitmap matching, introducing no additional memory copies or context switches — performance is identical to having no policy. You can safely apply L3/L4 NetworkPolicy to all workloads in bulk.

:::

### Resource Usage

| Component              | CPU avg | Memory avg |
| ---------------------- | ------- | ---------- |
| kube-proxy (iptables)  | ~1m     | ~13 MiB    |
| Cilium Agent (Native)  | 106m    | 194 MiB    |
| Cilium Agent (Overlay) | 181m    | 192 MiB    |

:::note

Cilium not only replaces kube-proxy but also provides NetworkPolicy, Hubble observability, identity-based security policies, and other capabilities simultaneously. If these features were deployed separately via sidecars, the total overhead would be greater. The memory difference (~180 MiB) comes from the runtime state of these additional capabilities.

:::

## Comparative Analysis

### Summary

| Dimension                           | Conclusion                         | Quantified Difference                                                     |
| ----------------------------------- | ---------------------------------- | ------------------------------------------------------------------------- |
| **Throughput**                      | No difference among the three      | All reach 10G+ line rate                                                  |
| **RPS (keep-alive)**                | Cilium ~13% lower than iptables    | 78K vs 90K (Legacy Host Routing dual-processing overhead)                 |
| **RPS (short connections)**         | Cilium ~53% lower than iptables    | 10K vs 22K (same reason, but absolute values far exceed production needs) |
| **Latency p99**                     | Cilium ~17 µs higher than iptables | 130 vs 113 µs (imperceptible to application layer)                        |
| **HTTP p99 @1000 QPS**              | **All three identical**            | All at 0.99 ms                                                            |
| **1000 Svc short conn degradation** | **iptables O(n) vs Cilium O(1)**   | iptables -5.9%, Cilium -1.6%~-4.1%                                        |
| **Hubble L3/L4 overhead**           | Negligible                         | < 0.5%                                                                    |
| **NetworkPolicy L3/L4 overhead**    | Zero overhead                      | ±0.7% (noise range)                                                       |
| **Cilium Native vs Overlay**        | No significant difference          | RPS ±2%, latency ±3 µs                                                    |

### Key Conclusions

1. **No performance difference under real workloads**: Under typical application load (HTTP p99 @1000 QPS), all three solutions have identical latency (0.99 ms). Microsecond-level differences are only visible in extreme stress tests.

2. **Cilium's cost**: Compared to iptables, Cilium has ~13% overhead in extreme RPS scenarios (Legacy Host Routing dual-processing in VPC-CNI Native mode), but in exchange provides enterprise-grade capabilities including NetworkPolicy, Hubble observability, and eBPF security policies.

3. **Cilium's advantages**:
   - O(1) Service lookup — only 1.6% short connection degradation after 1000 Services, while iptables degrades 5.9%; the gap widens with scale
   - Hubble L3/L4 observability with zero overhead (< 0.5%) — safe to enable across the board
   - L3/L4 NetworkPolicy with zero overhead — safe to apply in bulk

4. **Native vs Overlay**: Performance is nearly identical between the two. Selection should be based on network architecture requirements (whether Pod IPs need to be VPC-routable) rather than performance.

For detailed selection recommendations, see [Cilium Performance Test - Recommendations](./performance-test.md#recommendations).

## Related Links

- [Cilium Performance Test (cilium connectivity perf)](./performance-test.md)
- [VPC-CNI Native Routing Mode Details](./native-routing.md)
- [Install Cilium](../install.md)

# Cilium Network Performance Benchmark

This document uses the [`network-benchmark.sh`](https://imroc.cc/tke/scripts/network-benchmark.sh) script to perform a comprehensive network performance comparison between Cilium Native Routing and Overlay modes, covering throughput, HTTP RPS, TCP latency, and Service scale dimensions.

:::tip[Difference from cilium connectivity perf]

[Cilium Performance Test](./performance-test.md) uses `cilium connectivity perf` (based on netperf) to test TCP_RR latency and TCP_STREAM throughput. The `network-benchmark.sh` script in this document additionally covers:

- **HTTP layer**: fortio max-rate RPS testing (keepalive / short-connection)
- **Service path**: throughput and RPS through ClusterIP Service
- **Service scale impact**: eBPF lookup performance degradation with 1000 Services
- **Cilium Agent resource usage**: CPU / Memory sampling during tests

The two documents are complementary — we recommend reading both.

:::

## Test Method

### One-liner

```bash
bash -c "$(curl -sfL https://imroc.cc/tke/scripts/network-benchmark.sh)"
```

:::note[Prerequisites]

- `KUBECONFIG` points to the target cluster (current context is usable)
- Local machine needs `kubectl`, `python3`, `timeout` (macOS: `brew install coreutils`)
- Cluster needs at least 2 worker nodes

:::

### Custom Parameters

```bash
# Full run on large instances (no QoS concern)
ROUNDS=3 IPERF_DURATION=120 FORTIO_DURATION=120 bash network-benchmark.sh --dir ./bench

# Specify output directory and namespace
bash network-benchmark.sh --dir ./my-results --ns my-bench
```

| Environment Variable | Default | Description                                             |
| -------------------- | ------- | ------------------------------------------------------- |
| `IPERF_DURATION`     | 30      | iperf3 test duration per round (seconds)                |
| `FORTIO_DURATION`    | 60      | fortio / netperf test duration per round (seconds)      |
| `ROUNDS`             | 1       | Repetitions per scenario                                |
| `ROUND_SLEEP`        | 30      | Wait between rounds (seconds) for burst credit recovery |

### Test Metrics

| Tool    | What it tests                           | Metric                    |
| ------- | --------------------------------------- | ------------------------- |
| iperf3  | Cross-node TCP throughput               | Gbps (8 parallel streams) |
| fortio  | HTTP RPS (keepalive / short-connection) | req/s, p99 latency        |
| netperf | TCP_RR / TCP_CRR latency                | p50 / p99 microseconds    |
| fortio  | RPS degradation with 1000 Services      | Degradation percentage    |

## Test Environment

| Item               | Value                                                 |
| ------------------ | ----------------------------------------------------- |
| Kubernetes version | v1.34.1                                               |
| Cilium version     | v1.19.4                                               |
| Node OS            | TencentOS Server 4                                    |
| Kernel version     | 6.6.117-45.7.3.tl4.x86_64                             |
| Node spec          | SA5.LARGE8 (4C 8G, baseline 1.5 Gbps / burst 10 Gbps) |
| Node count         | 3                                                     |
| Test script        | network-benchmark.sh                                  |
| Native mode        | VPC-CNI + Cilium Native Routing (Legacy Host Routing) |
| Overlay mode       | VPC-CNI + Cilium VXLAN Overlay (BPF Host Routing)     |

## Test Results

### Throughput (iperf3, 30s, 8 streams, cross-node)

| Scenario                 | Native     | Overlay    | Difference |
| ------------------------ | ---------- | ---------- | ---------- |
| Node hostNet 8 streams   | 10.44 Gbps | 10.82 Gbps | +3.6%      |
| Pod-to-Pod single stream | 10.43 Gbps | 10.76 Gbps | +3.2%      |
| Pod-to-Pod 8 streams     | 10.43 Gbps | 10.77 Gbps | +3.3%      |
| Via Service 8 streams    | 10.43 Gbps | 10.76 Gbps | +3.2%      |

:::note

Both saturate 10+ Gbps near the SA5 burst bandwidth limit (10 Gbps). The ±3% difference comes from network path variation between different physical nodes, not mode differences. The Node hostNet test bypasses all CNI paths — similar values between the two confirm consistent underlying bandwidth.

:::

### RPS (fortio, 60s, max QPS, cross-node)

| Scenario                     | Native | Overlay | Difference |
| ---------------------------- | ------ | ------- | ---------- |
| Pod-to-Pod c64 keepalive     | 80,373 | 77,503  | -3.6%      |
| Via Svc c64 keepalive        | 80,231 | 77,342  | -3.6%      |
| Via Svc c256 keepalive       | 81,815 | 78,502  | -4.0%      |
| Via Svc c64 short-connection | 10,721 | —       | —          |

:::note

RPS difference is approximately 3-4%, within statistical noise. Small-packet HTTP request bottleneck is CPU (4-core node caps at ~80K req/s with keepalive). VXLAN encapsulation overhead for small packets is negligible. Short-connection (new TCP per request) QPS is ~1/8 of keepalive, mainly due to TCP handshake overhead.

:::

### Latency (netperf TCP_RR / TCP_CRR + fortio HTTP, cross-node)

| Metric             | Native  | Overlay | Difference |
| ------------------ | ------- | ------- | ---------- |
| TCP_RR p50         | 104 µs  | 105 µs  | +1 µs      |
| TCP_RR p99         | 127 µs  | 129 µs  | +2 µs      |
| TCP_CRR p99        | 628 µs  | 596 µs  | -32 µs     |
| HTTP p99 @1000 QPS | 0.99 ms | 0.99 ms | Same       |

:::note

Cross-node latency is virtually identical between the two modes. The TCP_RR p99 difference of only 2 µs is within VPC physical topology noise. The ~30 µs TCP_CRR fluctuation is also normal jitter. Completely imperceptible at the application layer.

:::

### Service Scale (RPS degradation after 1000 Services)

|                              | Native       | Overlay      |
| ---------------------------- | ------------ | ------------ |
| Baseline (Via Svc keepalive) | 80,231 req/s | 77,342 req/s |
| After 1000 Services          | 80,195 req/s | 76,087 req/s |
| Degradation                  | **-0.0%**    | **-1.6%**    |

Cilium uses eBPF hash maps for Service → Backend lookup (O(1) time complexity). 1000 Services do not increase per-request lookup overhead. Both show < 2% degradation, within noise.

### Cilium Agent Resource Usage (during test)

|            | Native  | Overlay |
| ---------- | ------- | ------- |
| CPU avg    | 106m    | 181m    |
| Memory avg | 194 MiB | 192 MiB |

Overlay mode has slightly higher CPU (VXLAN tunnel management and extra encapsulation path). Memory is essentially the same.

## Comparative Analysis

### Summary

| Dimension            | Conclusion                | Quantified Difference     |
| -------------------- | ------------------------- | ------------------------- |
| **Throughput**       | No difference             | Both reach 10G+ line rate |
| **RPS (keepalive)**  | No significant difference | ±4% (CPU-bound)           |
| **RPS (short-conn)** | No significant difference | ~10K req/s                |
| **Latency p99**      | No significant difference | ±2 µs                     |
| **Service Scale**    | No degradation            | ≤ 1.6% (eBPF O(1))        |
| **Agent CPU**        | Native slightly lower     | 106m vs 181m              |

### Key Conclusion

**On SA5 4C8G nodes, Cilium Native Routing and VXLAN Overlay show no statistically significant difference in cross-node network performance.** Both saturate 10G bandwidth, RPS differences are indistinguishable under CPU bottleneck, and latency differs by only 2 µs.

Performance should not be the deciding factor for mode selection — choose based on network architecture requirements (whether Pod IPs need to be VPC-routable) and operational preferences. See [Cilium Performance Test - Recommendations](./performance-test.md#recommendations) for details.

## Related Links

- [Cilium Performance Test (cilium connectivity perf)](./performance-test.md)
- [VPC-CNI Native Routing Mode Explained](./native-routing.md)
- [Install Cilium](../install.md)

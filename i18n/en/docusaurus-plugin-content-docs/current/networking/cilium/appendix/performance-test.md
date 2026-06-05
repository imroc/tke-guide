# Cilium Performance Test

This article explains how to run network performance tests on Cilium installed on a TKE cluster, and presents benchmark results for each recommended deployment scheme.

Cilium provides the [`cilium connectivity perf`](https://docs.cilium.io/en/stable/operations/performance/benchmark/) performance testing tool, which runs netperf-based TCP_RR (request-response latency) and TCP_STREAM (throughput) tests across **same-node / other-node** × **Pod network / Host network** — four network combinations in total.

## Test Method

### One-Click Script

The [one-click installation script](../install.md#one-click-installation-script) `cilium.sh` provides the `perf` subcommand wrapping `cilium connectivity perf`:

```bash
bash -c "$(curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh)" -- perf
```

If GitHub is unreachable, use the site mirror:

```bash
bash -c "$(curl -sfL https://imroc.cc/tke/scripts/cilium.sh)" -- perf
```

:::tip[Concurrent Streams]

On burst-capable instance types (e.g., SA5), the default 4 streams may not trigger burst bandwidth. It is recommended to use 8 streams:

```bash
# Direct cilium CLI usage
cilium connectivity perf --streams 8

# Or via the one-click script (pass via environment variable)
CILIUM_PERF_STREAMS=8 bash -c "$(curl -sfL ...)" -- perf
```

8 streams have been verified on multiple SA5 instance sizes to reliably reach burst bandwidth limits, providing a more accurate throughput measurement. If switching to a different instance type, refer to the instance's queue count — a good rule of thumb is to set `--streams` to 2× the queue count.

:::

The script does the following additional work compared to running `cilium connectivity perf` directly:

- **Replaces images**: netperf images are replaced with TKE-internal mirror addresses (`quay.tencentcloudcr.com/cilium/network-perf`) so nodes don't need public network access to pull images
- **Auto-cleans previous leftovers**: cleans up `cilium-test-*` namespaces left by previous test runs. `cilium connectivity perf` tries `kubectl delete ns cilium-test-1` on startup, but TKE's gatekeeper prevents namespace deletion when Pods still exist — without pre-cleaning, the script would hang (see [FAQ](#why-clean-up-cilium-test--namespace-before-perf))
- **Elapsed time summary**: prints total elapsed time at the end

### Manual Test

First install the [cilium CLI](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli):

```bash
cilium connectivity perf \
  --streams 8 \
  --performance-image quay.tencentcloudcr.com/cilium/network-perf:3.20-1772622563-6fd6a90
```

Common `cilium connectivity perf` parameters:

- `--duration 10s`: each RR/STREAM test runs for 10 seconds
- `--samples 1`: run each test once (can increase for averaged results)
- `--streams`: number of concurrent streams for TCP_STREAM_MULTI (default 4, recommended 8)
- `--rr / --throughput / --throughput-multi`: enable TCP_RR, TCP_STREAM, TCP_STREAM_MULTI tests (all on by default)
- `--pod-net / --host-net / --other-node / --same-node`: all four network combinations (all on by default)
- Add `--udp` for UDP, `--crr` for TCP_CRR (new connection per request), `--bandwidth` for bandwidth rate limiting tests

See `cilium connectivity perf --help` for all parameters.

### Test Types

| Test Type          | Description                                               | What It Measures                                                  |
| ------------------ | --------------------------------------------------------- | ----------------------------------------------------------------- |
| `TCP_RR`           | TCP Request-Response: send small requests, wait for reply | **Latency** (µs, lower is better); OP/s = transactions per second |
| `TCP_STREAM`       | Single-stream TCP bulk transfer                           | **Single-stream throughput** (Mb/s, higher is better)             |
| `TCP_STREAM_MULTI` | Multi-stream concurrent TCP transfer (`--streams`)        | **Multi-stream throughput** (Mb/s)                                |

### Network Combinations

| Scenario       | Node       | Description                                                   | Data Path                                                                         |
| -------------- | ---------- | ------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| `pod-to-pod`   | same-node  | client Pod → server Pod on the same node                      | client veth → cilium ebpf → server veth                                           |
| `pod-to-pod`   | other-node | client Pod → server Pod on a different node                   | client veth → cilium ebpf → NIC → underlay → peer NIC → cilium ebpf → server veth |
| `host-to-host` | same-node  | client (hostNetwork) → server (hostNetwork) on same node      | host stack → host stack (no cilium veth path)                                     |
| `host-to-host` | other-node | client (hostNetwork) → server (hostNetwork) on different node | host stack → NIC → underlay → peer NIC → host stack                               |

:::tip[Interpreting Results]

Performance data **strongly depends on instance type, VPC bandwidth, kernel version, and concurrent workloads**. The values here are measured on empty newly-created clusters and serve only as a **relative comparison between Cilium installation modes** — they should not be treated as production performance baselines.

The TCP_STREAM tests in `cilium connectivity perf` (based on netperf) use large default buffers that limit per-connection PPS, making it difficult to trigger burst bandwidth on burst-capable instance types. With `--streams 8`, multi-stream cross-node throughput roughly reflects the instance's baseline bandwidth, but burst limits are best measured with tools like iperf3. This article focuses on **relative differences** between modes rather than absolute values.

:::

## Test Environment

| Item               | Value                                                                                            |
| ------------------ | ------------------------------------------------------------------------------------------------ |
| Kubernetes version | v1.34.1 (containerd 1.7.28)                                                                      |
| Cilium version     | v1.19.4                                                                                          |
| Cilium CLI version | v0.19.4                                                                                          |
| Node OS            | TencentOS Server 4 (kernel 6.6.117-45.7.3.tl4.x86_64)                                            |
| Node count         | 3 nodes                                                                                          |
| Node public IP     | Nodes have EIP (performance tests don't require public access)                                   |
| Installation       | [One-click installation script](../install.md#one-click-installation-script) `cilium.sh install` |
| perf params        | `--streams 8` (8 concurrent streams for multi-stream tests)                                      |
| Native mode        | Legacy Host Routing (see [host-routing appendix](./host-routing.md))                             |
| Overlay mode       | BPF Host Routing (see [host-routing appendix](./host-routing.md))                                |

### Instance Types Tested

| Instance           | vCPU | Memory | Baseline / Burst Bandwidth | Queues | Rationale                     |
| ------------------ | ---- | ------ | -------------------------- | ------ | ----------------------------- |
| SA5.LARGE8 (4C)    | 4    | 8G     | 1.5 / 10 Gbps              | 4      | Most common TKE entry-level   |
| SA5.2XLARGE16 (8C) | 8    | 16G    | 3 / 10 Gbps                | 8      | Common upgrade, double queues |

## Test Results Summary

### TCP_RR (Request-Response Latency, µs)

| Instance | Mode    | Scenario   | Node       | Mean       | P50 | P90 | P99 | OP/s  |
| -------- | ------- | ---------- | ---------- | ---------- | --- | --- | --- | ----- |
| 4C       | Overlay | pod-to-pod | same-node  | **31.27**  | 31  | 34  | 44  | 31736 |
| 4C       | Native  | pod-to-pod | same-node  | **37.62**  | 37  | 41  | 53  | 26409 |
| 4C       | Overlay | pod-to-pod | other-node | **94.29**  | 94  | 100 | 116 | 10576 |
| 4C       | Native  | pod-to-pod | other-node | **112.83** | 113 | 119 | 138 | 8843  |
| 8C       | Overlay | pod-to-pod | same-node  | **31.94**  | 32  | 34  | 43  | 31092 |
| 8C       | Native  | pod-to-pod | same-node  | **38.03**  | 37  | 41  | 51  | 26135 |
| 8C       | Overlay | pod-to-pod | other-node | **106.21** | 105 | 114 | 127 | 9394  |
| 8C       | Native  | pod-to-pod | other-node | **94.13**  | 93  | 99  | 109 | 10598 |

### TCP_STREAM / TCP_STREAM_MULTI (Throughput, Mb/s)

| Instance | Mode    | Scenario   | Node       | Single-stream | Multi-stream (8 streams) |
| -------- | ------- | ---------- | ---------- | ------------- | ------------------------ |
| 4C       | Overlay | pod-to-pod | same-node  | **22,997**    | **75,623**               |
| 4C       | Native  | pod-to-pod | same-node  | **29,329**    | **64,128**               |
| 4C       | Overlay | pod-to-pod | other-node | **11,116**    | **11,721**               |
| 4C       | Native  | pod-to-pod | other-node | **10,767**    | **11,296**               |
| 8C       | Overlay | pod-to-pod | same-node  | **25,537**    | **94,666**               |
| 8C       | Native  | pod-to-pod | same-node  | **21,410**    | **88,831**               |
| 8C       | Overlay | pod-to-pod | other-node | **11,113**    | **11,148**               |
| 8C       | Native  | pod-to-pod | other-node | **10,768**    | **10,776**               |

> Same-node multi-stream throughput exceeds physical NIC limits because data travels on the loopback interface — bound by CPU and kernel stack performance, not the physical NIC.

## Comparison Analysis

### Key Metrics

| Metric                                 | Overlay vs Native (4C) | Overlay vs Native (8C) | Consistent? |
| -------------------------------------- | ---------------------- | ---------------------- | ----------- |
| **Same-node pod-to-pod TCP_RR Mean**   | Overlay **17% faster** | Overlay **16% faster** | ✅ Yes      |
| **Same-node pod-to-pod TCP_RR P99**    | Overlay 17% lower      | Overlay 16% lower      | ✅ Yes      |
| **Same-node multi-stream throughput**  | Overlay 15% higher     | Overlay 7% higher      | ✅ Yes      |
| **Other-node multi-stream throughput** | ~11.5 Gbps (tie)       | ~11 Gbps (tie)         | ✅ Yes      |
| **Other-node pod-to-pod TCP_RR**       | Unstable / varies      | Unstable / varies      | ❌ see text |

### Key Findings

#### Same-Node Latency: Overlay's Advantage is Clear and Stable

Overlay's BPF host routing performs endpoint lookup and redirect at the `cilium_host` device ingress, skipping the netfilter / conntrack / FIB overhead that Native's Legacy host routing must go through. This advantage is independent of CPU count and VPC topology — **deviations across multiple runs are < 1%, making this a reliable conclusion**.

| Metric                 | Overlay   | Native    | Gap                    |
| ---------------------- | --------- | --------- | ---------------------- |
| Same-node RR Mean      | 31.27µs   | 37.62µs   | Overlay **17% faster** |
| Same-node RR P99       | 44µs      | 53µs      | Overlay 17% faster     |
| Same-node multi-stream | 75.6 Gbps | 64.1 Gbps | Overlay **15% higher** |

> Same-node multi-stream throughput (loopback) far exceeds physical NIC limits — it reflects CPU/kernel stack processing power, not cross-node performance. Overlay is consistently 7-15% higher, but this is a local benchmark, not a cross-node metric.

#### Cross-Node Latency: Variable, No Stable Conclusion

Cross-node latency is heavily influenced by **VPC physical topology (switch hops / physical distance between nodes)**. Different node pairs in different subnets can produce different baselines. Across three test runs, the trend was inconsistent — the gap (~10-20µs) is well within noise.

Practical takeaway: **cross-node latency is not a decision factor** — the gap is far smaller than application-layer latency jitter and imperceptible in production.

#### Cross-Node Multi-Stream Throughput: No Difference

Both modes reach ~**11 Gbps** for multi-stream throughput, with no meaningful difference. This is close to SA5's burst bandwidth cap (10 Gbps), confirming the Cilium datapath is not the bottleneck.

:::note[Throughput Stability]
Cross-node multi-stream throughput occasionally falls to ~1.7 Gbps (baseline bandwidth). This is because SA5's burst mechanism uses a credit-based model, and netperf's PPS is sometimes insufficient to consume burst credits. **These run-to-run variations are NOT a mode difference — they reflect the test tool's limitation.** If throughput appears low, re-run the test 2-3 times.
:::

#### Cross-Node Single-Stream Throughput: Unstable, Not a Reliable Metric

Single-stream throughput typically falls at or near baseline bandwidth (1.5-3 Gbps), occasionally triggering burst. No mode conclusion can be drawn from this metric.

## Selection Guide

| Scenario                                                                   | Recommended                 | Reason                                                                                                                       |
| -------------------------------------------------------------------------- | --------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| **Same-node high-frequency small-packet workloads (RPC / KV / MQ)**        | Overlay (VPC-CNI) ⭐        | BPF host routing provides a stable **~17%** latency advantage for same-node traffic — the most reliable conclusion           |
| **Pod IPs must match VPC IPs (VPC routing / CLB / security groups / CCN)** | Native Routing (VPC-CNI) ⭐ | Pod IPs as VPC IPs is Native's core value; cross-node throughput matches Overlay                                             |
| **Cross-node bulk traffic (8+ streams)**                                   | No difference               | Both fill the VPC bandwidth cap with multi-stream concurrency                                                                |
| **Cross-node distributed services**                                        | No difference               | Cross-node latency is dominated by VPC topology, not mode differences; the gap is 10-20µs and imperceptible                  |
| **East-west NetworkPolicy / Hubble / KPR / Egress Gateway**                | No difference               | These are application-layer Cilium capabilities, independent of the host routing path                                        |
| **Operational simplicity (no VPC-CNI chaining dependency)**                | Overlay (VPC-CNI) ⭐        | Overlay gives Cilium full control of Pod networking, no VPC-CNI chaining required, simpler configuration and troubleshooting |

### Summary

**The only reliable performance difference is same-node latency: Overlay is ~17% faster.** For cross-node scenarios, there is no stable difference. If your workload is predominantly cross-node, performance is not a decision factor — both modes have identical cross-node throughput and full core capabilities (NetworkPolicy / Hubble / KPR). Choose based on operational preference and environment constraints.

For a deep dive into the two host routing paths and their hit conditions, see [Cilium Host Routing: Legacy vs BPF](./host-routing.md).

## FAQ

### Why clean up cilium-test-\* namespace before perf?

On startup, `cilium connectivity perf` runs `kubectl delete ns cilium-test-1`. However, TKE clusters have a gatekeeper policy `baseline.gatekeeper.sh / block-namespace-deletion-rule` that **prevents namespace deletion when Pods still exist**:

```text
admission webhook "baseline.gatekeeper.sh" denied the request:
[block-namespace-deletion-rule] The Namespace cilium-test-1 is not allowed
to be deleted. Reason: It is not allowed to delete a namespace when it
includes any pod resource.
```

If a previous `cilium connectivity test` had failures (e.g., the LRP edge case that always fails on Native), cilium-cli **preserves** test resources (namespace + Deployment + Pod) for debugging — these Pods block the namespace deletion step, causing the script to hang:

```text
🔥 [cls-cluster] Deleting connectivity check deployments...
⌛ [cls-cluster] Waiting for namespace cilium-test-1 to disappear
(stuck forever)
```

`cilium.sh perf` cleans up before the main flow: it deletes Deployment / DaemonSet / StatefulSet / ReplicaSet / Job / CronJob resources that hold Pods → waits for Pods to disappear (using `--grace-period=0 --force` if necessary) → then deletes the namespace. This bypasses the gatekeeper restriction.

For manual runs that hang, clean up with:

```bash
for ns in cilium-test-1 cilium-test-ccnp1 cilium-test-ccnp2; do
  kubectl -n $ns delete deployment,daemonset,statefulset,replicaset,job,cronjob --all --wait=false --ignore-not-found
done
sleep 30  # wait for Pods to actually disappear
for ns in cilium-test-1 cilium-test-ccnp1 cilium-test-ccnp2; do
  kubectl delete ns $ns --ignore-not-found
done
```

### Why recommend `--streams 8`?

SA5 instances have queue count = vCPU count (capped at 48). Real-world measurements:

| Instance | Queues | `--streams=4` | `--streams=8`  | `--streams=16` |
| -------- | ------ | ------------- | -------------- | -------------- |
| 4C       | 4      | ~1.7 Gbps     | **~11.8 Gbps** | —              |
| 8C       | 8      | ~1.7 Gbps     | **~11.1 Gbps** | ~3.4 Gbps      |

8 streams fill the burst bandwidth on both instance sizes; 16 streams actually reduce throughput (per-stream bandwidth gets too thin for PPS to consume burst credits). **`--streams 8` is recommended as the default.** For other instance types, set `--streams` to 2× the queue count (capped at 64) to fill burst bandwidth.

## Related Links

- [Install Cilium](../install.md)
- [Cilium Connectivity Test](./connectivity-test.md)
- [Cilium Host Routing: Legacy vs BPF](./host-routing.md)
- [Cilium Performance Documentation](https://docs.cilium.io/en/stable/operations/performance/)

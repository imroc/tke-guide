# Cilium Performance Test

This document describes how to run network performance tests on cilium installed on a TKE cluster, and presents the measured results for each recommended installation scheme.

Cilium provides the official [`cilium connectivity perf`](https://docs.cilium.io/en/stable/operations/performance/benchmark/) performance test tool. It uses netperf to deploy Pods in the cluster and run TCP_RR (request-response latency), TCP_STREAM (throughput), and other tests, covering **same-node / cross-node** × **Pod network / Host network** — a total of four network combinations.

## Test Methods

### One-Click Script

The [one-click install script](../install.md#one-click-install-script) `cilium.sh` provides a `perf` subcommand that wraps `cilium connectivity perf`:

```bash
bash -c "$(curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh)" -- perf
```

If the GitHub URL is not accessible from your network, use the site mirror:

```bash
bash -c "$(curl -sfL https://imroc.cc/tke/scripts/cilium.sh)" -- perf
```

:::tip[About Concurrent Stream Count]

For instance types like SA5 that support burst bandwidth, the default 4 streams may not trigger bursting. We recommend using 8 streams:

```bash
# Using cilium CLI directly
cilium connectivity perf --streams 8

# Or through the one-click script
bash -c "$(curl -sfL ...)" -- perf --streams 8
```

8 streams have been verified to stably saturate the burst bandwidth on all SA5 specifications, giving a more accurate throughput ceiling.

:::

Compared to running `cilium connectivity perf` directly, the script does the following:

- **Replaces images**: The netperf image is replaced with a mirror accessible from the TKE internal network (`quay.tencentcloudcr.com/cilium/network-perf`), so nodes can pull the image without public network access
- **Automatically cleans up previous resources**: Cleans up the `cilium-test-*` namespace left from previous runs beforehand. `cilium connectivity perf` runs `kubectl delete ns cilium-test-1` at startup, but TKE's gatekeeper prevents namespace deletion when it still contains Pods, so without pre-cleaning the script would hang (see [FAQ](#why-clean-up-the-cilium-test--namespace-before-running-perf))
- **Duration measurement**: Prints total elapsed time after the test completes

### Manual Testing

First install the [cilium CLI](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli):

```bash
cilium connectivity perf \
  --streams 8 \
  --performance-image quay.tencentcloudcr.com/cilium/network-perf:3.20-1772622563-6fd6a90
```

Common `cilium connectivity perf` parameters:

- `--duration 10s`: Each RR/STREAM test runs for 10 seconds
- `--samples 1`: Run each test once (can be increased for averaging)
- `--streams`: TCP_STREAM_MULTI concurrent stream count (default 4, recommended 8)
- `--rr / --throughput / --throughput-multi`: Test TCP_RR, TCP_STREAM, TCP_STREAM_MULTI by default
- `--pod-net / --host-net / --other-node / --same-node`: All enabled by default (covers Pod network + Host network + same/cross-node, 4 combinations)
- Add `--udp` for UDP testing, `--crr` for TCP_CRR (reconnects on each connection), `--bandwidth` for bandwidth rate limiting

See `cilium connectivity perf --help` for more parameters.

### Test Mode Description

| Test Type          | Description                              | What It Measures                              |
| ------------------ | ---------------------------------------- | --------------------------------------------- |
| `TCP_RR`           | TCP Request-Response, repeatedly sends small requests and waits for responses | **Latency** (µs, lower is better); OP/s = transactions per second |
| `TCP_STREAM`       | Single TCP stream continuous send        | **Single-stream throughput** (Mb/s, higher is better) |
| `TCP_STREAM_MULTI` | Multiple concurrent TCP streams (adjust with `--streams`) | **Multi-stream concurrent throughput** (Mb/s) |

### Network Combination Description

| Scenario       | Node       | Description                                          | Data Path                                                                            |
| -------------- | ---------- | ---------------------------------------------------- | ------------------------------------------------------------------------------------ |
| `pod-to-pod`   | same-node  | client Pod → same-node server Pod                    | client veth → cilium ebpf → server veth                                             |
| `pod-to-pod`   | other-node | client Pod → cross-node server Pod                   | client veth → cilium ebpf → NIC out → underlay → peer NIC → cilium ebpf → server veth |
| `host-to-host` | same-node  | client (hostNetwork) → same-node server (hostNetwork) | host stack → host stack (does not go through cilium veth path)                      |
| `host-to-host` | other-node | client (hostNetwork) → cross-node server (hostNetwork) | host stack → NIC → underlay → peer NIC → host stack                                 |

:::tip[Notes on Interpreting Results]

Performance data **strongly depends on the instance type, VPC bandwidth, kernel version, and other concurrent workloads**. The values provided in this document are measured on idle, newly created clusters and are intended only as a reference for comparing different cilium installation schemes — they should not be used as production performance baselines.

The TCP_STREAM test in `cilium connectivity perf` (based on netperf) uses relatively large default buffers and limited per-connection PPS, making it difficult to trigger the burst bandwidth mechanism specific to Tencent Cloud instance types. In multi-stream scenarios (`--streams 8`), cross-node throughput generally reflects the instance's baseline bandwidth, but the burst ceiling requires tools like iperf3 for accurate measurement. This document focuses on **relative differences** between modes rather than absolute values.

:::

## Test Environment

| Item             | Value                                                               |
| ---------------- | ------------------------------------------------------------------- |
| Kubernetes Version | v1.34.1 (containerd 1.7.28)                                        |
| Cilium Version   | v1.19.4                                                             |
| Cilium CLI Version | v0.19.4                                                             |
| Node OS          | TencentOS Server 4 (kernel 6.6.117-45.7.3.tl4.x86_64)               |
| Node Count       | 3 nodes                                                             |
| Installation     | [One-click install script](../install.md#one-click-install-script) `cilium.sh install` |
| perf parameters  | `--streams 8` (8 concurrent streams)                                |
| Native Mode      | Legacy Host Routing (see [Native Routing Details](./native-routing.md)) |
| Overlay Mode     | BPF Host Routing (see [Native Routing Details](./native-routing.md))   |

### Test Instance Types

| Spec                | vCPU | Memory | Baseline/Burst Bandwidth | Queue Count | Rationale                   |
| ------------------- | ---- | ------ | ------------------------ | ----------- | --------------------------- |
| SA5.LARGE8 (4C)     | 4    | 8G     | 1.5 / 10 Gbps            | 4           | Most common entry-level spec on TKE |
| SA5.2XLARGE16 (8C)  | 8    | 16G    | 3 / 10 Gbps              | 8           | Common upgrade spec, double queue count |

## Test Results Overview

### TCP_RR (Request-Response Latency, µs)

| Spec | Mode    | Scenario   | Node       | Mean       | P50 | P90 | P99 | OP/s  |
| ---- | ------- | ---------- | ---------- | ---------- | --- | --- | --- | ----- |
| 4C   | Overlay | pod-to-pod | same-node  | **31.27**  | 31  | 34  | 44  | 31736 |
| 4C   | Native  | pod-to-pod | same-node  | **37.62**  | 37  | 41  | 53  | 26409 |
| 4C   | Overlay | pod-to-pod | other-node | **94.29**  | 94  | 100 | 116 | 10576 |
| 4C   | Native  | pod-to-pod | other-node | **112.83** | 113 | 119 | 138 | 8843  |
| 8C   | Overlay | pod-to-pod | same-node  | **31.94**  | 32  | 34  | 43  | 31092 |
| 8C   | Native  | pod-to-pod | same-node  | **38.03**  | 37  | 41  | 51  | 26135 |
| 8C   | Overlay | pod-to-pod | other-node | **106.21** | 105 | 114 | 127 | 9394  |
| 8C   | Native  | pod-to-pod | other-node | **94.13**  | 93  | 99  | 109 | 10598 |

### TCP_STREAM / TCP_STREAM_MULTI (Throughput, Mb/s)

| Spec | Mode    | Scenario   | Node       | Single Stream | Multi-stream (8 concurrent) |
| ---- | ------- | ---------- | ---------- | ------------- | --------------------------- |
| 4C   | Overlay | pod-to-pod | same-node  | **22,997**   | **75,623**                  |
| 4C   | Native  | pod-to-pod | same-node  | **29,329**   | **64,128**                  |
| 4C   | Overlay | pod-to-pod | other-node | **11,116**   | **11,721**                  |
| 4C   | Native  | pod-to-pod | other-node | **10,767**   | **11,296**                  |
| 8C   | Overlay | pod-to-pod | same-node  | **25,537**   | **94,666**                  |
| 8C   | Native  | pod-to-pod | same-node  | **21,410**   | **88,831**                  |
| 8C   | Overlay | pod-to-pod | other-node | **11,113**   | **11,148**                  |
| 8C   | Native  | pod-to-pod | other-node | **10,768**   | **10,776**                  |

> Same-node multi-stream throughput far exceeds the NIC bandwidth limit because data is transmitted over the loopback device (not through the physical NIC), and is limited by CPU and kernel stack performance.

## Comparative Analysis

### Key Metrics Comparison

| Metric                             | Overlay vs Native (4C) | Overlay vs Native (8C) | Trend Consistency |
| ---------------------------------- | ---------------------- | ---------------------- | ----------------- |
| **Same-node pod-to-pod TCP_RR Mean** | Overlay **17% faster**  | Overlay **16% faster**  | ✅ Consistent    |
| **Same-node pod-to-pod TCP_RR P99**  | Overlay 17% faster    | Overlay 16% faster    | ✅ Consistent    |
| **Same-node multi-stream throughput** | Overlay 15% higher    | Overlay 7% higher     | ✅ Consistent    |
| **Cross-node multi-stream throughput** | Nearly identical (~11.5 Gbps) | Nearly identical (~11 Gbps) | ✅ Consistent |
| **Cross-node pod-to-pod TCP_RR**      | High variance, inconsistent | High variance, inconsistent | ❌ See below |

### Key Findings

#### Same-Node Latency: Overlay Has a Clear and Stable Advantage

Overlay's BPF host routing performs endpoint lookup + redirect at the `cilium_host` device ingress, skipping the full netfilter / conntrack / FIB overhead that Legacy host routing must go through in Native mode. This advantage is not affected by vCPU count or VPC topology. **Run-to-run deviation across multiple tests is < 1%, making this conclusion reliable**.

| Metric            | Overlay   | Native    | Difference            |
| ----------------- | --------- | --------- | --------------------- |
| Same-node RR Mean | 31.27µs   | 37.62µs   | Overlay **17% faster** |
| Same-node RR P99  | 44µs      | 53µs      | Overlay 17% faster    |
| Same-node multi-stream throughput | 75.6 Gbps | 64.1 Gbps | Overlay **15% higher** |

> Same-node multi-stream throughput (loopback) far exceeds the physical NIC limit and measures CPU/kernel stack processing capability. Overlay is consistently 7-15% higher, but both represent "local data copying" and cannot be used as cross-node performance references.

#### Cross-Node Latency: High Variance, No Stable Conclusion

Cross-node latency is heavily affected by the **VPC physical topology (switch hops / physical distance between nodes)**. The same pair of nodes may have different latency baselines across different clusters and VPC subnets. Across three test runs, the trend varied (sometimes Overlay was faster, sometimes Native), indicating the difference is within statistical noise.

Practical conclusion: **Cross-node latency is not a determining factor for choosing between modes** — the difference (~10-20µs) is far smaller than application-layer latency variance and is imperceptible in production.

#### Cross-Node Multi-Stream Throughput: No Difference

Both instance types show stable multi-stream throughput around **~11 Gbps**, with no substantial difference between Native and Overlay. This value is close to the actual VPC bandwidth ceiling for SA5 instances (SA5 burst bandwidth is 10 Gbps), indicating that cilium's data plane is not the bottleneck at this granularity.

:::note[About Throughput Stability]
Cross-node multi-stream throughput occasionally falls near the baseline bandwidth (~1.7 Gbps) in some runs. This is because SA5's burst bandwidth uses a credit-based mechanism that requires specific conditions to trigger. **The run-to-run variance is not a mode difference between Native and Overlay, but rather the netperf test stack's PPS not being high enough to consume burst credits.** We recommend running 2-3 times and using the data that best reflects peak performance.
:::

#### Cross-Node Single-Stream Throughput: Unstable, Not a Comparison Metric

Single-stream throughput typically falls at or near the baseline bandwidth (1.5-3 Gbps), occasionally triggering bursting. No mode difference conclusions can be drawn from this.

## Recommendations

| Scenario                                                             | Recommendation                   | Reason                                                                                             |
| -------------------------------------------------------------------- | -------------------------------- | -------------------------------------------------------------------------------------------------- |
| **Same-node high-frequency small packets (RPC / KV database / MQ broker)** | Overlay (VPC-CNI) ⭐             | BPF host routing provides a stable ~17% latency advantage for same-node small-packet workloads — the most reliable difference conclusion |
| **Require Pod IP consistency with VPC IP** (VPC routing / CLB / security groups / CCN) | Native Routing (VPC-CNI) ⭐      | Pod IP direct-to-VPC is Native's core value; cross-node throughput is identical to Overlay          |
| **Cross-node high-volume traffic** (stream count ≥ 8)               | No difference                   | Both modes saturate the VPC bandwidth ceiling with multi-stream concurrency                        |
| **Cross-node distributed services**                                  | No difference                   | Cross-node latency is more affected by VPC topology than by mode difference; the gap (10-20µs) is imperceptible at the application layer |
| **East-west NetworkPolicy / Hubble / KPR / Egress Gateway**          | No difference                   | These are application-layer capabilities of cilium, unrelated to the host routing path             |
| **Operational simplicity** (no VPC-CNI chaining dependency / no TKE VPC-CNI limitations) | Overlay (VPC-CNI) ⭐             | In Overlay mode, cilium fully manages Pod networking without relying on VPC-CNI's CNI chaining — simpler configuration and more straightforward troubleshooting |

### Summary

**The only reliable difference is same-node latency: Overlay is about 17% faster than Native.** Cross-node shows no stable difference. If your workloads primarily involve cross-node communication, performance is not a deciding factor for choosing between modes — both achieve identical cross-node multi-stream throughput, and all core capabilities (NetworkPolicy / Hubble / KPR) are fully available. Choose based on operational preference and environmental conditions.

Further reading: [VPC-CNI Native Routing Details](./native-routing.md) provides an in-depth explanation of the two host routing implementations and their enabling conditions.

## FAQ

### Why clean up the cilium-test-\* namespace before running perf?

`cilium connectivity perf` starts with `kubectl delete ns cilium-test-1`. However, TKE clusters have the gatekeeper policy `baseline.gatekeeper.sh / block-namespace-deletion-rule` enabled, which **prevents deleting a namespace that still contains Pods**:

```text
admission webhook "baseline.gatekeeper.sh" denied the request:
[block-namespace-deletion-rule] The Namespace cilium-test-1 is not allowed
to be deleted. Reason: It is not allowed to delete a namespace when it
includes any pod resource.
```

If a previous `cilium connectivity test` run had failed test cases (e.g., the LRP edge case in Native mode), cilium-cli by default **retains** the test resources (namespace + Deployment + Pod) for troubleshooting — these Pods then block the perf run's namespace deletion step, resulting in:

```text
🔥 [cls-cluster] Deleting connectivity check deployments...
⌛ [cls-cluster] Waiting for namespace cilium-test-1 to disappear
(hangs forever)
```

`cilium.sh perf` performs automatic cleanup before the main flow: first delete resources that own Pods (Deployment / DaemonSet / StatefulSet / ReplicaSet / Job / CronJob) → wait for Pods to actually disappear (using `--grace-period=0 --force` if necessary) → then delete the namespace. This bypasses the gatekeeper restriction and prevents the script from hanging.

If you are running `cilium connectivity perf` manually and it hangs, run the following cleanup commands manually before retrying:

```bash
for ns in cilium-test-1 cilium-test-ccnp1 cilium-test-ccnp2; do
  kubectl -n $ns delete deployment,daemonset,statefulset,replicaset,job,cronjob --all --wait=false --ignore-not-found
done
sleep 30  # wait for Pods to actually disappear
for ns in cilium-test-1 cilium-test-ccnp1 cilium-test-ccnp2; do
  kubectl delete ns $ns --ignore-not-found
done
```

### Why is `--streams` recommended to be 8?

For SA5 instances, the queue count = vCPU count (capped at 48). Measured results:

| Spec | Queue Count | `--streams=4` | `--streams=8`  | `--streams=16` |
| ---- | ----------- | ------------- | -------------- | --------------- |
| 4C   | 4           | ~1.7 Gbps     | **~11.8 Gbps** | —               |
| 8C   | 8           | ~1.7 Gbps     | **~11.1 Gbps** | ~3.4 Gbps       |

8 streams saturate the burst ceiling on both instance types; 16 streams actually decrease throughput (per-stream bandwidth is diluted, PPS insufficient to consume burst credits). Therefore, `--streams 8` is recommended as a general-purpose value. If switching to a different instance type, adjust proportionally based on the queue count — the rule is: set to 2x the target instance's queue count (capped at 64), which typically saturates the burst bandwidth.

## Related Links

- [Installing Cilium](../install.md)
- [Cilium Connectivity Test](./connectivity-test.md)
- [VPC-CNI Native Routing Details](./native-routing.md)
- [Cilium Performance Documentation](https://docs.cilium.io/en/stable/operations/performance/)

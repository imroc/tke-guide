# Cilium Network Performance Benchmark

This article uses the [`network-benchmark.sh`](https://imroc.cc/tke/scripts/network-benchmark.sh) one-click script to benchmark three TKE networking solutions side by side under **identical hardware, kernel, and VPC environments**, answering the question a TKE user cares most about when choosing a solution: **does replacing kube-proxy with Cilium win or lose on performance?**

The three clusters tested:

- **Cluster A — VPC-CNI + kube-proxy iptables**: traditional approach, performance baseline
- **Cluster B — VPC-CNI + Cilium Native Routing**: Cilium plugs into VPC-CNI via cni-chaining; Pod IPs remain legitimate VPC IPs
- **Cluster C — VPC-CNI + Cilium Overlay (VXLAN)**: Cilium is the sole Pod CNI; Pods use an independent overlay CIDR

Coverage: throughput, HTTP RPS (keepalive/short conn), TCP latency, Service-scale degradation (5000→30000, 4 Endpoints per Service), Hubble overhead, NetworkPolicy L3/L4 and L7 overhead, BPF memory, and component resources.

:::tip[Conclusions first]

- **Throughput and real-workload latency (HTTP p99 @1000 QPS) are identical across all three** — networking-solution differences are invisible under realistic load.
- **Small-scale saturation benchmarks**: iptables RPS leads Cilium (keepalive ~14%, short conn ~2.2x), because it has the shortest data path.
- **Large-scale Services is the watershed**: iptables short-connection performance **collapses linearly** with Service count, getting overtaken by Cilium at around **20,000 Services**; by **30,000 Services** iptables short-conn RPS has dropped to 70%~88% of Cilium's. The larger the scale, the more the balance tips toward Cilium.
- **L7 NetworkPolicy is the one performance cliff**: ~86-89% overhead, enable selectively; L3/L4 policy and Hubble are zero-overhead.

:::

## Glossary

First-time readers of network benchmarks can skim these terms; the tables below use them throughout.

| Term                            | Meaning                                                    | Plain explanation                                                                                                                                                          |
| ------------------------------- | ---------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **RPS**                         | Requests Per Second                                        | How many HTTP requests can be served per second — higher is better. Measured with fortio saturating the CPU.                                                               |
| **keepalive / long connection** | One TCP connection **reused** for many requests            | Like "making one phone call and discussing many things." Connection pools, HTTP keepalive, gRPC all work this way.                                                         |
| **short connection**            | **A new TCP connection per request**, closed after use     | Like "redialing for every sentence." Legacy clients without connection pools, some PHP/CGI scenarios.                                                                      |
| **c64 / c256**                  | concurrency = 64 / 256                                     | How many connections hammer the target simultaneously. c256 is heavier than c64.                                                                                           |
| **TCP_RR**                      | TCP Request/Response latency test                          | Round-trips on an **already-established** connection — measures single round-trip latency. Maps to "long connection."                                                      |
| **TCP_CRR**                     | TCP Connect/Request/Response latency test                  | **Establishes a new connection each time** then does one round-trip — measures full "connect + round-trip + teardown" latency. Maps to "short connection."                 |
| **p50 / p99**                   | 50th / 99th percentile latency                             | p99 = 99% of requests are faster than this. p99 is the key SLO metric for "tail latency / worst experience."                                                               |
| **Gbps**                        | Gigabits per second, throughput bandwidth                  | How much data per second — measures bulk-transfer capability.                                                                                                              |
| **Endpoint**                    | One backend Pod (IP:Port) behind a Service                 | A 4-replica Deployment's Service has 4 Endpoints.                                                                                                                          |
| **conntrack**                   | Kernel connection tracking table                           | Records each connection's forwarding decision; once established, subsequent packets hit the table directly without re-routing. This is why long connections don't degrade. |
| **KUBE-SERVICES chain**         | The iptables rule chain kube-proxy builds for all Services | A new connection's first packet **linearly scans** this chain to find its Service; chain length ≈ Service count — the root of iptables O(n) degradation.                   |
| **BPF map**                     | Cilium's in-kernel hash table for Services/Endpoints       | Cilium uses it for O(1) lookup — speed independent of Service count.                                                                                                       |
| **O(n) / O(1)**                 | Algorithmic complexity                                     | O(n): cost grows linearly with scale (iptables Service lookup); O(1): cost constant regardless of scale (Cilium BPF map).                                                  |
| **VXLAN**                       | An overlay tunnel encapsulation protocol                   | In Overlay mode, cross-node traffic is wrapped in VXLAN packets (+50-byte header), decoupling Pod networking from the underlying VPC.                                      |

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
- For ten-thousand-scale Service tests, the cluster tier must be large enough (e.g. TKE L500), otherwise total Service count is capped by the cluster limit

:::

### Custom Parameters

```bash
# Multiple rounds (for large instances without QoS concerns)
ROUNDS=3 IPERF_DURATION=120 FORTIO_DURATION=120 bash network-benchmark.sh --dir ./bench

# Custom Service scale steps and endpoints per service
SVC_SCALE_STEPS="5000,10000,20000,30000" SVC_ENDPOINTS=4 bash network-benchmark.sh
```

| Environment Variable  | Default                | Description                                           |
| --------------------- | ---------------------- | ----------------------------------------------------- |
| `IPERF_DURATION`      | 30                     | iperf3 test duration per round (seconds)              |
| `FORTIO_DURATION`     | 60                     | fortio / netperf test duration per round (seconds)    |
| `ROUNDS`              | 1                      | Repetition rounds per scenario                        |
| `ROUND_SLEEP`         | 30                     | Inter-round wait (seconds), for burst credit recovery |
| `SVC_SCALE_STEPS`     | 5000,10000,20000,30000 | Comma-separated Service scale steps (ascending)       |
| `SVC_ENDPOINTS`       | 4                      | Endpoints per dummy Service                           |
| `SVC_CREATE_PARALLEL` | 4                      | Parallel workers for Service creation                 |
| `AUTO_FIX_LB_MAP`     | (interactive prompt)   | `true` auto-raises Cilium LB map without prompting    |

:::tip[About the Endpoint count per dummy Service]

The load test hits a **single** fronting Service, whose new-connection first packet scans the `KUBE-SERVICES` chain (length = **Service count**), regardless of how many Endpoints each dummy svc has. Endpoints only inflate total rule count / BPF LB map / creation time, contributing nothing to the hot path. So we use 4 Endpoints (close to real multi-replica) and **drive degradation via Service count**.

:::

:::warning[Large-scale tests require raising Cilium's LB map limit]

Cilium's Service load-balancing BPF map defaults to `bpf-lb-map-max=65536`. Each Service consumes roughly `1 + endpoint count` LB entries, so **30,000 Services × (4+1) ≈ 150K entries will exceed the default and overflow the map** — manifesting as an abnormal RPS collapse at large scale (this is forwarding failure, not O(n) degradation, and pollutes the conclusions).

The script automatically preflight-checks capacity before the Service Scale test and interactively asks whether to raise it and restart cilium (`AUTO_FIX_LB_MAP=true` skips the prompt). You can also set it manually:

```bash
kubectl -n kube-system patch configmap cilium-config --type merge \
  -p '{"data":{"bpf-lb-map-max":"1048576"}}'
kubectl -n kube-system rollout restart ds/cilium
```

:::

### Tools and Metrics

| Tool    | Test Content                                          | Metric                         |
| ------- | ----------------------------------------------------- | ------------------------------ |
| iperf3  | Cross-node TCP throughput                             | Gbps (1/8/16 parallel streams) |
| fortio  | HTTP RPS (keep-alive / short conn)                    | req/s                          |
| netperf | TCP_RR / TCP_CRR latency                              | p50 / p99 microseconds         |
| fortio  | Multi-step Service scale (5000→30000) degradation     | Degradation percentage         |
| fortio  | Hubble on/off RPS comparison (Cilium only)            | Overhead percentage            |
| fortio  | NetworkPolicy L3/L4 + L7 RPS comparison (Cilium only) | Overhead percentage            |
| bpftool | BPF map memory statistics (Cilium only)               | MB                             |

## Test Environment

| Item                | Cluster A (iptables)          | Cluster B (Cilium Native)                      | Cluster C (Cilium Overlay)                    |
| ------------------- | ----------------------------- | ---------------------------------------------- | --------------------------------------------- |
| Network Solution    | VPC-CNI + kube-proxy iptables | VPC-CNI + Cilium cni-chaining (Native Routing) | Cilium VXLAN Overlay (Cilium as sole Pod CNI) |
| Kubernetes Version  | v1.34.1-tke.5                 | v1.34.1-tke.5                                  | v1.34.1-tke.5                                 |
| Cluster Tier        | L500                          | L500                                           | L500                                          |
| Cilium Version      | N/A                           | v1.19.4                                        | v1.19.4                                       |
| kube-proxy replaced | No (iptables mode)            | Yes (eBPF)                                     | Yes (eBPF)                                    |
| Node OS             | TencentOS Server 4            | TencentOS Server 4                             | TencentOS Server 4                            |
| Kernel Version      | 6.6.117-45.11.2               | 6.6.117-45.11.2                                | 6.6.117-45.11.2                               |
| Node Spec           | SA5.LARGE8 (4C 8G)            | SA5.LARGE8 (4C 8G)                             | SA5.LARGE8 (4C 8G)                            |
| Node Count          | 3                             | 3                                              | 3                                             |

All three clusters share the same VPC, hardware spec, kernel version (6.6.117-45.11.2), and cluster tier (L500, supporting 30K-scale Services). The Service Scale test attaches 4 Endpoints per Service. All RPS / latency tests are cross-node (different Workers).

## At a Glance

| Dimension                      | iptables   | Cilium Native | Cilium Overlay | Winner                                   |
| ------------------------------ | ---------- | ------------- | -------------- | ---------------------------------------- |
| Pod2Pod throughput (8 streams) | 10.43 Gbps | 10.43 Gbps    | 10.77 Gbps     | Tie                                      |
| RPS keepalive (c64)            | 115,434    | 100,416       | 100,955        | iptables (+14%)                          |
| RPS short conn (c64, small)    | 31,365     | 13,826        | 14,193         | iptables (+2.2x)                         |
| TCP_RR p99 (baseline)          | 107 µs     | 103 µs        | 118 µs         | Within noise, no clear winner            |
| HTTP p99 @1000 QPS             | 0.99 ms    | 0.99 ms       | 0.99 ms        | Tie                                      |
| **Short-conn RPS @20000 svc**  | 12,916     | 11,815        | **13,080**     | **Crossover: Overlay overtakes**         |
| **Short-conn RPS @30000 svc**  | **9,057**  | **10,286**    | **12,879**     | **Cilium clearly ahead**                 |
| L3/L4 NetworkPolicy overhead   | N/A        | -0.0%         | -2.2%          | Zero overhead                            |
| L7 NetworkPolicy overhead      | N/A        | -86.1%        | -88.7%         | Perf cliff, enable selectively           |
| Hubble L3/L4 overhead          | N/A        | -0.3%         | -0.2%          | Zero overhead                            |
| BPF map memory / node          | N/A        | 289.7 MB      | 289.7 MB       | Pre-allocated, doesn't grow              |
| Datapath component mem / node  | 926 MB     | 1111 MB       | 1104 MB        | See [Section 6](#6-resource-consumption) |

Details below, with deep dives on the counter-intuitive points.

## 1. Throughput: All Three Equivalent

| Scenario                 | iptables   | Cilium Native | Cilium Overlay |
| ------------------------ | ---------- | ------------- | -------------- |
| Node hostNet (8 streams) | 10.44 Gbps | 10.44 Gbps    | 10.82 Gbps     |
| Pod-to-Pod (single)      | 10.43 Gbps | 10.43 Gbps    | 10.75 Gbps     |
| Pod-to-Pod (8 streams)   | 10.43 Gbps | 10.43 Gbps    | 10.77 Gbps     |
| Pod-to-Pod (16 streams)  | 10.43 Gbps | 10.43 Gbps    | 10.77 Gbps     |
| Via Service (8 streams)  | 10.43 Gbps | 10.43 Gbps    | 10.77 Gbps     |

All three saturate ~10.4-10.8 Gbps, approaching the SA5.LARGE8 burst bandwidth ceiling — **throughput is fully equivalent**. The ±4% inter-cluster variance is VPC burst bandwidth fluctuation. 16 streams matches 8 streams, confirming 8 parallel streams already saturate the NIC.

Overlay's large-packet throughput is even slightly higher despite VXLAN — the 50-byte header is negligible at MTU-level packet sizes. VXLAN's cost only shows in small-packet high-frequency scenarios (see RPS).

## 2. RPS: iptables Leads at Small Scale, But That's the Shortest-Path Dividend

| Scenario                   | iptables         | Cilium Native    | Cilium Overlay   |
| -------------------------- | ---------------- | ---------------- | ---------------- |
| Pod-to-Pod c64 keepalive   | 115,903 req/s    | 100,338 req/s    | 93,159 req/s     |
| Via Svc c64 keepalive      | 115,434 req/s    | 100,416 req/s    | 100,955 req/s    |
| Via Svc c256 keepalive     | 119,434 req/s    | 102,827 req/s    | 94,148 req/s     |
| **Via Svc c64 short conn** | **31,365** req/s | **13,826** req/s | **14,193** req/s |

### Keepalive: iptables leads by ~14%

iptables (115K) > Native (100K) ≈ Overlay (101K). The gap is small but consistent, due to **path length**:

- **iptables has the shortest path**: each packet traverses the kernel stack once; kube-proxy's DNAT is just a few rule matches after conntrack hits.
- **Cilium Native**: VPC-CNI cni-chaining forces per-endpoint routing, Pod traffic bypasses `cilium_host`, traversing the kernel stack _and_ layering on eBPF conntrack + Service + Policy — one extra layer per packet.
- **Cilium Overlay**: BPF Host Routing skips part of the kernel stack, but every cross-node packet does VXLAN encap/decap — comparable in magnitude to Native's double-processing.

(Note: Overlay's lower c256 / pod2pod single figures are single-round noise; the svc-keepalive c64 of 100,955 — essentially on par with Native — is more representative.)

### Short conn: iptables leads by 2.2x — why so much?

The short-conn baseline iptables (31,365) is **2.2x** Cilium (~14,000), far larger than the keepalive gap. The root cause is that **keepalive and short-conn hit completely different code paths**:

- **Keepalive**: once established, every request reuses the same TCP connection; the forwarding decision is conntrack-cached, and subsequent packets hit cache — all three are just "conntrack lookup + forward", differing only by that one fixed layer.
- **Short conn**: every request opens a new TCP connection; every SYN must **fully redo Service selection + conntrack entry creation**. Cilium's disadvantage is amplified here:
  - Native does eBPF (BPF conntrack creation + backend selection) **on top of** kernel connection setup — genuinely "double work";
  - iptables, while also traversing rules per new connection, has an extremely short rule chain at **small scale (baseline has almost no dummy svc)**, so the cost is low.

In other words: the 2.2x short-conn baseline gap is iptables's dividend under "short rule chains". **This premise vanishes as Service scale grows** — see Section 4, the pivot of this whole article.

:::tip[But these differences are invisible to real workloads]

All three solutions' absolute RPS (short conn 14K-31K, keepalive 100K-115K) **far exceed** the load of a typical microservice Pod (usually < 10K req/s). The differences only appear under fortio's CPU-saturating extreme benchmarks. Under realistic load all three perform identically (see HTTP p99 @1000 QPS below).

:::

## 3. Latency: Identical Under Real Load

| Metric             | iptables | Cilium Native | Cilium Overlay |
| ------------------ | -------- | ------------- | -------------- |
| TCP_RR p50         | 84 µs    | 85 µs         | 95 µs          |
| TCP_RR p99         | 107 µs   | 103 µs        | 118 µs         |
| TCP_CRR p99        | 487 µs   | 546 µs        | 558 µs         |
| HTTP p99 @1000 QPS | 0.99 ms  | 0.99 ms       | 0.99 ms        |

:::tip[Latency differences vanish under real load]

- **HTTP p99 @1000 QPS: 0.99 ms, identical.** This is the single most important line. Under a realistic request rate (1000 QPS), all three have identical p99 latency. The 14% and 2.2x gaps from the RPS section vanish once the application does any real work (DB query, serialization, business logic). **The networking choice does not affect real application latency.**
- **TCP_RR p99 (keepalive round-trip)**: all within the ~100-120 µs noise band, with no stable direction (this time Native is even slightly below iptables). Sub-millisecond differences are invisible at the application layer.
- **TCP_CRR p99 (new-connection round-trip)**: iptables (487 µs) slightly below Cilium (546-558 µs), consistent with short-conn RPS — new connections cost Cilium one extra eBPF layer. This gap, too, reverses as Service scale grows (per-connect scan cost rises with svc count).

:::

:::note[On latency degradation with scale]

Latency and RPS are two sides of the same coin (under saturation, `RPS ≈ concurrency / latency`). In theory iptables's TCP_CRR p99 rises linearly with Service count while Cilium stays flat, paralleling the short-conn RPS degradation curve below. This round's per-scale latency data has sampling-timing noise, so it is omitted for now; this section will be filled in after a clean re-measurement.

:::

## 4. Service Scale Degradation: The Core Pivot

This is where replacing kube-proxy with Cilium pays off most. Method: incrementally create 5000 → 30000 dummy Services (**each with 4 Endpoints**), wait for sync at each step, benchmark, and compare degradation vs baseline.

### Keepalive: virtually zero degradation throughout

| Service count | iptables | Cilium Native | Cilium Overlay |
| ------------- | -------- | ------------- | -------------- |
| 5000          | -0.2%    | 0.0%          | -0.1%          |
| 10000         | -2.1%    | -0.7%         | 0.1%           |
| 20000         | -0.3%    | -1.5%         | 0.2%           |
| 30000         | -0.7%    | -9.2%         | 0.5%           |

Keepalive barely degrades — conntrack caches the first-packet decision, subsequent packets skip rule chains / BPF maps. **Production workloads using connection pools or HTTP keepalive are largely immune to Service scale.** (Native's -9.2% at 30000 svc is a single-round outlier from agent sync pressure; compared to Overlay's +0.5% at the same scale, it's clearly not datapath degradation.)

### Short conn: iptables collapses linearly, Cilium rock-solid, overtaken at ~20k svc

| Service count                    | iptables            | Cilium Native       | Cilium Overlay     |
| -------------------------------- | ------------------- | ------------------- | ------------------ |
| Baseline (small)                 | 31,365 req/s        | 13,826 req/s        | 14,193 req/s       |
| 5000                             | 22,237 (-29.1%)     | 12,774 (-7.6%)      | 13,122 (-7.5%)     |
| 10000                            | 17,261 (-45.0%)     | 11,895 (-14.0%)     | 12,746 (-10.2%)    |
| **20000**                        | **12,916 (-58.8%)** | 11,815 (-14.5%)     | **13,080 (-7.8%)** |
| **30000**                        | **9,057 (-71.1%)**  | **10,286 (-25.6%)** | **12,879 (-9.3%)** |
| KUBE-SERVICES chain / LB entries | 5011→30003          | 30018→179946        | 30042→179988       |

:::tip[O(n) vs O(1): the crossover appears at ~20,000 Services]

Short connections are the real test — every new connection's SYN must redo Service selection, missing the conntrack cache.

- **iptables is O(n) sequential traversal**: each SYN sequentially matches the `KUBE-SERVICES` chain (length = Service count). More Services, longer scan. Short-conn RPS drops from a 31K baseline to 9K at 30000 svc (**-71%**), collapsing nearly linearly with Service count.
- **Cilium is O(1) BPF hash map lookup**: lookup time is independent of Service count. Native degrades to -25.6%, Overlay only -9.3% — far gentler than iptables.

**The crossover is clearly visible**:

- **~20,000 Services**: iptables (12,916) has been overtaken by Overlay (13,080) and is essentially level with Native (11,815).
- **30,000 Services**: iptables (9,057) drops well below Native (10,286) and Overlay (12,879) — **both Cilium modes clearly lead**, iptables short-conn RPS is just 70% of Overlay's.

In one sentence: **small-scale iptables leads via "short path", gets overtaken by Cilium at ~20,000 Services, and the gap widens thereafter.** Keepalive workloads don't care either way.

:::

:::note[Why endpoint count doesn't affect this curve]

Degradation is driven by `KUBE-SERVICES` chain length (≈Service count), not by per-svc Endpoint count — the load test hits a single fronting Service, whose new-connection first packet scans this chain and jumps away once it matches its own entry, never entering the per-dummy-svc backend rules. So whether each dummy svc has 4 or 50 Endpoints, the degradation curve is the same. In real workloads, **Service count** is the key variable for iptables short-conn degradation.

:::

## 5. Hubble & NetworkPolicy: L3/L4 Zero-Overhead, L7 a Performance Cliff

### Hubble Observability (Cilium only)

| Metric       | Cilium Native | Cilium Overlay |
| ------------ | ------------- | -------------- |
| Hubble ON    | 100,007 req/s | 101,434 req/s  |
| Hubble OFF   | 100,271 req/s | 101,675 req/s  |
| **Overhead** | **-0.3%**     | **-0.2%**      |

Hubble L3/L4 observability overhead is within the ±0.5% noise range — **effectively zero**. Hubble only samples events into a ring buffer in the datapath, not participating in forwarding. Enable L3/L4 flow observation across production freely.

### NetworkPolicy L3/L4: zero overhead

| Metric            | Cilium Native | Cilium Overlay |
| ----------------- | ------------- | -------------- |
| No policy         | 99,985 req/s  | 101,514 req/s  |
| L3/L4 CNP applied | 99,965 req/s  | 99,249 req/s   |
| **Overhead**      | **-0.0%**     | **-2.2%**      |

L3/L4 CiliumNetworkPolicy is implemented in eBPF via identity lookup + bitmap match, with no extra memory copy or context switch — **zero overhead** (Overlay's -2.2% is within single-round noise). Apply broadly across all workloads.

### NetworkPolicy L7: a performance cliff, enable selectively

| Metric         | Cilium Native | Cilium Overlay |
| -------------- | ------------- | -------------- |
| No policy      | 99,985 req/s  | 101,514 req/s  |
| L7 CNP applied | 13,883 req/s  | 11,483 req/s   |
| **Overhead**   | **-86.1%**    | **-88.7%**     |

:::warning[Enable L7 policy only on Pods that need it]

L7 CiliumNetworkPolicy (e.g. HTTP path/method filtering) redirects traffic to an **Envoy proxy** for application-layer parsing, dropping RPS by **86-89%**. This is not a Cilium flaw, but the inherent cost of L7 visibility (any L7 policy / Service Mesh has comparable cost).

Correct usage:

- **L3/L4 policy**: covers the vast majority of production security needs (allow/deny by IP, port, namespace labels), zero overhead, enable broadly.
- **L7 policy**: enable selectively only on Pods that genuinely need application-layer control (external ingress gateways, sensitive API auditing). Don't roll out broadly.

:::

## 6. Resource Consumption

### CPU / Memory (full load 30000 svc × 4 ep, steady-state sampling)

| Component              | CPU avg / max | Memory avg / max |
| ---------------------- | ------------- | ---------------- |
| kube-proxy (iptables)  | 8.2m / 16m    | 926 / 928 MiB    |
| Cilium Agent (Native)  | 25.8m / 43m   | 1111 / 1216 MiB  |
| Cilium Agent (Overlay) | 25.4m / 33m   | 1104 / 1228 MiB  |

:::note[At full load, even kube-proxy memory approaches 1 GB]

At full load (30000 svc × 4 ep) all three components reach GB-level memory. kube-proxy (926 MiB) maintains the full in-memory representation of **540K iptables rules** and does rule diffs + full reflushes on every Service/Endpoint change — more rules, more memory. Its CPU is low (8m) because rule matching happens in the kernel.

Cilium Agent (~1.1 GiB) memory is mainly BPF maps (pre-allocated, see below) + endpoint/identity state. CPU (~25m) is also low and stable.

To emphasize: this is the **extreme scale of 30,000 Services**, far beyond what most clusters reach. At normal scale (hundreds to thousands of Services), all three components use hundreds of MiB.

:::

### BPF Map Memory: pre-allocated, doesn't grow with scale

| Metric           | Cilium Native | Cilium Overlay |
| ---------------- | ------------- | -------------- |
| BPF map total    | 289.7 MB      | 289.7 MB       |
| BPF map count    | 64            | 63             |
| Cilium Agent RSS | 870 MB        | 1014 MB        |

Top BPF map memory consumers (identical across clusters; LB map raised to 1020000 to support 30K svc):

| Map name (truncated) | Max Entries | Memory  |
| -------------------- | ----------- | ------- |
| cilium_lb4_affinity  | 1,020,000   | 93.8 MB |
| cilium_lb4_services  | 1,020,000   | 31.1 MB |
| cilium_lb4_backends  | 1,020,000   | 25.2 MB |
| cilium_lb4_reverse   | 1,020,000   | 18.1 MB |
| cilium_ct4_global    | 131,072     | 17.0 MB |

:::note[BPF map pre-allocation]

**BPF maps allocate their maximum memory at creation based on `max_entries`**; adding Services/Endpoints only fills already-allocated space, never growing dynamically. In this test, Services grew from 0 to 30000 yet BPF map total memory stayed steady at ~289.7 MB.

Note: this 289.7 MB is the pre-allocated value with the LB map raised to **1.02M** (to support 30K svc) — the higher the limit, the more is pre-allocated. At the default `bpf-lb-map-max=65536`, BPF map total memory is ~90 MB. **So this number is the result of "reserving for extreme scale," not a normal cluster's footprint.** Set `bpf-lb-map-max` to your needs to control this memory.

:::

## Summary & Selection Guide

### iptables vs Cilium: switch or not?

| Your situation                                        | Recommendation                                                                                |
| ----------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| Few Services (under a few thousand), chasing peak RPS | iptables leads small-scale RPS, keep it; but the gap is invisible under real load             |
| Many Services (≥20K), heavy short-conn                | **Cilium**: from ~20K svc Cilium short-conn RPS overtakes, iptables keeps collapsing linearly |
| Need NetworkPolicy / Hubble observability / Identity  | **Cilium**: L3/L4 policy and Hubble are zero-overhead, iptables lacks them                    |
| Only keepalive workloads (connection pool/keepalive)  | Either: keepalive is insensitive to scale and solution                                        |

Core trade-off: **switching to Cilium loses ~14% keepalive RPS in small-scale saturation benchmarks (invisible under real load), in exchange for non-collapsing short-connection performance at scale + zero-overhead security and observability.** For medium-to-large clusters or those with security/compliance needs, this trade is worth it.

### Cilium Native vs Overlay: architecture, not performance

All performance metric differences are within the noise range (baseline RPS/latency essentially level; on scale degradation Overlay is slightly better than Native, but both far better than iptables). **Choose by network architecture**:

- Pod IP must be directly routable in the VPC (direct CLB attach, cross-cluster / cross-VPC connectivity, legacy monitoring directly hitting Pods) → **Native**
- Pod CIDR decoupled from VPC (IP scarcity, cross-VPC CIDR reuse, Pod count far exceeding ENI capacity) → **Overlay**

> For why BPF Host Routing isn't actually hit in Native mode, and the commonality of cloud-provider Native IPAM, see [VPC-CNI Native Routing Details](./native-routing.md).

### Small scale vs large scale Services

iptables short-conn performance is strongly correlated with Service count (O(n)): from -29% at 5000 svc all the way to -71% at 30000 svc; Cilium is decoupled from Service count (O(1)), gentle throughout. **The crossover is at around 20,000 Services — this is the quantitative basis for large clusters to choose Cilium over kube-proxy.**

For detailed selection guidance, see [Cilium Performance Test - Recommendations](./performance-test.md#recommendations).

## References

- [Cilium Performance Test (cilium connectivity perf)](./performance-test.md)
- [VPC-CNI Native Routing Details](./native-routing.md)
- [Install Cilium](../install.md)

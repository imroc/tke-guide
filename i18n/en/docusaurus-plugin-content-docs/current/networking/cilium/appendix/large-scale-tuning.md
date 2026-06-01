# Cilium Tuning for Large-Scale Clusters

## When to Use This Guide

When your TKE cluster grows past any of the following thresholds, cilium's defaults may show apiserver pressure, cilium-agent OOMs, slow policy compilation, or BPF map exhaustion. Use this guide for tuning:

| Dimension           | Approximate Threshold |
| ------------------- | --------------------- |
| Node count          | ≥ 200                 |
| Pod count           | ≥ 10,000              |
| Service count       | ≥ 1,000               |
| Identity count      | ≥ 1,000               |
| NetworkPolicy count | ≥ 500                 |

Thresholds are guidance only — judge with concrete signals from cilium-agent / cilium-operator / apiserver (resource usage, latency, throttle metrics).

## Tuning Checklist

The table below summarizes every tuning item, sorted by recommended priority and risk:

| Priority                | Item                                                                  | Risk / Cost                            | When to enable                                       |
| ----------------------- | --------------------------------------------------------------------- | -------------------------------------- | ---------------------------------------------------- |
| ⭐ Strongly recommended | [1. Enable CiliumEndpointSlice](#1-enable-ciliumendpointslice)        | Beta on 1.19; track GA status          | Node count ≥ 200                                     |
| ⭐ Strongly recommended | [2. Enable APF rate limiting](#2-enable-apf-rate-limiting)            | Almost none                            | Any scale (the install script enables it by default) |
| Recommended             | [3. Tune K8s client QPS/Burst](#3-tune-k8s-client-qpsburst)           | Too high overloads apiserver           | When you see cilium-agent sync latency spikes        |
| Recommended             | [4. Trim Security Identities](#4-trim-security-identities)            | Label exclusion needs business design  | Identity count ≥ 1000 or visible identity bloat      |
| Recommended             | [5. Raise Agent/Operator resources](#5-raise-agentoperator-resources) | Uses more node resources               | Default limits hit OOM or CPU throttle               |
| As needed               | [6. Adjust BPF map size](#6-adjust-bpf-map-size)                      | Larger maps consume more kernel memory | BPF map writes fail or saturation alerts             |

## 1. Enable CiliumEndpointSlice

**Why**: Aggregates many CiliumEndpoint objects into a single CiliumEndpointSlice resource, dramatically reducing apiserver watch/list pressure.

**Background**: By default, each Pod gets a CiliumEndpoint object. In a cluster with tens of thousands of Pods, this means tens of thousands of objects for cilium-agent to watch and apiserver to maintain. CiliumEndpointSlice borrows the EndpointSlice design to group multiple CEPs into one slice object — reducing total objects by roughly 100x.

**Configuration**:

```yaml
ciliumEndpointSlice:
  enabled: true
```

:::warning[Beta Feature]

This feature was introduced in cilium 1.11 and is still **Beta** in 1.19. Validate thoroughly in a test cluster before enabling in production. Stable tracking: [cilium/cilium#31904](https://github.com/cilium/cilium/issues/31904).

There is no smooth rollback once enabled (CEPSlice and CEP are not dual-written) — plan your rollback strategy in advance.

:::

## 2. Enable APF Rate Limiting

**Why**: Use Kubernetes [API Priority and Fairness](https://kubernetes.io/docs/concepts/cluster-administration/flow-control/) to give cilium dedicated FlowSchema + PriorityLevelConfiguration, preventing cilium-agent's heavy list traffic from squeezing out other control-plane components.

**Configuration**: The one-click installer in [Installing Cilium](../install.md) provisions cilium-specific APF objects by default (see the "Configure API Priority and Fairness (APF)" section). For manual helm installs, apply the same YAML separately.

**Benefits**:

- cilium-agent restarts or cilium upgrades won't slow down kube-controller-manager, kube-scheduler, or other core components
- Avoid "Too many requests" / 429 errors stalling cilium synchronization

## 3. Tune K8s Client QPS/Burst

**Why**: cilium-agent / cilium-operator use client-go to talk to apiserver. Defaults are conservative and can become a sync bottleneck at scale.

**Defaults**:

| Component       | QPS | Burst |
| --------------- | --- | ----- |
| cilium-agent    | 10  | 20    |
| cilium-operator | 100 | 200   |

**Tuned configuration** (adjust based on cluster size):

```yaml
k8sClientRateLimit:
  qps: 20
  burst: 40
  operator:
    qps: 200
    burst: 400
```

:::tip[How to decide if you need this]

Check cilium-agent's client rate limit metrics (a high throttle count means you're being limited):

```bash
kubectl -n kube-system exec ds/cilium -- cilium metrics list | grep client_rate_limiter
```

If throttle counts are constantly growing, raise QPS/Burst.

:::

## 4. Trim Security Identities

**Why**: cilium allocates one Security Identity per unique label combination. Too many identities drive up cilium-agent memory and policy compilation cost, plus apiserver storage pressure for CiliumIdentity resources.

**Typical sources of identity bloat**:

| High-cardinality label               | Source                             |
| ------------------------------------ | ---------------------------------- |
| `pod-template-hash`                  | Changes on every Deployment update |
| `controller-revision-hash`           | StatefulSet/DaemonSet rollouts     |
| `job-name`                           | Job instance names                 |
| `batch.kubernetes.io/controller-uid` | Job controller UID                 |

**Configuration**: Exclude these labels via `extraConfig.labels` so they don't participate in Identity calculation:

```yaml
extraConfig:
  labels: "!pod-template-hash !controller-revision-hash !job-name !batch.kubernetes.io/controller-uid"
```

`!` means "exclude" (negation) — only the listed labels are excluded, all other labels still contribute to Identity.

**Verify the effect**:

```bash
# Total Identity count
kubectl get ciliumidentities | wc -l
```

After tuning, the count should drop noticeably over time.

## 5. Raise Agent/Operator Resources

**Why**: Default cilium-agent / cilium-operator resource requests/limits are conservative. Large clusters may hit OOMs or CPU throttling, causing policy sync lag and slow Pod network setup.

**Recommended configuration** (adjust based on observation):

```yaml
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 2000m
    memory: 2Gi
operator:
  resources:
    requests:
      cpu: 200m
      memory: 256Mi
    limits:
      cpu: 1000m
      memory: 1Gi
```

:::tip[How to size the limits]

Observe actual cilium-agent and cilium-operator usage:

```bash
kubectl -n kube-system top pod -l app.kubernetes.io/part-of=cilium
```

Set limit ≥ 2× the observed peak, leaving headroom for spikes.

:::

## 6. Adjust BPF Map Size

**Why**: cilium stores service / endpoint / policy data in BPF maps. Default sizes are calculated dynamically from node memory (`mapDynamicSizeRatio=0.0025`, i.e. about 0.25% of total memory). When a single Pod / Service fills up the map, writes fail.

**When to adjust**:

- cilium-agent logs show `Unable to update element for cilium_lb4_services_v2` or similar BPF map saturation errors
- Hubble alerts on BPF map utilization approaching 100%

**Tuned configuration**:

```yaml
bpf:
  mapDynamicSizeRatio: 0.005  # Use 0.5% of node memory (default 0.0025)
```

Or specify exact map sizes (not recommended unless you have specific needs):

```yaml
bpf:
  lbMapMax: 131072      # LoadBalancer service map (default 65536)
  policyMapMax: 32768   # NetworkPolicy map (default 16384)
```

:::warning[Memory Cost]

Larger BPF maps consume more kernel memory (not counted against container memory limits — they come directly from node memory). Observe before adjusting to avoid OOM-killing the node.

:::

## Post-Tuning Observability

After tuning, monitor these signals to confirm impact:

| Metric                                         | Healthy Baseline                                |
| ---------------------------------------------- | ----------------------------------------------- |
| cilium-agent CPU / memory usage                | Well under limits (keep 50% headroom)           |
| `cilium_endpoint_regeneration_time_seconds`    | p99 < 5s                                        |
| `cilium_policy_l7_total` / policy compile time | No visible backlog                              |
| apiserver `apiserver_request_duration_seconds` | cilium traffic doesn't degrade other components |
| Total CiliumIdentity count                     | Clear downward trend after tuning               |

## Related

- [Installing Cilium](../install.md)
- [Cilium Scaling Performance Tuning Guide](https://docs.cilium.io/en/stable/operations/performance/scalability/)
- [Cilium API Priority and Fairness](https://docs.cilium.io/en/stable/operations/scalability/apf/)
- [CiliumEndpointSlice Stable tracking](https://github.com/cilium/cilium/issues/31904)

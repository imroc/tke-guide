# Large-Scale Cilium Tuning Guide

## Applicable Scenarios

When a TKE cluster reaches any of the following scale thresholds, cilium's default configuration may exhibit issues such as high apiserver pressure, cilium-agent OOM, slow policy computation, or insufficient BPF map capacity. We recommend tuning as described in this document:

| Dimension        | Trigger Threshold (Reference) |
| ---------------- | ----------------------------- |
| Node count       | ≥ 200                         |
| Pod count        | ≥ 10,000                      |
| Service count    | ≥ 1,000                       |
| Identity count   | ≥ 1,000                       |
| NetworkPolicy count | ≥ 500                       |

Thresholds are for reference only. Whether tuning is needed should be determined by examining the resource usage and latency metrics of cilium-agent, cilium-operator, and apiserver.

## Tuning Checklist

The table below summarizes all tuning items, categorized by "recommended priority + evaluation needed" for quick decision-making:

| Priority       | Tuning Item                                                    | Risk/Cost                      | When to Enable                              |
| -------------- | -------------------------------------------------------------- | ------------------------------ | ------------------------------------------- |
| ⭐ Strongly recommended | [1. Enable CiliumEndpointSlice](#1-enable-ciliumendpointslice) | Still Beta in 1.19, track GA status | Enable when node count ≥ 200          |
| ⭐ Strongly recommended | [2. Enable APF Rate Limiting](#2-enable-apf-rate-limiting)     | Nearly zero                    | Should be enabled at any scale (default in install script) |
| Recommended    | [3. Adjust K8s Client QPS/Burst](#3-adjust-k8s-client-qps-burst) | Over-configuring may overwhelm apiserver | Enable when cilium-agent sync latency is observed |
| Recommended    | [4. Trim Security Identity](#4-trim-security-identity)         | Label exclusion policy must match business needs | Enable when identity count ≥ 1000 or identity bloat is observed |
| Recommended    | [5. Increase Agent/Operator Resources](#5-increase-agentoperator-resources) | Consumes more node resources | Enable when default limits are insufficient, OOM or throttling occurs |
| On demand      | [6. Adjust BPF Map Size](#6-adjust-bpf-map-size)               | Larger maps consume more kernel memory | Enable when BPF map writes fail or capacity warnings appear |

## 1. Enable CiliumEndpointSlice

**Effect**: Aggregates multiple CiliumEndpoints into a single CiliumEndpointSlice resource, significantly reducing apiserver watch/list pressure.

**Background**: By default, each Pod corresponds to one CiliumEndpoint object. In a cluster with tens of thousands of Pods, this means tens of thousands of objects that cilium-agent must watch and apiserver must maintain. CiliumEndpointSlice borrows the EndpointSlice concept to aggregate multiple CEPs into one slice object, reducing the total object count to roughly 1/100 of the original.

**Configuration**:

```yaml
ciliumEndpointSlice:
  enabled: true
```

:::warning[Beta Feature]

This feature was introduced in cilium 1.11 and is still **Beta** in 1.19. We recommend thorough verification in a test cluster before using it in production. Track Stable progress: [cilium/cilium#31904](https://github.com/cilium/cilium/issues/31904).

Once enabled, a smooth rollback is not possible (CEPSlice and CEP are not dual-written). Evaluate your rollback plan.

:::

## 2. Enable APF Rate Limiting

**Effect**: Uses Kubernetes [API Priority and Fairness](https://kubernetes.io/docs/concepts/cluster-administration/flow-control/) to configure dedicated FlowSchema and PriorityLevelConfiguration for cilium, preventing cilium-agent's large list requests from consuming apiserver quota for other control plane components.

**Configuration**: The one-click install script in [Installing Cilium](../install.md) already creates dedicated APF configuration for cilium by default (see the "Configure APF Rate Limiting" section in install.md). For manual helm installations, we recommend applying the YAML from the script separately.

**Benefits**:

- cilium-agent restarts or cilium upgrades will not slow down core components like kube-controller-manager or kube-scheduler
- Prevents "Too many requests" / 429 errors on apiserver that could stall cilium synchronization

## 3. Adjust K8s Client QPS/Burst

**Effect**: cilium-agent and cilium-operator use client-go internally to communicate with apiserver. The default QPS/Burst values are conservative and may become a synchronization bottleneck at scale.

**Default values**:

| Component       | QPS | Burst |
| --------------- | --- | ----- |
| cilium-agent    | 10  | 20    |
| cilium-operator | 100 | 200   |

**Tuning configuration** (adjust based on cluster size):

```yaml
k8sClientRateLimit:
  qps: 20
  burst: 40
  operator:
    qps: 200
    burst: 400
```

:::tip[Determining if adjustment is needed]

Run the following command to check cilium-agent's client rate limit metrics (significant throttling indicates rate limiting):

```bash
kubectl -n kube-system exec ds/cilium -- cilium metrics list | grep client_rate_limiter
```

If the throttle count keeps increasing, you need to raise QPS/Burst.

:::

## 4. Trim Security Identity

**Effect**: Cilium assigns a Security Identity to each unique set of labels. Too many identities increases cilium-agent memory usage and policy computation overhead, as well as the storage pressure on CiliumIdentity resources on apiserver.

**Typical sources of identity bloat**:

| High-cardinality label                  | Source                       |
| --------------------------------------- | ---------------------------- |
| `pod-template-hash`                     | Changes with every Deployment update |
| `controller-revision-hash`              | StatefulSet/DaemonSet rolling updates |
| `job-name`                              | Job instance name            |
| `batch.kubernetes.io/controller-uid`    | Job controller UID           |

**Configuration**: Exclude these labels via `extraConfig.labels` to prevent them from participating in Identity computation:

```yaml
extraConfig:
  labels: "!pod-template-hash !controller-revision-hash !job-name !batch.kubernetes.io/controller-uid"
```

`!` means exclude (negation). Only the specified labels are excluded; all other labels still participate in Identity computation.

**Verify the effect**:

```bash
# Check current total Identity count
kubectl get ciliumidentities | wc -l
```

After adjustment, observe for a while — the total Identity count should decrease significantly.

## 5. Increase Agent/Operator Resources

**Effect**: The default resource requests/limits for cilium-agent and cilium-operator are conservative. At large scale, OOM or CPU throttling may occur, causing policy synchronization delays and late Pod network configuration.

**Recommended configuration** (adjust based on actual observation):

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

:::tip[How to determine appropriate limits]

Observe the actual resource usage of cilium-agent and cilium-operator:

```bash
kubectl -n kube-system top pod -l app.kubernetes.io/part-of=cilium
```

Set limits to ≥ 2x the actual peak usage (to avoid OOMKill during traffic bursts).

:::

## 6. Adjust BPF Map Size

**Effect**: Cilium stores service, endpoint, policy, and other data in BPF maps. The default map capacity is auto-calculated based on node memory (`mapDynamicSizeRatio=0.0025`, i.e., 0.25% of total memory). Once a single Pod or Service runs out of capacity, writes will fail.

**When to adjust**:

- cilium-agent logs show `Unable to update element for cilium_lb4_services_v2` or similar BPF map full errors
- Hubble alerts BPF map usage near 100%

**Tuning configuration**:

```yaml
bpf:
  mapDynamicSizeRatio: 0.005  # Calculate as 0.5% of node memory (default 0.0025)
```

Or specify individual map sizes directly (not recommended unless you have special requirements):

```yaml
bpf:
  lbMapMax: 131072      # LoadBalancer service map (default 65536)
  policyMapMax: 32768   # NetworkPolicy map (default 16384)
```

:::warning[Memory Overhead]

Increasing BPF map sizes increases kernel memory usage (not counted against container memory limits; it directly consumes node memory). Adjust gradually and observe, to avoid exhausting node memory.

:::

## Post-Deployment Observation

After completing the tuning, observe the following metrics to verify the effect:

| Metric                                          | Healthy Baseline                 |
| ----------------------------------------------- | -------------------------------- |
| cilium-agent CPU/memory usage                   | Well below limits (recommend 50% headroom) |
| `cilium_endpoint_regeneration_time_seconds`      | p99 < 5s                         |
| `cilium_policy_l7_total` / policy computation time | No significant backlog         |
| apiserver `apiserver_request_duration_seconds`  | cilium-related requests do not affect other components |
| Total CiliumIdentity count                      | Significant downward trend after tuning |

## Related Links

- [Installing Cilium](../install.md)
- [Cilium Scaling Performance Tuning Guide](https://docs.cilium.io/en/stable/operations/performance/scalability/)
- [Cilium API Priority and Fairness Documentation](https://docs.cilium.io/en/stable/operations/scalability/apf/)
- [CiliumEndpointSlice Stable Progress](https://github.com/cilium/cilium/issues/31904)

# Cilium Host Routing: legacy vs BPF

:::note[Prerequisites]

This article, together with the following two, forms the design principles trilogy for Native Routing mode:

1. This article: Explains why Native mode can only use legacy host routing, and how Overlay mode achieves BPF host routing.
2. **[Why Native Needs local-router-ipv4](./local-router-ipv4.md)**: Understand the `cilium_host` IP configuration requirement under legacy host routing.
3. **[Why Native Disables sysctlfix](./sysctlfix.md)**: Understand the cascading impact of `systemd-sysctl` restart on rp_filter in the same mode.

:::

## What is Host Routing

Host Routing determines **how a packet is forwarded** (next hop decision) after it enters the node's host network namespace. Cilium provides two implementations:

- **Legacy Host Routing**: The default implementation — packets traverse the full Linux network stack through netfilter (iptables) hooks, conntrack, and kernel routing table lookup before being forwarded to the target device (other Pod's lxc, node eth0, tunnel, etc.). Fully functional with the best compatibility, but each hop incurs overhead.
- **BPF Host Routing**: Introduced in Cilium 1.9+, it uses tc-bpf programs on the `cilium_host` device ingress to perform endpoint lookup, service backend lookup, dst MAC rewrite, and redirect to the target device — **completely bypassing netfilter / kernel routing**, delivering higher performance (improved latency and throughput for small packets).

```
              ┌──────────────────────────────────────────────────────┐
              │      Packet forwarding path comparison after         │
              │          entering the node                           │
              ├──────────────────────────────────────────────────────┤
Legacy        │ ingress → tc-bpf (policy) → host stack               │
              │       → netfilter / conntrack → routing table         │
              │       → veth/eth → out                               │
              ├──────────────────────────────────────────────────────┤
BPF host      │ ingress → tc-bpf (policy + lookup + redirect)        │
routing       │       → veth/eth → out  (skips netfilter / routing) │
              └──────────────────────────────────────────────────────┘
```

## Two Independent Requirements for BPF Host Routing

Whether Cilium actually uses BPF host routing after startup depends on **two independent conditions** — both must be met:

### Condition 1: Configuration Layer Must Not Force a Fallback

When cilium-agent starts (`pkg/kpr/initializer/kube_proxy_replacement.go`), it checks:

```go
case option.Config.IptablesMasqueradingEnabled():
    // BPF host routing requires BPF masquerade. Fallback to legacy.
case !r.kprCfg.KubeProxyReplacement:
    // BPF host routing requires KPR=true. Fallback to legacy.
```

In other words:

- **`enableIPv4Masquerade=true` but `bpf.masquerade=true` not set** → uses iptables masquerade → forced fallback to legacy
- **`kubeProxyReplacement=false`** → forced fallback to legacy

To enable BPF host routing, you must explicitly set:

```yaml
kubeProxyReplacement: true
enableIPv4Masquerade: true # or false
bpf:
  masquerade: true # key switch
```

### Condition 2: Packets on the Data Path Must Actually Pass Through `cilium_host`

The BPF host routing code (the `ENABLE_HOST_ROUTING` branch in `bpf/bpf_host.c`) only takes effect in the tc-bpf program on the `cilium_host` device. If packets never go through `cilium_host`, that code is never executed — even if the configuration layer is fully enabled, BPF host routing won't actually be used.

**`endpointRoutes.enabled=true` is exactly this case**: each Pod has a dedicated kernel route on the node (`ip route` pointing directly to the lxc device), so packets bypass `cilium_host`. This is the fundamental reason why VPC-CNI Native mode (which must enable endpointRoutes) cannot use BPF host routing — **unrelated to the fallback check at cilium-agent startup**.

## Host Routing Used by Each TKE Deployment Scheme

| Deployment Scheme              | Key helm values                                  | Which fallback / limitation                    | Actual Host Routing       |
| ------------------------------ | ------------------------------------------------ | ---------------------------------------------- | ------------------------- |
| GR + Overlay (vxlan)           | `bpf.masquerade=true` + endpointRoutes disabled  | None                                           | ✅ BPF                    |
| VPC-CNI + Overlay              | `bpf.masquerade=true` + endpointRoutes disabled  | None                                           | ✅ BPF                    |
| VPC-CNI + Native (no SNAT)     | `enableIPv4Masquerade=false` + endpointRoutes=true | endpointRoutes bypasses `cilium_host`        | ❌ Legacy (condition 2)   |
| VPC-CNI + Native + ip-masq     | `bpf.masquerade=true` + endpointRoutes=true        | endpointRoutes bypasses `cilium_host`        | ❌ Legacy (condition 2)   |
| VPC-CNI + Native + Egress      | `bpf.masquerade=true` + endpointRoutes=true        | endpointRoutes bypasses `cilium_host`        | ❌ Legacy (condition 2)   |

The one-click install script `cilium.sh` **explicitly sets `bpf.masquerade=true` by default** for GR Overlay / VPC-CNI Overlay paths, so Overlay installations get BPF host routing directly.

> Historical pitfall: Cilium's default masquerade implementation is iptables-based. If your helm values only set `enableIPv4Masquerade=true` but omit `bpf.masquerade=true`, cilium will log `BPF host routing requires enable-bpf-masquerade. Falling back to legacy host routing.` at startup, and `cilium status` will show `Host: Legacy` and `Masquerading: IPTables`. In this case, the intuition that "Overlay defaults to BPF" is incorrect.

## Verification

```bash
# Check the Routing and Masquerading lines in cilium status
kubectl -n kube-system exec ds/cilium -- cilium status | grep -E 'Routing:|Masquerading:'
# Expected (BPF path):
#   Routing:                 Network: Tunnel [vxlan]   Host: BPF
#   Masquerading:            BPF
# Degraded (legacy path):
#   Routing:                 Network: Tunnel [vxlan]   Host: Legacy
#   Masquerading:            IPTables ...

# Check cilium-agent startup logs for fallback reason (if Legacy)
kubectl -n kube-system logs ds/cilium | grep -iE 'host.legacy|bpf host routing|falling back'
# Example:
#   BPF host routing requires enable-bpf-masquerade. Falling back to legacy host routing.
```

## Performance Impact

Legacy host routing incurs additional overhead compared to BPF host routing:

- Each packet goes through 5 additional netfilter hooks (PREROUTING / FORWARD / INPUT / OUTPUT / POSTROUTING)
- Conntrack table lookup and update (even without rules, the connection tracking state machine runs)
- Kernel routing table lookup (FIB lookup)

Measured on 4C8G S5, TencentOS 4, kernel 6.6, small-packet RR: Native mode (Legacy) TCP_RR is about 10-15% lower than Overlay mode (BPF, with `bpf.masquerade=true` explicitly set); single-stream TCP_STREAM throughput difference is negligible (bounded by NIC bandwidth). See [Cilium Performance Test](./performance-test.md) for full data.

## Should You Switch to BPF Host Routing?

**It is not recommended to give up VPC-CNI Native mode just to get BPF host routing**:

- Native mode's core value is Pod IP consistency with VPC IP — natively recognized by VPC routing, security groups, CLB, and CCN
- Switching to Overlay to get BPF host routing means losing: direct Pod IP routing to external networks, L4 LB direct Pod access, and unified VPC-managed IPAM
- Most workloads are not sensitive to the ~5µs per-packet host stack overhead

**Only consider switching to Overlay for BPF host routing in these scenarios**:

- High-frequency small-packet workloads (RPC, KV databases, MQ brokers) pursuing minimal RTT
- High node PPS pressure where netfilter / conntrack is the bottleneck (indicated by `nf_conntrack_count` approaching `nf_conntrack_max`)

## Side-by-Side Comparison: AWS EKS with Cilium ENI IPAM Has the Same Limitation

The official cilium helm chart **automatically sets** `enable-endpoint-routes: "true"` when `eni.enabled=true` (cilium-managed AWS ENI IPAM):

```yaml
# install/kubernetes/cilium/templates/cilium-configmap.yaml (v1.19.4)
{{- if .Values.eni.enabled }}
  {{- if not .Values.endpointRoutes.enabled }}
  enable-endpoint-routes: "true"
  {{- end }}
```

The reason is identical to TKE Native: AWS ENI IPs are also valid VPC IPs ("directly routable in the AWS VPC"), so cilium does not need to (and should not) funnel traffic through `cilium_host` for redirect. Instead, it uses endpointRoutes to give each Pod an independent route — but this also means BPF host routing is never hit in this mode (condition 2 is not met).

| Scheme                                  | IPAM          | endpointRoutes      | Host Routing |
| --------------------------------------- | ------------- | ------------------- | ------------ |
| TKE VPC-CNI + Native (chained CNI)      | tke-eni-ipamd | Must be true (manual) | Legacy       |
| AWS EKS with cilium ENI IPAM (non-chained) | cilium eni  | Auto true (chart)   | Legacy       |
| AWS EKS chained aws-cni                 | aws-vpc-cni   | Must be true (manual) | Legacy       |

As shown: **as long as the Pod IP is a valid VPC IP, cilium uses endpointRoutes and cannot get BPF host routing** — this is a common trade-off for cloud-native routing schemes.

## Unaffected Capabilities

Although host routing falls back to legacy, the following core cilium capabilities work **normally** in all deployment schemes:

- **L3/L4/L7 NetworkPolicy**: BPF programs are attached to lxc device ingress/egress hooks (decoupled from host routing)
- **Hubble Observability**: same, flow collection goes through lxc BPF programs
- **kubeProxyReplacement**: fully replaces kube-proxy (ClusterIP / NodePort / HostPort forwarding)
- **CiliumLocalRedirectPolicy**: available for node-local DNS cache and similar scenarios
- **Egress Gateway**: available, see [Egress Gateway Practice](../egress-gateway.md)

## Related Links

- [Installing Cilium](../install.md)
- [Why Native Needs local-router-ipv4](./local-router-ipv4.md)
- [Why Native Disables sysctlfix](./sysctlfix.md)
- [Cilium Performance Test](./performance-test.md)
- [Cilium Docs: eBPF Host-Routing](https://docs.cilium.io/en/stable/operations/performance/tuning/#ebpf-host-routing)
- [GitHub Issue #20135: generic-veth chaining incompatible with BPF host routing](https://github.com/cilium/cilium/issues/20135)

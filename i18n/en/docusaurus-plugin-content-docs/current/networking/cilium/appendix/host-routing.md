# Cilium Host Routing: Legacy vs BPF

## What is Host Routing

Host Routing refers to **how packets are forwarded once they enter the node's host network namespace** — i.e. how the next-hop and target device are decided. Cilium provides two implementations:

- **Legacy Host Routing**: the default implementation. Packets traverse the full Linux network stack — netfilter (iptables) hooks, conntrack, and the kernel routing table — before being forwarded to the target device (another Pod's lxc, the node's eth0, a tunnel, etc.). Maximum compatibility, but every hop adds overhead.
- **BPF Host Routing**: introduced in cilium 1.9+. A tc-bpf program performs endpoint lookup, service backend lookup, dst MAC rewrite, and redirect to the target device — all at the `cilium_host` device ingress, **completely bypassing netfilter / kernel routing**. Higher performance, especially for small-packet latency and throughput.

```
              ┌──────────────────────────────────────────────────────┐
              │     Packet forwarding path inside the node           │
              ├──────────────────────────────────────────────────────┤
Legacy        │ ingress → tc-bpf (policy) → host stack               │
              │       → netfilter / conntrack → routing table        │
              │       → veth/eth → out                               │
              ├──────────────────────────────────────────────────────┤
BPF host      │ ingress → tc-bpf (policy + lookup + redirect)        │
routing       │       → veth/eth → out  (skips netfilter / routing)  │
              └──────────────────────────────────────────────────────┘
```

## BPF Host Routing Has Two Independent Requirements

Whether cilium actually uses BPF host routing at runtime is gated by **two independent conditions**, both must hold:

### Condition 1: configuration layer doesn't get force-fallback'd

When cilium-agent starts (`pkg/kpr/initializer/kube_proxy_replacement.go`):

```go
case option.Config.IptablesMasqueradingEnabled():
    // BPF host routing requires BPF masquerade. Falling back to legacy.
case !r.kprCfg.KubeProxyReplacement:
    // BPF host routing requires KPR=true. Falling back to legacy.
```

In other words:

- **`enableIPv4Masquerade=true` without `bpf.masquerade=true`** → uses iptables masquerade → forced fallback to legacy
- **`kubeProxyReplacement=false`** → forced fallback to legacy

To get BPF host routing, you must explicitly set:

```yaml
kubeProxyReplacement: true
enableIPv4Masquerade: true # or false
bpf:
  masquerade: true # the critical switch
```

### Condition 2: packets must actually pass through `cilium_host`

The BPF host routing code (the `ENABLE_HOST_ROUTING` branch in `bpf/bpf_host.c`) only fires inside the tc-bpf program attached to the `cilium_host` device. If packets never traverse `cilium_host`, that code is never executed — even if the configuration layer is fully unlocked, runtime still won't use BPF host routing.

**`endpointRoutes.enabled=true` mode is exactly this case**: each Pod gets its own kernel route on the node (`ip route` pointing straight at lxc), so packets bypass `cilium_host` entirely. This is the root reason VPC-CNI Native mode (which mandates endpointRoutes) cannot use BPF host routing — **it has nothing to do with the agent's startup fallback check**.

## Host Routing per TKE Deployment Mode

| Deployment Mode            | Key helm values                                    | Limit hit                                          | Effective Host Routing        |
| -------------------------- | -------------------------------------------------- | -------------------------------------------------- | ----------------------------- |
| GR + Overlay (vxlan)       | `bpf.masquerade=true` + endpointRoutes off         | None                                               | ✅ BPF                        |
| VPC-CNI + Overlay          | `bpf.masquerade=true` + endpointRoutes off         | None                                               | ✅ BPF                        |
| VPC-CNI + Native (no SNAT) | `enableIPv4Masquerade=false` + endpointRoutes=true | endpointRoutes routes packets around `cilium_host` | ❌ Legacy (Condition 2 fails) |
| VPC-CNI + Native + ip-masq | `bpf.masquerade=true` + endpointRoutes=true        | endpointRoutes routes packets around `cilium_host` | ❌ Legacy (Condition 2 fails) |
| VPC-CNI + Native + Egress  | `bpf.masquerade=true` + endpointRoutes=true        | endpointRoutes routes packets around `cilium_host` | ❌ Legacy (Condition 2 fails) |

The one-click installer `cilium.sh` **explicitly sets `bpf.masquerade=true`** for both GR Overlay and VPC-CNI Overlay paths, so a fresh Overlay install lands directly on BPF host routing.

> Historical pitfall: cilium's default masquerade is the iptables variant. If the helm values only set `enableIPv4Masquerade=true` and forget `bpf.masquerade=true`, cilium-agent logs `BPF host routing requires enable-bpf-masquerade. Falling back to legacy host routing.` at startup, and `cilium status` shows `Host: Legacy` / `Masquerading: IPTables`. The intuition that "Overlay is BPF by default" is wrong here.

## How to Verify

```bash
# Inspect cilium status — Routing & Masquerading lines
kubectl -n kube-system exec ds/cilium -- cilium status | grep -E 'Routing:|Masquerading:'
# Expected (BPF path):
#   Routing:                 Network: Tunnel [vxlan]   Host: BPF
#   Masquerading:            BPF
# Degraded (legacy path):
#   Routing:                 Network: Tunnel [vxlan]   Host: Legacy
#   Masquerading:            IPTables ...

# Confirm fallback reason from agent logs (when stuck on Legacy)
kubectl -n kube-system logs ds/cilium | grep -iE 'host.legacy|bpf host routing|falling back'
# e.g.:
#   BPF host routing requires enable-bpf-masquerade. Falling back to legacy host routing.
```

## Performance Impact

Extra overhead of legacy host routing compared to BPF host routing:

- Each packet additionally traverses 5 netfilter hooks (PREROUTING / FORWARD / INPUT / OUTPUT / POSTROUTING)
- Conntrack table lookup and update (the connection tracking state machine runs even without iptables rules)
- Kernel routing table (FIB) lookup

In our benchmarks (4C8G S5, TencentOS 4, kernel 6.6), small-packet TCP_RR in Native mode (Legacy) is ~10-15% lower than in Overlay mode (BPF, assuming `bpf.masquerade=true` is set explicitly). Single-stream TCP_STREAM throughput shows little difference (capped by NIC bandwidth). Full numbers in [Cilium Performance Tests](./performance-test.md).

## Should You Switch to BPF Host Routing?

**Switching off VPC-CNI Native mode just to gain BPF host routing is generally NOT worth it**:

- The core value of Native mode is that Pod IP == VPC IP — recognized natively by VPC routing, security groups, CLB, and CCN
- Moving to Overlay gains BPF host routing but loses: direct Pod IP routing to external systems, layer-4 LB pass-through to Pods, unified IPAM via the VPC
- Most workloads are insensitive to the ~5μs-per-packet host-stack overhead

**Switching to Overlay is only worthwhile when**:

- High-PPS small-packet workloads (RPC, KV stores, MQ brokers) chase ultra-low RTT
- Node PPS is high and netfilter / conntrack is the bottleneck (check via `nf_conntrack_count` approaching `nf_conntrack_max`)

## Cross-cloud comparison: AWS EKS with Cilium ENI IPAM has the same limitation

The official cilium helm chart **automatically writes** `enable-endpoint-routes: "true"` whenever `eni.enabled=true` (cilium's own AWS ENI IPAM):

```yaml
# install/kubernetes/cilium/templates/cilium-configmap.yaml (v1.19.4)
{{- if .Values.eni.enabled }}
  {{- if not .Values.endpointRoutes.enabled }}
  enable-endpoint-routes: "true"
  {{- end }}
```

The reason is identical to TKE Native: AWS ENI IPs are also valid VPC IPs ("directly routable in the AWS VPC"), so cilium has no reason — and no need — to funnel traffic through `cilium_host` for redirect; instead each Pod gets its own kernel route via endpointRoutes. But this also means BPF host routing is not triggered in this mode either (Condition 2 fails).

| Solution                                   | IPAM          | endpointRoutes    | Host Routing |
| ------------------------------------------ | ------------- | ----------------- | ------------ |
| TKE VPC-CNI + Native (chained CNI)         | tke-eni-ipamd | required (manual) | Legacy       |
| AWS EKS with cilium ENI IPAM (not chained) | cilium eni    | automatic (chart) | Legacy       |
| AWS EKS chained aws-cni                    | aws-vpc-cni   | required (manual) | Legacy       |

The pattern is clear: **whenever Pod IPs are valid VPC IPs, cilium uses endpointRoutes and BPF host routing is unavailable** — a common cost of cloud-native "Native" routing solutions.

## Capabilities Unaffected

Even with legacy host routing, the following cilium core capabilities work **fully** in all deployment modes:

- **L3/L4/L7 NetworkPolicy**: BPF programs are attached to lxc ingress/egress hooks (decoupled from host routing)
- **Hubble Observability**: same as above — flow capture happens on lxc BPF programs
- **kubeProxyReplacement**: full kube-proxy replacement (ClusterIP / NodePort / HostPort forwarding)
- **CiliumLocalRedirectPolicy**: usable for node-local DNS cache and similar scenarios
- **Egress Gateway**: works — see [Egress Gateway Practice](../egress-gateway.md)

## Related Links

- [Installing Cilium](../install.md)
- [Cilium Performance Tests](./performance-test.md)
- [Cilium Docs: eBPF Host-Routing](https://docs.cilium.io/en/stable/operations/performance/tuning/#ebpf-host-routing)
- [GitHub Issue #20135: generic-veth chaining incompatible with BPF host routing](https://github.com/cilium/cilium/issues/20135)

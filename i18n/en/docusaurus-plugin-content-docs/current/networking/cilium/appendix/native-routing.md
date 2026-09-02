# VPC-CNI Native Routing Details

When installing Cilium on TKE with **Native Routing (VPC-CNI)**, three configurations differ from the Overlay mode:

| Config                          | Native                            | Overlay                                   | Reason                                     |
| ------------------------------- | -------------------------------- | ----------------------------------------- | ------------------------------------------ |
| `extraConfig.local-router-ipv4` | `169.254.32.16` (explicit)       | Auto-assigned                             | cilium doesn't manage Pod IPAM             |
| `sysctlfix.enabled`             | `false` (must disable)           | `false` (disabled) + deploy sysctl override DS | systemd-sysctl restart replays distro defaults |
| BPF Host Routing data-path hit  | ❌ bypassed                      | ✅ hit                                    | endpointRoutes bypasses `cilium_host`      |

These three configs share a single root cause: **Pod IPs are legitimate VPC IPs, so cilium uses `endpointRoutes` to create per-Pod routes, and packets bypass `cilium_host`**. This is the common characteristic of any solution that hands Pods cloud-provider VPC IPs — including cilium's own native ENI/GKE/Azure IPAM and chained CNI setups like AWS EKS.

This article explains the principles behind each configuration.

## Why local-router-ipv4?

### The Role of cilium_host

Cilium creates a pair of virtual interfaces on every node:

- `cilium_host`: The "gateway" interface on the node, serving as the next-hop for all pods on that node.
- `cilium_net`: The veth peer paired with `cilium_host`.

`cilium_host` must have an IP address; otherwise node-local routing lacks an "exit".

```text
                ┌──────────────────────────────────────┐
                │                Node                  │
                │                                      │
                │   ┌──────────┐      ┌────────────┐   │
                │   │   Pod    │─────▶│ cilium_host│──▶│  Egress
                │   │ (lxcXX)  │      │  (gateway) │   │
                │   └──────────┘      └────────────┘   │
                └──────────────────────────────────────┘
```

### The Native Mode Special Case

In Native Routing (VPC-CNI) mode, **cilium does not manage Pod IP allocation**: Pods are attached to ENIs directly, with IPs assigned by VPC-CNI from VPC subnets. Cilium has no knowledge of Pod IP sources.

Since cilium can't determine a suitable IP for `cilium_host`, the user must explicitly specify one via `local-router-ipv4` — an address that won't conflict with any Pod IP.

### Why 169.254.32.16?

`169.254.0.0/16` is the IPv4 link-local address range (RFC 3927):

1. **Non-routable**: Never conflicts with VPC IPs or Service CIDRs.
2. **Uniform across nodes**: All nodes can use the same value, simplifying configuration and troubleshooting.
3. **TKE-verified**: `169.254.32.16` is confirmed not to be used by other TKE components.

:::tip[Other uses of 169.254/16 on TKE]

TKE also uses the `169.254.0.0/16` range for:

- Metadata Service (IMDS)
- apiserver internal VIP (the address returned by `kubectl get ep kubernetes`)
- COS / image registry / some internal service VIPs

`169.254.32.16` is confirmed not to conflict with any of the above.

:::

### Why Overlay Doesn't Need It

In Overlay mode, cilium manages Pod IP allocation (multi-pool IPAM). It knows the node's PodCIDR and automatically assigns a non-conflicting IP to `cilium_host` from that range — no user intervention needed.

## Why Disable sysctlfix?

sysctlfix **restarts the host's `systemd-sysctl.service`** on every cilium pod start, replaying all distro sysctl defaults. For Native mode this breaks networking outright: `tke-eni-agent` sets eth0's `rp_filter` to `2` (loose) to accommodate VPC-CNI policy routing, and the replay resets it to `1` (strict), dropping asymmetric traffic for auxiliary-ENI IPs.

Native mode **just disables sysctlfix — no compensation needed**: `endpointRoutes` provides symmetric per-endpoint routes for every Pod, so the lxc rp_filter value doesn't affect connectivity (Overlay mode is different — its routes aggregate to `cilium_host`, creating asymmetry that requires the `cilium-sysctl-override` DaemonSet compensation).

For the full analysis (sysctlfix's two actions, the udev per-interface sysctl replay, the routing symmetry principle, the per-mode decision table and troubleshooting), see [sysctlfix and rp_filter Deep Dive](./sysctlfix.md).

## BPF Host Routing Not Hit in Native Mode

### What is Host Routing

Host Routing refers to how packets are forwarded after entering the node's host network namespace. Cilium provides two implementations:

- **Legacy Host Routing**: The default. Packets traverse the full Linux network stack — netfilter (iptables) hooks, conntrack, kernel routing table lookup — before being forwarded to the target device. Feature-complete and most compatible, but each hop has overhead.
- **BPF Host Routing**: Introduced in cilium 1.9+. Uses tc-bpf programs at the `cilium_host` device ingress to perform endpoint lookup, service backend lookup, dst MAC rewrite, and redirect to the target device in one shot — **completely bypassing netfilter / kernel routing**. Higher performance.

```
              ┌──────────────────────────────────────────────────────┐
              │          Packet forwarding paths on node             │
              ├──────────────────────────────────────────────────────┤
Legacy        │ ingress → tc-bpf (policy) → host stack               │
              │       → netfilter / conntrack → routing table        │
              │       → veth/eth → out                               │
              ├──────────────────────────────────────────────────────┤
BPF host      │ ingress → tc-bpf (policy + lookup + redirect)        │
routing       │       → veth/eth → out  (skips netfilter / routing)  │
              └──────────────────────────────────────────────────────┘
```

### Why BPF host routing is not hit in Native mode

For BPF host routing to actually take effect on the data path, two conditions must hold simultaneously:

**Condition 1: cilium-agent does not force fallback at the config layer**

cilium-agent checks at startup and force-sets `EnableHostLegacyRouting=true` (so the `ENABLE_HOST_ROUTING` macro is not compiled into the BPF program) under either condition (source: `pkg/kpr/initializer/kube_proxy_replacement.go:46-64`):

- `kubeProxyReplacement=false` → fallback
- `enableIPv4Masquerade=true` without `bpf.masquerade=true` (i.e. iptables masquerade) → fallback

Required helm values:

```yaml
kubeProxyReplacement: true
bpf:
  masquerade: true  # key switch
```

When both are satisfied, `cilium status` reports `Host Routing: BPF`.

**Condition 2: packets actually traverse `cilium_host`**

The BPF host routing code is attached to the tc-bpf program on the `cilium_host` device (source: `ENABLE_HOST_ROUTING` macro branch in `bpf/bpf_host.c`). If packets never reach `cilium_host`, the code is never executed — even if config-layer requirements are met and `cilium status` reports `BPF`, **BPF host routing does not actually hit on the data path**.

**`endpointRoutes.enabled=true` is exactly this case**: each Pod has its own kernel route (`ip route` pointing directly to the lxc device), so packets bypass `cilium_host`. The comment in `pkg/endpoint/endpoint.go:999-1012` `NewDatapathConfiguration()` confirms this directly:

> _"Since routing occurs via endpoint interface directly, BPF program on cilium_host interface is bypassed"_

VPC-CNI Native must enable endpointRoutes (because Pod IPs are legitimate VPC IPs and cilium does not own IPAM). The result is that cilium status and the data path diverge: **status reports BPF, but the data path does not actually hit it**. This is unrelated to the cilium-agent fallback check.

### BPF host routing hit status by TKE deployment

| Deployment                 | Key helm values                                    | cilium status | Data-path hit                 |
| -------------------------- | -------------------------------------------------- | ------------- | ----------------------------- |
| GR + Overlay (vxlan)       | `bpf.masquerade=true` + no endpointRoutes          | BPF           | ✅ Hit                        |
| VPC-CNI + Overlay          | `bpf.masquerade=true` + no endpointRoutes          | BPF           | ✅ Hit                        |
| VPC-CNI + Native (no SNAT) | `enableIPv4Masquerade=false` + endpointRoutes=true | BPF           | ❌ packets bypass cilium_host |
| VPC-CNI + Native + ip-masq | `bpf.masquerade=true` + endpointRoutes=true        | BPF           | ❌ packets bypass cilium_host |
| VPC-CNI + Native + Egress  | `bpf.masquerade=true` + endpointRoutes=true        | BPF           | ❌ packets bypass cilium_host |

All three install plans in the `cilium.sh` script set `kubeProxyReplacement=true` and none of them trigger the config-level fallback described in the "historical pitfall" above, so cilium status uniformly reports `Host Routing: BPF`. However, each plan arrives at that state for different reasons:

- **The two Overlay plans**: explicitly set `bpf.masquerade=true` — the standard path (condition 1).
- **Plain Native (SNAT off)**: `enableIPv4Masquerade=false` disables masquerading entirely — the fallback check only downgrades when iptables masquerading is enabled, so the condition never fires and BPF is still reported.
- **Native + ip-masq / Egress Gateway**: the script adds `bpf.masquerade=true` when these features are enabled.

In Native mode `Host Routing: BPF` is the status-level state, **not a guarantee that BPF host routing actually hits on the data path** — that further depends on whether packets traverse cilium_host.

> Historical pitfall: if helm values set `enableIPv4Masquerade=true` but forget `bpf.masquerade=true`, cilium logs `BPF host routing requires enable-bpf-masquerade. Falling back to legacy host routing.` at startup, and `cilium status` directly reports `Host: Legacy`, `Masquerading: IPTables`. This is config-level fallback, distinct from the data-path-bypass issue caused by endpointRoutes.

### Verification

The `cilium status` `Host Routing` field only reflects cilium-agent's config-layer state (it reports `BPF` whenever `kubeProxyReplacement=true` + `bpf.masquerade=true`). **It does not tell you whether the data path actually hits BPF host routing.** A VPC-CNI Native cluster will also show `Host: BPF` in cilium status, but because endpointRoutes makes packets bypass `cilium_host`, the BPF code is in fact not executed.

To accurately determine whether BPF host routing is hit on the data path, check both:

```bash
# Step 1: check cilium-agent config status
kubectl -n kube-system exec ds/cilium -- cilium status | grep -E 'KubeProxyReplacement:|Host Routing:|Masquerading:'
# Config OK:
#   KubeProxyReplacement:    True
#   Host Routing:            BPF
#   Masquerading:            BPF (...)
# Config NOT OK (fallback to legacy):
#   Host Routing:            Legacy
# Fallback usually means KPR=False or enableIPv4Masquerade is using iptables; check cilium-agent logs:
kubectl -n kube-system logs ds/cilium | grep -iE 'host.legacy|bpf host routing|falling back'

# Step 2: check whether endpointRoutes is enabled — if yes, the BPF program on cilium_host is bypassed
kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.enable-endpoint-routes}'
# Output "true": Pod traffic uses per-endpoint veth routes, BPF host routing is NOT hit
# Output ""/missing: Pod traffic flows through cilium_host, BPF host routing IS hit
```

> Source reference: `pkg/endpoint/endpoint.go` (v1.20.1) `NewDatapathConfiguration` comment explicitly states _"Since routing occurs via endpoint interface directly, BPF program on cilium_host interface is bypassed"_.

## Performance Impact

When `cilium_host` is bypassed and Pod traffic flows via per-endpoint veth, each packet incurs the following extra cost:

- Extra netfilter hooks (PREROUTING / FORWARD / INPUT / OUTPUT / POSTROUTING)
- Conntrack table lookup and update (the state machine runs even without explicit rules)
- Kernel routing table lookup (FIB lookup)

Measured (SA5.LARGE8 4C8G, TencentOS 4, kernel 6.6):

- Cross-node single-stream throughput hits 10 Gbps burst ceiling for all three; **no throughput difference**
- Cross-node keepalive RPS: Native and Overlay are nearly identical (&lt;1% difference); both are ~18% below iptables (Native pays for cni-chaining + per-endpoint routing; Overlay pays for VXLAN encap/decap; the magnitudes are comparable)
- Cross-node short-conn RPS: Native and Overlay are also nearly identical
- TCP_RR p99: Native 136 µs vs Overlay 130 µs vs iptables 112 µs (Cilium ~20 µs above iptables; Native vs Overlay differs &lt;10 µs)
- HTTP p99 @1000 QPS: 0.99 ms across all three clusters — **under realistic application load all three are equivalent**

Full data: [Cilium Network Performance Benchmark](./network-benchmark.md) and [Cilium Performance Test](./performance-test.md).

**Do not abandon VPC-CNI Native just to get BPF host routing**:

- Native mode's core value is Pod IP = VPC IP — natively recognized by VPC routing, security groups, CLB, and CCN
- Switching to Overlay does make the BPF program on cilium_host hit, but you lose: direct Pod IP routing externally, L4 LB direct-to-Pod, unified VPC IPAM
- Measured Native vs Overlay end-to-end RPS/latency differ &lt;1%; **the practical gain of "BPF host routing hit" on the cross-node path is minimal**

**Real reasons to switch to Overlay**:

- Pod IP count exceeds ENI capacity, or you need cross-VPC CIDR reuse (architectural reasons)
- Node under heavy PPS, `nf_conntrack_count` approaching `nf_conntrack_max` (still depends on traffic pattern, not host routing implementation)

## Unaffected Capabilities

Even though the BPF program on cilium_host is bypassed, the following cilium core capabilities work normally across all deployment modes:

- **L3/L4/L7 NetworkPolicy**: BPF programs are attached to lxc device ingress/egress hooks (decoupled from host routing)
- **Hubble Observability**: Same as above; flow collection uses lxc BPF programs
- **kubeProxyReplacement**: Fully replaces kube-proxy (ClusterIP / NodePort / HostPort forwarding)
- **CiliumLocalRedirectPolicy**: Node-local DNS cache and similar scenarios
- **Egress Gateway**: Available; see [Egress Gateway Practices](../egress-gateway.md)

## Cross-Cloud Comparison: All Cloud-Provider Native IPAM is the Same

Cilium's official helm chart **automatically sets** `enable-endpoint-routes: "true"` when `eni.enabled=true` (cilium managing AWS ENI IPAM):

```yaml
# install/kubernetes/cilium/templates/cilium-configmap.yaml (v1.20.1)
{{- if .Values.eni.enabled }}
  {{- if not .Values.endpointRoutes.enabled }}
  enable-endpoint-routes: "true"
  {{- end }}
```

GKE configuration (`gke.enabled=true`) also auto-enables endpoint-routes (source: `Documentation/network/concepts/routing.rst`).

The reason is the same as TKE Native: **whenever Pod IPs are legitimate cloud-provider VPC IPs** (whether via cni-chaining or cilium native IPAM), cilium does not own the IP source and should not route everything via `cilium_host`, so it uses endpointRoutes for per-Pod routes — but this also makes the BPF program on cilium_host useless.

| Solution                                      | IPAM           | endpointRoutes         | Pod IP type         | BPF host routing hit |
| --------------------------------------------- | -------------- | ---------------------- | ------------------- | -------------------- |
| TKE VPC-CNI + Native (cni-chaining)           | tke-eni-ipamd  | Required true (manual) | VPC IP              | ❌                   |
| AWS EKS + cilium ENI IPAM (non-chained)       | cilium eni     | Auto true (chart)      | VPC IP              | ❌                   |
| AWS EKS + chained aws-cni                     | aws-vpc-cni    | Required true (manual) | VPC IP              | ❌                   |
| GKE + cilium GKE mode                         | k8s host-scope | Auto true (chart)      | Alias IP (VPC)      | ❌                   |
| Self-hosted Cilium Native + Cluster Pool IPAM | cluster-pool   | Default false          | Cilium-managed CIDR | ✅                   |
| TKE Cilium Overlay                            | multi-pool     | Default false          | Cilium-managed CIDR | ✅                   |

The last two rows are the counter-examples — **when cilium fully owns Pod CIDR** (Native or Overlay), endpointRoutes is not forced on, and the BPF program on cilium_host hits on the data path. **So the real determinant of "BPF host routing hit or miss" is not the routing mode (Native/Tunnel) and not whether cni-chaining is used, but whether Pod IPs come from cloud-provider VPC**.

## References

- [Installing Cilium](../install.md)
- [sysctlfix and rp_filter Deep Dive](./sysctlfix.md)
- [Cilium Performance Test](./performance-test.md)
- [Cilium Docs: eBPF Host-Routing](https://docs.cilium.io/en/stable/operations/performance/tuning/#ebpf-host-routing)
- [GitHub Issue #20135: generic-veth chaining incompatible with BPF host routing](https://github.com/cilium/cilium/issues/20135)

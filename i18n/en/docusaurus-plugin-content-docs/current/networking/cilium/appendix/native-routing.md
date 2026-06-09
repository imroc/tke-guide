# VPC-CNI Native Routing Details

When installing Cilium on TKE with **Native Routing (VPC-CNI)**, three configurations differ from the Overlay mode:

| Config | Native | Overlay | Reason |
|---|---|---|---|
| `extraConfig.local-router-ipv4` | `169.254.32.16` (explicit) | Auto-assigned | cilium doesn't manage Pod IPAM |
| `sysctlfix.enabled` | `false` (must disable) | `true` (default) | systemd-sysctl restart resets eth0 rp_filter |
| Host Routing | Legacy (BPF unreachable) | BPF (with `bpf.masquerade`) | endpointRoutes bypasses `cilium_host` |

These three configs share a single root cause: **Pod IPs are legitimate VPC IPs, so cilium uses `endpointRoutes` to create per-Pod routes, and packets bypass `cilium_host`**. This is also the common characteristic of cloud-native Native Routing solutions like AWS EKS.

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

In Overlay mode, cilium manages Pod IP allocation (cluster-pool IPAM). It knows the node's PodCIDR and automatically assigns a non-conflicting IP to `cilium_host` from that range — no user intervention needed.

## Why Disable sysctlfix?

### Background

Cilium enables a feature called `sysctlfix` by default: an init container writes `/etc/sysctl.d/99-zzz-override_cilium.conf` on each node, sets `rp_filter` to 0 on lxc interfaces (the veths cilium creates for Pods), and **restarts `systemd-sysctl.service`** to apply the change.

`rp_filter` (Reverse Path Filtering) is a Linux kernel security mechanism: when a packet arrives on an interface, the kernel performs a reverse route lookup to verify "if I were to reply to this source IP, would it go out the same interface?" If not, the packet is dropped to prevent IP spoofing.

Cilium adjusts lxc `rp_filter` so that host → local Pod return traffic can pass through. But on TKE, the impact of sysctlfix differs dramatically between modes.

### Native Routing (VPC-CNI): Must Disable

- **Data path**: Cilium coexists with VPC-CNI; Pod IPs come from the VPC. **Return packets enter via eth0**.
- **Risk**: sysctlfix restarts `systemd-sysctl.service`, which re-applies OS default configs. TKE OS images default `eth0`'s `rp_filter` to `1` (strict mode). Under strict validation, Pod IPs on eth0 don't match and get dropped, causing network outages.
- **Conclusion**: **Must disable** sysctlfix:

  ```bash
  --set sysctlfix.enabled=false
  ```

### Overlay: Must Enable (default)

- **Data path**: Pod IPs come from cilium's own CIDR; cross-node traffic goes through the vxlan tunnel. Pod IPs are invisible on eth0, so `eth0.rp_filter=1` causes no issues.
- **Risk**: Host → local Pod return traffic passes through lxc interfaces, which need `lxc*.rp_filter=0` or the traffic gets dropped.
- **Conclusion**: Overlay mode **must enable** sysctlfix (enabled by default, no explicit config needed).

### Decision Summary

| Mode                     | sysctlfix | Key Reason |
| ------------------------ | --------- | ---------- |
| Native Routing (VPC-CNI) | ❌ Must disable | systemd-sysctl restart resets eth0 config |
| Overlay (VPC-CNI / GR)   | ✅ Must enable  | host → Pod return traffic needs lxc rp_filter=0 |

### Troubleshooting

If `cilium-health status` shows localhost endpoint 0/1 (host → Pod unreachable) in Overlay mode, sysctlfix likely didn't take effect:

```bash
# Check if all lxc interface rp_filter values are 0
sysctl -a 2>/dev/null | grep 'conf\.lxc.*rp_filter'

# If any value is non-zero, check if the sysctlfix init container ran successfully
kubectl -n kube-system get pod -l k8s-app=cilium -o jsonpath='{.items[0].status.initContainerStatuses}'
```

Troubleshooting flow:

1. If all `lxc*.rp_filter` are 0 but still unreachable → the issue is not sysctlfix, investigate other paths.
2. If any value is non-zero → the sysctlfix init container may not have run successfully; check init container logs.
3. If init container logs look normal but sysctl values still haven't taken effect → systemd-sysctl.service may have been overridden by another process or script; try `sysctl -w` manually.

## Host Routing: Legacy Only

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

### Why Native Can Only Use Legacy

BPF host routing requires two conditions:

**Condition 1: Not force-fallbacked at the config layer**

cilium-agent checks at startup; the following force fallback to legacy:

- `enableIPv4Masquerade=true` without `bpf.masquerade=true` → iptables masquerade → fallback
- `kubeProxyReplacement=false` → fallback

To get BPF host routing, explicitly set:

```yaml
kubeProxyReplacement: true
bpf:
  masquerade: true  # key switch
```

**Condition 2: Packets actually pass through `cilium_host`**

The BPF host routing code (`ENABLE_HOST_ROUTING` branch in `bpf/bpf_host.c`) only takes effect in the tc-bpf program on the `cilium_host` device. If packets never reach `cilium_host`, that code is never executed — even if the config layer meets all requirements.

**`endpointRoutes.enabled=true` is exactly this scenario**: each Pod has an independent kernel route (`ip route` pointing directly to the lxc device), so packets bypass `cilium_host`. This is the root cause why VPC-CNI Native mode (which requires endpointRoutes) cannot use BPF host routing — **independent of cilium-agent's startup fallback checks**.

### Host Routing by TKE Deployment

| Deployment | Key helm values | Actual Host Routing |
|---|---|---|
| GR + Overlay (vxlan) | `bpf.masquerade=true` + no endpointRoutes | ✅ BPF |
| VPC-CNI + Overlay | `bpf.masquerade=true` + no endpointRoutes | ✅ BPF |
| VPC-CNI + Native (no SNAT) | `enableIPv4Masquerade=false` + endpointRoutes=true | ❌ Legacy |
| VPC-CNI + Native + ip-masq | `bpf.masquerade=true` + endpointRoutes=true | ❌ Legacy |
| VPC-CNI + Native + Egress | `bpf.masquerade=true` + endpointRoutes=true | ❌ Legacy |

The `cilium.sh` install script explicitly sets `bpf.masquerade=true` on GR Overlay / VPC-CNI Overlay paths, so Overlay deployments get BPF host routing by default.

> Historical pitfall: cilium's default masquerade is the iptables implementation. If helm values only set `enableIPv4Masquerade=true` without `bpf.masquerade=true`, cilium logs `BPF host routing requires enable-bpf-masquerade. Falling back to legacy host routing.` at startup, and `cilium status` shows `Host: Legacy`, `Masquerading: IPTables`.

### Verification

```bash
# Check Routing and Masquerading lines in cilium status
kubectl -n kube-system exec ds/cilium -- cilium status | grep -E 'Routing:|Masquerading:'
# Expected (BPF path):
#   Routing:                 Network: Tunnel [vxlan]   Host: BPF
#   Masquerading:            BPF
# Degraded (legacy path):
#   Routing:                 Network: Tunnel [vxlan]   Host: Legacy
#   Masquerading:            IPTables ...

# Check cilium-agent startup logs for fallback reason
kubectl -n kube-system logs ds/cilium | grep -iE 'host.legacy|bpf host routing|falling back'
```

## Performance Impact

Legacy host routing adds the following overhead vs BPF host routing:

- An additional 5 netfilter hooks per packet (PREROUTING / FORWARD / INPUT / OUTPUT / POSTROUTING)
- Conntrack table lookup and update (connection tracking runs even without explicit rules)
- Kernel routing table lookup (FIB lookup)

Measured (4C8G S5, TencentOS 4, kernel 6.6): in small-packet RR scenarios, TCP_RR for Native mode (Legacy) is ~10-15% lower than Overlay mode (BPF). Single-stream TCP_STREAM throughput difference is negligible (bottlenecked by NIC bandwidth). Full data: [Cilium Performance Test](./performance-test.md).

**Do not switch to Overlay just for BPF host routing**:

- Native mode's core value is Pod IP = VPC IP — natively recognized by VPC routing, security groups, CLB, and CCN
- Switching to Overlay for BPF host routing loses: direct Pod IP routing externally, L4 LB direct-to-Pod, unified VPC IPAM
- Most workloads are not sensitive to ~5μs-level host stack overhead per packet

**Only switch to Overlay for BPF host routing in these cases**:

- High-frequency small-packet workloads (RPC, KV databases, MQ brokers) pursuing extreme RTT
- Node PPS under pressure, netfilter / conntrack is the bottleneck (check `nf_conntrack_count` approaching `nf_conntrack_max`)

## Unaffected Capabilities

Despite legacy host routing, the following cilium core capabilities work normally across all deployment modes:

- **L3/L4/L7 NetworkPolicy**: BPF programs are attached to lxc device ingress/egress hooks (decoupled from host routing)
- **Hubble Observability**: Same as above; flow collection uses lxc BPF programs
- **kubeProxyReplacement**: Fully replaces kube-proxy (ClusterIP / NodePort / HostPort forwarding)
- **CiliumLocalRedirectPolicy**: Node-local DNS cache and similar scenarios
- **Egress Gateway**: Available; see [Egress Gateway Practices](../egress-gateway.md)

## Cross-Cloud Comparison: AWS EKS Has the Same Limitation

Cilium's official helm chart **automatically sets** `enable-endpoint-routes: "true"` when `eni.enabled=true` (cilium managing AWS ENI IPAM):

```yaml
# install/kubernetes/cilium/templates/cilium-configmap.yaml (v1.19.4)
{{- if .Values.eni.enabled }}
  {{- if not .Values.endpointRoutes.enabled }}
  enable-endpoint-routes: "true"
  {{- end }}
```

The reason is identical to TKE Native: AWS ENI IPs are also legitimate VPC IPs, so cilium uses endpointRoutes for per-Pod routes — but this also means BPF host routing is unreachable.

| Solution | IPAM | endpointRoutes | Host Routing |
|---|---|---|---|
| TKE VPC-CNI + Native (chained CNI) | tke-eni-ipamd | Required true (manual) | Legacy |
| AWS EKS with cilium ENI IPAM (non-chained) | cilium eni | Auto true (chart) | Legacy |
| AWS EKS chained aws-cni | aws-vpc-cni | Required true (manual) | Legacy |

**Whenever Pod IPs are legitimate VPC IPs, cilium uses endpointRoutes and cannot get BPF host routing** — this is the common cost of cloud-native Native Routing solutions.

## References

- [Installing Cilium](../install.md)
- [Cilium Performance Test](./performance-test.md)
- [Cilium Docs: eBPF Host-Routing](https://docs.cilium.io/en/stable/operations/performance/tuning/#ebpf-host-routing)
- [GitHub Issue #20135: generic-veth chaining incompatible with BPF host routing](https://github.com/cilium/cilium/issues/20135)
- [Cilium Source - sysctlfix](https://github.com/cilium/cilium/blob/main/daemon/cmd/sysctlfix.go)
- [Linux Kernel rp_filter Documentation](https://www.kernel.org/doc/Documentation/networking/ip-sysctl.txt)
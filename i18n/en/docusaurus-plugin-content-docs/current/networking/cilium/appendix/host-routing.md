# Cilium Host Routing: Legacy vs BPF

## What is Host Routing

Host Routing refers to **how packets are forwarded once they enter the node's host network namespace** — i.e. how the next-hop and target device are decided. Cilium provides two implementations:

- **Legacy Host Routing**: the default implementation. Packets traverse the full Linux network stack — netfilter (iptables) hooks, conntrack, and the kernel routing table — before being forwarded to the target device (another Pod's lxc, the node's eth0, a tunnel, etc.). Maximum compatibility, but every hop adds overhead.
- **BPF Host Routing**: introduced in cilium 1.9+. A tc-bpf program performs endpoint lookup, service backend lookup, dst MAC rewrite, and redirect to the target device — all at the NIC ingress, **completely bypassing netfilter / kernel routing**. Higher performance, especially for small-packet latency and throughput.

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

## Host Routing per TKE Deployment Mode

| Deployment Mode      | Host Routing           | Switchable to BPF?                                                                       |
| -------------------- | ---------------------- | ---------------------------------------------------------------------------------------- |
| GR + Overlay (vxlan) | ✅ BPF (default)       | Already BPF                                                                              |
| VPC-CNI + Overlay    | ✅ BPF (default)       | Already BPF                                                                              |
| VPC-CNI + Native     | ❌ Legacy (**forced**) | **No** — under `endpointRoutes.enabled=true`, the BPF host routing path is never reached |

In VPC-CNI Native mode, setting `bpf.hostRouting=true` in helm values has no effect — this is determined by the data path of endpointRoutes mode itself, not an active fallback by cilium.

## Why VPC-CNI Native Mode Cannot Use BPF Host Routing

Causal chain:

1. **In TKE Native mode, Pod IPs must be valid VPC IPs, and each Pod has its own kernel routing entry on the node**
   - Pod IPs are allocated by `tke-eni-ipamd` from the node's secondary ENI IP pool — cilium does not own IPAM
   - Cross-node connectivity relies on the VPC route table (ARP within a subnet, VPC routing across subnets) — cilium does not own routing
   - This data path requires `endpointRoutes.enabled=true` in helm values — a per-Pod kernel route pointing directly to its lxc device

2. **The essence of `endpointRoutes` mode: host RX bypasses `cilium_host` and goes directly via kernel routing to lxc**
   - In default (non-endpointRoutes) mode, all packets entering the host netns first hit the `cilium_host` device, where its tc-bpf program dispatches them — this is exactly where BPF Host Routing operates
   - In endpointRoutes mode, each Pod has an independent kernel route (`ip route` pointing straight at lxc); packets **do not pass through** `cilium_host` at all
   - In cilium's BPF source, the `ENABLE_HOST_ROUTING` branch in `bpf_host.c` only takes effect on the `cilium_host` path; under endpointRoutes mode this code is never executed

3. **Result: under endpointRoutes mode, packets must traverse the full kernel network stack (netfilter / conntrack / FIB)**
   - Cilium still attaches BPF programs to lxc ingress/egress hooks for NetworkPolicy / Service / Hubble observability
   - But **forwarding inside the host** can only rely on the kernel — that is the very definition of legacy host routing

So Native mode (Pod IP = VPC IP) → must `endpointRoutes.enabled=true` → host RX skips `cilium_host` → BPF host routing is never triggered.

## Cross-cloud comparison: AWS EKS with Cilium ENI IPAM has the same limitation

The official cilium helm chart **automatically writes** `enable-endpoint-routes: "true"` whenever `eni.enabled=true` (cilium's own AWS ENI IPAM):

```yaml
# install/kubernetes/cilium/templates/cilium-configmap.yaml (v1.19.4)
{{- if .Values.eni.enabled }}
  {{- if not .Values.endpointRoutes.enabled }}
  enable-endpoint-routes: "true"
  {{- end }}
```

The reason is identical to TKE Native: AWS ENI IPs are also valid VPC IPs ("directly routable in the AWS VPC"), so cilium has no reason — and no need — to funnel traffic through `cilium_host` for redirect; instead each Pod gets its own kernel route via endpointRoutes. But this also means BPF host routing is not triggered in this mode either.

| Solution                                   | IPAM          | endpointRoutes    | Host Routing |
| ------------------------------------------ | ------------- | ----------------- | ------------ |
| TKE VPC-CNI + Native (chained CNI)         | tke-eni-ipamd | required (manual) | Legacy       |
| AWS EKS with cilium ENI IPAM (not chained) | cilium eni    | automatic (chart) | Legacy       |
| AWS EKS chained aws-cni                    | aws-vpc-cni   | required (manual) | Legacy       |

The pattern is clear: **whenever Pod IPs are valid VPC IPs, cilium uses endpointRoutes and BPF host routing is unavailable**. This is the common cost of cloud-native "Native" routing solutions, not a TKE-specific implementation choice.

## Performance Impact

Extra overhead of legacy host routing compared to BPF host routing:

- Each packet additionally traverses 5 netfilter hooks (PREROUTING / FORWARD / INPUT / OUTPUT / POSTROUTING)
- Conntrack table lookup and update (the connection tracking state machine runs even without iptables rules)
- Kernel routing table (FIB) lookup

In our benchmarks (4C8G S5, TencentOS 4, kernel 6.6), small-packet TCP_RR in Native mode is ~10-15% lower than in Overlay mode (which uses BPF host routing). Single-stream TCP_STREAM throughput shows little difference (capped by NIC bandwidth). Full numbers in [Cilium Performance Tests](./performance-test.md).

## Should You Switch to BPF Host Routing?

**Switching off VPC-CNI Native mode just to gain BPF host routing is generally NOT worth it**:

- The core value of Native mode is that Pod IP == VPC IP — recognized natively by VPC routing, security groups, CLB, and CCN
- Moving to Overlay gains BPF host routing but loses: direct Pod IP routing to external systems, layer-4 LB pass-through to Pods, unified IPAM via the VPC
- Most workloads are insensitive to the ~5μs-per-packet host-stack overhead

**Switching to Overlay is only worthwhile when**:

- High-PPS small-packet workloads (RPC, KV stores, MQ brokers) chase ultra-low RTT
- Node PPS is high and netfilter / conntrack is the bottleneck (check via `nf_conntrack_count` approaching `nf_conntrack_max`)

## Capabilities Unaffected

Even with legacy host routing, the following cilium core capabilities work **fully** in VPC-CNI Native mode:

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

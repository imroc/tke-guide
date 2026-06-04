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

| Deployment Mode      | Host Routing           | Switchable to BPF?              |
| -------------------- | ---------------------- | ------------------------------- |
| GR + Overlay (vxlan) | ✅ BPF (default)       | Already BPF                     |
| VPC-CNI + Overlay    | ✅ BPF (default)       | Already BPF                     |
| VPC-CNI + Native     | ❌ Legacy (**forced**) | **No** — cilium auto-falls-back |

In VPC-CNI Native mode, even setting `bpf.hostRouting=true` in helm values has no effect — cilium detects the situation at startup and falls back to legacy.

## Why VPC-CNI Native Mode Cannot Use BPF Host Routing

Causal chain:

1. **TKE Native mode requires cilium to run in chained CNI mode alongside `tke-route-eni`**
   - Pod IPs must be allocated by `tke-eni-ipamd` from the node's secondary ENI IP pool — cilium does not own IPAM
   - Cross-node connectivity relies on the VPC route table (ARP within a subnet, VPC routing across subnets) — cilium does not own routing
   - Cilium only attaches BPF programs to handle NetworkPolicy / Service / Observability
   - This forces helm values: `cni.chainingMode=generic-veth` and `endpointRoutes.enabled=true`

2. **In chained CNI mode, cilium does not own the data path**
   - BPF Host Routing requires cilium to **fully take over forwarding decisions** on the node — endpoint table lookup, service backend lookup, redirect to the right device
   - In chained mode, the underlying connectivity belongs to the other CNI (`tke-route-eni` here); cilium cannot bypass it to redirect directly

3. **Cilium source code enforces this constraint**
   - At startup, when chained CNI is detected, cilium forcibly sets `EnableHostLegacyRouting=true` (i.e. disables BPF host routing). This cannot be overridden via helm values.
   - Upstream discussion: [GitHub Issue #20135](https://github.com/cilium/cilium/issues/20135)

So: chained CNI mode → `endpointRoutes.enabled=true` is mandatory → cilium falls back to legacy host routing. This is an unavoidable chain.

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

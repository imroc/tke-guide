# Why GR Native Routing does not support L7/DNS NetworkPolicy

## Background

After installing cilium on a TKE cluster, you may want to use **L7/DNS** capabilities in your NetworkPolicy:

- `toFQDNs`: control egress by domain name
- `toPorts.rules.dns`: filter DNS queries by domain pattern

These rules are **not supported** in **Native Routing (GR)** mode. Pods selected by such a policy will experience DNS query timeouts — **all DNS resolution fails** (no response, not even NXDOMAIN/REFUSED), even for cluster-internal service names like `kubernetes.default.svc`.

This document explains the root cause and the workarounds.

## This is a known limitation of cilium

The official cilium documentation explicitly lists "Layer 7 Policy" as one of the Limitations of generic-veth chaining mode:

- [Cilium Docs - Generic Veth Chaining § Limitations](https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/#limitations)
- Tracking issue: [cilium/cilium#12454 - Proxy redirect issue when running Cilium on top of Calico (CNI-Chaining)](https://github.com/cilium/cilium/issues/12454) (packet mark conflict causing proxy redirect failure — same root cause as the TKE GR scenario)

## Technical mechanism

How cilium's L7 DNS policy works:

1. cilium's BPF program identifies DNS traffic from Pods selected by the policy and marks the packets.
2. iptables TPROXY rules use the mark to redirect DNS packets to cilium-agent's built-in DNS proxy socket.
3. The DNS proxy resolves, records the response, and adds resolved IPs to the toFQDNs allow list.

```text
Pod ──DNS query──▶ BPF (mark) ──▶ iptables TPROXY ──▶ cilium DNS proxy ──▶ upstream DNS
                                    ▲
                                    │
                                    └─ requires socket dispatch (lookup → process socket)
```

### Where it breaks in GR mode

GR mode uses [generic-veth chaining](https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/) coexisting with tke-bridge — Pod traffic goes through the Linux bridge `cbr0`:

```text
Pod ─▶ veth ─▶ cbr0 (bridge forwarding) ─▶ eth0 ─▶ upstream
                  ▲
                  │
                  └─ Bridge-forwarded packets do NOT enter IP routing/socket lookup
                     iptables TPROXY socket dispatch doesn't take effect
```

Bridge-forwarded packets **don't really enter IP routing / socket lookup**, so iptables TPROXY's socket dispatch doesn't take effect — and cilium's DNS proxy never receives traffic.

### Why VPC-CNI and Overlay don't have this issue

- **VPC-CNI Native Routing**: Pods attach directly to ENIs and don't go through `cbr0` — DNS redirection works end-to-end.
- **Overlay (VPC-CNI / GR)**: cilium fully owns the Pod datapath, all traffic goes through cilium's BPF — DNS redirection works end-to-end.

## Symptoms and identification

In GR Native Routing mode, **Pods selected by a CiliumNetworkPolicy containing `rules.dns` or `toFQDNs`**:

- All DNS queries time out
- No NXDOMAIN/REFUSED — just **no response** (clients see timeout)
- Even cluster-internal names like `kubernetes.default.svc.cluster.local` fail to resolve
- Removing the NetworkPolicy immediately restores normal resolution

## Workarounds

If you're stuck on GR Native Routing and need egress control:

| Workaround                                  | Suitable for                                                  | Limitation                             |
| ------------------------------------------- | ------------------------------------------------------------- | -------------------------------------- |
| `toCIDR` / `toCIDRSet` listing IP ranges    | Stable target IP ranges, e.g. Tencent Cloud internal services | Must update the policy when IPs change |
| `toEntities: [world]` allowing all internet | Coarse-grained "allow internet" use cases                     | No real access control                 |
| `toEndpoints` with namespace/Pod labels     | In-cluster Pod-to-Pod control                                 | Only applies to in-cluster targets     |
| Switch to Overlay mode                      | Business genuinely requires domain-based egress               | Requires changing network mode         |

## Summary

| Mode                     | toFQDNs / dns L7 | Reason                                          |
| ------------------------ | ---------------- | ----------------------------------------------- |
| Native Routing (VPC-CNI) | ✅ Fully         | No cbr0; DNS redirection works                  |
| Native Routing (GR)      | ❌ Unsupported   | cbr0 bridge forwarding bypasses socket dispatch |
| Overlay (VPC-CNI / GR)   | ✅ Fully         | cilium fully owns datapath                      |

## See also

- [Install Cilium](../install.md)
- [NetworkPolicy Practice - Mode Compatibility](../networkpolicy.md#mode-compatibility)
- [Cilium Docs - Generic Veth Chaining § Limitations](https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/#limitations)
- [cilium/cilium#12454](https://github.com/cilium/cilium/issues/12454)

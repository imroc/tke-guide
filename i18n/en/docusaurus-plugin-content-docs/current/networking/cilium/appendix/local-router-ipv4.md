# Why Native Routing mode needs local-router-ipv4

## Background

When installing cilium on a TKE cluster, if you choose **Native Routing (VPC-CNI)**, you must explicitly configure a `local-router-ipv4` for cilium:

```bash
--set extraConfig.local-router-ipv4=169.254.32.16
```

**Overlay mode** does not need this. This document explains the rationale, and why we choose the specific value `169.254.32.16`.

## The role of cilium_host

On every node, cilium creates a pair of virtual interfaces:

- `cilium_host`: the "gateway" interface on the node, serving as the next-hop for all Pods on this node.
- `cilium_net`: the veth peer of `cilium_host`.

`cilium_host` must have an IP — otherwise the node's routing table is missing an "outbound exit".

```text
                ┌──────────────────────────────────────┐
                │                Node                  │
                │                                      │
                │   ┌──────────┐      ┌────────────┐   │
                │   │   Pod    │─────▶│ cilium_host│──▶│  egress
                │   │ (lxcXX)  │      │  (gateway) │   │
                │   └──────────┘      └────────────┘   │
                └──────────────────────────────────────┘
```

## The Native Routing (VPC-CNI) situation

In Native Routing (VPC-CNI) mode, **cilium does not allocate Pod IPs**: Pods attach directly to ENIs; IPs come from VPC-CNI out of the VPC subnet. cilium has no Pod IP source information at all.

Because cilium doesn't own IP allocation, it cannot automatically decide what IP to use for `cilium_host` — the user must explicitly pick a guaranteed-non-conflicting IP via `local-router-ipv4`.

## Why 169.254.32.16?

`169.254.0.0/16` is the IPv4 link-local range (RFC 3927), with several useful properties:

1. **Not routable**: never collides with VPC IPs or Service CIDR.
2. **Uniform across nodes**: every node can use the same value, simplifying both config and troubleshooting.
3. **Reserved on TKE**: the specific address `169.254.32.16` is verified not to clash with other components on TKE.

:::tip[Other uses of 169.254 on TKE]

TKE also uses `169.254.0.0/16` for the following — avoid these when picking a custom value:

- Instance metadata service (IMDS)
- apiserver internal VIP (the address shown by `kubectl get ep kubernetes`)
- COS / image registry / some other internal services

`169.254.32.16` is a value confirmed not to collide with the above.

:::

## Why Overlay doesn't need it

In Overlay mode, cilium manages Pod IP allocation itself (cluster-pool IPAM). It has full knowledge of every node's PodCIDR and automatically assigns a non-conflicting IP to `cilium_host`. No user intervention required.

## Summary

| Mode                     | local-router-ipv4 | Reason                               |
| ------------------------ | ----------------- | ------------------------------------ |
| Native Routing (VPC-CNI) | ✅ Required       | cilium doesn't own Pod IP allocation |
| Overlay (VPC-CNI / GR)   | ❌ Auto-assigned  | cilium manages IPAM itself           |

GR clusters only support Overlay mode — see [Why this guide does not offer GR Native Routing](./gr-native-not-recommended.md).

## See also

- [Install Cilium](../install.md)
- [Cilium Docs - local-router-ipv4](https://docs.cilium.io/en/stable/network/concepts/routing/)

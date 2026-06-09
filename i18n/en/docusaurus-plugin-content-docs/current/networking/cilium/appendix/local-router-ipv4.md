# Why Is local-router-ipv4 Required in Native Routing Mode?

:::note[Prerequisites]

This article, together with the following two, forms the design principles trilogy for Native Routing mode. Recommended reading order:

1. **[Cilium Host Routing](./host-routing.md)**: Understand how endpointRoutes forces Native mode into legacy host routing.
2. This article: Explains why `cilium_host`'s IP must be manually specified under legacy host routing.
3. **[Why Native Disables sysctlfix](./sysctlfix.md)**: Explains the cascading impact on rp_filter in the same mode.

:::

## Background

When installing cilium on a TKE cluster, if you choose **Native Routing (VPC-CNI)**, you must explicitly set a `local-router-ipv4` parameter:

```bash
--set extraConfig.local-router-ipv4=169.254.32.16
```

The **Overlay** mode does not need this configuration. This article explains the difference and why we chose `169.254.32.16` as the address.

## The Role of the cilium_host Interface

Cilium creates a pair of virtual interfaces on each node:

- `cilium_host`: The "gateway" interface on the node, serving as the next hop for all Pods on this node.
- `cilium_net`: The veth peer paired with `cilium_host`.

`cilium_host` must have an IP address; otherwise, the node's routing table would lack an "exit" point.

```text
                ┌──────────────────────────────────────┐
                │                Node                  │
                │                                      │
                │   ┌──────────┐      ┌────────────┐   │
                │   │   Pod    │─────▶│ cilium_host│──▶│  Outbound
                │   │ (lxcXX)  │      │  (gateway) │   │
                │   └──────────┘      └────────────┘   │
                └──────────────────────────────────────┘
```

## The Special Case of Native Routing (VPC-CNI)

In Native Routing (VPC-CNI) mode, **cilium does not manage Pod IP allocation**: Pods are attached directly to elastic network interfaces, and IPs are allocated from VPC subnets by VPC-CNI. Cilium has no information about Pod IP sources.

Since cilium does not control IP allocation, it cannot automatically decide what IP to use for `cilium_host`. The user must explicitly specify an address that "will never conflict with Pod IPs" via `local-router-ipv4`.

## Why 169.254.32.16?

`169.254.0.0/16` is the IPv4 link-local address range (RFC 3927), with the following characteristics:

1. **Non-routable**: Never conflicts with VPC IPs or Service CIDRs.
2. **Uniform across nodes**: All nodes can use the same value, simplifying configuration and troubleshooting.
3. **TKE-specific reservation**: The specific address `169.254.32.16` is not used by any other component on TKE and has been verified as safe.

:::tip[Other uses of the 169.254.0.0/16 range on TKE]

TKE uses the `169.254.0.0/16` range for the following capabilities — be careful not to cause conflicts:

- Metadata service (IMDS)
- Internal VIP for apiserver (the address shown by `kubectl get ep kubernetes`)
- VIPs for COS, image registry, and some internal services

`169.254.32.16` has been confirmed not to conflict with any of the above services.

:::

## Why Overlay Mode Doesn't Need It

In Overlay mode, cilium manages Pod IP allocation itself (cluster-pool IPAM). It knows all the PodCIDR information for the node and automatically assigns a non-conflicting IP for `cilium_host` from the PodCIDR, without user intervention.

## Summary

| Mode                     | local-router-ipv4 | Reason                        |
| ------------------------ | ----------------- | ----------------------------- |
| Native Routing (VPC-CNI) | ✅ Must be set    | Cilium does not manage Pod IP allocation |
| Overlay (VPC-CNI / GR)   | ❌ Auto-assigned  | Cilium manages IPAM itself    |

GR clusters only support Overlay mode; see [Why Not Provide a GR Native Routing Deployment Scheme?](./gr-native-not-recommended.md).

## Related Links

- [Installing Cilium](../install.md)
- [Cilium Host Routing](./host-routing.md)
- [Why Native Disables sysctlfix](./sysctlfix.md)
- [Cilium Docs - local-router-ipv4](https://docs.cilium.io/en/stable/network/concepts/routing/)

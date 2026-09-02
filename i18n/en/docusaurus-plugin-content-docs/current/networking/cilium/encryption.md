# Enable Communication Encryption

## Overview

This guide describes how to enable transparent encryption of inter-node Pod traffic for the three deployment plans in [Installing Cilium](./install.md). Cilium supports the following encryption methods:

- **WireGuard**: a UDP tunnel based on the in-kernel WireGuard module, with fully automated key management (each node automatically generates its key pair and distributes the public key via the `network.cilium.io/wg-pub-key` annotation on the CiliumNode CRD). **Recommended by this tutorial series**.
- **IPsec**: based on the Linux XFRM/ESP framework. Requires manually creating a key Secret and manually rotating keys. Only usable with the Overlay plans (see the [compatibility matrix](#compatibility-matrix) below for details).
- **ztunnel** (Beta): the per-node L4 proxy of Istio ambient mode, providing mTLS encryption. Only relevant when the cluster uses Istio ambient mode (see [Coexisting with Istio Ambient/ztunnel](#coexisting-with-istio-ambientztunnel)).

Two boundary notes that apply to both methods:

- **Only inter-node traffic of Cilium-managed pods is encrypted**: traffic between pods on the same node is not encrypted (plaintext is always observable on the node, so encryption provides no benefit); traffic from pods to destinations outside the cluster (public internet / non-Pod IPs in the VPC) is not encrypted either.
- Encryption decisions rely on Cilium identities: before the identity of a newly joined node or newly created pod has propagated through the cluster, the first packets sent to it may leave the node unencrypted (Cilium cannot know in advance that the IP belongs to a remote pod).

## Compatibility Matrix

| Deployment Plan | WireGuard | IPsec |
| --------------- | --------- | ----- |
| Native Routing (VPC-CNI) | ✅ Usable (one extra MTU parameter required, see [below](#enable-wireguard-encryption)) | ❌ Not usable (CNI chaining limitation) |
| Overlay (VPC-CNI) | ✅ Usable (MTU handled automatically) | ⚠️ Officially supported, untested in this tutorial series, not recommended |
| Overlay (GR) | ✅ Usable (MTU handled automatically) | ⚠️ Officially supported, untested in this tutorial series, not recommended |

**Why IPsec does not work with Native Routing (VPC-CNI)** — the causal chain:

1. This plan runs in CNI chaining mode: Cilium is chained on top of the TKE VPC-CNI as a generic-veth plugin, Pod IPs are VPC IPs, inter-node routing is performed by the VPC underlay (ENI policy routing), and underlay connectivity is owned by the TKE CNI.
2. Cilium's IPsec transparent encryption relies on the Linux XFRM framework: BPF programs mark outgoing packets for encryption, kernel XFRM policies match on the mark at the underlay layer of the node network stack and perform ESP tunnel encapsulation, and the peer node restores the packets on its decryption interfaces — the whole mechanism requires Cilium to fully control the underlay forwarding path.
3. That premise does not hold in chaining mode. The Cilium project explicitly states that **IPsec transparent encryption is not supported when chaining Cilium on top of other CNI plugins** ([official documentation Limitations](https://docs.cilium.io/en/stable/security/network/encryption-ipsec/), tracking issue [cilium/cilium#15596](https://github.com/cilium/cilium/issues/15596): the underlying connectivity is the responsibility of the other CNI plugin, so it is difficult for Cilium to correctly integrate at that layer to ensure traffic is encrypted).

Therefore, the accurate boundary of the claim that "Pods on VPC-CNI networking cannot use IPsec" is: **only Native Routing (VPC-CNI) (chaining mode) cannot use it**. In the two Overlay plans Cilium is the exclusive CNI and builds its own VXLAN tunnel, which is outside the scope of that limitation.

**Why WireGuard works with all three plans**: the encryption decision and encapsulation of WireGuard happen entirely inside Cilium's own BPF programs and the `cilium_wg0` tunnel device. The only underlay requirement is "UDP reachability between node IPs" — it does not require taking over underlay routing, so it still holds in chaining mode (the official documentation for chaining + WireGuard only notes an MTU caveat, not a usability limitation).

## Enable WireGuard Encryption

### Prerequisites

1. **Kernel wireguard module**: included in Linux 5.6+ (`CONFIG_WIREGUARD=m`). All kernels of the 8 verified node OSes in [Verified Node Operating Systems](./appendix/verified-os.md) are between 5.10 and 6.8, all no lower than 5.6, so the module works out of the box (see [below](#os-kernel-module)).
2. **Allow UDP 51871 between nodes**: the WireGuard tunnel endpoint listens on UDP port 51871 on every node. If you have tightened node security group rules, make sure this port is allowed between all cluster nodes.

### Enable

Append two parameters to your existing installation values (common to all three deployment plans):

```bash
helm upgrade cilium cilium/cilium --version 1.20.1 \
  --namespace kube-system \
  --reuse-values \
  --set encryption.enabled=true \
  --set encryption.type=wireguard
```

:::warning[Native Routing (VPC-CNI) requires an extra MTU parameter]

In chaining mode Cilium does not manage Pod MTU by default (see [MTU Considerations](#mtu-considerations)). Append `--set cni.enableRouteMTUForCNIChaining=true`, otherwise large Pod packets inflated by WireGuard encapsulation will exceed the NIC MTU and get fragmented after enabling encryption, degrading network performance:

```bash
helm upgrade cilium cilium/cilium --version 1.20.1 \
  --namespace kube-system \
  --reuse-values \
  --set encryption.enabled=true \
  --set encryption.type=wireguard \
  --set cni.enableRouteMTUForCNIChaining=true
```

:::

### Verify

1. Check the Encryption line in the Cilium status (`Peers` should equal the node count minus one):

   ```bash
   kubectl -n kube-system exec ds/cilium -- cilium-dbg status | grep Encryption
   # Example output:
   # Encryption: Wireguard [cilium_wg0 (Pubkey: <..>, Port: 51871, Peers: 2)]
   ```

2. Check encryption details (interface name, public key, peer count):

   ```bash
   kubectl -n kube-system exec ds/cilium -- cilium-dbg encrypt status
   ```

   To further inspect each peer's `allowed-ips` (which should contain the Pod IPs on the peer node) and handshake time, use `cilium-dbg debuginfo --output json | jq .encryption`.

3. Capture packets to confirm traffic actually goes through the WireGuard tunnel (install tcpdump inside any Cilium pod first):

   ```bash
   tcpdump -n -i cilium_wg0
   ```

## MTU Considerations

WireGuard encapsulation adds extra overhead (outer IP + UDP + WireGuard headers; Cilium reserves a conservative 95 bytes). After enabling it, the usable MTU for pods shrinks, and the behavior differs between the two modes:

- **Overlay plans (Cilium as exclusive CNI) — handled automatically, no configuration needed**: Cilium auto-detects the base MTU from node NICs, computes the route MTU as `base MTU − VXLAN overhead (50) − WireGuard overhead (95)`, and applies it to the default route in each Pod netns. On an underlay with 1500 MTU, the effective MTU for inter-node traffic is about 1355. The Pod NIC MTU stays unchanged, so same-node local traffic still enjoys the full MTU.
- **Native Routing (VPC-CNI) — must explicitly enable `cni.enableRouteMTUForCNIChaining=true`**: in chaining mode Cilium does not manage Pod route MTU by default (Pod routes are configured by the TKE CNI side). Without this parameter, a 1500-byte Pod packet exceeds the NIC MTU once WireGuard-encapsulated and can only be sent in fragments, showing up as reduced throughput. Once enabled, newly created pods get the correct route MTU (about 1405) written directly by the CNI plugin while setting up the interface, and existing pods are updated periodically by cilium-agent — no business pod restart needed.

## OS Kernel Module

WireGuard requires the kernel to provide the wireguard module (merged into mainline Linux 5.6+, `CONFIG_WIREGUARD=m`). The kernels of the [8 verified node OSes](./appendix/verified-os.md) for all three deployment plans (5.10–6.8: TencentOS Server 4 is 6.6, Ubuntu 22.04 is 5.15, etc.) all satisfy this — the module ships with the kernel and needs no separate installation. When using custom images outside the list, verify the module on the node first with `modinfo wireguard`.

## Why This Guide Does Not Recommend IPsec

Beyond the hard unavailability in the Native plan, this tutorial series uniformly recommends WireGuard even in the Overlay plans where IPsec is usable:

- **Key management**: IPsec requires manually creating the `cilium-ipsec-keys` Secret, and key rotation must be performed manually following the official procedure (with KEYID rolling and transition-window constraints); WireGuard key generation, distribution, and renewal are fully automatic.
- **Performance**: Cilium IPsec decryption is limited to a single CPU core per tunnel, which easily becomes a bottleneck at high throughput (explicitly documented in the official Limitations); the in-kernel WireGuard implementation has no such limit, and community benchmarks generally show better throughput than Cilium IPsec (the gap narrows with AES-NI hardware acceleration).
- **Feature coverage**: the ingress side of encryption strict mode (dropping unencrypted intra-cluster ingress traffic) only supports WireGuard, not IPsec.
- **Operational details**: Overlay + IPsec requires node security groups to allow ESP (IP protocol 50), while WireGuard uses UDP 51871, which is more compatible with conventional security group management practices.

## Coexisting with Istio Ambient/ztunnel

If the cluster uses Istio ambient mode, mTLS encryption between pods can be handled by its per-node ztunnel proxy, so there is no need to additionally enable Cilium WireGuard/IPsec encryption — this avoids the extra overhead and troubleshooting complexity of double encryption. Cilium itself also supports `encryption.type=ztunnel` (Beta) integration with ztunnel, which this tutorial series does not cover.

## References

- [Cilium Transparent Encryption](https://docs.cilium.io/en/stable/security/network/encryption/)
- [Cilium WireGuard Transparent Encryption](https://docs.cilium.io/en/stable/security/network/encryption-wireguard/)
- [Cilium IPsec Transparent Encryption](https://docs.cilium.io/en/stable/security/network/encryption-ipsec/)
- [CNI chaining limitation (IPsec unsupported), issue cilium/cilium#15596](https://github.com/cilium/cilium/issues/15596)

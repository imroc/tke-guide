# Configuring IP Masquerade

## IP Masquerade Overview

In simple terms, IP masquerade translates the source IP of outbound Pod traffic to the node IP (SNAT). It is typically used when Pod IPs cannot be routed directly outside the cluster but outbound access is still needed.

## VPC-CNI Mostly Does Not Need IP Masquerade

In TKE VPC-CNI network mode, Pod IPs are VPC IPs, just like node IPs, and can be routed directly within the VPC. When connected to other VPCs or other clouds (e.g., AWS) via Cloud Connect Network, Pod IPs can also be routed directly. Additionally, NAT Gateways are supported, allowing Pods to access the internet through them.

Therefore, in most scenarios, IP masquerade is not needed. The default installation method in [Installing Cilium](./install.md) also disables Cilium's IP masquerade feature (`--set enableIPv4Masquerade=false`).

## When Is IP Masquerade Needed?

Enable Cilium's IP masquerade if you have the following requirements:

1. Pods need to use the node's public bandwidth to access the internet.
2. Pods need to call certain Tencent Cloud APIs that authenticate based on node IP, such as [CVM metadata API](https://cloud.tencent.com/document/product/213/4934).
3. Cross-VPC or cross-cloud connectivity with overlapping CIDRs, but node IPs can communicate.

:::caution[VPC-CNI Native Mode: Pods Must Enable IP Masquerade for Outbound Internet]

In VPC-CNI Native mode, Pod IPs are allocated from the **secondary ENI** IP pool — valid VPC IPs. However, the node's EIP is only bound to the **primary ENI**. So when a Pod accesses the internet:

1. The packet source IP = Pod IP (VPC IP on the secondary ENI);
2. The kernel forwards the packet through the corresponding secondary ENI (bypassing the primary ENI);
3. The secondary ENI has no EIP, so the packet has no return path at the VPC boundary;
4. Result: **Even if the node has an EIP, the Pod cannot access the internet**.

To allow Native mode Pods to access the internet, one of the following conditions must be met:

- Configure a NAT Gateway in the VPC (suitable for most scenarios, cleanest approach);
- Enable [Cilium Egress Gateway](./egress-gateway.md) (suitable for scenarios requiring per-namespace/Pod fixed egress IP selection);
- Enable the ip-masq-agent described in this article to SNAT outbound VPC traffic to the node IP, going out through the node's primary ENI + node EIP (self-built TKE ip-masq-agent).

GR and VPC-CNI Overlay modes do not have this issue:

- **GR / Overlay**: Pod IPs are not valid VPC IPs, Cilium enables IP masquerade by default (`enableIPv4Masquerade=true`), traffic is SNATed to node IP when leaving the node. The node has an EIP, so outbound internet works;
- **Native**: Pod IPs are valid VPC IPs, Cilium disables IP masquerade by default (`enableIPv4Masquerade=false`), hence the issue above.

:::

## Cilium IP Masquerade Features

Cilium enables IP masquerade by default. To disable it, explicitly configure `--set enableIPv4Masquerade=false`.

The default behavior is to SNAT any traffic whose destination IP is not local to the node IP. Since Pod IPs are typically routable within the cluster, if all Pod IPs are within a fixed CIDR range, you can configure `ipv4NativeRoutingCIDR` to only masquerade traffic destined outside that CIDR.

## eBPF vs iptables

Cilium supports both eBPF and iptables implementations for IP masquerade. In TKE environments, the eBPF implementation must be used.

The eBPF implementation also has two approaches:

1. Use `ipv4NativeRoutingCIDR` to configure a single CIDR that should not be SNATed.
2. Enable the eBPF-based ipMasqAgent to configure multiple CIDRs that should not be SNATed.

Tencent Cloud VPC supports adding secondary CIDRs to extend the VPC CIDR range, meaning Pod IPs in the same cluster may belong to different large internal network ranges (e.g., Pod A's IP is 172.x.x.x, while Pod B's IP is 10.x.x.x). Additionally, when interconnecting with Kubernetes clusters on other clouds (e.g., AWS EKS), the Pod IPs used by both sides may also belong to different large internal network ranges.

Therefore, if you need to enable IP masquerade, it is recommended to use Cilium's built-in eBPF-based ipMasqAgent.

## How to Enable IP Masquerade?

Enable it with the following command:

```bash showLineNumbers
helm upgrade cilium cilium/cilium --version 1.19.4 \
  --namespace kube-system \
  --reuse-values \
  # highlight-add-start
  --set enableIPv4Masquerade=true \
  --set bpf.masquerade=true \
  --set ipMasqAgent.enabled=true \
  --set ipMasqAgent.config.masqLinkLocal=true
  # highlight-add-end
```

:::info[Note]

If adjusting an already installed Cilium configuration, existing nodes need a cilium-agent restart to take effect:

```bash
kubectl -n kube-system rollout restart daemonset cilium
```

:::

:::tip[Parameter Explanation]

Below is the `values.yaml` with relevant parameter explanations:

```yaml title="values.yaml"
# Enable Cilium's IP MASQUERADE feature
enableIPv4Masquerade: true
bpf:
  # Cilium's IP MASQUERADE has bpf and iptables implementations. In TKE environments, use the bpf version. See https://docs.cilium.io/en/stable/network/concepts/masquerading/
  masquerade: true
ipMasqAgent:
  # Use Cilium's eBPF-based ipMasqAgent to control IP MASQUERADE, supporting multiple CIDR ranges that should not be SNATed.
  # Note: ipv4NativeRoutingCIDR only supports a single CIDR, while Tencent Cloud VPC supports adding secondary CIDRs to extend VPC CIDR, so
  # Pod IPs in the same cluster may belong to different large internal network ranges (e.g., Pod A's IP is 172.x.x.x, and Pod B's IP is 10.x.x.x).
  enabled: true
  config:
    # masqLinkLocal controls whether the link-local range (169.254.0.0/16) is SNATed. This range is used for public services on Tencent Cloud,
    # such as CVM metadata service (querying current CVM metadata) or other interfaces requiring node IP authentication. Pods calling
    # these interfaces need to ensure SNAT to node IP, so set masqLinkLocal to true to ensure traffic to 169.254.0.0/16 is SNATed
    # to node IP, preventing such interface calls from failing.
    masqLinkLocal: true
```

:::

## Configuring nonMasqueradeCIDRs

The IP masquerade enablement method described above does not SNAT traffic to all internal network ranges (except 169.255.0.0/16). For more fine-grained control, you can explicitly configure which CIDRs should not be SNATed, as follows.

1. Prepare the ip-masq-agent ConfigMap in a file `ip-masq-agent-config.yaml`:

:::tip[Note]

Add CIDRs that do not need SNAT to nonMasqueradeCIDRs, typically the VPC CIDRs used by Pods in the TKE cluster (including VPC secondary CIDRs).

:::

```yaml title="ip-masq-agent-config.yaml"
apiVersion: v1
kind: ConfigMap
metadata:
  name: ip-masq-agent
  namespace: kube-system
data:
  config: |
    nonMasqueradeCIDRs:
    - 10.0.0.0/16
    - 172.18.0.0/16
    - 192.168.0.0/17
    masqLinkLocal: true
```

2. Create the ConfigMap:

```bash
kubectl apply -f ip-masq-agent-config.yaml
```

3. Update Cilium configuration:

```bash showLineNumbers
helm upgrade cilium cilium/cilium --version 1.19.4 \
  --namespace kube-system \
  --reuse-values \
  # highlight-add-start
  --set enableIPv4Masquerade=true \
  --set bpf.masquerade=true \
  --set ipMasqAgent.enabled=true
  # highlight-add-end
```

4. Restart cilium-agent:

```bash
kubectl -n kube-system rollout restart daemonset cilium
```

## References

- [Masquerading](https://docs.cilium.io/en/stable/network/concepts/masquerading/)

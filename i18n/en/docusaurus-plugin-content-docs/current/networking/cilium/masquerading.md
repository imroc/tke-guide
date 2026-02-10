# Configuring IP Masquerading

## Introduction to IP Masquerading

Simply put, IP masquerading is the process of disguising the source IP of Pod traffic leaving the cluster as the node IP (SNAT). This is typically used in scenarios where the Pod IP cannot be directly routed outside the cluster, but traffic still needs to be accessible externally.

## VPC-CNI Mostly Does Not Require IP Masquerading

In TKE VPC-CNI network mode, Pod IPs use VPC IPs, which are the same as node IPs and can be directly routed within the VPC. After connecting with other VPCs or other clouds (such as AWS) through cloud networking, Pod IPs can also be directly routed. Additionally, it also supports NAT gateways, allowing Pods to access the public internet through NAT gateways.

Therefore, in most scenarios, we don't need to enable IP masquerading. The default installation method provided in [Installing Cilium](./install.md) also disables Cilium's IP masquerading function (`--set enableIPv4Masquerade=false`).

## When is IP Masquerading Needed?

You can enable Cilium's IP masquerading function in the following scenarios:
1. Want Pods to utilize the node's public bandwidth to access the public internet.
2. Pods need to call certain Tencent Cloud interfaces that authenticate based on node IP, such as [CVM metadata interface](https://cloud.tencent.com/document/product/213/4934).
3. When interconnecting across VPCs or across clouds, the network segments overlap, but Node IPs can communicate with each other.

## Cilium's IP Masquerading Function Introduction

Cilium enables IP masquerading by default, and requires explicit configuration to disable it with `--set enableIPv4Masquerade=false`.

The default behavior is that as long as the destination IP is not on the local machine, it will be SNATed to the node IP. Typically, Pod IPs are routable within the cluster. If all Pod IPs are within a fixed network segment, you can configure `ipv4NativeRoutingCIDR` to only masquerade IP communications outside that segment.

## eBPF vs iptables
Cilium supports both eBPF and iptables implementations for IP masquerading. In TKE environments, you need to use the eBPF implementation.

The eBPF implementation also has two usage methods:
1. Configure `ipv4NativeRoutingCIDR` to avoid SNAT for a single CIDR.
2. Enable the eBPF version of ipMasqAgent implementation, which can be configured to avoid SNAT for multiple CIDRs.

Tencent Cloud VPC supports adding secondary CIDRs to extend the VPC's CIDR range. Pod IPs in the same cluster may therefore belong to different large internal network segments (e.g., Pod A's IP is 172.x.x.x, while Pod B's IP is 10.x.x.x). Additionally, if you plan to interconnect with Kubernetes clusters on other clouds (such as AWS EKS clusters), the Pod IPs used by both clusters may also belong to different large internal network segments.

Therefore, if you need to enable IP masquerading, it's recommended to use Cilium's built-in eBPF version of ipMasqAgent.

## How to Enable IP Masquerading?

You can enable it with the following command:

```bash showLineNumbers
helm upgrade cilium cilium/cilium --version 1.19.0 \
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

If you're adjusting the configuration of an already installed Cilium, existing nodes need to restart cilium-agent for the changes to take effect:

```bash
kubectl -n kube-system rollout restart daemonset cilium
```

:::

:::tip[Parameter Explanation]

Here's a `values.yaml` file containing explanations of the relevant parameters:

```yaml title="values.yaml"
# Enable Cilium's IP MASQUERADE function
enableIPv4Masquerade: true
bpf:
  # Cilium's IP MASQUERADE function has both bpf and iptables versions. In TKE environments, you need to use the bpf version. Reference: https://docs.cilium.io/en/stable/network/concepts/masquerading/
  masquerade: true
ipMasqAgent:
  # Use Cilium's eBPF-based ipMasqAgent to control IP MASQUERADE, which supports configuring multiple CIDR segments to avoid SNAT.
  # Note: The ipv4NativeRoutingCIDR method only supports a single CIDR, while Tencent Cloud VPC supports adding secondary CIDRs to extend the VPC's CIDR range.
  # Therefore, Pod IPs in the same cluster may belong to different large internal network segments (e.g., Pod A's IP is 172.x.x.x, while Pod B's IP is 10.x.x.x).
  enabled: true
  config:
    # masqLinkLocal controls whether to perform SNAT for the link local segment (169.254.0.0/16). This segment is used for public services on Tencent Cloud,
    # such as CVM metadata service (querying current CVM metadata), or other interfaces that require node IP authentication.
    # When calling these interfaces from Pods, you need to ensure SNAT to node IP, so set masqLinkLocal to true to ensure that traffic sent to the 169.254.0.0/16
    # segment is SNATed to node IP, avoiding failures when calling such interfaces.
    masqLinkLocal: true
```

:::

## Configuring nonMasqueradeCIDRs

The previous IP masquerading enabling method avoids SNAT for all internal network segments (except 169.255.0.0/16). If you need more granular control, you can explicitly configure specific CIDRs to avoid SNAT. The specific method is as follows.

1. Prepare the ip-masq-agent ConfigMap in the file `ip-masq-agent-config.yaml`:

:::tip[Explanation]

Add all CIDRs that don't require SNAT to nonMasqueradeCIDRs. These are typically the VPC CIDRs used by Pods in the TKE cluster (including VPC secondary CIDRs).

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
helm upgrade cilium cilium/cilium --version 1.19.0 \
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

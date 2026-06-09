# Why Not Provide a GR Native Routing Deployment Scheme?

This guide **no longer provides a deployment scheme for GR clusters with Native Routing**. This document summarizes all the issues found during verification of this mode, the technical principles behind them, and alternative solutions.

:::warning[Conclusion]

When installing cilium on a GR cluster, use only **Overlay mode**; if you need **Native Routing**, use a **VPC-CNI cluster**.

GR + Native Routing runs into all 4 categories of issues below, making it practically unusable for production:

1. ❌ **Cross-node Pod-to-Pod traffic fails** (most critical, see "1. Cross-node Pod-to-Pod Traffic Failure" below)
2. ❌ **L7 / DNS / `toFQDNs` NetworkPolicy not supported**
3. ⚠️ **Node pools must have the `node.cilium.io/agent-not-ready` taint added** (not required in the other three modes)
4. ⚠️ **GR and VPC-CNI coexistence is broken**

We performed a complete [e2e verification](./connectivity-test.md) of this scheme: in cilium's [generic-veth chaining](https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/) mode on top of tke-bridge's `cbr0` bridge, cilium's eBPF datapath and the Linux bridge forwarding path are incompatible — basic connectivity fails. The failure points are listed below.

:::

## 1. Cross-node Pod-to-Pod Traffic Failure

This is the **fatal issue** of this scheme. The e2e test fails at the setup stage:

```text
⌛ Waiting for pod cilium-test-1/client3 to reach DNS server on cilium-test-1/echo-same-node pod...
timeout reached waiting for lookup ... context deadline exceeded
```

Reproduction:

```bash
# client pod on node 105 accessing pod on node 222
$ kubectl -n cilium-test-1 exec deploy/client -- ping -c 2 -W 2 9.230.0.14
2 packets transmitted, 0 received, 100% packet loss

# But node 105 itself (host network) can reach the pod on node 222 normally
$ kubectl run nettest --rm -i --restart=Never --image=... \
    --overrides='{"spec":{"hostNetwork":true,"nodeSelector":{...}}}' \
    -- ping -c 3 -W 2 9.230.0.14
3 packets transmitted, 3 received, 0% packet loss
```

`cilium monitor` shows outbound packets entering the host stack:

```text
-> stack flow 0x0, identity 24059->417, ifindex 0
   9.230.0.208 -> 9.230.0.14 icmp EchoRequest
```

But **no return packets are recorded** — when the return packet reaches the peer node's eth0, it is intercepted or dropped by cilium's eBPF program (`cil_from_netdev`), and cannot reach cbr0 → veth → pod.

**Root cause**:

- In TKE GR clusters, cross-node PodCIDR routing is maintained by GlobalRouter on the hypervisor layer. Outbound packets from a node go through the default gateway and are forwarded by the hypervisor to the peer node.
- However, in chained CNI mode, cilium attaches the `cil_from_netdev` eBPF program to eth0's ingress.
- For traffic coming from outside the node destined for the local node's PodCIDR, cilium does not control IPAM and does not know these IPs are legitimate endpoints managed by cilium. The processing path is incompatible with cbr0 bridge forwarding, causing packet loss.

Same-node Pod-to-Pod communication works because it doesn't go through eth0 ingress. This creates the illusion that "cilium is installed correctly," but any cross-node workload will fail.

## 2. L7 / DNS / `toFQDNs` NetworkPolicy Not Supported

Cilium's L7 capabilities rely on DNS proxy and envoy proxy redirect, with the following chain:

```text
Pod ──DNS query──▶ BPF (mark) ──▶ iptables TPROXY ──▶ cilium DNS proxy ──▶ upstream DNS
                                    ▲
                                    │
                                    └─ depends on socket dispatch (lookup → process socket)
```

With GR Native Routing, Pod traffic goes through the `cbr0` bridge:

```text
Pod ─▶ veth ─▶ cbr0 (bridge forwarding) ─▶ eth0 ─▶ upstream
                  ▲
                  │
                  └─ On the bridge forwarding path, packets do not enter
                     IP routing / socket lookup. iptables TPROXY cannot
                     perform socket dispatch.
```

On the bridge forwarding path, packets **never actually enter IP routing / socket lookup**, so iptables TPROXY's socket dispatch does not work, and cilium's DNS proxy cannot receive traffic.

**Symptoms**: Pods selected by CiliumNetworkPolicy containing `rules.dns` or `toFQDNs` — **all DNS queries time out** (not NXDOMAIN/REFUSED, but no response at all), even for in-cluster service names like `kubernetes.default.svc`; removing the NetworkPolicy immediately restores functionality.

Cilium's official documentation explicitly marks this as a Limitation of generic-veth chaining:

- [Cilium Docs - Generic Veth Chaining § Limitations](https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/#limitations)
- Tracking issue: [cilium/cilium#12454](https://github.com/cilium/cilium/issues/12454) (packet mark conflict causing proxy redirect failure, same origin as the GR scenario)

## 3. Node Pools Must Have the `node.cilium.io/agent-not-ready` Taint Added

In GR mode:

- **Each node has a different PodCIDR** (GR allocates a subnet segment to each node as its PodCIDR)
- The CNI configuration is dynamically generated by `tke-bridge-agent` per node, **containing the node-specific subnet information**

This means cilium **cannot use a unified CNI configuration to manage all nodes like VPC-CNI or Overlay** — it can only watch the CNI configuration generated by tke-bridge through `chainingTarget`, then append itself to the end of the chain.

Race condition:

```text
T0: Node joins the cluster
T1: tke-bridge-agent writes CNI config ──┐
T2: kubelet sees CNI ready, immediately schedules Pod │ Timing issue: cilium hasn't appended yet!
T3: Pod starts with "bare tke-bridge CNI" ─┘
T4: cilium agent starts, appends to chain
T5: Newly created Pods get cilium enhancement
```

Pods created during T2 → T3 are in a "deficient state" — their network configuration comes from bare tke-bridge without cilium-cni enhancements:

- Missing masquerade, may not be able to access TKE metadata services, etc.
- Missing NetworkPolicy enforcement
- Even if cilium agent starts later, these Pods have already "missed" cilium-cni initialization and will not be automatically fixed

**Workaround**: Add the `node.cilium.io/agent-not-ready=true:NoSchedule` taint to the node pool. Once cilium agent starts, it automatically removes this taint, and scheduling begins.

However, this is an additional configuration burden unique to this mode — none of the other three modes require it. If omitted, the symptoms are subtle (Pods appear Running, but workloads discover network issues).

## 4. GR and VPC-CNI Coexistence Is Broken

GR clusters natively support coexistence of GR and VPC-CNI by [enabling VPC-CNI network capability](https://cloud.tencent.com/document/product/457/50354) (default goes through GR, Pods with special annotations go through VPC-CNI).

However, **after installing cilium as described in this guide, this feature becomes unavailable**:

- Cilium chaining uses multus configuration (`defaultDelegates=tke-bridge`) to manage all Pod networks
- When creating a Pod with the `tke.cloud.tencent.com/networks: tke-route-eni` annotation, the IP still comes from the GR ClusterCIDR range (not the VPC-CNI subnet), and the traffic does not actually go through the VPC-CNI path
- The `EnableVpcCniNetworkType` API can be called successfully, and the components are deployed, but there is no actual effect on Pod networking

If your workloads require this coexistence, you must use a VPC-CNI cluster.

## Alternatives

Choose based on your needs from the table below:

| Scenario                                       | Recommended Solution                                |
| ---------------------------------------------- | --------------------------------------------------- |
| Existing GR cluster, want to use cilium        | **Overlay (GR)** — full features, same experience as VPC-CNI clusters |
| New cluster, performance-first, direct Pod routing | **Native Routing (VPC-CNI)** — recommended          |
| New cluster, limited IP resources or want Pod CIDR decoupled from VPC | **Overlay (VPC-CNI)** — recommended |

All three recommended schemes have passed [complete e2e testing](./connectivity-test.md) (see the "Test Results" section of that article).

If you already have a GR cluster in production but **haven't installed cilium yet**, we recommend installing cilium in Overlay mode. The impact on your workloads is that Pod IPs will no longer come from the GR network range (using a dedicated CIDR), but all other capabilities remain intact.

## Related Links

- [Installing Cilium](../install.md)
- [Cilium Connectivity Test](./connectivity-test.md)
- [Cilium Performance Test](./performance-test.md)
- [Cilium Docs - Generic Veth Chaining § Limitations](https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/#limitations)
- [cilium/cilium#12454](https://github.com/cilium/cilium/issues/12454)

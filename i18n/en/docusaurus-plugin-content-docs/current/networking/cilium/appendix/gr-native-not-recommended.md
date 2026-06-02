# Why this guide does not offer GR Native Routing

This guide **no longer offers** the **GR cluster + Native Routing** deployment option. This document collects every issue we ran into on that combination, the technical rationale behind each, and the alternatives — for readers who want to understand why, or who already deployed it.

:::warning[Bottom line]

When installing cilium on a GR cluster, use **Overlay mode only**. If you need **Native Routing**, use a **VPC-CNI cluster**.

GR + Native Routing hits all four problems below at once, which combined make it impractical for production:

1. ❌ **Cross-node Pod-to-Pod traffic is broken** (the worst — see "1. Cross-node Pod-to-Pod traffic broken")
2. ❌ **L7 / DNS / `toFQDNs` NetworkPolicy is unsupported**
3. ⚠️ **Node pools must add an extra `node.cilium.io/agent-not-ready` taint** (none of the other 3 modes need this)
4. ⚠️ **GR + VPC-CNI coexistence is broken**

:::

## Why we tried this in the first place

GR clusters have a large existing footprint among TKE users in China; we initially wanted "GR clusters can also benefit from full Native Routing performance", so we shipped GR + Native Routing as one of the recommended options.

Only after running [the full 4-option e2e test suite](./e2e-test-report.md) did it become clear that, on top of cilium's [generic-veth chaining](https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/) + tke-bridge's `cbr0`, cilium's eBPF datapath and the Linux bridge forwarding path are mutually incompatible — basic connectivity itself doesn't pass. This document lists each failure point.

## 1. Cross-node Pod-to-Pod traffic is broken

This is the **fatal** issue. The e2e test fails right at the setup stage:

```text
⌛ Waiting for pod cilium-test-1/client3 to reach DNS server on cilium-test-1/echo-same-node pod...
timeout reached waiting for lookup ... context deadline exceeded
```

Reproduction:

```bash
# A pod on node 105 reaching a pod on node 222
$ kubectl -n cilium-test-1 exec deploy/client -- ping -c 2 -W 2 9.230.0.14
2 packets transmitted, 0 received, 100% packet loss

# But node 105 itself (host network) can reach the pod on node 222 just fine
$ kubectl run nettest --rm -i --restart=Never --image=... \
    --overrides='{"spec":{"hostNetwork":true,"nodeSelector":{...}}}' \
    -- ping -c 3 -W 2 9.230.0.14
3 packets transmitted, 3 received, 0% packet loss
```

`cilium monitor` captures only the outbound packet entering the host stack:

```text
-> stack flow 0x0, identity 24059->417, ifindex 0
   9.230.0.208 -> 9.230.0.14 icmp EchoRequest
```

But there is **no return packet** — when the reply hits the destination node's eth0, cilium's eBPF program (`cil_from_netdev`) intercepts or drops it before it can reach cbr0 → veth → pod.

**Root cause:**

- A TKE GR cluster maintains cross-node PodCIDR routes at the host-machine layer; egress packets go through the default gateway and are then forwarded by the host machine to the destination node
- But cilium under chained CNI mode attaches `cil_from_netdev` to eth0 ingress
- For ingress traffic destined for the local node's PodCIDR, since cilium doesn't own IPAM and doesn't recognize these IPs as legitimate cilium-managed endpoints, its handling path is incompatible with the cbr0 bridge forwarding model — and packets get lost

Same-node Pod-to-Pod traffic works because it doesn't traverse eth0 ingress. This creates an illusion of "cilium is installed and working" but any cross-node business workload will fail.

## 2. L7 / DNS / `toFQDNs` NetworkPolicy is unsupported

cilium's L7 capabilities depend on the DNS proxy and the envoy proxy redirect chain:

```text
Pod ──DNS query──▶ BPF (mark) ──▶ iptables TPROXY ──▶ cilium DNS proxy ──▶ upstream DNS
                                       ▲
                                       │
                                       └─ depends on socket dispatch (lookup → process socket)
```

In GR Native Routing, Pod traffic traverses the `cbr0` bridge:

```text
Pod ─▶ veth ─▶ cbr0 (bridge forwarding) ─▶ eth0 ─▶ upstream
                  ▲
                  │
                  └─ Bridge-forwarded frames don't actually enter
                     IP routing/socket lookup, so iptables TPROXY
                     socket dispatch doesn't fire — cilium's DNS
                     proxy receives no traffic.
```

Bridge-forwarded frames **do not actually enter IP routing / socket lookup**, so iptables TPROXY's socket dispatch is a no-op and cilium's DNS proxy receives no traffic.

**Symptom**: Pods selected by a CiliumNetworkPolicy containing `rules.dns` or `toFQDNs` will see **all DNS queries time out** (no NXDOMAIN/REFUSED — just no response). Even cluster-internal names like `kubernetes.default.svc` cannot be resolved. Removing the policy restores DNS instantly.

cilium's official docs explicitly list this as a generic-veth chaining limitation:

- [Cilium Docs - Generic Veth Chaining § Limitations](https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/#limitations)
- Tracking issue: [cilium/cilium#12454](https://github.com/cilium/cilium/issues/12454) (packet mark conflict breaking proxy redirect — same root cause as the GR scenario)

## 3. Node pools must add an extra `node.cilium.io/agent-not-ready` taint

In GR mode:

- **Each node has a different PodCIDR** (GR allocates a per-node subnet as that node's PodCIDR)
- The CNI config is generated per-node by `tke-bridge-agent` and **contains node-specific subnet info**

This means cilium **cannot use a single uniform CNI ConfigMap to take over all nodes** as VPC-CNI or Overlay can — it can only watch the CNI config produced by tke-bridge via `chainingTarget` and append itself.

The race condition:

```text
T0: Node joins
T1: tke-bridge-agent writes CNI config ────┐
T2: kubelet sees CNI ready, schedules Pods │ Race: cilium hasn't appended yet!
T3: Pods start with "raw tke-bridge CNI" ──┘
T4: cilium agent finishes startup, appends to chain
T5: Future newly created Pods get the cilium enhancements
```

Pods created during T2 → T3 are in a "degraded" state — their networking is the raw tke-bridge config, missing cilium's enhancements:

- No masquerade — they may fail to access TKE metadata services
- No NetworkPolicy enforcement
- Even after cilium starts, these Pods have already "missed" cilium-cni's init step and won't auto-recover

**Workaround**: add `node.cilium.io/agent-not-ready=true:NoSchedule` to the node pool. cilium-agent removes the taint automatically after it's ready, then scheduling proceeds.

But this is a mode-specific extra setup burden — none of the other 3 modes require it. And missing it produces a subtle failure: Pods look Running, but only at runtime do you discover that some Pods have broken networking.

## 4. GR + VPC-CNI coexistence is broken

GR clusters natively support [enabling VPC-CNI for coexistence](https://cloud.tencent.com/document/product/457/50354) — by default Pods use GR, while Pods with a special annotation use VPC-CNI.

But **after installing cilium per this guide, that capability stops actually working**:

- cilium chaining takes over all Pod networking via multus config (`defaultDelegates=tke-bridge`)
- Pods created with `tke.cloud.tencent.com/networks: tke-route-eni` annotation still get IPs from the GR ClusterCIDR (not the VPC-CNI subnet) — the VPC-CNI path is never actually used
- The `EnableVpcCniNetworkType` API call succeeds and the components deploy, but it has no real effect on Pod networking

If you need this kind of coexistence, you must use a VPC-CNI cluster.

## Alternatives

Pick from this table based on your actual need:

| Need                                                         | Recommended option                                                |
| ------------------------------------------------------------ | ----------------------------------------------------------------- |
| Existing GR cluster, want to use cilium                      | **Overlay (GR)** — full feature set, on par with VPC-CNI clusters |
| New cluster, performance-first, Pod IP routable directly     | **Native Routing (VPC-CNI)** — recommended                        |
| New cluster, IP scarcity or want Pod CIDR decoupled from VPC | **Overlay (VPC-CNI)** — recommended                               |

All three recommended options have passed [the full e2e test](./e2e-test-report.md) (56/59 cases, the remaining 3 being node public-IP unreachable, unrelated to cilium).

If you're already on a GR cluster in production but **haven't installed cilium yet**, install cilium in Overlay mode. The only impact on workloads is that Pod IPs no longer come from the GR CIDR (they come from an independent CIDR); all other capabilities are intact.

If you already deployed GR Native Routing per **an early version of this guide**:

- Same-node workloads may be fine, but **any cross-node Pod-to-Pod or cross-node Service access is unreliable**
- Migrate to GR Overlay or VPC-CNI clusters as soon as practical
- Migration path: typically [roll back to TKE built-in CNI](../install.md#rolling-back-to-tkes-built-in-cni), then re-install cilium in Overlay mode; do this during a maintenance window

## Cleaning up legacy GR Native Routing residue

If you want to fully clean up GR Native Routing state and bring the cluster to a state where Overlay can be installed:

```bash
# 1. Uninstall cilium (and the ip-masq-agent ConfigMap it created)
helm uninstall cilium -n kube-system
kubectl -n kube-system delete cm ip-masq-agent

# 2. Restore tke-bridge-agent settings
#    (GR Native installation modified --cni-conf-dir and added --port-mapping=false)
kubectl -n kube-system edit ds tke-bridge-agent
# Change the --cni-conf-dir path back to /host/etc/cni/net.d/multus
# Remove --port-mapping=false
kubectl -n kube-system rollout status ds/tke-bridge-agent

# 3. Remove the node.cilium.io/agent-not-ready taint from node pools (if present)

# 4. Restart or recreate nodes (recreate is safer — avoids residual eBPF programs and iptables rules)
```

Then install per the Overlay flow.

## See also

- [Installing Cilium](../install.md)
- [Cilium E2E Test Results](./e2e-test-report.md)
- [Cilium Docs - Generic Veth Chaining § Limitations](https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/#limitations)
- [cilium/cilium#12454](https://github.com/cilium/cilium/issues/12454)

# Cilium Debugging Quick Reference

This page collects the cilium debugging commands actually used throughout this tutorial series, each with a one-sentence purpose and a copyable command for quick troubleshooting. Commands are organized for cilium 1.20 (the currently verified version of this tutorial series), and every subcommand has been cross-checked against that version's source.

:::note[The CLI is named cilium-dbg in cilium 1.20]

Starting from cilium 1.16, the former `cilium` CLI binary was renamed to `cilium-dbg`; the cilium 1.20 container image still keeps a `cilium` symlink pointing to `cilium-dbg`, so both names are equivalent. This page uses `cilium-dbg` consistently, executed inside the cilium Pod via `kubectl -n kube-system exec ds/cilium -- cilium-dbg <subcommand>`.

:::

## Check Feature Status

Check the actual status of various cilium features in the current deployment:

<Tabs>
  <TabItem value="basic" label="Summary">

```bash
kubectl -n kube-system exec ds/cilium -- cilium-dbg status
```

  </TabItem>
  <TabItem value="verbose" label="Verbose">

```bash
kubectl -n kube-system exec ds/cilium -- cilium-dbg status --verbose
```

  </TabItem>
</Tabs>

The three lines most worth checking during troubleshooting:

| Field                  | Meaning              | What to look for                                                                                  |
| ---------------------- | -------------------- | ------------------------------------------------------------------------------------------------- |
| `KubeProxyReplacement` | kube-proxy replacement | Should be `True`; if `False`, Service forwarding falls back to kube-proxy                       |
| `Host Routing`         | Host routing mode    | `BPF` or `Legacy`; `Legacy` indicates a configuration-level fallback (e.g. `bpf.masquerade=true` missing) |
| `Masquerading`         | IP masquerading mode | `BPF`, `IPTables`, or `Disabled`; changes in tandem with `Host Routing`                            |

:::warning[status showing BPF does not mean the datapath hits it]

The `Host Routing` field of `cilium status` only reflects the cilium-agent configuration layer: in VPC-CNI Native mode, endpointRoutes is enabled and Pod traffic bypasses the `cilium_host` device, so status shows `BPF` while the datapath never hits it. See [VPC-CNI Native Routing in Depth](./native-routing.md) for the full analysis.

:::

## Monitor Cilium Network on a Specific Node

<Tabs>
  <TabItem value="bash" label="bash">

```bash
NODE=172.22.48.23
POD=$(kubectl --namespace=kube-system get pod --field-selector spec.nodeName=$NODE -l k8s-app=cilium -o json | jq -r '.items[0].metadata.name')
kubectl --namespace=kube-system exec -it $POD -- cilium-dbg monitor
```

  </TabItem>

  <TabItem value="fish" label="fish">

```bash
set NODE 172.22.48.23
set POD $(kubectl --namespace=kube-system get pod --field-selector spec.nodeName=$NODE -l k8s-app=cilium -o json | jq -r '.items[0].metadata.name')
kubectl --namespace=kube-system exec -it $POD -- cilium-dbg monitor
```

  </TabItem>
</Tabs>

:::note[Note]

Replace `NODE` with the actual name of the node you want to monitor.

:::

## Observe Pod-to-Pod Traffic in Real Time

The cilium-agent has a built-in Hubble Server, and the Pod image also ships the `hubble` CLI (which targets the local node's unix domain socket by default), so you can observe traffic in real time on a node without deploying Hubble Relay:

```bash
# Observe traffic of a specific Pod in real time (matches source or destination Pod, Ctrl+C to exit)
kubectl -n kube-system exec ds/cilium -- hubble observe --pod default/my-app -f

# Observe dropped traffic in real time (NetworkPolicy denial, blackhole drops, etc.) to quickly spot policy misfires
kubectl -n kube-system exec ds/cilium -- hubble observe --verdict DROPPED -f

# Observe traffic from Pod a to Pod b (--from-pod/--to-pod pin the direction)
kubectl -n kube-system exec ds/cilium -- hubble observe --from-pod default/a --to-pod default/b
```

:::note[Replaying recent flows]

Without `-f`, `hubble observe` prints the most recent 20 flows from the buffer and exits; use `--last N` to adjust how many flows to look back.

:::

To observe cluster-wide (Hubble Relay aggregating multiple nodes) or to use Hubble UI, see [Enhancing Observability with Cilium](../observability.md).

## Inspect BPF Maps and Agent Internal State

### Inspect Load-Balancing Maps

With kubeProxyReplacement, Service frontends and backends are written by cilium into BPF maps. When troubleshooting unreachable Services or empty backends, check the kernel-side data first:

```bash
kubectl -n kube-system exec ds/cilium -- cilium-dbg bpf lb list
```

Then compare it with the service data in the cilium-agent process memory, to tell whether the agent never received the backends (watch issue) or received them but failed to write them into the BPF map (sync issue):

```bash
kubectl -n kube-system exec ds/cilium -- cilium-dbg shell -- db/show frontends
```

For a real troubleshooting case, see [connection to apiserver reports operation not permitted](./troubleshooting/connect-apiserver-operation-not-permitted.md) (how empty Service backends were located).

### Inspect Egress Gateway Rules

When traffic breaks after configuring Egress Gateway policies, check the egress BPF rules actually in effect on the node (`Source IP` is the Pod IP; an `Egress IP` of `0.0.0.0` means no rule selects the current node):

```bash
kubectl -n kube-system exec ds/cilium -- cilium-dbg bpf egress list
```

See the "FAQ" section of [Egress Gateway in Practice](../egress-gateway.md) for details.

### Inspect Endpoints and Identities

When troubleshooting Pods not taken over by cilium, or NetworkPolicy identity matching not working, inspect the endpoint and security identity data on the node:

```bash
# All endpoint (Pod) entries in the node's BPF map
kubectl -n kube-system exec ds/cilium -- cilium-dbg bpf endpoint list

# Mapping between security identities and labels
kubectl -n kube-system exec ds/cilium -- cilium-dbg identity list

# Mapping between IPs (including node IP/EIP) and identities
kubectl -n kube-system exec ds/cilium -- cilium-dbg bpf ipcache list
```

For large-scale clusters, first watch whether the total identity count is ballooning via `kubectl get ciliumidentities | wc -l`, then drill down with the commands above; see [Large-Scale Cluster Tuning Guide](./large-scale-tuning.md).

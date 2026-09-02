# Building Multi-Cluster Networks with Cilium

## Overview

If you want to connect the networks of multiple clusters — cross-cluster Pod-to-Pod connectivity, cross-cluster Service load balancing (global Services), and identity-based cross-cluster network policies — you can use Cilium's ClusterMesh capability to form a mesh of clusters; this article describes how to do it on TKE. All three deployment plans (Native Routing (VPC-CNI), Overlay (VPC-CNI), Overlay (GR)) are supported, verified with cilium 1.20.1 + TKE 1.32. The prerequisite is underlying network connectivity between clusters (see the next section).

## Network Prerequisites

ClusterMesh only synchronizes control plane information such as Pods, Services, and security identities between clusters; whether the data plane can communicate depends on the underlying network between the clusters themselves. All clusters must satisfy:

1. **Same routing mode**: All clusters must use the same routing mode (all Native Routing or all Overlay); they cannot be mixed.
2. **Small version gap**: The cilium versions of all clusters must differ by no more than one minor release (for example, 1.19.x and 1.20.x can interconnect).
3. **Non-overlapping CIDRs**: Pod CIDRs and Node IPs of all clusters must not overlap (for Overlay mode, plan a different Pod CIDR per cluster, such as `10.244.0.0/16`).

<Tabs>
<TabItem value="native" label="Native Routing (VPC-CNI)" default>

Pod IPs are VPC IPs, so cross-cluster Pod communication is equivalent to cross-subnet communication within the VPC — reachability depends on the VPC network itself:

- **Two clusters in the same VPC**: Naturally connected, no extra configuration needed.
- **Two clusters in different VPCs**: Connect them via [Peering Connection](https://www.tencentcloud.com/document/product/553) or [Cloud Connect Network](https://www.tencentcloud.com/document/product/877), and make sure the routes cover the peer cluster's Pod CIDR (the VPC-CNI Pod subnet).
- **Security groups**: Must allow traffic from the peer cluster's Pod CIDR to this cluster's nodes (Pod-to-Pod, any port); otherwise cross-cluster Pod connectivity fails.

</TabItem>
<TabItem value="overlay" label="Overlay (VPC-CNI / GR)">

Pod IPs come from a dedicated CIDR (not routable VPC addresses). Cross-cluster Pod traffic is encapsulated into the VXLAN tunnel straight to the peer node, just like intra-cluster traffic, so only **node-level connectivity** is required and Pod CIDRs do not need to be routable in the underlay:

- **Two clusters in the same VPC**: Nodes are naturally connected, no extra configuration needed.
- **Two clusters in different VPCs**: Just connect the node subnets via peering or Cloud Connect Network.
- **Security groups**: Must allow UDP 8472 (cilium's default VXLAN port) from the peer cluster's node CIDR to this cluster's nodes.

</TabItem>
</Tabs>

:::note[Open port 2379 for clustermesh-apiserver]

Regardless of the plan, the clustermesh-apiserver exposes this cluster's Cilium control plane to other clusters via an internal CLB (TCP 2379). KVStoreMesh is enabled by default in cilium 1.20: each cluster's clustermesh-apiserver actively connects to the peer CLB to pull data, while cilium-agents only connect to their own cluster's clustermesh-apiserver. Therefore, the nodes running clustermesh-apiserver in the peer cluster must be able to reach the CLB: within the same VPC this is naturally reachable; across VPCs, the peering/CCN must cover the CLB subnet, and node security groups must allow TCP 2379 from the peer cluster.

:::

## Prepare kubeconfig

Merge the kubeconfig files of all clusters to be meshed into a single file, use contexts to distinguish clusters, name each context after the TKE cluster ID (cls-xxx), and make sure the current kubeconfig points to this file. The rest of this article refers to the two clusters via environment variables, which you can set first: `export CLUSTER1=cls-xxxxxxxx CLUSTER2=cls-yyyyyyyy`.

## Specify Cluster Name, ID, and clustermesh-apiserver Internal CLB at Installation

On top of [Installing Cilium](./install.md), append the following parameters for each cluster (different for each cluster):

```bash
helm --kube-context=$CLUSTER1 upgrade --install cilium cilium/cilium --version 1.20.1 \
  --namespace kube-system \
  --set cluster.name=$CLUSTER1 \
  --set cluster.id=1 \
  --set clustermesh.apiserver.service.annotations."service\.kubernetes\.io\/qcloud\-loadbalancer\-internal\-subnetid"="$CLUSTER1_SUBNET_ID" \
  # omit other parameters
```

The second cluster follows the same pattern: `cluster.name=$CLUSTER2`, `cluster.id=2`, and the CLB subnet replaced with `$CLUSTER2_SUBNET_ID`.

Parameter notes:

- `cluster.name`: Cluster name, unique across the mesh. It can be the same as the TKE cluster ID (format cls-xxx; only lowercase letters, digits, and dashes are allowed, up to 32 characters).
- `cluster.id`: Numeric cluster ID (1-255), unique across the mesh.
- `clustermesh.apiserver.service.annotations`: The clustermesh-apiserver exposes this cluster's Cilium control plane to other clusters via a LoadBalancer-type Service; on TKE this creates an internal CLB, and this annotation specifies the subnet ID for the CLB (replace `$CLUSTERx_SUBNET_ID` with a subnet ID in that cluster's VPC).

**Specify the cluster name and ID at installation time**: both take part in generating security identities, and changing them on a running cluster requires restarting all workloads to rebuild identities. To add these parameters to an already-installed cluster, run `helm upgrade cilium cilium/cilium --version 1.20.1 -n kube-system --reuse-values` with the `--set` flags above appended.

## Enable ClusterMesh

### Enable in the first cluster

```bash
cilium clustermesh enable --context $CLUSTER1 --service-type=LoadBalancer
```

This command deploys the clustermesh-apiserver via helm (Deployment + LoadBalancer Service, which creates the internal CLB) and issues mTLS certificates with a certgen Job, later rotated automatically by a CronJob every 4 months. TKE is not among the cloud providers cilium-cli can auto-detect, so `--service-type=LoadBalancer` must be specified explicitly.

### Share the CA

`cilium clustermesh connect` validates that the CA certificates of the two clusters match, and fails outright when they do not (unless you explicitly pass `--allow-mismatching-ca`, which adds the remote CA to the trust bundle). The standard practice is therefore to share the same CA across all clusters: copy the `cilium-ca` Secret generated in the first cluster to the other clusters:

```bash
kubectl --context=$CLUSTER1 -n kube-system get secret cilium-ca -o yaml > cilium-ca.yaml
kubectl --context=$CLUSTER2 -n kube-system delete secret cilium-ca --ignore-not-found
kubectl --context=$CLUSTER2 -n kube-system apply -f cilium-ca.yaml
```

Additionally, if you plan to use cross-cluster Hubble Relay (observing traffic of the whole mesh from any single cluster), all clusters must also use the same CA so that cross-cluster mTLS works correctly.

:::warning[The CA must be copied before enabling ClusterMesh on the target cluster]

When ClusterMesh is enabled, certgen runs with `--ca-reuse-secret`: if the `cilium-ca` Secret already exists it is reused to issue the clustermesh certificates, and only otherwise is a new CA created. Therefore the CA copy must happen before running `cilium clustermesh enable` on the target cluster — otherwise the certificates are not signed by the same CA.

If a cluster has already enabled ClusterMesh with its own CA, merely replacing `cilium-ca` afterwards does not re-issue the existing certificates, and running components do not reload certificates or CAs (the etcd clients of cilium-agent / cilium-operator only hot-reload the client certificate; the trusted CA is loaded when the process starts). Fix it manually:

1. Replace `cilium-ca` (same three commands as above) and delete the old leaf certificate Secrets: `clustermesh-apiserver-server-cert`, `clustermesh-apiserver-admin-cert`, `clustermesh-apiserver-remote-cert`, `clustermesh-apiserver-local-cert`.
2. Trigger a certificate issuance manually: `kubectl --context=$CLUSTER2 -n kube-system create job --from=cronjob/clustermesh-apiserver-generate-certs cert-regen`.
3. Restart that cluster's `clustermesh-apiserver` and `cilium-operator` (Deployments) and `cilium` (DaemonSet) to reload the certificates.

:::

### Enable in the remaining clusters

After copying the CA, run the same enable command in the remaining clusters (for example, `cilium clustermesh enable --context $CLUSTER2 --service-type=LoadBalancer`). When more clusters join the mesh, repeat the "Share the CA" and "Enable" steps for each cluster: keep `cluster.id` and `cluster.name` unique across the mesh, and always copy the CA from the first cluster.

## Connect the Clusters

```bash
cilium clustermesh connect --context $CLUSTER1 --destination-context $CLUSTER2
```

This only needs to be run in one direction (the default `--connection-mode=bidirectional` makes cilium-cli configure both clusters at once, taking effect in both directions). To connect more clusters, pass a comma-separated list of `--destination-context` values, or run the command multiple times.

## Validate

```bash
cilium clustermesh status --context $CLUSTER1 --wait
cilium clustermesh status --context $CLUSTER2 --wait
```

The output looks like this:

```bash
✅ Cluster access information is available:
  - 10.168.0.89:2379
✅ Service "clustermesh-apiserver" of type "LoadBalancer" found
⌛ Waiting (12s) for clusters to be connected: 2 nodes are not ready
✅ All 2 nodes are connected to all clusters [min:1 / avg:1.0 / max:1]
🔌 Cluster Connections:
- cls-yyyyyyyy: 2/2 configured, 2/2 connected
```

Once you see `✅ All N nodes are connected to all clusters` and the peer cluster shows `connected` under Cluster Connections, the control plane is connected properly.

Then run the multi-cluster connectivity test to verify cross-cluster Pod connectivity and Service forwarding (see [Cilium Functional Tests](./appendix/connectivity-test.md) for single-cluster usage; add `--multi-cluster` for multi-cluster mode):

```bash
cilium connectivity test --context $CLUSTER1 --multi-cluster $CLUSTER2
```

## Global Service Example

Annotate a Service with `service.cilium.io/global: "true"` to declare it a global Service; Cilium then automatically synchronizes the backends on both sides and load balances across clusters. Create a Service with the same name and namespace in **every cluster**:

```yaml title="rebel-base.yaml"
apiVersion: v1
kind: Service
metadata:
  name: rebel-base
  annotations:
    service.cilium.io/global: "true" # declare a global Service
spec:
  type: ClusterIP
  ports:
  - port: 80
  selector:
    name: rebel-base
```

Deploy this Service in both clusters together with their own backends (it is also fine for only one side to have backend Pods — access from the other side is then forwarded to the remote backends). Accessing `rebel-base` from a Pod in either cluster shows responses from Pods of both clusters when both sides have backends.

- By default local backends are also shared with the peer (implicitly `service.cilium.io/shared: "true"`); adding `service.cilium.io/shared: "false"` to a Service on one side stops that cluster's backends from being shared with the peer (access from that cluster still load balances to both sides).
- Cross-cluster load balancing does not prefer local backends by default; for "local-first" affinity, see the official [Service Affinity](https://docs.cilium.io/en/stable/network/clustermesh/affinity/) documentation.

## Important Notes

### Ensure No SNAT for Cross-Cluster Pod Traffic

If IP masquerade is enabled, make sure the Pod CIDRs of all clusters are excluded from SNAT: in Native Routing mode, add the peer clusters' Pod CIDRs to `nonMasqueradeCIDRs` as well — see [Configuring IP Masquerade](./appendix/masquerading.md) for details. Otherwise the source IP of cross-cluster Pod traffic is SNATed to a node IP, the peer cannot map the traffic back to the Pod's Cilium identity, and identity-based cross-cluster NetworkPolicies stop working. In Overlay mode, cross-cluster Pod traffic is VXLAN-encapsulated (outer layer is the node IP) and is not affected by masquerade, so nothing needs to be done.

### Incompatible with Egress Gateway and CiliumEndpointSlice

Egress Gateway is not compatible with ClusterMesh: the egress node selected by a CiliumEgressGatewayPolicy must be in the same cluster as the Pods matching the policy, an assumption broken by ClusterMesh's cross-cluster identity and endpoint synchronization. Egress Gateway is likewise incompatible with CiliumEndpointSlice (upstream known issue [cilium#24833](https://github.com/cilium/cilium/issues/24833)). Therefore, do not join a cluster that has Egress Gateway enabled into a ClusterMesh, and vice versa — see the "Known Issues" section of [Egress Gateway Best Practices](./egress-gateway.md).

## References

- [Multi-cluster Networking](https://docs.cilium.io/en/stable/network/clustermesh/)
- [Setting up Cluster Mesh](https://docs.cilium.io/en/stable/network/clustermesh/clustermesh/)
- [Global Services](https://docs.cilium.io/en/stable/network/clustermesh/global-services/)
- [Egress Gateway](https://docs.cilium.io/en/stable/network/egress-gateway/egress-gateway/)

# Building Multi-Cluster Networks with Cilium

## Overview

If you want to centrally manage the networking of multiple clusters — such as multi-cluster Service load balancing and cross-cluster communication security policy management — you can form a mesh (Cluster Mesh) among the clusters. This article describes how to set it up.

## Prepare kubeconfig

Merge the kubeconfig files of all clusters that need to be part of the Cluster Mesh into a single file. Use contexts to differentiate clusters, with context names set to the TKE cluster IDs (cls-xxx). Ensure the current kubeconfig points to this file.

## Specify Cluster Name, ID, and Cluster Mesh Apiserver Private CLB

When installing Cilium, specify the cluster name (can be the same as the TKE cluster ID, format cls-xxx), the cluster numeric ID (1-255), and the subnet ID for the clustermesh-apiserver component's private CLB (this component exposes the current cluster's Cilium control plane to other Cilium clusters, creating a CLB via a LoadBalancer-type Service; the private CLB requires specifying the subnet ID):

```bash
helm --kube-context=$CLUSTER1 upgrade --install cilium cilium/cilium --version 1.19.4 \
  --namespace kube-system \
  --set cluster.name=$CLUSTER1 \
  --set cluster.id=1 \
  --set clustermesh.apiserver.service.annotations."service\.kubernetes\.io\/qcloud\-loadbalancer\-internal\-subnetid"="$CLUSTER1_SUBNET_ID" \
  # omit other parameters

helm --kube-context=$CLUSTER2 upgrade --install cilium cilium/cilium --version 1.19.4 \
  --namespace kube-system \
  --set cluster.name=$CLUSTER2 \
  --set cluster.id=2 \
  --set clustermesh.apiserver.service.annotations."service\.kubernetes\.io\/qcloud\-loadbalancer\-internal\-subnetid"="$CLUSTER2_SUBNET_ID" \
  # omit other parameters
```

## Share CA

If you plan to allow Hubble Relay across clusters, ensure the CA certificates are identical in each cluster so that cross-cluster mTLS works correctly.

You can copy the CA certificate from one cluster to another:

```bash
kubectl --context=$CLUSTER1 -n kube-system get secret cilium-ca -o yaml > cilium-ca.yaml
kubectl --context=$CLUSTER2 -n kube-system delete secret cilium-ca
kubectl --context=$CLUSTER2 apply -f cilium-ca.yaml
```

## Enable Cluster Mesh

Use the cilium command to enable Cluster Mesh:

```bash
cilium clustermesh enable --context $CLUSTER1 --service-type=LoadBalancer
cilium clustermesh enable --context $CLUSTER2 --service-type=LoadBalancer
```

## Connect Clusters

```bash
cilium clustermesh connect --context $CLUSTER1 --destination-context $CLUSTER2
```

## Important Notes

### Ensure No SNAT for Cross-Cluster Pod Traffic

If IP masquerade is enabled, make sure Pod CIDRs in all clusters are not subject to SNAT. See [Configuring IP Masquerade](./appendix/masquerading.md) for configuration details.

## References

- [Multi-cluster Networking](https://docs.cilium.io/en/stable/network/clustermesh/)
- [Setting up Cluster Mesh](https://docs.cilium.io/en/stable/network/clustermesh/clustermesh/)

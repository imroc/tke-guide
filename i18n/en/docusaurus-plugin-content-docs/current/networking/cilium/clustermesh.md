# Building Multi-Cluster Networks with Cilium

## Overview

If you want to uniformly manage networks across multiple clusters, such as multi-cluster Service load balancing and security policy control for inter-cluster communication, you can form a mesh of multiple clusters (Cluster Mesh). This article explains how to do this.

## Preparing kubeconfig

You need to merge the kubeconfig files of all clusters that need to form a Cluster Mesh into one file, distinguishing clusters by context. The context name should be the TKE cluster ID (cls-xxx), and ensure that the currently used kubeconfig points to this file.

## Specifying Cluster Name, ID, and clustermesh-apiserver Internal CLB

When installing Cilium, specify the cluster name (which can be the same as the TKE cluster ID, format cls-xxx), cluster numeric ID (1-255), and the subnet ID where the clustermesh-apiserver component's internal CLB is located (this component is used to expose the current cluster's Cilium control plane to other Cilium clusters, created using LoadBalancer type Service, and the internal CLB needs to specify a subnet ID):

```bash
helm --kube-context=$CLUSTER1 upgrade --install cilium cilium/cilium --version 1.18.6 \
  --namespace kube-system \
  --set cluster.name=$CLUSTER1 \
  --set cluster.id=1 \
  --set clustermesh.apiserver.service.annotations."service\.kubernetes\.io\/qcloud\-loadbalancer\-internal\-subnetid"="$CLUSTER1_SUBNET_ID" \
  # omit other parameters

helm --kube-context=$CLUSTER2 upgrade --install cilium cilium/cilium --version 1.18.6 \
  --namespace kube-system \
  --set cluster.name=$CLUSTER2 \
  --set cluster.id=2 \
  --set clustermesh.apiserver.service.annotations."service\.kubernetes\.io\/qcloud\-loadbalancer\-internal\-subnetid"="$CLUSTER2_SUBNET_ID" \
  # omit other parameters
```

## Sharing CA

If you plan to enable Hubble Relay across clusters, you need to ensure that the CA certificates in each cluster are the same, so that cross-cluster mTLS can work properly.

You can copy the CA certificate from one cluster to another:

```bash
kubectl --context=$CLUSTER1 -n kube-system get secret cilium-ca -o yaml > cilium-ca.yaml
kubectl --context=$CLUSTER2 -n kube-system delete secret cilium-ca
kubectl --context=$CLUSTER2 apply -f cilium-ca.yaml
```

## Enabling Cluster Mesh

Enable Cluster Mesh using the cilium command:

```bash
cilium clustermesh enable --context $CLUSTER1 --service-type=LoadBalancer
cilium clustermesh enable --context $CLUSTER2 --service-type=LoadBalancer
```

## Connecting Clusters

```bash
cilium clustermesh connect --context $CLUSTER1 --destination-context $CLUSTER2
```

## Considerations

### Ensuring No SNAT for Cross-Cluster Pod Communication

If IP masquerading is enabled, you should ensure that all CIDR used by Pods across all clusters do not have SNAT. For specific configuration methods, refer to [Configuring IP Masquerading](./masquerading.md).

## References

- [Multi-cluster Networking](https://docs.cilium.io/en/stable/network/clustermesh/)
- [Setting up Cluster Mesh](https://docs.cilium.io/en/stable/network/clustermesh/clustermesh/)

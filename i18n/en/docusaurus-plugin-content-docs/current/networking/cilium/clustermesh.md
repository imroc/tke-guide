# 使用 Cilium 构建多集群网络

## 概述

如果希望统一管理多个集群的网络，如多集群 Service 负载均衡，集群间通信的安全策略管控，可将多个集群组成网格（Cluster Mesh），本文介绍如何操作。

## 准备 kubeconfig

需将所有需要组 Cluster Mesh 的集群的 kubeconfig 合并到一个文件，通过 context 区分集群，context 名称为 TKE 集群 ID（cls-xxx），且确保当前使用的 kubeconfig 指向该文件。

## 指定集群名称、ID 和 clustermesh-apiserver 内网 CLB

安装 cilium 指定下集群名称（可与 TKE 集群 ID 相同，格式 cls-xxx）、集群数字 ID（1-255）和 clustermesh-apiserver 组件内网 CLB 所在子网 ID（该组件用于暴露当前集群 cilium 控制面给其它 cilium 集群，使用 LoadBalancer 类型 Service 方式创建 CLB，内网 CLB 需指定子网 ID）：

```bash
helm --kube-context=$CLUSTER1 upgrade --install cilium cilium/cilium --version 1.18.3 \
  --namespace kube-system \
  --reuse-values \
  --set cluster.name=$CLUSTER1 \
  --set cluster.id=1 \
  --set clustermesh.apiserver.service.annotations."service\.kubernetes\.io\/qcloud\-loadbalancer\-internal\-subnetid"="$CLUSTER1_SUBNET_ID"


helm --kube-context=$CLUSTER2 upgrade --install cilium cilium/cilium --version 1.18.3 \
  --namespace kube-system \
  --reuse-values \
  --set cluster.name=$CLUSTER2 \
  --set cluster.id=2 \
  --set clustermesh.apiserver.service.annotations."service\.kubernetes\.io\/qcloud\-loadbalancer\-internal\-subnetid"="$CLUSTER2_SUBNET_ID"
```

## 共享 CA

如果您计划跨集群允许 Hubble Relay，需确保每个集群中的 CA 证书相同，以便让跨集群的 mTLS 能够正常工作。

可以将一个集群的 CA 证书复制到另一个集群：

```bash
kubectl --context=$CLUSTER1 -n kube-system get secret cilium-ca -o yaml > cilium-ca.yaml
kubectl --context=$CLUSTER2 -n kube-system delete secret cilium-ca
kubectl --context=$CLUSTER2 apply -f cilium-ca.yaml
```

## 启用 Cluster Mesh

通过 cilium 命令启用 Cluster Mesh：

```bash
cilium clustermesh enable --context $CLUSTER1 --service-type=LoadBalancer
cilium clustermesh enable --context $CLUSTER2 --service-type=LoadBalancer
```

## 连接集群

```bash
cilium clustermesh connect --context $CLUSTER1 --destination-context $CLUSTER2
```

## 注意事项

### 确保跨集群 Pod 通信没有 SNAT

如果启用了 IP 伪装功能，应确保所有集群的 Pod 使用的网段都不能有 SNAT，具体配置方法参考 [配置 IP 伪装](./masquerading.md)。

## 参考资料

- [Multi-cluster Networking](https://docs.cilium.io/en/stable/network/clustermesh/)
- [Setting up Cluster Mesh](https://docs.cilium.io/en/stable/network/clustermesh/clustermesh/)

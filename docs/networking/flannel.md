# 在 TKE 自建 Flannel CNI

## 概述

本文介绍如何在 TKE 自建 Flannel CNI。

## 什么场景需要自建 Flannel CNI？

1. 希望 Pod IP 不占用 VPC 的 IP 网段（包括 VPC 主网段和辅助网段）。
2. 希望使用注册节点，但不希望使用 CiliumOverlay 网络插件（Cilium 有很多限制，且引入了额外的复杂度，大规模场景也可能对 apiserver 有压力）。

## 准备 TKE 集群

TKE 集群使用 VPC-CNI 网络模式，不勾选安装 ip-masq-agent。

## 卸载 TKE CNI 插件

TODO

## 使用 helm 安装 flannel

```bash
kubectl create ns kube-flannel
kubectl label --overwrite ns kube-flannel pod-security.kubernetes.io/enforce=privileged

helm repo add flannel https://flannel-io.github.io/flannel/
helm upgrade --install flannel --namespace kube-flannel flannel/flannel \
  --set flannel.image.repository="docker.io/flannel/flannel" \
  --set flannel.image_cni.repository="docker.io/flannel/flannel-cni-plugin" \
  --set podCidr="10.244.0.0/16"
```

## 相关链接

- [flannel 项目地址](https://github.com/flannel-io/flannel)

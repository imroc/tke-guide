# 在 TKE 自建 Flannel

## 概述

本文介绍如何在 TKE 自建 Flannel CNI。

## 什么场景需要自建 Flannel CNI？

1. Pod 数量极大，需要消耗大量 IP 资源，希望 Pod IP 不占用 VPC 的 IP 网段（包括 VPC 主网段和辅助网段）。
2. 使用注册节点纳管第三方节点且需要使用容器网络（Pod 分配 IP），但不希望使用 CiliumOverlay 网络插件（Cilium 有很多限制，且引入了额外的复杂度，大规模场景也可能对 apiserver 有压力）。

## 准备 TKE 集群

在 [容器服务控制台](https://console.cloud.tencent.com/tke2/cluster) 创建 TKE 集群，注意以下关键选项：

- 网络模式：选择 VPC-CNI。
- 节点：安装前不要向集群添加任何普通节点或原生节点，避免残留相关规则和配置，等安装完成后再添加。
- 基础组件：取消勾选安装 ip-masq-agent（VPC-CNI 网络模式下此组件是可选的，由于我们需要安装 flannel，pod ip 固定只能在集群内访问，出集群流量必须 SNAT，而这个功能是 flannel 自带的，所以不需要安装 ip-masq-agent）。

集群创建成功后，需开启集群访问来暴露集群的 apiserver 提供后续使用 helm 安装 flannel 时，helm 命令能正常操作 TKE 集群，参考 [开启集群访问的方法](https://cloud.tencent.com/document/product/457/32191#.E6.93.8D.E4.BD.9C.E6.AD.A5.E9.AA.A4)。

根据自身情况，选择开启内网访问还是公网访问，主要取决于 helm 命令所在环境的网络是否与 TKE 集群所在 VPC 互通：

1. 如果可以互通就开启内网访问。
2. 如果不能互通就开启公网访问。当前开启公网访问需要向集群下发 `kubernetes-proxy` 组件作为中转，依赖集群中需要有节点存在（未来可能会取消该依赖，但当前现状是需要依赖），如果要使用公网访问方式，建议向集群先添加个超级节点，以便 `kubernetes-proxy` 的 pod 能够正常调度，等 flannel 安装完成后，再删除该超级节点。

### 准备 helm 环境

1. 确保 [helm](https://helm.sh/zh/docs/intro/install/) 和 [kubectl](https://kubernetes.io/zh-cn/docs/tasks/tools/install-kubectl-linux/) 已安装，并配置好可以连接集群的 kubeconfig（参考 [连接集群](https://cloud.tencent.com/document/product/457/32191#a334f679-7491-4e40-9981-00ae111a9094)）。
2. 添加 flannel 的 helm repo:
   ```bash
   helm repo add flannel https://flannel-io.github.io/flannel/
   ```

## 调整 TKE CNI 插件

由于我们要自建 Flannel CNI，为避免冲突，我们需要避免 TKE 的 CNI 组件调度到注册节点（让 `tke-cni-agent` 这个 DaemonSet 不调度到注册节点）：

```bash
kubectl -n kube-system patch daemonset tke-cni-agent --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/affinity",
    "value": {
      "nodeAffinity": {
        "requiredDuringSchedulingIgnoredDuringExecution": {
          "nodeSelectorTerms": [
            {
              "matchExpressions": [
                {
                  "key": "node.kubernetes.io/instance-type",
                  "operator": "NotIn",
                  "values": ["external"]
                }
              ]
            }
          ]
        }
      }
    }
  }
]'
```

> 注册节点的 `node.kubernetes.io/instance-type` 标签值为 `external`，通过上述 nodeAffinity 配置，可以让 `tke-cni-agent` 不调度到注册节点上。

## 使用 helm 安装 flannel

flannel 默认使用基于 vxlan 的 overlay 网络，需要指定一个集群网段（podCidr 参数），集群中所有的 Pod IP 都是从该网段分配，根据自己需求配置 podCidr 参数。

使用如下命令安装 flannel：

```bash
kubectl create ns kube-flannel
kubectl label --overwrite ns kube-flannel pod-security.kubernetes.io/enforce=privileged

helm repo add flannel https://flannel-io.github.io/flannel/
helm upgrade --install flannel --namespace kube-flannel flannel/flannel \
  --set flannel.image.repository="docker.io/flannel/flannel" \
  --set flannel.image_cni.repository="docker.io/flannel/flannel-cni-plugin" \
  --set podCidr="10.244.0.0/16"
```

## 添加注册节点

flannel 安装好后，如果想要纳管第三方节点，可先开启注册节点：

## 相关链接

- [flannel 项目地址](https://github.com/flannel-io/flannel)

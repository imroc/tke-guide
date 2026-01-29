# 在 TKE 自建 Flannel

:::warning[警告]

本方案是本人探索的在 TKE 上自建 Flannel 网络的非标方案，不是 TKE 官方方案，没有技术支持和 SLA 保障，请谨慎参考。

目前基础功能跑通了，但未经过其它测试和生产验证。

:::

## 概述

如果需要使用 TKE 注册节点纳管第三方节点且需要使用容器网络（Pod 分配 IP），但不希望使用 CiliumOverlay 网络插件（Cilium 有很多限制，且引入了额外的复杂度，大规模场景也可能对 apiserver 有压力），可以在 TKE 自建 Flannel CNI，为注册节点的 Pod 分配 Pod IP。

本文介绍如何在 TKE 自建 Flannel CNI。

## 准备 TKE 集群

在 [容器服务控制台](https://console.cloud.tencent.com/tke2/cluster) 创建 TKE 集群，注意以下关键选项：

- 网络模式：选择 VPC-CNI。
- 节点：安装前不要向集群添加任何普通节点或原生节点，避免残留相关规则和配置，等安装完成后再添加。
- 基础组件：取消勾选安装 ip-masq-agent（VPC-CNI 网络模式下此组件是可选的，由于我们需要安装 flannel，pod ip 固定只能在集群内访问，出集群流量必须 SNAT，而这个功能是 flannel 自带的，所以不需要安装 ip-masq-agent）。

集群创建成功后，需开启集群访问来暴露集群的 apiserver 提供后续使用 helm 安装 flannel 时，helm 命令能正常操作 TKE 集群，参考 [开启集群访问的方法](https://cloud.tencent.com/document/product/457/32191#.E6.93.8D.E4.BD.9C.E6.AD.A5.E9.AA.A4)。

根据自身情况，选择开启内网访问还是公网访问，主要取决于 helm 命令所在环境的网络是否与 TKE 集群所在 VPC 互通：

1. 如果可以互通就开启内网访问。
2. 如果不能互通就开启公网访问。当前开启公网访问需要向集群下发 `kubernetes-proxy` 组件作为中转，依赖集群中需要有节点存在（未来可能会取消该依赖，但当前现状是需要依赖），如果要使用公网访问方式，建议向集群先添加个超级节点，以便 `kubernetes-proxy` 的 pod 能够正常调度，等 flannel 安装完成后，再删除该超级节点。

## 开启注册节点能力

1. 进入 TKE 集群基本信息页面。
2. 点击 **基础信息** 选项卡。
3. 开启 **注册节点能力**：勾选 **专线连接**，选择代理弹性网卡所在子网（用于代理注册节点访问云上资源），最后点击 **确认开启**。

## 规划集群网段

在安装 flannel 之前，需要先确定好集群网段（Pod CIDR），这个网段将用于为所有 Pod 分配 IP 地址。规划时需注意：

- 网段不能与 VPC 网段冲突，否则 Pod 可能无法访问集群外的资源（比如数据库）。
- 网段大小决定了集群可分配的 Pod IP 数量（如 /16 可分配约 65534 个 IP）。
- 确定后不建议更改，请根据业务规模预留足够空间。

## 准备安装工具

确保 [helm](https://helm.sh/zh/docs/intro/install/) 和 [kubectl](https://kubernetes.io/zh-cn/docs/tasks/tools/install-kubectl-linux/) 已安装，并配置好可以连接集群的 kubeconfig（参考 [连接集群](https://cloud.tencent.com/document/product/457/32191#a334f679-7491-4e40-9981-00ae111a9094)）。

由于安装依赖的 helm chart 包在 github，确保当前工具所在环境能够访问 github。

## 卸载 TKE 网络组件

为了能让 Flannel CNI 在 TKE 集群上安装和运行，我们需要对 TKE 自带的一些网络组件进行卸载，避免冲突：

```bash
# 卸载 VPC-CNI 相关网络组件
kubectl -n kube-system patch daemonset tke-eni-agent -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
kubectl -n kube-system patch deployment tke-eni-ipamd -p '{"spec":{"replicas":0,"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
kubectl -n kube-system patch deployment tke-eni-ip-scheduler -p '{"spec":{"replicas":0,"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
kubectl delete mutatingwebhookconfigurations.admissionregistration.k8s.io add-pod-eni-ip-limit-webhook

# 清理卸载前自动创建的 pod 和 rs
kubectl -n kube-system delete pod --all
kubectl -n kube-system delete replicasets.apps --all

# tke-cni-agent 不卸载，用于拷贝基础的 CNI 二进制（如 loopback）到 CNI 二进制目录给 flannel 用，
# 但要禁用生成 TKE 的 CNI 配置文件，避免与 flannel 的 CNI 配置文件冲突
kubectl patch configmap tke-cni-agent-conf -n kube-system --type='json' -p='[{"op": "remove", "path": "/data"}]'
```

## 安装 podcidr-controller

由于 TKE VPC-CNI 模式下没有集群网段概念，kube-controller-manager 不会自动为节点分配 podCIDR，也无法通过自定义参数来实现。而默认情况下 flannel 依赖 kube-controller-manager 先为节点分配 podCIDR，然后 flannel 再根据当前节点的分配到的 podCIDR 为 Pod 分配 IP。flannel 另外也支持使用 etcd 来存储网段配置和 IP 分配信息，但会引入额外的 etcd，维护成本较高。

为了解决这个问题，可以使用轻量级的 [podcidr-controller](https://github.com/imroc/podcidr-controller) 来自动为节点分配 podCIDR。

使用以下命令安装：

```bash
helm repo add podcidr-controller https://imroc.github.io/podcidr-controller
helm repo update podcidr-controller

helm upgrade --install podcidr-controller podcidr-controller/podcidr-controller \
  -n kube-system \
  --set clusterCIDR="10.244.0.0/16" \
  --set nodeCIDRMaskSize=24 \
  --set removeTaints[0]=tke.cloud.tencent.com/eni-ip-unavailable \
  --set tolerations[0].key=tke.cloud.tencent.com/eni-ip-unavailable \
  --set tolerations[0].operator=Exists \
  --set tolerations[1].key=node-role.kubernetes.io/master \
  --set tolerations[1].operator=Exists \
  --set tolerations[2].key=tke.cloud.tencent.com/uninitialized \
  --set tolerations[2].operator=Exists \
  --set tolerations[3].key=node.cloudprovider.kubernetes.io/uninitialized \
  --set tolerations[3].operator=Exists
```

参数说明：

- `clusterCIDR`：集群网段，需与后续安装 flannel 时的 `podCidr` 保持一致。
- `nodeCIDRMaskSize`：每个节点分配的子网掩码大小，如设为 24 表示每个节点可分配 254 个 Pod IP。
- `removeTaints`: 自动移除节点污点。如果向 TKE 集群加入普通节点或原生节点（非注册节点），默认会给节点添加 `tke.cloud.tencent.com/eni-ip-unavailable` 这个污点，等待节点上 VPC-CNI 相关组件就绪后，会自动移除该污点，但由于我们需要使用 flannel 来完全替代 TKE 自带的网络插件，就不会自动移除该污点了，所以利用当前组件来自动移除该污点，避免 Pod 无法调度。
- `tolerations`: 配置 podcidr-controller 的污点容忍，因为 Flannel CNI 依赖此组件为节点分配 podCIDR，而节点初始化完成也依赖 CNI 就绪，所以这个组件优先级很高，需要容忍一些污点。

## 安装 flannel

flannel 默认使用基于 vxlan 的 overlay 网络，需要指定一个集群网段（podCidr 参数），集群中所有的 Pod IP 都是从该网段分配，根据自己需求配置 podCidr 参数。

使用如下命令安装 flannel：

```bash
kubectl create ns kube-flannel
kubectl label --overwrite ns kube-flannel pod-security.kubernetes.io/enforce=privileged

helm repo add flannel https://flannel-io.github.io/flannel/
helm upgrade --install flannel --namespace kube-flannel flannel/flannel \
  --set podCidr="10.244.0.0/16" \
  --set flannel.image.repository="docker.io/flannel/flannel" \
  --set flannel.image_cni.repository="docker.io/flannel/flannel-cni-plugin"
```

参数说明：

- `podCidr`: 集群网段，需与 podcidr-controller 中的 `clusterCIDR` 保持一致。
- `flannel.image.repository` 与 `flannel.image_cni.repository`：指定 flannel 相关镜像地址，默认使用 `ghcr.io`，对节点的网络条件有要求，改为 dockerhub 上的 mirror 地址，在 TKE 环境有镜像加速（包括注册节点），可直接内网拉取镜像。

## 使用注册节点纳管第三方机器

使用以下方式将第三方机器通过注册节点纳管到 TKE 集群中：

1. 进入 TKE 集群**节点管理**页面。
2. 点击 **点击节点池** 选项卡。
3. 点击 **新建**。
4. 选择 **注册节点** 并点击 **创建**。
5. 根据自身情况配置并点击 **创建节点池**。
6. 进入节点池详情页。
7. 点击 **新建节点**。
8. 节点初始化方式选择 **内网**。
9. 根据提示使用注册脚本将第三方机器纳管到 TKE 集群中。

:::tip[备注]

注册脚本会对当前机器进行校验，如果不符合要求，会有告警信息，执行注册时也不会成功。

由于使用 flannel 作为 CNI 插件，对 OS 和内核要求很低，如果不希望严格的校验，可修改注册脚本，将 `check` 函数中的 `check_os` 和 `check_kernel` 函数注释掉。

:::

## 常见问题

### br_netfilter 内核模块未加载

flannel 依赖 br_netfilter 内核模块，如果未加载，会导致 flannel 无法正常工作:

```txt
E0127 04:42:47.627500       1 main.go:278] Failed to check br_netfilter: stat /proc/sys/net/bridge/bridge-nf-call-iptables: no such file or directory
```

解决方法：

```bash
# 加载内核模块
modprobe br_netfilter

# 设置开机自动加载
echo "br_netfilter" > /etc/modules-load.d/br_netfilter.conf
```

## 相关链接

- [flannel 项目地址](https://github.com/flannel-io/flannel)
- [podcidr-controller 项目地址](https://github.com/imroc/podcidr-controller)

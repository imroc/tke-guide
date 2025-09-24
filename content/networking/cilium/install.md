# 安装 Cilium

## 操作场景

本文介绍如何在 TKE 集群中安装 [cilium](https://cilium.io/)。

## 前提条件

- 集群版本：TKE 1.30 及以上，参考 [Cilium Kubernetes Compatibility](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/)
- 网络模式：VPC-CNI 或 GlobalRouter
- 节点类型：普通节点（原生节点的内核版本较低，会有兼容性问题）
- 操作系统：TencentOS>=4
- kube-proxy: 使用 iptables 转发模式或者卸载 kube-proxy 并使用 cilium 替代

## 原生路由

Cilium 路由支持两种模式：
1. Encapsulation（封装模式）：即在原有的网络基础上再做一层网络封包进行转发。优点是兼容性好，可适配各种网络环境，缺点是性能较差。
2. Native-Routing（原生路由）：Pod IP 直接在底层网络上进行路由转发，Cilium 不管。优点是性能好，缺点是依赖底层网络对 Pod IP 的路由转发的支持，不通用。

在包括 TKE 在内的云上托管的 Kubernetes 集群中，VPC 底层网络都已支持 Pod IP 的路由转发，无需再走一层 overlay，可获得最佳的网络性能，所以通常使用 Native-Routing 模式安装 cilium，本文介绍的安装方法也是使用 Native-Routing 的模式。

> 更多详情请参考 Cilium 官方文档：[Routing](https://docs.cilium.io/en/stable/network/concepts/routing/)。

## 操作步骤

### 创建 TKE 集群

创建 TKE 标准集群：
- Kubernetes 版本: 不低于 1.30.0，建议选择最新版。
- 操作系统：TencentOS 4.0 及以上或者 Ubuntu 24.04 及以上。
- 容器网络插件：VPC-CNI 共享网卡多 IP 或者 Global Router
- Kube-proxy 转发模式：iptables

### 新建节点池

以下是通过 [容器服务控制台](https://console.cloud.tencent.com/tke2/cluster) 创建节点池的步骤：
1. 在集群列表中，单击集群 ID，进入集群详情页。
2. 选择左侧菜单栏中的**节点管理**，点击**节点池**进入节点池列表页面。
3. 点击**新建**。
4. 选择**普通节点**。
5. **操作系统**选择**TencentOS 4**或者**Ubuntu 24.04**。
6. **自定义脚本**配置**节点初始化后**执行的脚本（修改 containerd 配置，添加 quay.io 的镜像加速）:
    ```bash
    sed -i '/\[plugins\."io.containerd.grpc.v1.cri"\.registry\.mirrors\]/ a\\ \ \ \ \ \ \ \ [plugins."io.containerd.grpc.v1.cri".registry.mirrors."quay.io"]\n\ \ \ \ \ \ \ \ \ \ endpoint = ["https://quay.tencentcloudcr.com"]' /etc/containerd/config.toml
    systemctl restart containerd
    ```
7. 其余选项根据自身需求自行选择。
8. 点击**创建节点池**。

如果你想通过 terraform 来创建节点池，参考以下片段：
```hcl
resource "tencentcloud_kubernetes_node_pool" "pool" {
  name       = "test"
  cluster_id = tencentcloud_kubernetes_cluster.tke_cluster.id
  node_os    = "img-gqmik24x" # TencentOS 4
  node_config {
    # 自定义脚本：修改 containerd 配置，添加 quay.io 的镜像加速
    user_data = "c2VkIC1pICcvXFtwbHVnaW5zXC4iaW8uY29udGFpbmVyZC5ncnBjLnYxLmNyaSJcLnJlZ2lzdHJ5XC5taXJyb3JzXF0vIGFcXCBcIFwgXCBcIFwgXCBcIFtwbHVnaW5zLiJpby5jb250YWluZXJkLmdycGMudjEuY3JpIi5yZWdpc3RyeS5taXJyb3JzLiJxdWF5LmlvIl1cblwgXCBcIFwgXCBcIFwgXCBcIFwgZW5kcG9pbnQgPSBbImh0dHBzOi8vcXVheS50ZW5jZW50Y2xvdWRjci5jb20iXScgL2V0Yy9jb250YWluZXJkL2NvbmZpZy50b21sCnN5c3RlbWN0bCByZXN0YXJ0IGNvbnRhaW5lcmQK"
  }
}
```

### 使用 helm 安装 cilium
1. 确保添加 cilium 的 helm repo:

```bash
helm repo add cilium https://helm.cilium.io/
```

2. 准备 cilium 部署配置：

```bash
# 获取 apiserver 地址
k8sServiceHost=$(kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}')
# 创建 cilium helm chart 的 values 配置（替换 apiserver 地址）
cat > tke-values.yaml <<EOF
routingMode: "native"
endpointRoutes:
  enabled: true
enableIPv4Masquerade: false # 有 ip-masq-agent 控制 SNAT，cilium 无需参与
cni:
  chainingMode: generic-veth
  chainingTarget: "multus-cni"
ipam:
  mode: "delegated-plugin" # IP 分配由 VPC-CNI 网络插件完成，cilium 无需负责 IP 分配
kubeProxyReplacement: "true" # 需使用 cilium 替代 kube-proxy 才能用到 cilium 完整能力
k8sServiceHost: ${k8sServiceHost} # 关键，替换为 endpoint default/kubernetes 指向的 IP
k8sServicePort: 60002
extraConfig:
  local-router-ipv4: 169.254.32.16
EOF
```

3. 删除 kube-proxy:

```bash
kubectl -n kube-system delete ds kube-proxy
```

4. 执行安装（后续配置更新和升级版本都可复用这个命令）：
```bash
helm upgrade --install --namespace kube-system -f values.yaml --version 1.18.2 cilium cilium/cilium
```

## FAQ

### 如何查看 Cilium 全部的默认安装配置？

Cilium 的 helm 安装包提供了大量的自定义配置项，上面安装步骤只给出了在 TKE 环境中安装 Cilium 的必要配置，实际可根据自身需求调整更多配置。

执行下面的命令可查看所有的安装配置项：

```bash
helm show values cilium/cilium --version 1.18.2
```

### 连不上 cilium 的 helm repo 怎么办？

使用 helm 安装 cilium 时，helm 会从 cilium 的 helm repo 获取 chart 相关信息并下载，如果连不上则会报错。

解决办法是在可以连上的环境下载 chart 压缩包：
```bash
$ helm pull cilium/cilium --version 1.18.2
$ ls cilium-*.tgz
cilium-1.18.2.tgz
```

然后将 chart 压缩包复制到执行 helm 安装的机器上，安装时指定下 chart 压缩包的路径：
```bash
helm upgrade --install --namespace kube-system -f values.yaml --version 1.18.2 cilium ./cilium-1.18.2.tgz
```

## TODO

- Cluster Mesh 多集群安装

## 参考资料

- [Cilium 官方文档: Installation using Helm](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)

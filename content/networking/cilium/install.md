# 安装 Cilium

## 操作场景

本文介绍如何在 TKE 集群中安装 [cilium](https://cilium.io/)。

## 前提条件

- 集群版本：TKE 1.30 及以上，参考 [Cilium Kubernetes Compatibility](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/)。
- 网络模式：VPC-CNI 共享网卡多 IP。
- 节点类型：普通节点或原生节点。
- 操作系统：TencentOS>=4 或 Ubuntu>=22.04。
- kube-proxy: 使用 iptables 转发模式或者卸载 kube-proxy 并使用 cilium 替代。

## 原生路由

Cilium 路由支持两种模式：
1. Encapsulation（封装模式）：即在原有的网络基础上再做一层网络封包进行转发。优点是兼容性好，可适配各种网络环境，缺点是性能较差。
2. Native-Routing（原生路由）：Pod IP 直接在底层网络上进行路由转发，Cilium 不管。优点是性能好，缺点是依赖底层网络对 Pod IP 的路由转发的支持，不通用。

在包括 TKE 在内的云上托管的 Kubernetes 集群中，VPC 底层网络都已支持 Pod IP 的路由转发，无需再走一层 overlay，可获得最佳的网络性能，所以通常使用 Native-Routing 模式安装 cilium，本文介绍的安装方法也是使用 Native-Routing 的模式。

> 更多详情请参考 Cilium 官方文档：[Routing](https://docs.cilium.io/en/stable/network/concepts/routing/)。

## 操作步骤

### 创建 TKE 集群

在 [容器服务控制台](https://console.cloud.tencent.com/tke2/cluster) 创建 TKE 标准集群，注意以下关键选项：
- Kubernetes 版本: 不低于 1.30.0，建议选择最新版。
- 操作系统：**TencentOS 4.0** 及以上或者 **Ubuntu 22.04** 及以上。
- 容器网络插件：VPC-CNI 共享网卡多 IP。
- Kube-proxy 转发模式：iptables。

### 新建节点池

以下是通过 [容器服务控制台](https://console.cloud.tencent.com/tke2/cluster) 创建原生节点池和普通节点池的步骤（根据需求任选一种）：

<Tabs>
  <TabItem value="1" label="新建原生节点池">

  1. 在集群列表中，单击集群 ID，进入集群详情页。
  2. 选择左侧菜单栏中的**节点管理**，点击**节点池**进入节点池列表页面。
  3. 点击**新建**。
  4. 选择 **原生节点**。
  5. 在 **高级设置** 的 Annotations 点击 **新增**：`node.tke.cloud.tencent.com/beta-image=ts4-public`（原生节点默认使用 TencentOS 3.1，与最新版的 cilium 不兼容，通过注解指定原生节点使用 TencentOS 4）。
      ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F09%2F25%2F20250925162022.png)
  6. 在 **高级设置** 的 **Taints** 点击 **新建Taint**: `node.cilium.io/agent-not-ready=true:NoExecute`（让节点上的 cilium 组件 ready 后再调度 pod 上来）。
      ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F09%2F25%2F20250925155023.png)
  7. 在 **高级设置** 的 **自定义脚本** 中，配置 **节点初始化后** 执行的脚本来修改 containerd 配置，添加 `quay.io` 的镜像加速（cilium 的官方容器镜像主要在 `quay.io`，如果你的集群在中国大陆或者节点没有公网，建议配置这个自定义脚本）:
      ```bash
      sed -i '/\[plugins\."io.containerd.grpc.v1.cri"\.registry\.mirrors\]/ a\\ \ \ \ \ \ \ \ [plugins."io.containerd.grpc.v1.cri".registry.mirrors."quay.io"]\n\ \ \ \ \ \ \ \ \ \ endpoint = ["https://quay.tencentcloudcr.com"]' /etc/containerd/config.toml
      systemctl restart containerd
      ```
  8. 其余选项根据自身需求自行选择。
  9. 点击 **创建节点池**。

  如果你想通过 terraform 来创建节点池，参考以下片段：
  ```hcl
  resource "tencentcloud_kubernetes_native_node_pool" "cilium" {
    name       = "cilium"
    cluster_id = tencentcloud_kubernetes_cluster.tke_cluster.id
    type       = "Native"
    annotations { # 添加注解指定原生节点使用 TencentOS 4，以便能够与 cilium 兼容
      name  = "node.tke.cloud.tencent.com/beta-image"
      value = "ts4-public"
    }
    taints { # 添加污点，让节点上的 cilium 组件 ready 后再调度 pod 上来
      key    = "node.cilium.io/agent-not-ready"
      effect = "NoExecute"
      value  = "true"
    }
    native {
      lifecycle {
        # 自定义脚本：修改 containerd 配置，添加 quay.io 的镜像加速
        post_init = "c2VkIC1pICcvXFtwbHVnaW5zXC4iaW8uY29udGFpbmVyZC5ncnBjLnYxLmNyaSJcLnJlZ2lzdHJ5XC5taXJyb3JzXF0vIGFcXCBcIFwgXCBcIFwgXCBcIFtwbHVnaW5zLiJpby5jb250YWluZXJkLmdycGMudjEuY3JpIi5yZWdpc3RyeS5taXJyb3JzLiJxdWF5LmlvIl1cblwgXCBcIFwgXCBcIFwgXCBcIFwgZW5kcG9pbnQgPSBbImh0dHBzOi8vcXVheS50ZW5jZW50Y2xvdWRjci5jb20iXScgL2V0Yy9jb250YWluZXJkL2NvbmZpZy50b21sCnN5c3RlbWN0bCByZXN0YXJ0IGNvbnRhaW5lcmQK"
      }
      # 省略其它必要但不相关配置
    }
  }
  ```

  </TabItem>
  <TabItem value="2" label="新建普通节点池">

  1. 在集群列表中，单击集群 ID，进入集群详情页。
  2. 选择左侧菜单栏中的**节点管理**，点击**节点池**进入节点池列表页面。
  3. 点击**新建**。
  4. 选择 **普通节点**。
  5. **操作系统** 选择 **TencentOS 4**、**Ubuntu 22.04** 或 **Ubuntu 24.04**。
  6. 在 **高级设置** 中 **Taints** 点击 **新建Taint**: `node.cilium.io/agent-not-ready=true:NoExecute`（让节点上的 cilium 组件 ready 后再调度 pod 上来）。
      ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F09%2F25%2F20250925155023.png)
  7. 在 **高级设置** 的 **自定义脚本** 中，配置 **节点初始化后** 执行的脚本来修改 containerd 配置，添加 `quay.io` 的镜像加速（cilium 的官方容器镜像主要在 `quay.io`，如果你的集群在中国大陆或者节点没有公网，建议配置这个自定义脚本）:
      ```bash
      sed -i '/\[plugins\."io.containerd.grpc.v1.cri"\.registry\.mirrors\]/ a\\ \ \ \ \ \ \ \ [plugins."io.containerd.grpc.v1.cri".registry.mirrors."quay.io"]\n\ \ \ \ \ \ \ \ \ \ endpoint = ["https://quay.tencentcloudcr.com"]' /etc/containerd/config.toml
      systemctl restart containerd
      ```
  8. 其余选项根据自身需求自行选择。
  9. 点击**创建节点池**。

  如果你想通过 terraform 来创建节点池，参考以下片段：
  ```hcl
  resource "tencentcloud_kubernetes_node_pool" "cilium" {
    name       = "cilium"
    cluster_id = tencentcloud_kubernetes_cluster.tke_cluster.id
    node_os    = "img-gqmik24x" # TencentOS 4 的镜像 ID
    taints { # 添加 taint，让节点上的 cilium 组件 ready 后再调度 pod 上来
      key    = "node.cilium.io/agent-not-ready"
      effect = "NoExecute"
      value  = "true"
    }
    node_config {
      # 自定义脚本：修改 containerd 配置，添加 quay.io 的镜像加速
      user_data = "c2VkIC1pICcvXFtwbHVnaW5zXC4iaW8uY29udGFpbmVyZC5ncnBjLnYxLmNyaSJcLnJlZ2lzdHJ5XC5taXJyb3JzXF0vIGFcXCBcIFwgXCBcIFwgXCBcIFtwbHVnaW5zLiJpby5jb250YWluZXJkLmdycGMudjEuY3JpIi5yZWdpc3RyeS5taXJyb3JzLiJxdWF5LmlvIl1cblwgXCBcIFwgXCBcIFwgXCBcIFwgZW5kcG9pbnQgPSBbImh0dHBzOi8vcXVheS50ZW5jZW50Y2xvdWRjci5jb20iXScgL2V0Yy9jb250YWluZXJkL2NvbmZpZy50b21sCnN5c3RlbWN0bCByZXN0YXJ0IGNvbnRhaW5lcmQK"
      # 省略其它必要但不相关配置
    }
  }
  ```

  </TabItem>
</Tabs>

### 安装 cilium
1. 确保 [helm](https://helm.sh/zh/docs/intro/install/) 和 [kubectl](https://kubernetes.io/zh-cn/docs/tasks/tools/install-kubectl-linux/) 已安装，并配置好可以连接集群的 kubeconfig（参考 [连接集群](https://cloud.tencent.com/document/product/457/32191#a334f679-7491-4e40-9981-00ae111a9094)）。
2. 添加 cilium 的 helm repo:

```bash
helm repo add cilium https://helm.cilium.io/
```

3. 安装 cilium（有两种方式，取决于是否需要保留 kube-proxy，推荐不保留，使用 cilium 完全替代 kube-proxy，可减少整体的资源开销并获得更好的 Service 转发性能）：

<Tabs>
  <TabItem value="1" label="完全替代 kube-proxy">

  先卸载 kube-proxy（保险起见，通过加 nodeSelector 方式让 kube-proxy 不部署到任何节点，避免后续升级集群时 kube-proxy 又被重新创建回来）：

  ```bash
  kubectl -n kube-system patch ds kube-proxy -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
  ```

  然后使用 helm 安装 cilium:

  ```bash
  helm install cilium cilium/cilium --version 1.18.2 \
    --namespace kube-system \
    --set routingMode=native \
    --set endpointRoutes.enabled=true \
    --set enableIPv4Masquerade=false \
    --set cni.chainingMode=generic-veth \
    --set cni.chainingTarget=multus-cni \
    --set ipamd.mode=delegated-plugin \
    --set kubeProxyReplacement=true \
    --set k8sServiceHost=$(kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}') \
    --set k8sServicePort=60002 \
    --set extraConfig.local-router-ipv4=169.254.32.16
  ```

  :::info[注意]
  
  如果 kube-proxy 是 ipvs 模式，且集群中有节点存在，需重启所有节点来清理下 kube-proxy 相关规则，否则可能出现 Service 无法访问的情况。
  
  :::

  </TabItem>

  <TabItem value="2" label="与 kube-proxy 共存">

  确保 kube-proxy 使用的是 iptables 转发模式，然后使用 helm 安装 cilium：

  ```bash
  helm install cilium cilium/cilium --version 1.18.2 \
    --namespace kube-system \
    --set routingMode=native \
    --set endpointRoutes.enabled=true \
    --set enableIPv4Masquerade=false \
    --set cni.chainingMode=generic-veth \
    --set cni.chainingTarget=multus-cni \
    --set ipamd.mode=delegated-plugin \
    --set extraConfig.local-router-ipv4=169.254.32.16
  ```

  > cilium 与 kube-proxy ipvs 模式不兼容，在 TKE 环境无法与 cilium 共存，详细请参考常见问题中的解释。

  </TabItem>
</Tabs>

## 常见问题

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

### 为什么不能与 kube-proxy ipvs 共存？

cilium 与 kube-proxy ipvs 模式不兼容，详见[这个issue](https://github.com/cilium/cilium/issues/18610)。

在 TKE 环境的具体表现是访问 service 不通。

具体底层细节正在研究中。

### 如何修改 cilium 安装配置或升级？

安装时，建议将所有安装配置写到 `values.yaml` 中，如：

```yaml showLineNumbers title="values.yaml"
routingMode: "native"
endpointRoutes:
  enabled: true
enableIPv4Masquerade: false
cni:
  chainingMode: generic-veth
  chainingTarget: multus-cni
ipam:
  mode: delegated-plugin
kubeProxyReplacement: true
k8sServiceHost: 169.254.128.27 # 注意替换为实际的 apiserver 地址，获取方法：kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}'
k8sServicePort: 60002
extraConfig:
  local-router-ipv4: 169.254.32.16
```

安装和更新配置，都通过执行下面的命令来完成：

```bash
helm upgrade --install --namespace kube-system -f values.yaml --version 1.18.2 cilium cilium/cilium
```

> 修改配置通过修改 `values.yaml` 文件来完成，完整配置项通过 `helm show values cilium/cilium --version 1.18.2` 查看。

如果是升级版本，替换 `--version` 的值即可：

```bash
helm upgrade --install --namespace kube-system -f values.yaml --version 1.18.3 cilium cilium/cilium
```

### Global Router 网络模式的集群能否安装？

测试结论是：不能。

应该是 cilium 不支持 bridge CNI 插件（Global Router 网络插件基于 bridge CNI 插件），相关 issue:
- [CFP: eBPF with bridge mode](https://github.com/cilium/cilium/issues/35011)
- [CFP: cilium CNI chaining can support cni-bridge](https://github.com/cilium/cilium/issues/20336)

### 能否勾选 DataPlaneV2？

结论是：不能。

选择 VPC-CNI 网络插件时，有个 DataPlaneV2 选项：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F09%2F26%2F20250926092351.png)

勾选后，会部署 cilium 组件到集群中（替代 kube-proxy 组件），如果再自己安装 cilium 会造成冲突，而且 DataPlaneV2 所使用的 OS 与 cilium 最新版也不兼容，所以不能勾选此选项。

## 参考资料

- [Cilium 官方文档: Installation using Helm](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)

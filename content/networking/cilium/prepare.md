# 集群准备

本文介绍如何创建一个满足 cilium 安装条件的 TKE 集群。

## 前提条件

如果要在 TKE 集群中安装 cilium，需满足以下前提条件：
- 集群版本：TKE 1.30 及以上，参考 [Cilium Kubernetes Compatibility](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/)。
- 网络模式：VPC-CNI 共享网卡多 IP。
- 节点类型：普通节点或原生节点。
- 操作系统：TencentOS>=4 或 Ubuntu>=22.04。

## 创建 TKE 集群

在 [容器服务控制台](https://console.cloud.tencent.com/tke2/cluster) 创建 TKE 标准集群，注意以下关键选项：
- Kubernetes 版本: 不低于 1.30.0，建议选择最新版。
- 操作系统：**TencentOS 4.0** 及以上或者 **Ubuntu 22.04** 及以上。
- 容器网络插件：VPC-CNI 共享网卡多 IP。

## 新建节点池

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


# 安装 cilium

本文介绍如何在 TKE 集群中安装 cilium。

## 准备 TKE 集群

安装 cilium 是对集群一个很重大的变更，不建议在有生产业务运行的集群中安装，否则安装过程中可能会影响线上业务的正常运行，建议在新创建的 TKE 集群中安装 cilium。

在 [容器服务控制台](https://console.cloud.tencent.com/tke2/cluster) 创建 TKE 集群，注意以下关键选项：
- 集群类型：标准集群
- Kubernetes 版本: 不低于 1.30.0，建议选择最新版。
- 操作系统：**TencentOS 4.0** 及以上或者 **Ubuntu 22.04** 及以上。
- 容器网络插件：VPC-CNI 共享网卡多 IP。
- 节点：建议不添加任何节点，避免清理存量节点相关配置。
- 基础组件：取消勾选 ip-masq-agent，避免冲突。
- 增强组件：如果希望在安装 cilium 后还能让节点按需自动扩缩容，要用 karpenter 节点池来管理节点，需勾选安装 karpenter 组件，否则无需勾选。

集群创建成功后，需开启集群访问来暴露集群的 apiserver 提供后续使用 helm 安装 cilium 时，helm 命令能正常操作 TKE 集群，参考 [开启集群访问的方法](https://cloud.tencent.com/document/product/457/32191#.E6.93.8D.E4.BD.9C.E6.AD.A5.E9.AA.A4)。

根据自身情况，选择开启内网访问还是公网访问，主要取决于 helm 命令所在环境的网络是否与 TKE 集群所在 VPC 互通：
1. 如果可以互通就开启内网访问。
2. 如果不能互通就开启公网访问。当前开启公网访问需要向集群下发 `kubernetes-proxy` 组件作为中转，依赖集群中需要有节点存在（未来可能会取消该依赖，但当前现状是需要依赖），如果要使用公网访问方式，建议向集群先添加个超级节点，以便 `kubernetes-proxy` 的 pod 能够正常调度，等 cilium 安装完成后，再删除该超级节点。

## 准备 helm 环境

1. 确保 [helm](https://helm.sh/zh/docs/intro/install/) 和 [kubectl](https://kubernetes.io/zh-cn/docs/tasks/tools/install-kubectl-linux/) 已安装，并配置好可以连接集群的 kubeconfig（参考 [连接集群](https://cloud.tencent.com/document/product/457/32191#a334f679-7491-4e40-9981-00ae111a9094)）。
2. 添加 cilium 的 helm repo:
```bash
helm repo add cilium https://helm.cilium.io/
```

## 安装 cilium

### 添加容忍

1. 为 tke-eni-ipamd 增加 cilium 污点的容忍：
```bash
kubectl -n kube-system patch deployment tke-eni-ipamd --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/tolerations/-",
    "value": {
      "key": "node.cilium.io/agent-not-ready",
      "operator": "Exists"
    }
  }
]'
```

:::tip[说明]

tke-eni-ipamd 是 TKE VPC-CNI 网络中的关键组件，负责 Pod IP 的分配，使用 HostNetwork，不依赖 cilium-agent 的启动，所以可以加 cilium 污点的容忍。

:::

2. (可选) 如果你将 cilium 依赖镜像同步到了 TCR 私有镜像仓库，且安装了 TCR 扩展组件实现免密拉取 TCR 私有镜像，也需要为这个组件增加 cilium 污点的容忍（避免拉取 cilium 组件镜像和启动 TCR 组件形成循环依赖）：

```bash
kubectl -n tcr-assistant-system patch deployment tcr-assistant-controller-manager --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/tolerations",
    "value": [{
      "key": "node.cilium.io/agent-not-ready",
      "operator": "Exists"
    }]
  }
]'
```


### 配置 CNI

为 cilium 准备 CNI 配置的 ConfigMap `cni-configuration.yaml`：

```yaml title="cni-configuration.yaml"
apiVersion: v1
kind: ConfigMap
metadata:
  name: cni-configuration
  namespace: kube-system
data:
  cni-config: |-
    {
      "cniVersion": "0.3.1",
      "name": "generic-veth",
      "plugins": [
        {
          "type": "tke-route-eni",
          "routeTable": 1,
          "disableIPv6": true,
          "mtu": 1500,
          "ipam": {
            "type": "tke-eni-ipamc",
            "backend": "127.0.0.1:61677"
          }
        },
        {
          "type": "cilium-cni",
          "chaining-mode": "generic-veth"
        }
      ]
    }
```

创建 CNI ConfigMap:

```bash
kubectl apply -f cni-configuration.yaml
```

### 使用 helm 安装 cilium

使用 helm 执行安装：

:::info[注意]

`k8sServiceHost` 是 apiserver 地址，通过命令动态获取。

:::

```bash
helm upgrade --install cilium cilium/cilium --version 1.18.2 \
  --namespace kube-system \
  --set routingMode=native \
  --set endpointRoutes.enabled=true \
  --set enableIPv4Masquerade=false \
  --set ipam.mode=delegated-plugin \
  --set cni.chainingMode=generic-veth \
  --set cni.exclusive=false \
  --set cni.customConf=true \
  --set cni.configMap=cni-configuration \
  --set cni.externalRouting=true \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=$(kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}') \
  --set k8sServicePort=60002 \
  --set extraArgs="{--devices=eth+}" \
  --set extraConfig.local-router-ipv4=169.254.32.16
```

:::tip[说明]

以下是是包含各参数解释的 `values.yaml`:

```yaml showLineNumbers title="values.yaml"
# 使用 native routing，Pod 直接使用 VPC IP 路由，无需 overlay，参考 native routing: https://docs.cilium.io/en/stable/network/concepts/routing/#native-routing
routingMode: "native" 
endpointRoutes:
  # 使用 native routing，此选项必须置为 true。表示转发 Pod 流量时，直接路由到 veth 设备而不需要经过 cilium_host 网卡
  enabled: true 
ipam:
  # TKE Pod IP 分配由 tke-eni-ipamd 组件负责，cilium 无需负责 Pod IP 分配
  mode: "delegated-plugin"
# 使用 VPC-CNI 无需 IP 伪装
enableIPv4Masquerade: false
cni:
  # 使用 generic-veth 与 VPC-CNI 做 CNI Chaining，参考：https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/
  chainingMode: generic-veth
  # 不让 cilium 管理整个 CNI 配置目录，避免干扰其它 CNI 配置，有更高的灵活性，比如与 istio 集成：https://docs.cilium.io/en/latest/network/servicemesh/istio/
  exclusive: false
  # CNI 配置完全自定义
  customConf: true
  # 存放 CNI 配置的 ConfigMap 名称
  configMap: cni-configuration
  # VPC-CNI 会自动配置 Pod 路由，cilium 不需要配置
  externalRouting: true
# 替代 kube-proxy，包括 ClusterIP 转发、NodePort 转发，另外还附带了 HostPort 转发的能力
kubeProxyReplacement: "true"
# 注意替换为实际的 apiserver 地址，获取方法：kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}'
k8sServiceHost: 169.254.128.112 
k8sServicePort: 60002
extraConfig:
  # cilium 不负责 Pod IP 分配，需手动指定一个不会有冲突的 IP 地址，作为每个节点上 cilium_host 虚拟网卡的 IP 地址
  local-router-ipv4: 169.254.32.16
extraArgs:
- --devices=eth+ # TKE 节点中 eth 开头的网卡都可能出入流量，需标识为外部网卡，让 cilium ebpf 程序挂上去，否则可能导致部分场景下网络不通（如跨节点访问 HostPort）
```

生产环境部署建议将参数保存到 `values.yaml`，然后在安装或更新时，都可以执行下面的命令（如果要升级版本，替换 `--version` 即可）：

```bash
helm upgrade --install cilium cilium/cilium --version 1.18.2 --namespace=kube-system -f values.yaml
```

:::

确保 cilium 相关 pod 正常运行：

```bash
$ kubectl --namespace=kube-system get pod -l app.kubernetes.io/part-of=cilium
NAME                              READY   STATUS    RESTARTS   AGE
cilium-5rfrk                      1/1     Running   0          1m
cilium-9mntb                      1/1     Running   0          1m
cilium-envoy-4r4x9                1/1     Running   0          1m
cilium-envoy-kl5cz                1/1     Running   0          1m
cilium-envoy-sgl5v                1/1     Running   0          1m
cilium-operator-896cdbf88-jlgt7   1/1     Running   0          1m
cilium-operator-896cdbf88-nj6jc   1/1     Running   0          1m
cilium-zrxwn                      1/1     Running   0          1m
```

### 卸载 TKE 组件

通过 kubectl patch 来清理 tke-cni-agent 和 kube-proxy 所有 pod：

```bash
kubectl -n kube-system patch daemonset kube-proxy -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
kubectl -n kube-system patch daemonset tke-cni-agent -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
```

:::tip[说明]

1. 通过加 nodeSelector 方式让 daemonset 不部署到任何节点，等同于卸载，同时也留个退路。
2. 如果 Pod 使用 VPC-CNI 网络，可以不需要 tke-cni-agent，卸载以避免 CNI 配置文件冲突。
3. 前面提到过安装 cilium 之前不建议添加节点，如果因某些原因导致在安装 cilium 前添加了普通节点或原生节点，可以在执行卸载操作前为 tke-cni-agent 增加 preStop，用于清理存量节点的 CNI 配置:

```bash
kubectl -n kube-system patch daemonset tke-cni-agent --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/lifecycle",
    "value": {
      "preStop": {
        "exec": {
          "command": ["rm", "/host/etc/cni/net.d/00-multus.conf"]
        }
      }
    }
  }
]'
kubectl -n kube-system rollout status daemonset/tke-cni-agent --watch # 等待存量节点的 tke-cni-agent pod 更新完成，确保 preStop 全部成功加上
```

:::

如果创建集群时没有取消勾选 ip-masq-agent，可以卸载下：

```bash
kubectl -n kube-system patch daemonset ip-masq-agent -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
```

## 新建节点池

### 节点池选型

以下三种节点池类型能够适配 cilium:
- 普通节点池：基于 CVM 和 cluster-autoscaler (CA)，优点是 OS 镜像比较灵活，缺点是安装 cilium 后无法自动扩容节点。
- 原生节点池：基于原生节点和 cluster-autoscaler，优点是功能丰富，也是 TKE 推荐的节点类型（参考 [原生节点 VS 普通节点](https://cloud.tencent.com/document/product/457/78197#.E5.8E.9F.E7.94.9F.E8.8A.82.E7.82.B9-vs-.E6.99.AE.E9.80.9A.E8.8A.82.E7.82.B9)），缺点是 OS 只支持 TencentOS，且安装 cilium 后无法自动扩容节点。
- karpenter 节点池：基于原生节点和 karpenter，优点是安装 cilium 后可以支持自动扩容节点，缺点是 OS 只支持 TencentOS。


| 节点池类型       | 节点类型        | 可用 OS 镜像                | 自动扩容                          |
| ---------------- | --------------- | --------------------------- | --------------------------------- |
| 普通节点池       | 普通节点（CVM） | Ubuntu/TencentOS/自定义镜像 | ❌ (CA 不支持 startup taint)      |
| 原生节点池       | 原生节点        | TencentOS                   | ❌ (CA 不支持 startup taint)      |
| karpenter 节点池 | 原生节点        | TencentOS                   | ✅ (karpenter 支持 startup taint) |


可根据自身情况评估选择合适的节点池类型，以下是选型建议：
1. 如果需要节点自动扩容，只能使用 karpenter 节点池。
2. 如果希望使用 TencentOS 之外的操作系统，使用普通节点池。
3. 其余情况，优先使用原生节点池。

以下创建各种节点池的步骤。

### 新建 karpenter 节点池

在新建 karpenter 节点池之前，确保 karpenter 组件已启用，参考 [tke-karpenter 说明](https://cloud.tencent.com/document/product/457/111805)。

准备用于配置 karpenter 节点池的 `node-pool.yaml`，以下是示例:

```yaml title="node-pool.yaml"
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 5m
    budgets:
    - nodes: 10%
  template:
    metadata:
      annotations:
        # 原生节点默认安装 TencentOS 3，与最新 cilium 版本不兼容，指定该注解安装 TencentOS 4（未来原生节点会默认安装 TencentOS 4，但当前还不是，需要用这个注解指定下）
        beta.karpenter.k8s.tke.machine.spec/annotations: node.tke.cloud.tencent.com/beta-image=ts4-public 
    spec:
      requirements:
      - key: kubernetes.io/arch
        operator: In
        values: ["amd64"]
      - key: kubernetes.io/os
        operator: In
        values: ["linux"]
      - key: karpenter.k8s.tke/instance-family
        operator: In
        values: ["S5", "SA2"] # 指定期望的机型
      - key: karpenter.sh/capacity-type
        operator: In
        values: ["on-demand"]
      - key: "karpenter.k8s.tke/instance-cpu"
        operator: Gt
        values: ["1"] # 指定扩容时最小的 CPU 核数
      nodeClassRef:
        group: karpenter.k8s.tke
        kind: TKEMachineNodeClass
        name: default # 引用 TKEMachineNodeClass
  limits:
    cpu: 10

---
apiVersion: karpenter.k8s.tke/v1beta1
kind: TKEMachineNodeClass
metadata:
  name: default
  annotations:
    kubernetes.io/description: "General purpose TKEMachineNodeClass"
spec:
  subnetSelectorTerms: # 节点所属 VPC 子网
  - id: subnet-12sxk3z4
  - id: subnet-b8qyi2dk
  securityGroupSelectorTerms: # 节点绑定的安全组
  - id: sg-nok01xpa
  sshKeySelectorTerms: # 节点绑定的 ssh 密钥
  - id: skey-3t01mlvf
```

创建 karpenter 节点池：

```bash
kubectl apply -f node-pool.yaml
```

### 新建原生节点池

1. 在集群列表中，单击集群 ID，进入集群详情页。
2. 选择左侧菜单栏中的**节点管理**，点击**节点池**进入节点池列表页面。
3. 点击**新建**。
4. 选择 **原生节点**。
5. 在 **高级设置** 的 Annotations 点击 **新增**：`node.tke.cloud.tencent.com/beta-image=ts4-public`（原生节点默认使用 TencentOS 3.1，与最新版的 cilium 不兼容，通过注解指定原生节点使用 TencentOS 4）。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F09%2F25%2F20250925162022.png)
6. 在 **高级设置** 的 **Taints** 点击 **新建Taint**: `node.cilium.io/agent-not-ready=true:NoExecute`（让节点上的 cilium 组件 ready 后再调度 pod 上来）。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F09%2F25%2F20250925155023.png)
7. 在 **高级设置** 的 **自定义脚本** 中，配置 **节点初始化后** 执行的脚本来修改 containerd 配置，添加 `quay.io` 的镜像加速（cilium 的官方容器镜像主要在 `quay.io`，如果你的集群在中国大陆或者节点没有公网，可以配置这个自定义脚本）:
    ```bash
    sed -i '/\[plugins\."io.containerd.grpc.v1.cri"\.registry\.mirrors\]/ a\\ \ \ \ \ \ \ \ [plugins."io.containerd.grpc.v1.cri".registry.mirrors."quay.io"]\n\ \ \ \ \ \ \ \ \ \ endpoint = ["https://quay.tencentcloudcr.com"]' /etc/containerd/config.toml
    systemctl restart containerd
    ```
    :::tip[说明]
    
    1. 如果计划将 cilium 依赖镜像同步到自己的镜像仓库来使用（如 TCR 镜像仓库），可以忽略该步骤。
    2. 如果集群不在中国大陆，且节点都可以访问公网，也可以忽略该步骤。
    
    :::
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
### 新建普通节点池

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

## 常见问题

### 如何查看 Cilium 全部的默认安装配置？

Cilium 的 helm 安装包提供了大量的自定义配置项，上面安装步骤只给出了在 TKE 环境中安装 Cilium 的必要配置，实际可根据自身需求调整更多配置。

执行下面的命令可查看所有的安装配置项：

```bash
helm show values cilium/cilium --version 1.18.2
```

### 为什么要加 local-router-ipv4 配置？

cilium 会在每台节点上创建 `cilium_host` 虚拟网卡，并需要配置一个 IP 地址，由于我们要让 cilium 与 TKE VPC-CNI 网络插件共存，IP 分配需要由 TKE VPC-CNI 插件来完成，cilium 就不负责 IP 分配了，所以需要我们通过 `local-router-ipv4` 参数来手动指定一个不会有冲突的 IP 地址，而 `169.254.32.16` 这个 IP 地址在 TKE 上不会与其它 IP 冲突，所以就指定这个 IP 地址。

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

### 大规模场景如何优化？

如果集群规模较大，建议开启 [CiliumEndpointSlice](https://docs.cilium.io/en/stable/network/kubernetes/ciliumendpointslice/) 特性，该特性于  1.11 开始引入，当前（1.18.2）仍在 Beta 阶段（详见 [CiliumEndpointSlice Graduation to Stable](https://github.com/cilium/cilium/issues/31904)），在大规模场景下，该特性可以显著提升 cilium 性能并降低 apiserver 的压力。

默认没有启用，启用方法是在使用 helm 安装 cilium 时，通过加 `--set ciliumEndpointSlice.enabled=true` 参数来开启。

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

### Pod 如何出公网？

## 参考资料

- [Installation using Helm](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)
- [Generic Veth Chaining](https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/)
- [Kubernetes Without kube-proxy](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)

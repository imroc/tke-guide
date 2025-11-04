# 安装 cilium

本文介绍如何在 TKE 集群中安装 cilium。

## 前期准备

### 准备 TKE 集群

:::info[注意]

安装 cilium 是对集群一个很重大的变更，不建议在有生产业务运行的集群中安装，否则安装过程中可能会影响线上业务的正常运行，建议在新创建的 TKE 集群中安装 cilium。

:::

在 [容器服务控制台](https://console.cloud.tencent.com/tke2/cluster) 创建 TKE 集群，注意以下关键选项：
- 集群类型：标准集群
- Kubernetes 版本: 不低于 1.30.0，建议选择最新版（参考 [Cilium Kubernetes Compatibility](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/)）。
- 操作系统：TencentOS 4 或者 Ubuntu >= 22.04。
- 容器网络插件：VPC-CNI 共享网卡多 IP。
- 节点：安装前不要向集群添加任何普通节点或原生节点，避免残留相关规则和配置，等安装完成后再添加。
- 基础组件：取消勾选 ip-masq-agent，避免冲突。
- 增强组件：如果希望在安装 cilium 后还能让节点按需自动扩缩容，要用 Karpenter 节点池来管理节点，需勾选安装 Karpenter 组件，否则无需勾选。

集群创建成功后，需开启集群访问来暴露集群的 apiserver 提供后续使用 helm 安装 cilium 时，helm 命令能正常操作 TKE 集群，参考 [开启集群访问的方法](https://cloud.tencent.com/document/product/457/32191#.E6.93.8D.E4.BD.9C.E6.AD.A5.E9.AA.A4)。

根据自身情况，选择开启内网访问还是公网访问，主要取决于 helm 命令所在环境的网络是否与 TKE 集群所在 VPC 互通：
1. 如果可以互通就开启内网访问。
2. 如果不能互通就开启公网访问。当前开启公网访问需要向集群下发 `kubernetes-proxy` 组件作为中转，依赖集群中需要有节点存在（未来可能会取消该依赖，但当前现状是需要依赖），如果要使用公网访问方式，建议向集群先添加个超级节点，以便 `kubernetes-proxy` 的 pod 能够正常调度，等 cilium 安装完成后，再删除该超级节点。

如果使用 terraform 创建集群，参考以下代码片段：

```hcl
resource "tencentcloud_kubernetes_cluster" "tke_cluster" {
  # 标准集群
  cluster_deploy_type = "MANAGED_CLUSTER"
  # Kubernetes 版本 >= 1.30.0
  cluster_version = "1.32.2"
  # 操作系统， TencentOS 4 的镜像 ID，当前使用该镜像还需要提工单申请
  cluster_os = "img-gqmik24x" 
  # 容器网络插件: VPC-CNI
  network_type = "VPC-CNI"
  # 集群 APIServer 开启访问
  cluster_internet = true
  # 通过内网 CLB 暴露 APIServer，需指定 CLB 所在子网 ID
  cluster_intranet_subnet_id = "subnet-xxx" 
  # 不安装 ip-masq-agent （disable_addons 要求 tencentcloud provider 版本 1.82.33+）
  disable_addons = ["ip-masq-agent"]
  # 省略其它必要但不相关配置
}
```

### 准备 helm 环境

1. 确保 [helm](https://helm.sh/zh/docs/intro/install/) 和 [kubectl](https://kubernetes.io/zh-cn/docs/tasks/tools/install-kubectl-linux/) 已安装，并配置好可以连接集群的 kubeconfig（参考 [连接集群](https://cloud.tencent.com/document/product/457/32191#a334f679-7491-4e40-9981-00ae111a9094)）。
2. 添加 cilium 的 helm repo:
    ```bash
    helm repo add cilium https://helm.cilium.io/
    ```

## 安装 cilium

### 升级 tke-eni-agent

由于 cilium 固定使用了 2004 和 2005 两个路由表 ID，可能会与 TKE 的 VPC-CNI 网络模式所使用的路由表 ID 冲突，新版 VPC-CNI 网络模式将会调整路由表 ID 生成的算法，避免与 cilium 的路由表 ID 冲突，但目前还没正式发版（v3.8.0 版本），所以这里可以先手动升级镜像版本到 v3.8.0 的 rc 版。

通过以下脚本升级 tke-eni-agent 镜像版本：

:::info[注意]

等 eniipamd 组件正式发布 v3.8.0 后，可以在组件管理中操作升级 eniipamd。

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F10%2F31%2F20251031120006.png)

:::

<Tabs>
  <TabItem value="1" label="bash">

   ```bash
   # 获取当前镜像
   CURRENT_IMAGE=$(kubectl get daemonset tke-eni-agent -n kube-system \
     -o jsonpath='{.spec.template.spec.containers[0].image}')

   # 构造新镜像名称（保留仓库路径，替换 tag）
   REPOSITORY=${CURRENT_IMAGE%%:*}
   NEW_IMAGE="${REPOSITORY}:v3.8.0-rc.0"

   # 升级 tke-eni-agent 镜像
   kubectl patch daemonset tke-eni-agent -n kube-system \
     --type='json' \
     -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "'"${NEW_IMAGE}"'"}]'
   ```

  </TabItem>
  <TabItem value="2" label="fish">

   ```bash
   # 获取当前镜像
   set -l current_image (kubectl get daemonset tke-eni-agent -n kube-system \
     -o jsonpath="{.spec.template.spec.containers[0].image}")
   
   # 提取仓库路径（去除标签部分）
   set -l repository (echo $current_image | awk -F: '{print $1}')
   
   # 构造新镜像名称
   set -l new_image "$repository:v3.8.0-rc.0"
   
   # 升级 tke-eni-agent 镜像
   kubectl patch daemonset tke-eni-agent -n kube-system \
     --type='json' \
     -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "'$new_image'"}]'   
   ```

  </TabItem>
</Tabs>


### 配置 CNI

为 cilium 准备 CNI 配置的 ConfigMap `cni-config.yaml`：

```yaml title="cni-config.yaml"
apiVersion: v1
kind: ConfigMap
metadata:
  name: cni-config
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
kubectl apply -f cni-config.yaml
```

### 使用 helm 安装 cilium

使用 helm 执行安装：

:::info[注意]

`k8sServiceHost` 是 apiserver 地址，通过命令动态获取。

:::

```bash
helm upgrade --install cilium cilium/cilium --version 1.18.3 \
  --namespace kube-system \
  --set image.repository=quay.tencentcloudcr.com/cilium/cilium \
  --set envoy.image.repository=quay.tencentcloudcr.com/cilium/cilium-envoy \
  --set operator.image.repository=quay.tencentcloudcr.com/cilium/operator \
  --set routingMode=native \
  --set endpointRoutes.enabled=true \
  --set ipam.mode=delegated-plugin \
  --set enableIPv4Masquerade=false \
  --set devices=eth+ \
  --set cni.chainingMode=generic-veth \
  --set cni.customConf=true \
  --set cni.configMap=cni-config \
  --set cni.externalRouting=true \
  --set extraConfig.local-router-ipv4=169.254.32.16 \
  --set operator.tolerations[0].key="node-role.kubernetes.io/control-plane",operator.tolerations[0].operator="Exists" \
  --set operator.tolerations[1].key="node-role.kubernetes.io/master",operator.tolerations[1].operator="Exists" \
  --set operator.tolerations[2].key="node.kubernetes.io/not-ready",operator.tolerations[2].operator="Exists" \
  --set operator.tolerations[3].key="node.cloudprovider.kubernetes.io/uninitialized",operator.tolerations[3].operator="Exists" \
  --set operator.tolerations[4].key="tke.cloud.tencent.com/uninitialized",operator.tolerations[4].operator="Exists" \
  --set operator.tolerations[5].key="tke.cloud.tencent.com/eni-ip-unavailable",operator.tolerations[5].operator="Exists" \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=$(kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}') \
  --set k8sServicePort=60002
```

:::tip[说明]

以下是是包含各参数解释的 `values.yaml`:

```yaml showLineNumbers title="values.yaml"
# 替换 cilium, cilium-envoy 和 cilium-operator 的镜像为 TKE 上可以直接拉取到的 mirror 仓库地址
image:
  repository: quay.tencentcloudcr.com/cilium/cilium
envoy:
  image:
    repository: quay.tencentcloudcr.com/cilium/cilium-envoy
operator:
  image:
    repository: quay.tencentcloudcr.com/cilium/operator
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
# TKE 节点中 eth 开头的网卡都可能出入流量（Pod 流量走辅助网卡，eth1, eth2 ...），用这个参数让所有 eth 开头的网卡都挂载 cilium ebpf 程序，
# 以便让报文能够根据 conntrack 被正常反向 nat， 否则可能导致部分场景下网络不通（如跨节点访问 HostPort）
devices: eth+
cni:
  # 使用 generic-veth 与 VPC-CNI 做 CNI Chaining，参考：https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/
  chainingMode: generic-veth
  # CNI 配置完全自定义
  customConf: true
  # 存放 CNI 配置的 ConfigMap 名称
  configMap: cni-configuration
  # VPC-CNI 会自动配置 Pod 路由，cilium 不需要配置
  externalRouting: true
operator:
  tolerations:
  - key: "node-role.kubernetes.io/control-plane"
    operator: Exists
  - key: "node-role.kubernetes.io/master"
    operator: Exists
  - key: "node.kubernetes.io/not-ready"
    operator: Exists
  - key: "node.cloudprovider.kubernetes.io/uninitialized"
    operator: Exists
  # 容忍 TKE 的污点，避免循环依赖
  - key: tke.cloud.tencent.com/uninitialized 
    operator: Exists
  - key: tke.cloud.tencent.com/eni-ip-unavailable 
    operator: Exists
extraConfig:
  # cilium 不负责 Pod IP 分配，需手动指定一个不会有冲突的 IP 地址，作为每个节点上 cilium_host 虚拟网卡的 IP 地址
  local-router-ipv4: 169.254.32.16
# 替代 kube-proxy，包括 ClusterIP 转发、NodePort 转发，另外还附带了 HostPort 转发的能力
kubeProxyReplacement: "true"
# 注意替换为实际的 apiserver 地址，获取方法：kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}'
k8sServiceHost: 169.254.128.112 
k8sServicePort: 60002
```

生产环境部署建议将参数保存到 `values.yaml`，然后在安装或更新时，都可以执行下面的命令（如果要升级版本，替换 `--version` 即可）：

```bash
helm upgrade --install cilium cilium/cilium --version 1.18.3 \
  --namespace=kube-system \
  -f values.yaml
```

如果自定义的配置较多，建议拆成多个 yaml 文件维护，比如替换镜像地址的配置放到 `image-values.yaml`，用于启用 Egress Gateway 的配置放到 `egress-values.yaml`，配置容器 request 与 limit 的放到 `resources-values.yaml`，更新配置时通过加多个 `-f` 参数来合并多个 yaml 文件：

```bash
helm upgrade --install cilium cilium/cilium --version 1.18.3 \
  --namespace=kube-system \
  -f values.yaml \
  -f image-values.yaml \
  -f egress-values.yaml \
  -f resources-values.yaml
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

1. 通过加 nodeSelector 方式让 daemonset 不部署到任何节点，等同于卸载，同时也留个退路；当前 kube-proxy 也只能通过这种方式卸载，如果直接删除 kube-proxy，后续集群升级会被阻塞。
3. 如果 Pod 使用 VPC-CNI 网络，可以不需要 tke-cni-agent，卸载以避免 CNI 配置文件冲突。
4. 前面提到过安装 cilium 之前不建议添加节点，如果因某些原因导致在安装 cilium 前添加了普通节点或原生节点，又不希望在安装 cilium 重启存量节点，那可以在执行卸载操作前为 tke-cni-agent 增加 preStop，用于清理存量节点的 CNI 配置:

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
- 原生节点池：基于原生节点，原生节点功能很丰富，也是 TKE 推荐的节点类型（参考 [原生节点 VS 普通节点](https://cloud.tencent.com/document/product/457/78197#.E5.8E.9F.E7.94.9F.E8.8A.82.E7.82.B9-vs-.E6.99.AE.E9.80.9A.E8.8A.82.E7.82.B9)），OS 固定使用 TencentOS。
- 普通节点池：基于普通节点（CVM），OS 镜像比较灵活。
- Karpenter 节点池：与原生节点池类似，基于原生节点，OS 固定使用 TencentOS，只是节点管理使用的功能更强大的 [Karpenter](https://karpenter.sh/) 而非普通节点池与原生节点池所使用的 [cluster-autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler) (CA)。

以下是这几种节点池的对比，根据自身情况选择合适的节点池类型：

| 节点池类型       | 节点类型        | 可用 OS 镜像                | 节点扩缩容组件     |
| ---------------- | --------------- | --------------------------- | ------------------ |
| 原生节点池       | 原生节点        | TencentOS                   | cluster-autoscaler |
| 普通节点池       | 普通节点（CVM） | Ubuntu/TencentOS/自定义镜像 | cluster-autoscaler |
| Karpenter 节点池 | 原生节点        | TencentOS                   | Karpenter          |


以下创建各种节点池的步骤。

### 新建 Karpenter 节点池

在新建 Karpenter 节点池之前，确保 Karpenter 组件已启用，参考 [tke-karpenter 说明](https://cloud.tencent.com/document/product/457/111805)。

准备用于配置 Karpenter 节点池的 `nodepool.yaml`，以下是示例:

```yaml title="nodepool.yaml"
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
        # 原生节点默认安装 TencentOS 3，与最新 cilium 版本不兼容，指定该注解安装 TencentOS 4
        # 注意：当前使用该系统镜像还需要提工单申请
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
        # 指定期望使用的机型列表，可在控制台先确认下集群所在地域和相关可用区实际售卖的机型有哪些
        # 完整列表参考: https://cloud.tencent.com/document/product/213/11518#INSTANCETYPE
        values: ["S5", "SA2"]
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
    cpu: 100 # 限制节点池的最大 CPU 核数

---
apiVersion: karpenter.k8s.tke/v1beta1
kind: TKEMachineNodeClass
metadata:
  name: default
spec:
  subnetSelectorTerms: # 节点所属 VPC 子网
  - id: subnet-12sxk3z4
  - id: subnet-b8qyi2dk
  securityGroupSelectorTerms: # 节点绑定的安全组
  - id: sg-nok01xpa
  sshKeySelectorTerms: # 节点绑定的 ssh 密钥
  - id: skey-3t01mlvf
```

创建 Karpenter 节点池：

```bash
kubectl apply -f nodepool.yaml
```

### 新建原生节点池

以下是通过 [容器服务控制台](https://console.cloud.tencent.com/tke2) 新建原生节点池的步骤：
1. 在集群列表中，单击集群 ID，进入集群详情页。
2. 选择左侧菜单栏中的**节点管理**，点击**节点池**进入节点池列表页面。
3. 点击**新建**。
4. 选择 **原生节点**。
5. 在 **高级设置** 的 Annotations 点击 **新增**：`node.tke.cloud.tencent.com/beta-image=ts4-public`（原生节点默认使用 TencentOS 3.1，与最新版的 cilium 不兼容，通过注解指定原生节点使用 TencentOS 4）。
6. 其余选项根据自身需求自行选择。
7. 点击 **创建节点池**。

如果你想通过 terraform 来创建原生节点池，参考以下代码片段：

```hcl
resource "tencentcloud_kubernetes_native_node_pool" "cilium" {
  name       = "cilium"
  cluster_id = tencentcloud_kubernetes_cluster.tke_cluster.id
  type       = "Native"
  annotations { # 添加注解指定原生节点使用 TencentOS 4，以便能够与 cilium 兼容，当前使用该系统镜像还需要提工单申请
    name  = "node.tke.cloud.tencent.com/beta-image"
    value = "ts4-public"
  }
}
```
### 新建普通节点池

以下是通过 [容器服务控制台](https://console.cloud.tencent.com/tke2) 新建普通节点池的步骤：
1. 在集群列表中，单击集群 ID，进入集群详情页。
2. 选择左侧菜单栏中的**节点管理**，点击**节点池**进入节点池列表页面。
3. 点击**新建**。
4. 选择 **普通节点**。
5. **操作系统** 选择 **TencentOS 4**、**Ubuntu 22.04** 或 **Ubuntu 24.04**。
6. 其余选项根据自身需求自行选择。
7. 点击**创建节点池**。

如果你想通过 terraform 来创建普通节点池，参考以下代码片段：

```hcl
resource "tencentcloud_kubernetes_node_pool" "cilium" {
  name       = "cilium"
  cluster_id = tencentcloud_kubernetes_cluster.tke_cluster.id
  node_os    = "img-gqmik24x" # TencentOS 4 的镜像 ID，当前使用该系统镜像还需要提工单申请
}
```

## 常见问题

### 如何查看 Cilium 全部的默认安装配置？

Cilium 的 helm 安装包提供了大量的自定义配置项，上面安装步骤只给出了在 TKE 环境中安装 Cilium 的必要配置，实际可根据自身需求调整更多配置。

执行下面的命令可查看所有的安装配置项：

```bash
helm show values cilium/cilium --version 1.18.3
```

### 为什么要加 local-router-ipv4 配置？

cilium 会在每台节点上创建 `cilium_host` 虚拟网卡，并需要配置一个 IP 地址，由于我们要让 cilium 与 TKE VPC-CNI 网络插件共存，IP 分配需要由 TKE VPC-CNI 插件来完成，cilium 就不负责 IP 分配了，所以需要我们通过 `local-router-ipv4` 参数来手动指定一个不会有冲突的 IP 地址，而 `169.254.32.16` 这个 IP 地址在 TKE 上不会与其它 IP 冲突，所以就指定这个 IP 地址。

### 连不上 cilium 的 helm repo 怎么办？

使用 helm 安装 cilium 时，helm 会从 cilium 的 helm repo 获取 chart 相关信息并下载，如果连不上则会报错。

解决办法是在可以连上的环境下载 chart 压缩包：

```bash
$ helm pull cilium/cilium --version 1.18.3
$ ls cilium-*.tgz
cilium-1.18.3.tgz
```

然后将 chart 压缩包复制到执行 helm 安装的机器上，安装时指定下 chart 压缩包的路径：
```bash
helm upgrade --install cilium ./cilium-1.18.3.tgz \
  --namespace kube-system \
  -f values.yaml
```

### 大规模场景如何优化？

如果集群规模较大，建议开启 [CiliumEndpointSlice](https://docs.cilium.io/en/stable/network/kubernetes/ciliumendpointslice/) 特性，该特性于  1.11 开始引入，当前（1.18.3）仍在 Beta 阶段（详见 [CiliumEndpointSlice Graduation to Stable](https://github.com/cilium/cilium/issues/31904)），在大规模场景下，该特性可以显著提升 cilium 性能并降低 apiserver 的压力。

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

### Pod 如何访问公网？

可以创建公网 NAT 网关，然后在集群所在 VPC 的路由表中新建路由规则，让访问外网的流量转发到公网 NAT 网关，并确保路由表关联到了集群使用的子网，参考 [通过 NAT 网关访问外网](https://cloud.tencent.com/document/product/457/48710)。

如果是节点本身有公网带宽，希望 Pod 能直接利用节点的公网能力出公网，需要在部署 cilium 时做一些配置调整：

```bash showLineNumbers
helm upgrade cilium cilium/cilium --version 1.18.3 \
  --namespace kube-system \
  --reuse-values \
  # highlight-add-start
  --set enableIPv4Masquerade=true \
  --set ipv4NativeRoutingCIDR="VPC_CIDR" \
  --set bpf.masquerade=true
  # highlight-add-end
```

:::info[注意]

如果是调整已安装的 cilium 配置，存量节点需重启 cilium daemonset 才能生效：

```bash
kubectl -n kube-system rollout restart daemonset cilium
```

:::

:::tip[参数说明]

以下是是包含相关参数解释的 `values.yaml`:

```yaml title="values.yaml"
# 启用 cilium 的 IP MASQUERADE 功能
enableIPv4Masquerade: true
# 指定集群所在 VPC 的 CIDR（注意替换为集群所在 VPC 的实际 CIDR），表示 VPC 内的流量不做 SNAT，其余的流量要做 SNAT。
# 这样 Pod 访问公网时就会 SNAT 成节点 IP，就可以利用节点的公网能力访问公网。
ipv4NativeRoutingCIDR: 172.22.0.0/16
bpf:
  # cilium 的 IP MASQUERADE 功能有 bpf 和 iptables 两个版本，在 TKE 环境需使用 bpf 版本。参考 https://docs.cilium.io/en/stable/network/concepts/masquerading/
  masquerade: true
```

:::

如果有更高级的流量外访需求（比如指定某些 Pod 用某个公网 IP 访问公网），可以参考 [使用 Egress Gateway 控制集群外访流量](egress-gateway.md)。

### 镜像拉取失败？

cilium 依赖的大部分镜像在 `quay.io`，如果安装时没使用本文给的替换镜像地址的参数配置，可能导致 cilium 相关镜像拉取失败（比如节点没有访问公网的能力，或者集群在中国大陆）。

在 TKE 环境中，提供了 `quay.tencentcloudcr.com` 这个 mirror 仓库地址，用于下载 `quay.io` 域名下的镜像，直接将原镜像地址中 `quay.io` 域名替换为 `quay.tencentcloudcr.com` 即可，拉取时走内网，无需节点有公网能力，也没有地域限制。

如果你配置了更多安装的参数，可能会涉及更多的镜像依赖，没有配置镜像地址替换的话可能导致镜像拉取失败，用以下命令可将所有 cilium 依赖镜像一键替换为 TKE 环境中可直接内网拉取的 mirror 仓库地址：

```bash
helm upgrade cilium cilium/cilium --version 1.18.3 \
  --namespace kube-system \
  --reuse-values \
  --set image.repository=quay.tencentcloudcr.com/cilium/cilium \
  --set envoy.image.repository=quay.tencentcloudcr.com/cilium/cilium-envoy \
  --set operator.image.repository=quay.tencentcloudcr.com/cilium/operator \
  --set certgen.image.repository=quay.tencentcloudcr.com/cilium/certgen \
  --set hubble.relay.image.repository=quay.tencentcloudcr.com/cilium/hubble-relay \
  --set hubble.ui.backend.image.repository=quay.tencentcloudcr.com/cilium/hubble-ui-backend \
  --set hubble.ui.frontend.image.repository=quay.tencentcloudcr.com/cilium/hubble-ui \
  --set nodeinit.image.repository=quay.tencentcloudcr.com/cilium/startup-script \
  --set preflight.image.repository=quay.tencentcloudcr.com/cilium/cilium \
  --set preflight.envoy.image.repository=quay.tencentcloudcr.com/cilium/cilium-envoy \
  --set clustermesh.apiserver.image.repository=quay.tencentcloudcr.com/cilium/clustermesh-apiserver \
  --set authentication.mutual.spire.install.agent.image.repository=docker.io/k8smirror/spire-agent \
  --set authentication.mutual.spire.install.server.image.repository=docker.io/k8smirror/spire-server
```

如果你使用 yaml 管理配置，可以将镜像替换的配置保存到 `image-values.yaml`:

```yaml title="image-values.yaml"
image:
  repository: quay.tencentcloudcr.com/cilium/cilium
envoy:
  image:
    repository: quay.tencentcloudcr.com/cilium/cilium-envoy
operator:
  image:
    repository: quay.tencentcloudcr.com/cilium/operator
certgen:
  image:
    repository: quay.tencentcloudcr.com/cilium/certgen
hubble:
  relay:
    image:
      repository: quay.tencentcloudcr.com/cilium/hubble-relay
  ui:
    backend:
      image:
        repository: quay.tencentcloudcr.com/cilium/hubble-ui-backend
    frontend:
      image:
        repository: quay.tencentcloudcr.com/cilium/hubble-ui
nodeinit:
  image:
    repository: quay.tencentcloudcr.com/cilium/startup-script
preflight:
  image:
    repository: quay.tencentcloudcr.com/cilium/cilium
  envoy:
    image:
      repository: quay.tencentcloudcr.com/cilium/cilium-envoy
clustermesh:
  apiserver:
    image:
      repository: quay.tencentcloudcr.com/cilium/clustermesh-apiserver
authentication:
  mutual:
    spire:
      install:
        agent:
          image:
            repository: docker.io/k8smirror/spire-agent
        server:
          image:
            repository: docker.io/k8smirror/spire-server
```

更新 cilium 时追加一个 `-f image-values.yaml` 将镜像替换的配置加上：

```bash showLineNumbers
helm upgrade --install cilium cilium/cilium --version 1.18.3 \
  --namespace=kube-system \
  -f values.yaml \
  # highlight-add-line
  -f image-values.yaml
```

:::tip[说明]

使用 TKE 提供的 mirror 仓库地址拉取外部镜像，本身不提供 SLA 保障，某些时候可能也会拉取失败，通常最终会自动重试成功。

如果希望拉取镜像具备更高的可用性，可 [使用 TCR 托管 Cilium 镜像](tcr.md) 将 cilium 依赖镜像同步到自己的 [TCR 镜像仓库](https://cloud.tencent.com/product/tcr)，然后参考这里的依赖镜像替换的配置，将相应镜像再替换为自己同步后的镜像地址。

:::

### 无法使用 TencentOS 4 ？

TencentOS 4 系统镜像目前内测中，需要 [提交工单](https://console.cloud.tencent.com/workorder/category) 进行申请。

如果没有申请，添加普通节点将无法选择到 TencentOS 4 的系统镜像，原生节点如果指定了注解使用 TencentOS 4，节点将无法成功初始化。

## 参考资料

- [Installation using Helm](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)
- [Generic Veth Chaining](https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/)
- [Kubernetes Without kube-proxy](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)

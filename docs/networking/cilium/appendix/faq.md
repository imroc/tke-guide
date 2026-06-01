# 常见问题

本文汇总在 TKE 上自建 Cilium 过程中常见的"能不能 / 怎么做 / 出错怎么办"类问题。如果是「为什么这么设计」相关的疑问，请查看 Cilium 附录目录下的其它原理性文章。

## 如何查看 Cilium 全部的默认安装配置？

Cilium 的 helm 安装包提供了大量的自定义配置项，[安装 Cilium](../install.md) 中给出的只是 TKE 环境中安装 Cilium 的必要配置，实际可根据自身需求调整更多配置。

执行下面的命令可查看所有的安装配置项：

```bash
helm show values cilium/cilium --version 1.19.4
```

## 连不上 cilium 的 helm repo 怎么办？

使用 helm 安装 cilium 时，helm 会从 cilium 的 helm repo 获取 chart 相关信息并下载，如果连不上则会报错。

解决办法是在可以连上的环境下载 chart 压缩包：

```bash
$ helm pull cilium/cilium --version 1.19.4
$ ls cilium-*.tgz
cilium-1.19.4.tgz
```

然后将 chart 压缩包复制到执行 helm 安装的机器上，安装时指定下 chart 压缩包的路径：

```bash
helm upgrade --install cilium ./cilium-1.19.4.tgz \
  --namespace kube-system \
  -f values.yaml
```

## 大规模场景如何优化？

集群规模较大（数百节点 / 万级 Pod 以上）时，可从以下几方面优化：

### 1. 启用 CiliumEndpointSlice（推荐）

将多个 CiliumEndpoint 聚合为一个 CiliumEndpointSlice 资源，显著减少 apiserver 的 watch/list 压力：

```yaml
ciliumEndpointSlice:
  enabled: true
```

该特性于 1.11 引入，1.19 仍为 Beta（[追踪 Stable 进展](https://github.com/cilium/cilium/issues/31904)）。

### 2. 调整 K8s Client 限速

cilium-agent 默认 QPS=10、Burst=20，大规模下可能成为瓶颈；cilium-operator 默认 QPS=100、Burst=200：

```yaml
k8sClientRateLimit:
  qps: 20
  burst: 40
  operator:
    qps: 200
    burst: 400
```

### 3. 精简 Identity 数量

cilium 为每组唯一的 label 组合分配一个 Security Identity，过多 Identity 会增加内存和策略计算开销。通过排除无关 label 可有效减少 Identity 数：

```yaml
# 排除高基数 label，减少 Identity 膨胀
extraConfig:
  labels: "!pod-template-hash !controller-revision-hash !job-name !batch.kubernetes.io/controller-uid"
```

### 4. 配置 Agent / Operator 资源

默认资源配置偏保守，大规模集群建议显式设置：

```yaml
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 2000m
    memory: 2Gi
operator:
  resources:
    requests:
      cpu: 200m
      memory: 256Mi
    limits:
      cpu: 1000m
      memory: 1Gi
```

### 5. 使用 API Priority and Fairness (APF)

[安装 Cilium](../install.md) 中给的安装脚本已默认创建 cilium 专属的 APF FlowSchema 和 PriorityLevelConfiguration，防止 cilium 的 list 请求影响其他组件。如果手动安装，建议也参照脚本配置。

### 6. BPF Map 动态调整

默认 BPF map 容量基于系统内存自动计算。如需手动调整比例：

```yaml
bpf:
  mapDynamicSizeRatio: 0.0025
```

## GR 集群安装 cilium 后能否动态启用 VPC-CNI？

不建议。GR 集群本身支持通过启用 VPC-CNI 网络能力实现 GR 与 VPC-CNI 共存，但**安装本文方案的 cilium 后此功能将不再实际可用**：

- cilium chaining 通过 multus 配置（`defaultDelegates=tke-bridge`）接管所有 Pod 网络
- 创建带 `tke.cloud.tencent.com/networks: tke-route-eni` annotation 的 Pod 后，IP 仍然来自 GR 的 ClusterCIDR 段（而不是 VPC-CNI 子网），实际并未走 VPC-CNI 路径
- 操作上 `EnableVpcCniNetworkType` 接口可以调用成功，组件也会部署，但对 Pod 网络没有实际影响

如果业务确有 VPC-CNI 需求，请直接使用 **VPC-CNI 集群 + Native Routing** 方案，不要选择 GR 集群。

## VPC-CNI 集群创建时能否勾选 DataPlaneV2？

不能。

选择 VPC-CNI 网络插件时，有个 DataPlaneV2 选项：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F09%2F26%2F20250926092351.png)

勾选后，会部署 cilium 组件到集群中（替代 kube-proxy 组件），如果再自己安装 cilium 会造成冲突，而且 DataPlaneV2 所使用的 OS 与 cilium 最新版也不兼容，所以不能勾选此选项。

## Pod 如何访问公网？

可以创建公网 NAT 网关，然后在集群所在 VPC 的路由表中新建路由规则，让访问外网的流量转发到公网 NAT 网关，并确保路由表关联到了集群使用的子网，参考 [通过 NAT 网关访问外网](https://cloud.tencent.com/document/product/457/48710)。

如果是节点本身有公网带宽，希望 Pod 能直接利用节点的公网能力出公网，需要开启 Cilium 的 IP Masquerade 能力，具体方法参考 [配置 IP 伪装](../masquerading.md)。

如果有更高级的流量外访需求（比如指定某些 Pod 用某个公网 IP 访问公网），可以参考 [Egress Gateway 应用实践](../egress-gateway.md)。

## 镜像拉取失败？

cilium 依赖的大部分镜像在 `quay.io`，如果安装时没使用[安装 Cilium](../install.md)给的替换镜像地址的参数配置，可能导致 cilium 相关镜像拉取失败（比如节点没有访问公网的能力，或者集群在中国大陆）。

在 TKE 环境中，提供了 `quay.tencentcloudcr.com` 这个 mirror 仓库地址，用于下载 `quay.io` 域名下的镜像，直接将原镜像地址中 `quay.io` 域名替换为 `quay.tencentcloudcr.com` 即可，拉取时走内网，无需节点有公网能力，也没有地域限制。

如果你配置了更多安装的参数，可能会涉及更多的镜像依赖，没有配置镜像地址替换的话可能导致镜像拉取失败，用以下命令可将所有 cilium 依赖镜像一键替换为 TKE 环境中可直接内网拉取的 mirror 仓库地址：

```bash
helm upgrade cilium cilium/cilium --version 1.19.4 \
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
helm upgrade --install cilium cilium/cilium --version 1.19.4 \
  --namespace=kube-system \
  -f values.yaml \
  # highlight-add-line
  -f image-values.yaml
```

:::tip[说明]

使用 TKE 提供的 mirror 仓库地址拉取外部镜像，本身不提供 SLA 保障，某些时候可能也会拉取失败，通常最终会自动重试成功。

如果希望拉取镜像具备更高的可用性，可 [使用 TCR 托管 Cilium 镜像](../tcr.md) 将 cilium 依赖镜像同步到自己的 [TCR 镜像仓库](https://cloud.tencent.com/product/tcr)，然后参考这里的依赖镜像替换的配置，将相应镜像再替换为自己同步后的镜像地址。

:::

## cilium-operator 在超级节点无法就绪？

cilium-operator 使用 hostNetwork 并配置了就绪探针，在超级节点上使用 hostNetwork 时探测请求不通，所以 cilium-operator 无法就绪。

安装 cilium 的集群不建议使用超级节点，可以移除掉，如果一定要用，可给超级节点打上污点，再给需要调度到超级节点的 Pod 加上对应的容忍。

## cilium-agent 连 apiserver 报错 `operation not permitted`？

如果安装 cilium 时 `k8sServiceHost` 指向的是 CLB 地址（开启集群内网访问时使用的 CLB），地址为 CLB VIP 或最终解析到 CLB VIP 的域名，此时 cilium-agent 连接 apiserver 的链路会被 cilium 自身拦截并转发，不会真正到 CLB 转发。cilium 转发该地址最终是 ebpf 程序实现的，ebpf 程序转发该地址又是基于存放在内核中的 ebpf 数据（endpoint 列表），在某种触发条件下，ebpf 数据可能被刷新，刷新可能导致 endpoint 列表被临时清空，而一旦清空 cilium-agent 就再也连不上 apiserver（报错 `operation not permitted`），也就无法感知当前真实的 endpoint 列表来更新 ebpf 数据，形成循环依赖，重启节点后才会恢复正常。

所以建议是 `k8sServiceHost` 不要配置 apiserver 的 CLB 地址，而是使用集群 `169.254.x.x` 的 apiserver 地址（`kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}'`），该地址也是一个 VIP，但不会被 cilium 拦截转发，并且是自集群创建完后就再也不会变的，可以放心作为 `k8sServiceHost` 配置。如果希望使用辨识度更高的域名方式配置，也可以将域名解析到该地址然后再配置到 `k8sServiceHost`。

完整的根因分析、复现步骤和 cilium 上游 PR 链接，参见 [问题排查：连接 APIServer 报错 operation not permitted](../troubleshooting/connect-apiserver-operation-not-permitted.md)。

## 相关链接

- [安装 Cilium](../install.md)
- [Cilium 问题排查](../troubleshooting/debug.md)

# 安装 Cilium

## 概述

本文介绍如何在 TKE 集群中安装 Cilium。

## 前提条件

- 集群版本：1.22 及以上
- 网络模式：VPC-CNI 或 GlobalRouter
- 节点类型：普通节点或原生节点
- 操作系统：TencentOS 4

## 网络选型：Encapsulation vs Native-Routing

Cilium 路由支持两种模式：
1. Encapsulation（封装模式）：即在原有的网络基础上再做一层网络封包进行转发。优点是兼容性好，可适配各种网络环境，缺点是性能较差。
2. Native-Routing（原生路由）：Pod IP 直接在底层网络上进行路由转发，Cilium 不管。优点是性能好，缺点是依赖底层网络对 Pod IP 的路由转发的支持，不通用。

在包括 TKE 在内的云上托管的 Kubernetes 集群中，底层网络都已支持 Pod IP 的路由转发，如果对网络转发性能有要求，推荐使用 Native-Routing 模式，如果希望安装更简单通用，可使用 Encapsulation 模式。

> 更多详情请参考 Cilium 官方文档：[Routing](https://docs.cilium.io/en/stable/network/concepts/routing/)。

## 准备 TKE 集群

准备好符合前提条件的 TKE 集群。

## Native-Routing 模式安装步骤

下面介绍在 TKE 安装 Cilium（Native-Routing）的步骤。

1. 修改 tke-cni-agent 的配置，删除默认的 cni 配置，避免与 cilium 的 cni 配置冲突。

```bash
kubectl -n kube-system patch configmap tke-cni-agent --type json -p='[{"op": "remove", "path": "/data"}]'
```

2. 准备 Cilium 自定义的 CNI 配置：

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
          "name": "multus-cni",
          "type": "multus",
          "kubeconfig": "/etc/kubernetes/tke-cni-kubeconfig",
          "logLevel": "info",
          "defaultDelegates": "tke-route-eni",
          "capabilities": {
            "bandwidth": true,
            "portMappings": true
          }
        },
        {
          "type": "cilium-cni",
          "chaining-mode": "generic-veth"
        }
      ]
    }
```

3. 创建 Cilium 自定义 CNI 配置：
 
```bash
kubectl apply -f cni-configuration.yaml
```

4. 确保添加 cilium 的 helm repo:

```bash
helm repo add cilium https://helm.cilium.io/
```

5. 准备安装配置：
```yaml title="values.yaml"
routingMode: "native"
ipv4NativeRoutingCIDR: "10.0.0.0/8"
enableIPv4Masquerade: false
cni:
  customConf: true
  configMap: cni-configuration
  chainingMode: generic-veth
  exclusive: true
ipam:
  mode: "delegated-plugin"
extraConfig:
  local-router-ipv4: 169.254.32.16
  enable-endpoint-routes: "true"
```
6. （可选）如果集群地域在中国大陆，拉取不到 cilium 依赖的的镜像，可以在安装配置指定使用 dockerhub 上的 mirror 镜像（TKE 环境有 dockerhub 的加速，默认就可以直接拉取）：
```yaml title="image-values.yaml"
image:
  repository: "docker.io/cilium/cilium"
certgen:
  image:
    repository: "docker.io/cilium/certgen"
hubble:
  relay:
    image:
      repository: "docker.io/cilium/hubble-relay"
  ui:
    backend:
      image:
        repository: "docker.io/cilium/hubble-ui-backend"
    frontend:
      image:
        repository: "docker.io/cilium/hubble-ui"
envoy:
  image:
    repository: "docker.io/imroc/cilium-envoy"
operator:
  image:
    repository: "docker.io/cilium/operator"
nodeinit:
  image:
    repository: "docker.io/cilium/startup-script"
preflight:
  image:
    repository: "docker.io/cilium/cilium"
  envoy:
    image:
      repository: "docker.io/imroc/cilium-envoy"
clustermesh:
  apiserver:
    image:
      repository: "docker.io/cilium/clustermesh-apiserver"
authentication:
  mutual:
    spire:
      install:
        initImage:
          repository: "docker.io/library/busybox"
        agent:
          image:
            repository: "docker.io/imroc/spire-agent"
        server:
          image:
            repository: "docker.io/imroc/spire-server"
```
7. 执行安装（后续配置更新和升级版本都可复用这个命令）：
```bash
helm upgrade --install --namespace kube-system -f values.yaml --version 1.18.0 cilium cilium/cilium
```
> 如果集群地域在中国大陆，安装时可额外指定镜像替换的安装配置（`-f` 可指定多次，最终会合并所有的安装配置）：
> ```bash
> helm upgrade --install --namespace kube-system -f values.yaml -f image-values.yaml --version 1.18.0 cilium cilium/cilium
> ```

## FAQ

### 如何查看 Cilium 全部的默认安装配置？

Cilium 的 helm 安装包提供了大量的自定义配置项，上面安装步骤只给出了在 TKE 环境中安装 Cilium 的必要配置，实际可根据自身需求调整更多配置。

执行下面的命令可查看所有的安装配置项：

```bash
helm show values cilium/cilium --version 1.18.0
```

### 连不上 cilium 的 helm repo 怎么办？

使用 helm 安装 cilium 时，helm 会从 cilium 的 helm repo 获取 chart 相关信息并下载，如果连不上则会报错。

解决办法是在可以连上的环境下载 chart 压缩包：
```bash
$ helm pull cilium/cilium --version 1.18.0
$ ls cilium-*.tgz
cilium-1.18.0.tgz
```

然后将 chart 压缩包复制到执行 helm 安装的机器上，安装时指定下 chart 压缩包的路径：
```bash
helm upgrade --install --namespace kube-system -f values.yaml --version 1.18.0 cilium ./cilium-1.18.0.tgz
```

## TODO

- 基于 FQDN 的网络策略功能验证没过，创建 CiliumNetworkPolicy 后，解析域名 dns 不通。（验证参考 [Locking Down External Access with DNS-Based Policies](https://docs.cilium.io/en/stable/security/dns/)）
- Overlay 模式安装
- Cluster Mesh 多集群安装

## 参考资料

- [Cilium 官方文档: Installation using Helm](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)

# 安装 cilium

## 准备 helm

1. 确保 [helm](https://helm.sh/zh/docs/intro/install/) 和 [kubectl](https://kubernetes.io/zh-cn/docs/tasks/tools/install-kubectl-linux/) 已安装，并配置好可以连接集群的 kubeconfig（参考 [连接集群](https://cloud.tencent.com/document/product/457/32191#a334f679-7491-4e40-9981-00ae111a9094)）。
2. 添加 cilium 的 helm repo:

```bash
helm repo add cilium https://helm.cilium.io/
```

## 简易安装

使用下面命令可快捷安装 cilium，与 kube-proxy 共存（非满血版 cilium）：

```bash
helm --install cilium cilium/cilium --version 1.18.2 \
  --namespace kube-system \
  --set routingMode=native \
  --set endpointRoutes.enabled=true \
  --set enableIPv4Masquerade=false \
  --set cni.chainingMode=generic-veth \
  --set cni.chainingTarget=multus-cni \
  --set ipam.mode=delegated-plugin \
  --set extraConfig.local-router-ipv4=169.254.32.16
```

## 高级安装

如果想要使用满血版 cilium，可让 cilium 完全替代 kube-proxy，减少整体的资源开销并获得更好的 Service 转发性能，并具有更高的灵活性，还可实现与 istio 等其它工具集成。

下面介绍安装步骤：

1. 先卸载 kube-proxy 和 tke-cni-agent：

```bash
kubectl -n kube-system patch ds kube-proxy -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
kubectl -n kube-system patch ds tke-cni-agent -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
```

:::tip[说明]

1. 通过加 nodeSelector 方式让 daemonset 不部署到任何节点，等同于卸载，同时也留个退路。
2. 如果 Pod 使用 VPC-CNI 网络，可以不需要 tke-cni-agent，卸载以避免 CNI 配置文件冲突。

:::

2. 重启存量节点，清理残留的 kube-proxy 规则和 CNI 配置。

3. 为 tke-eni-ipamd 增加 cilium 污点的容忍：

```bash
kubectl patch deployment tke-eni-ipamd -n kube-system --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/tolerations/-",
    "value": {
      "effect": "NoExecute",
      "key": "node.cilium.io/agent-not-ready",
      "operator": "Exists"
    }
  }
]'
```

:::tip[说明]

tke-eni-ipamd 是 TKE VPC-CNI 网络中的关键组件，负责 Pod IP 的分配，使用 HostNetwork，不依赖 cilium-agent 的启动，所以可以加 cilium 污点的容忍。

:::

4. 准备 CNI 配置的 ConfigMap `cni-configuration.yaml`：

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

5. 创建 CNI ConfigMap:

```bash
kubectl apply -f cni-configuration.yaml
```

6. 使用 helm 安装 cilium：

```bash
helm install cilium cilium/cilium --version 1.18.2 \
  --namespace kube-system \
  --set routingMode=native \
  --set endpointRoutes.enabled=true \
  --set enableIPv4Masquerade=false \
  --set ipam.mode=delegated-plugin \
  --set cni.chainingMode=generic-veth \
  --set cni.chainingTarget=multus-cni \
  --set cni.exclusive=false \
  --set cni.customConf=true \
  --set cni.configMap=cni-configuration \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=$(kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}') \
  --set k8sServicePort=60002 \
  --set extraConfig.local-router-ipv4=169.254.32.16
```

:::tip[说明]

`k8sServiceHost` 是 apiserver 地址，通过命令动态获取。

:::

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

### 大规模场景如何优化？

如果集群规模较大，建议开启 [CiliumEndpointSlice](https://docs.cilium.io/en/stable/network/kubernetes/ciliumendpointslice/) 特性，该特性于  1.11 开始引入，当前（1.18.2）仍在 Beta 阶段（详见 [CiliumEndpointSlice Graduation to Stable](https://github.com/cilium/cilium/issues/31904)），在大规模场景下，该特性可以显著提升 cilium 性能并降低 apiserver 的压力。

默认没有启用，启用方法是在使用 helm 安装 cilium 时，通过加 `--set ciliumEndpointSlice.enabled=true` 参数来开启。

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

```bash showLineNumbers
helm upgrade --install  --namespace kube-system  --version 1.18.2 -f values.yaml cilium cilium/cilium
```

:::tip[说明]

1. 修改配置通过修改 `values.yaml` 文件并再次执行上述命令来完成，完整配置项通过 `helm show values cilium/cilium --version 1.18.2` 查看。
2. 如果是升级版本，替换 `--version` 的值即可。

:::


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

- [Installation using Helm](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)
- [Generic Veth Chaining](https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/)
- [Kubernetes Without kube-proxy](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)

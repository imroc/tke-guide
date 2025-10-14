# 常见问题

## 如何查看 Cilium 全部的默认安装配置？

Cilium 的 helm 安装包提供了大量的自定义配置项，上面安装步骤只给出了在 TKE 环境中安装 Cilium 的必要配置，实际可根据自身需求调整更多配置。

执行下面的命令可查看所有的安装配置项：

```bash
helm show values cilium/cilium --version 1.18.2
```

## 连不上 cilium 的 helm repo 怎么办？

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

## 大规模场景如何优化？

如果集群规模较大，建议开启 [CiliumEndpointSlice](https://docs.cilium.io/en/stable/network/kubernetes/ciliumendpointslice/) 特性，该特性于  1.11 开始引入，当前（1.18.2）仍在 Beta 阶段（详见 [CiliumEndpointSlice Graduation to Stable](https://github.com/cilium/cilium/issues/31904)），在大规模场景下，该特性可以显著提升 cilium 性能并降低 apiserver 的压力。

默认没有启用，启用方法是在使用 helm 安装 cilium 时，通过加 `--set ciliumEndpointSlice.enabled=true` 参数来开启。

## 为什么不能与 kube-proxy ipvs 共存？

cilium 与 kube-proxy ipvs 模式不兼容，详见[这个issue](https://github.com/cilium/cilium/issues/18610)。

在 TKE 环境的具体表现是访问 service 不通。

具体底层细节正在研究中。

## 如何修改 cilium 安装配置或升级？

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
helm upgrade --install \
  --namespace kube-system \
  -f values.yaml \
  --version 1.18.2 \
  cilium cilium/cilium
```

> 修改配置通过修改 `values.yaml` 文件来完成，完整配置项通过 `helm show values cilium/cilium --version 1.18.2` 查看。

如果是升级版本，替换 `--version` 的值即可：

```bash showLineNumbers
helm upgrade --install \
  --namespace kube-system \
  -f values.yaml \
  # highlight-next-line
  --version 1.18.3 \
  cilium cilium/cilium
```

## Global Router 网络模式的集群能否安装？

测试结论是：不能。

应该是 cilium 不支持 bridge CNI 插件（Global Router 网络插件基于 bridge CNI 插件），相关 issue:
- [CFP: eBPF with bridge mode](https://github.com/cilium/cilium/issues/35011)
- [CFP: cilium CNI chaining can support cni-bridge](https://github.com/cilium/cilium/issues/20336)

## 能否勾选 DataPlaneV2？

结论是：不能。

选择 VPC-CNI 网络插件时，有个 DataPlaneV2 选项：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F09%2F26%2F20250926092351.png)

勾选后，会部署 cilium 组件到集群中（替代 kube-proxy 组件），如果再自己安装 cilium 会造成冲突，而且 DataPlaneV2 所使用的 OS 与 cilium 最新版也不兼容，所以不能勾选此选项。


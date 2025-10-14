# 安装 cilium

## 准备 helm

1. 确保 [helm](https://helm.sh/zh/docs/intro/install/) 和 [kubectl](https://kubernetes.io/zh-cn/docs/tasks/tools/install-kubectl-linux/) 已安装，并配置好可以连接集群的 kubeconfig（参考 [连接集群](https://cloud.tencent.com/document/product/457/32191#a334f679-7491-4e40-9981-00ae111a9094)）。
2. 添加 cilium 的 helm repo:

```bash
helm repo add cilium https://helm.cilium.io/
```

## 简易安装

使用下面命令可快捷安装 cilium，与 kube-proxy 共存（非满血版 cilium）：

```bash showLineNumbers
helm upgrade --install cilium cilium/cilium --version 1.18.2 \
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

如果想要使用满血版 cilium，可让 cilium 完全替代 kube-proxy，减少整体的资源开销并获得更好的 Service 转发性能，并具有更高的灵活性，可实现与 istio 等其它工具集成。

下面介绍安装步骤：

1. 先卸载 kube-proxy：

```bash
kubectl -n kube-system patch ds kube-proxy -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
```

:::tip[说明]

通过加 nodeSelector 方式让 kube-proxy 不部署到任何节点，避免后续升级集群时 kube-proxy 又被重新创建回来。

:::


2. 再卸载 tke-cni-agent：

```bash
kubectl -n kube-system delete ds tke-cni-agent
```

:::tip[说明]

如果使用 Pod VPC-CNI 网络，可以不需要此组件，卸载以避免 CNI 配置文件冲突。

:::

3. 准备 CNI 配置的 ConfigMap `cni-configuration.yaml`：

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

:::tip[说明]

CNI 配置完全自行掌控，不与 TKE 自带的 CNI 配置冲突，还可以实现与 isito 之类的工具集成。

:::

4. 创建 CNI ConfigMap:

```bash
kubectl apply -f cni-configuration.yaml
```

5. 准备 cilium 安装配置 `values.yaml`：

```yaml title=”values.yaml“
routingMode: "native"
endpointRoutes:
  enabled: true
ipam:
  mode: "delegated-plugin"
enableIPv4Masquerade: false
cni:
  chainingMode: generic-veth
  exclusive: false
  customConf: true
  configMap: cni-configuration
kubeProxyReplacement: "true"
k8sServiceHost: ${APISERVER_HOST} # kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}'
k8sServicePort: 60002
extraConfig:
  local-router-ipv4: 169.254.32.16
```

:::info[注意]

- `k8sServiceHost` 需通过 `kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}'` 来获取。

:::

6. 使用 helm 安装 cilium：

```bash
helm upgrade --install \
  --namespace kube-system \
  --version 1.18.2 \
  -f values.yaml \
  cilium cilium/cilium
```

:::tip[说明]

- 如果要更新配置，可直接修改 `values.yaml` 文件，然后重新执行上述命令进行更新。
- 如果要升级版本，也可复用上述命令，仅修改 `--version` 参数即可。

:::


## 参考资料

- [Installation using Helm](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)
- [Generic Veth Chaining](https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/)
- [Kubernetes Without kube-proxy](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)

# Cilium 与 Nodelocal DNSCache 共存

## 概述

[Nodelocal DNS Cache](https://github.com/kubernetes/kubernetes/tree/master/cluster/addons/dns/nodelocaldns) 用于 DNS 缓存和加速，可减轻 coredns 压力并提高 DNS 查询性能。

本文介绍安装 Cilium 的 TKE 集群如何实现与 Nodelocal DNSCache 共存。

## 与 TKE 的 NodeLocalDNSCache 插件不兼容

安装 Cilium 并替代了 kube-proxy，访问 coredns 的请求会被 cilium 的 ebpf 程序拦截并转发，无法被节点上的 `node-local-dns` Pod 拦截，也就无法直接实现 DNS 缓存的能力，该插件的能力将会失效。

Cilium 官方给出了通过配置 CiliumLocalRedirectPolicy 来实现与 Nodelocal DNSCache 共存的方法，但如果使用的是 TKE 的 [NodeLocalDNSCache](https://cloud.tencent.com/document/product/457/40613) 插件， 即使通过配置 CiliumLocalRedirectPolicy 也无法实现与 NodeLocalDNSCache 共存，因为该插件使用了 HostNetwork 网络且不监听 节点/Pod IP （监听的是 `169.254.20.10` 和 `kube-dns` 的 Cluster IP），导致 DNS 流量无法被 CiliumLocalRedirectPolicy 重定向到本机的 `node-local-dns` Pod。

所以，若想在安装 Cilium 的集群使用 Nodelocal DNSCache，建议自建 Nodelocal DNSCache，具体方法参考下文。

## 自建 Nodelocal DNSCache

1. 保存以下内容到文件 `node-local-dns.yaml`:

:::tip[说明]

以下内容是根据 Ciium 官方文档 [Node-local DNS cache](https://docs.cilium.io/en/stable/network/kubernetes/local-redirect-policy/#node-local-dns-cache) 中的 **Manual Configuration** 方式，将 node-local-dns 官方的部署 YAML 文件 [nodelocaldns.yaml](https://raw.githubusercontent.com/kubernetes/kubernetes/refs/heads/master/cluster/addons/dns/nodelocaldns/nodelocaldns.yaml) 修改而来，另外替换镜像地址成 dockerhub 上的 mirror 镜像，方便在 TKE 环境中直接内网拉取到，并且禁用了 HINFO 请求避免日志一直报错（VPC 的 DNS 服务不支持 HINFO 请求）。

:::

<FileBlock file="cilium/node-local-dns.yaml" title="node-local-dns.yaml" />

2. 安装：
    ```bash
    kubedns=$(kubectl get svc kube-dns -n kube-system -o jsonpath={.spec.clusterIP}) && sed -i "s/__PILLAR__DNS__SERVER__/$kubedns/g;" node-local-dns.yaml
    kubectl apply -f node-local-dns.yaml
    ```

3. 保持以下内容到文件 `localdns-redirect-policy.yaml`:
    ```yaml title="localdns-redirect-policy.yaml"
    apiVersion: cilium.io/v2
    kind: CiliumLocalRedirectPolicy
    metadata:
      name: nodelocaldns
      namespace: kube-system
    spec:
      redirectFrontend:
        serviceMatcher:
          serviceName: kube-dns
          namespace: kube-system
      redirectBackend:
        localEndpointSelector:
          matchLabels:
            k8s-app: node-local-dns
        toPorts:
        - port: "53"
          name: dns
          protocol: UDP
        - port: "53"
          name: dns-tcp
          protocol: TCP
    ```

4. 创建 CiliumLocalRedirectPolicy (将 dns 的请求重定向到本机的 node-local-dns pod)：
    ```bash
    kubectl apply -f localdns-redirect-policy.yaml
    ```


## 常见问题

### sed 报错: extra characters at the end of n command

macOS 下执行安装 Nodelocal DNSCache 时，sed 报错：

```bash
$ kubedns=$(kubectl get svc kube-dns -n kube-system -o jsonpath={.spec.clusterIP}) && sed -i "s/__PILLAR__DNS__SERVER__/$kubedns/g;" node-local-dns.yaml

sed: 1: "node-local-dns.yaml
": extra characters at the end of n command
```

是因为 macOS 自带的 sed 命令不是标准的（GNU），语法有些不一样，可安装 GNU 版的 sed：

```bash
brew install gnu-sed
```

并设置下 PATH：

```bash
PATH="/usr/local/opt/gnu-sed/libexec/gnubin:$PATH"
```

最后新开终端重新执行安装命令即可。

### 无法创建 CiliumLocalRedirectPolicy

CiliumLocalRedirectPolicy 的能力没有默认开启，需在安装时加参数 `--set localRedirectPolicies.enabled=true` 来开启。

若 Cilium 已安装，通过以下方式更新 Cilium 配置来开启：

```bash

helm upgrade cilium cilium/cilium --version 1.18.3 \
  --namespace kube-system \
  --reuse-values \
  --set localRedirectPolicies.enabled=true
```

再需重启下 operator 和 agent 生效:

```bash
kubectl rollout restart deploy cilium-operator -n kube-system
kubectl rollout restart ds cilium -n kube-system
```

## 参考资料

- [Local Redirect Policy Use Cases: Node-local DNS cache](https://docs.cilium.io/en/stable/network/kubernetes/local-redirect-policy/#node-local-dns-cache)
- [在 Kubernetes 集群中使用 NodeLocal DNSCache](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/nodelocaldns/)
- [TKE DNS 最佳实践](https://cloud.tencent.com/document/product/457/78005)

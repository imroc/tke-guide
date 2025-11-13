# 快速开始

:::warning[警告]

Nginx Ingress 将会退役，Kubernetes 社区不再维护: https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/

建议迁移到 Ingresss 到 Gateway API，比如使用 EnvoyGateway 作为 GatewayAPI 的实现（参考 [在 TKE 使用 EnvoyGateway 流量网关](../envoygateway.md)）。

:::

## 概述

[Nginx Ingress Controller](https://github.com/kubernetes/ingress-nginx) 是基于高性能 NGINX 反向代理实现的 Kubernetes Ingress 控制器，也是最常用的开源 Ingress 实现。本文介绍如何在 TKE 环境中自建 Nginx Ingress Controller，主要使用 helm 进行安装，提供一些 `values.yaml` 配置指引。

## 前提条件

* 创建了 TKE 集群。
* 安装了 [helm](https://helm.sh/)。
* 配置了 TKE 集群的 kubeconfig，且有权限操作 TKE 集群（参考 [连接集群](https://cloud.tencent.com/document/product/457/32191#a334f679-7491-4e40-9981-00ae111a9094)）。

## 使用 helm 安装

添加 helm repo:

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
```

:::tip[说明]

如果 helm 命令所在机器连不上 GitHub，将添加失败，可参考后面的 [常见问题：连不上 GitHub 导致安装失败](#%E5%B8%B8%E8%A7%81%E9%97%AE%E9%A2%98%E8%BF%9E%E4%B8%8D%E4%B8%8A-github-%E5%AF%BC%E8%87%B4%E5%AE%89%E8%A3%85%E5%A4%B1%E8%B4%A5) 进行解决。

:::

查看默认配置:

```bash
helm show values ingress-nginx/ingress-nginx
```

Nginx Ingress 依赖的镜像在 `registry.k8s.io` 这个 registry 下，国内网络环境无法拉取，可替换为 docker hub 中的 mirror 镜像。

准备 `values.yaml`:

```yaml
controller: # 以下配置将依赖镜像替换为了 docker hub 上的 mirror 镜像以保证在国内环境能正常拉取
  image:
    registry: docker.io
    image: k8smirror/ingress-nginx-controller
  admissionWebhooks:
    patch:
      image:
        registry: docker.io
        image: k8smirror/ingress-nginx-kube-webhook-certgen
  defaultBackend:
    image:
      registry: docker.io
      image: k8smirror/defaultbackend-amd64
  opentelemetry:
    image:
      registry: docker.io
      image: k8smirror/ingress-nginx-opentelemetry
```

> 配置中的 mirror 镜像均使用 [image-porter](https://github.com/imroc/image-porter) 长期自动同步，可放心安装和升级。

安装：

```bash showLineNumbers
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  -f values.yaml
```

> 后续如果需要修改 values 配置，或者升级版本，都可以通过执行这个命令来更新 Nginx Ingress Controller。

查看流量入口(CLB VIP 或域名)：

```bash
$ kubectl get services -n ingress-nginx
NAME                                 TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)                      AGE
ingress-nginx-controller             LoadBalancer   172.16.145.161   162.14.91.101   80:30683/TCP,443:32111/TCP   53s
ingress-nginx-controller-admission   ClusterIP      172.16.166.237   <none>          443/TCP                      53s
```

> `LoadBalancer` 类型 Service 的 `EXTERNAL-IP` 就是 CLB 的 VIP 或域名，可以配置下 DNS 解析。如果是 VIP，就配 A 记录；如果是 CLB 域名，就配置 CNAME 记录。

## 常见问题：连不上 GitHub 导致安装失败

`ingress-nginx` 的 helm chart 仓库地址在 GitHub，如果 helm 命令所在环境连不上 GitHub，就无法下载 chart 包，`helm repo add` 操作也会失败。

如果遇到这个问题，可以将 chart 先在能连上 GitHub 的机器上下载下来，然后拷贝到 helm 命令所在机器上。

下载方法：

```bash showLineNumbers
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm fetch ingress-nginx/ingress-nginx
```

> 如果是下载指定版本的 chart，给 fetch 子命令加 `--version` 参数指定即可，如：`helm fetch ingress-nginx/ingress-nginx --version 4.7.5`

查看下载的 chart 包:

```bash
$ ls
ingress-nginx-4.11.2.tgz
```

将这个压缩包拷贝到 helm 命令所在机器上，安装命令将 chart 名称替换成压缩包文件路径即可：

```bash showLineNumbers
helm upgrade --install ingress-nginx ingress-nginx-4.11.2.tgz \
  --namespace ingress-nginx --create-namespace \
  -f values.yaml
```

## 版本与升级

Nginx Ingress 的版本需要与 Kubernetes 集群版本能够兼容，可参考官方 [Supported Versions table](https://github.com/kubernetes/ingress-nginx?tab=readme-ov-file#supported-versions-table) 确认下当前集群版本能否支持最新的 nginx ingress，如果不支持，安装的时候指定下 chart 版本。

比如当前的 TKE 集群版本是 1.24，chart 版本最高只能到 `4.7.*`，通过以下命令检查有哪些可用版本：

```bash
$ helm search repo ingress-nginx/ingress-nginx --versions | grep 4.7.
ingress-nginx/ingress-nginx     4.7.5           1.8.5           Ingress controller for Kubernetes using NGINX a...
ingress-nginx/ingress-nginx     4.7.3           1.8.4           Ingress controller for Kubernetes using NGINX a...
ingress-nginx/ingress-nginx     4.7.2           1.8.2           Ingress controller for Kubernetes using NGINX a...
ingress-nginx/ingress-nginx     4.7.1           1.8.1           Ingress controller for Kubernetes using NGINX a...
ingress-nginx/ingress-nginx     4.7.0           1.8.0           Ingress controller for Kubernetes using NGINX a...
```

可以看到 `4.7.*` 版本最高是 `4.7.5`，安装的时候加上版本号：

```bash showLineNumbers
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  # highlight-next-line
  --version 4.7.5 \
  -f values.yaml
```

:::info[注意]

TKE 集群升级前，先检查当前 Nginx Ingress 版本能否兼容升级后的集群版本，如果不能兼容，先升级 Nginx Ingress（用上面的命令指定 chart 版本号）。

:::

## 使用 Ingress

Nginx Ingress 实现了 Kubernetes 的 Ingress API 定义的标准能力，Ingress 的基础用法可参考 [Kubernetes 官方文档](https://kubernetes.io/docs/concepts/services-networking/ingress/)。

创建 Ingress 时必须指定 `ingressClassName` 为 Nginx Ingress 实例所使用的 IngressClass（默认为 `nginx`）:

```yaml showLineNumbers
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx
spec:
  # highlight-next-line
  ingressClassName: nginx
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nginx
                port:
                  number: 80
```

除此之外，Nginx Ingress 还有很多其它特有的功能，通过 Ingress 注解来扩展 Ingress 的功能，参考 [Nginx Ingress Annotations](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/) 。

## 更多自定义

如果需要对 Nginx Ingress 进行更多的自定义，可参考接下来的几篇指引文档，根据自己需求合并下 `values.yaml` 配置，最后一篇也提供了合并后的 `values.yaml` 完整配置示例。

另外你也可以将 `values.yaml` 拆成多个文件维护，执行安装或更新命令时，用多个 `-f` 参数指定下多个配置文件即可：

```bash showLineNumbers
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  # highlight-start
  -f image-values.yaml \
  -f prom-values.yaml \
  -f logrotate-values.yaml \
  -f autoscaling-values.yaml
  # highlight-end
```


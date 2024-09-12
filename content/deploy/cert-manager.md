# 在 TKE 上安装 cert-manager

## 安装方法

cert-manager 的安装可参考官方文档 [Installing with Helm](https://cert-manager.io/docs/installation/helm/) 进行安装，但 cert-manager 依赖的镜像地址域名是 `quay.io`，在国内一般会拉取镜像失败。

解决方案是将镜像地址替换为 Docker Hub 上的 mirror 镜像（TKE 环境无需任何配置即可走内网拉取 DockerHub 上的镜像）：

| 原始镜像地址                                  | DockerHub mirror 镜像地址                                                                                                        |
| --------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| quay.io/jetstack/cert-manager-controller      | [docker.io/imroc/cert-manager-controller](https://hub.docker.com/repository/docker/imroc/cert-manager-controller/tags)           |
| quay.io/jetstack/cert-manager-cainjector      | [docker.io/imroc/cert-manager-cainjector](https://hub.docker.com/repository/docker/imroc/cert-manager-cainjector/tags)           |
| quay.io/jetstack/cert-manager-webhook         | [docker.io/imroc/cert-manager-webhook](https://hub.docker.com/repository/docker/imroc/cert-manager-webhook/tags)                 |
| quay.io/jetstack/cert-manager-acmesolver      | [docker.io/imroc/cert-manager-acmesolver](https://hub.docker.com/repository/docker/imroc/cert-manager-acmesolver/tags)           |
| quay.io/jetstack/cert-manager-startupapicheck | [docker.io/imroc/cert-manager-startupapicheck](https://hub.docker.com/repository/docker/imroc/cert-manager-startupapicheck/tags) |

:::tip[说明]

cert-manager 的 mirror 镜像均使用 [image-porter](https://github.com/imroc/image-porter) 长期自动同步，可放心安装和升级。

:::

## 安装步骤

1. 添加 helm repo:

```bash
helm repo add jetstack https://charts.jetstack.io --force-update
```

2. 准备 `values.yaml`:

```yaml showLineNumbers title="values.yaml"
crds:
  enabled: true
webhook:
  image:
    repository: docker.io/imroc/cert-manager-webhook
cainjector:
  image:
    repository: docker.io/imroc/cert-manager-cainjector
acmesolver:
  image:
    repository: docker.io/imroc/cert-manager-acmesolver
startupapicheck:
  image:
    repository: docker.io/imroc/cert-manager-startupapicheck
image:
  repository: docker.io/imroc/cert-manager-controller
```

3. 安装：

```bash
helm upgrade --install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  -f values.yaml
```

> 后续如果需要修改 `values.yaml` 配置，或者升级版本，都可以通过执行这个命令来更新 cert-manager。

## 验证

查看 pod 状态：

```bash
$ kubectl -n cert-manager get pod
NAME                                           READY   STATUS    RESTARTS   AGE
cert-manager-774c68d885-db59h                  1/1     Running   0          23s
cert-manager-cainjector-56c45955bc-zdzmd       1/1     Running   0          23s
cert-manager-webhook-79958f7fd5-vjlt9          1/1     Running   0          23s
```

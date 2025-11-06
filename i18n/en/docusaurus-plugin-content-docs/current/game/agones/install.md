# 在 TKE 安装 Agones

## 安装方法

可参考 Agones 的官方文档 [Install Agones using Helm](https://agones.dev/site/docs/installation/install-agones/helm/) 进行安装，但 Agones 依赖的镜像地址域名是 `us-docker.pkg.dev`，在国内一般会拉取镜像失败。

解决方案是将镜像地址替换为 Docker Hub 上的 mirror 镜像（TKE 环境无需任何配置即可走内网拉取 DockerHub 上的镜像）：

| 原始镜像地址                                              | DockerHub mirror 镜像地址                                                                                                |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| us-docker.pkg.dev/agones-images/release/agones-allocator  | [docker.io/k8smirror/agones-allocator](https://hub.docker.com/repository/docker/k8smirror/agones-allocator/tags?ordering=name)   |
| us-docker.pkg.dev/agones-images/release/agones-controller | [docker.io/k8smirror/agones-controller](https://hub.docker.com/repository/docker/k8smirror/agones-controller/tags?ordering=name) |
| us-docker.pkg.dev/agones-images/release/agones-extensions | [docker.io/k8smirror/agones-extensions](https://hub.docker.com/repository/docker/k8smirror/agones-extensions/tags?ordering=name) |
| us-docker.pkg.dev/agones-images/release/agones-ping       | [docker.io/k8smirror/agones-ping](https://hub.docker.com/repository/docker/k8smirror/agones-ping/tags?ordering=name)             |
| us-docker.pkg.dev/agones-images/release/agones-sdk        | [docker.io/k8smirror/agones-sdk](https://hub.docker.com/repository/docker/k8smirror/agones-sdk/tags?ordering=name)               |

:::tip[说明]

Agones 的 mirror 镜像均使用 [image-porter](https://github.com/k8smirror/image-porter) 长期自动同步，可放心安装和升级。

:::

## 安装步骤

1. 添加 helm repo:

```bash
helm repo add agones https://agones.dev/chart/stable --force-update
```

2. 安装：

```bash
helm upgrade --install agones agones/agones \
  --namespace agones-system --create-namespace \
  --set agones.image.registry=docker.io/k8smirror
```

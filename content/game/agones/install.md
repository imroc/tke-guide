# 在 TKE 安装 Agones

## 安装方法

可参考 Agones 的官方文档 [Install Agones using Helm](https://agones.dev/site/docs/installation/install-agones/helm/) 进行安装，但 Agones 依赖的镜像地址域名是 `us-docker.pkg.dev`，在国内一般会拉取镜像失败。

解决方案是将镜像地址替换为 Docker Hub 上的 mirror 镜像（TKE 环境无需任何配置即可走内网拉取 DockerHub 上的镜像）：

| 原始镜像地址                                              | DockerHub mirror 镜像地址                                                                                  |
| --------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| us-docker.pkg.dev/agones-images/release/agones-allocator  | [docker.io/imroc/agones-allocator](https://hub.docker.com/repository/docker/imroc/agones-allocator/tags)   |
| us-docker.pkg.dev/agones-images/release/agones-controller | [docker.io/imroc/agones-controller](https://hub.docker.com/repository/docker/imroc/agones-controller/tags) |
| us-docker.pkg.dev/agones-images/release/agones-extensions | [docker.io/imroc/agones-extensions](https://hub.docker.com/repository/docker/imroc/agones-extensions/tags) |
| us-docker.pkg.dev/agones-images/release/agones-ping       | [docker.io/imroc/agones-ping](https://hub.docker.com/repository/docker/imroc/agones-ping/tags)             |
| us-docker.pkg.dev/agones-images/release/agones-sdk        | [docker.io/imroc/agones-sdk](https://hub.docker.com/repository/docker/imroc/agones-sdk/tags)               |

:::tip[说明]

Agones 的 mirror 镜像均使用 [image-porter](https://github.com/imroc/image-porter) 长期自动同步，可放心安装和升级。

:::

## 安装步骤

1. 添加 helm repo:

```bash
helm repo add agones https://agones.dev/chart/stable --force-update
```

2. 准备 `values.yaml` 配置：


```yaml
agones:
  image:
    registry: docker.io/imroc
```

3. 安装：

```bash
helm upgrade --install \
  agones agones/agones \
  --namespace agones-system --create-namespace \
  -f values.yaml
```
> 后续如果需要修改 `values.yaml` 配置，或者升级版本，都可以通过执行这个命令来更新 agones。

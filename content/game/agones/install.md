# 在 TKE 安装 Agones

## 使用 Helm 安装

参考 Agones 的官方安装文档：[Install Agones using Helm](https://agones.dev/site/docs/installation/install-agones/helm/)。

> Agones 依赖的镜像在国内环境拉取不到 (`us-docker.pkg.dev`)，会导致镜像拉取失败。好在依赖的镜像也有在 DockerHub 上的 mirror，而 TKE 环境无需任何配置就可以拉取 DockerHub 上的镜像，所以可以在安装 Agones 前需配置下替换镜像地址。

准备 `values.yaml` 配置：

```yaml
agones:
  image:
    registry: docker.io/imroc
```

安装：

```bash
helm repo add agones https://agones.dev/chart/stable
helm repo update
helm upgrade --install agones --namespace agones-system --create-namespace -f values.yaml agones/agones
```

> 后续修改 `values.yaml` 配置或升级 agones 时，都只需重新执行最后一条命令。

## 附录：DockerHub Mirror

以下是 Agones 依赖的镜像及其在 DockerHub 上自动同步的 mirror 镜像对照表：

| 原始镜像地址                                              | DockerHub mirror 镜像地址         |
| --------------------------------------------------------- | --------------------------------- |
| us-docker.pkg.dev/agones-images/release/agones-allocator  | docker.io/imroc/agones-allocator  |
| us-docker.pkg.dev/agones-images/release/agones-controller | docker.io/imroc/agones-controller |
| us-docker.pkg.dev/agones-images/release/agones-extensions | docker.io/imroc/agones-extensions |
| us-docker.pkg.dev/agones-images/release/agones-ping       | docker.io/imroc/agones-ping       |
| us-docker.pkg.dev/agones-images/release/agones-sdk        | docker.io/imroc/agones-sdk        |

:::tip[说明]

Agones 的 mirror 镜像均使用 [image-porter](https://github.com/imroc/image-porter) 长期自动同步，可放心安装和升级。

:::

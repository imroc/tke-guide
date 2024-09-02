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

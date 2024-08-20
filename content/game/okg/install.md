# 在 TKE 安装 OpenKruiseGame

## 安装说明

[OpenKruiseGame](https://openkruise.io/zh/kruisegame/introduction) 及其依赖的 [OpenKruise](https://openkruise.io/zh/docs/)，它们的镜像都在 DockerHub，而在 TKE 环境是无需任何配置就能直接拉取 DockerHub 镜像的，所以可以在 TKE 上安装 `OpenKruiseGame` 并无特殊之处，直接按照 [官方安装文档](https://openkruise.io/zh/kruisegame/installation/) 进行安装即可。

## 前提条件

安装前先确保满足以下前提条件：
1. 创建了 [TKE](https://cloud.tencent.com/product/tke) 集群，且集群版本大于等于 1.18。
2. 本地安装了 [helm](https://helm.sh) 命令，且能通过 helm 命令操作 TKE 集群（参考[本地 Helm 客户端连接集群](https://cloud.tencent.com/document/product/457/32731)）。

## 安装 Kruise 与 Kruise-Game

参考 [官方安装文档](https://openkruise.io/zh/kruisegame/installation/) 进行安装。

## 常见问题: helm 命令所在环境连不上 github 怎么办？

使用 helm 命令安装时，依赖托管在 github 上的 helm repo，如果 helm 命令所在环境连不上 github，会导致安装失败。

如果不能解决 helm 所在机器的网络问题，可以尝试在能连上 github 的机器上执行 helm 命令将依赖的 chart 包下载下来：

```bash
$ helm repo add openkruise https://openkruise.github.io/charts/
$ helm fetch openkruise/kruise
$ helm fetch openkruise/kruise-game
$ ls kruise-*.tgz
kruise-1.6.3.tgz  kruise-game-0.8.0.tgz
```
然后将下载到的 `tgz` 压缩包拷贝到原来 helm 命令所在机器上，再执行 helm 命令安装：

```bash
helm install kruise kruise-1.6.3.tgz
helm install kruise-game kruise-game-0.8.0.tgz
```

> 注意替换文件名。

# 在 TKE 安装 OpenKruiseGame

## 安装方式

两种方式：
1. 通过 TKE 应用市场安装，优势是简单方便，直接在控制台点点点就可以安装。
2. 通过 OKG 官方提供的 helm 命令方式安装。优势是版本跟进及时，还可通过 GitOps 方式进行安装和管理（如ArgoCD），更灵活。

## 通过 TKE 应用市场安装

在 [TKE 应用市场](https://console.cloud.tencent.com/tke2/helm) 中搜索 `kruise`, 可以看到 `kruise` 和 `kruise-game`, 将它们安装到集群中即可。

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F12%2F26%2F20241226161254.png)

## 通过 helm 安装

[OpenKruiseGame](https://openkruise.io/zh/kruisegame/introduction) 及其依赖的 [OpenKruise](https://openkruise.io/zh/docs/)，它们的镜像都在 DockerHub，而在 TKE 环境是无需任何配置就能直接拉取 DockerHub 镜像的，所以可以在 TKE 上安装 `OpenKruiseGame` 并无特殊之处，直接按照 [官方安装文档](https://openkruise.io/zh/kruisegame/installation/) 进行安装即可。

### 前提条件

安装前先确保满足以下前提条件：
1. 创建了 [TKE](https://cloud.tencent.com/product/tke) 集群，且集群版本大于等于 1.18。
2. 本地安装了 [helm](https://helm.sh) 命令，且能通过 helm 命令操作 TKE 集群（参考[本地 Helm 客户端连接集群](https://cloud.tencent.com/document/product/457/32731)）。

### 安装 Kruise 与 Kruise-Game

参考 [官方安装文档](https://openkruise.io/zh/kruisegame/installation/) 进行安装。

### helm 命令所在环境连不上 github 怎么办？

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

### kruise-game-controller-manager 报错 client-side throttling

使用默认配置在 TKE 安装 `OpenKruiseGame` 的时候（v0.8.0），`kruise-game-controller-manager` 的 Pod 可能会起不来：

```log
I0708 03:28:11.315405       1 request.go:601] Waited for 1.176544858s due to client-side throttling, not priority and fairness, request: GET:https://172.16.128.1:443/apis/operators.coreos.com/v1alpha2?timeout=32s
I0708 03:28:21.315900       1 request.go:601] Waited for 11.176584459s due to client-side throttling, not priority and fairness, request: GET:https://172.16.128.1:443/apis/install.istio.io/v1alpha1?timeout=32s
```

是因为 `OpenKruiseGame` 的 helm chart 包中，默认的本地 APIServer 限速太低 (`values.yaml`):

```yaml
kruiseGame:
  apiServerQps: 5
  apiServerQpsBurst: 10
```

可以改高点：

```yaml
kruiseGame:
  apiServerQps: 50
  apiServerQpsBurst: 100
```

## 安装 tke-extend-network-controller 网络插件

如需使用 OKG 的 [TencentCloud-CLB](https://openkruise.io/zh/kruisegame/user-manuals/network#tencentcloud-clb) 网络接入，还需确保安装了 `tke-extend-network-controller` 和 `cert-manager` 这两个组件，

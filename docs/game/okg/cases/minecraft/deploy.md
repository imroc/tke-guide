# 快速部署

## 安装 OpenKruiseGame

在 TKE 上安装 OpenKruiseGame 并无特殊之处，可直接参考 [OpenKruiseGame 官方安装文档](https://openkruise.io/zh/kruisegame/installation) 进行安装。

本人使用默认配置安装 OpenKruiseGame 的时候（v0.8.0），`kruise-game-controller-manager` 的 Pod 起不来：

```log
I0708 03:28:11.315405       1 request.go:601] Waited for 1.176544858s due to client-side throttling, not priority and fairness, request: GET:https://172.16.128.1:443/apis/operators.coreos.com/v1alpha2?timeout=32s
I0708 03:28:21.315900       1 request.go:601] Waited for 11.176584459s due to client-side throttling, not priority and fairness, request: GET:https://172.16.128.1:443/apis/install.istio.io/v1alpha1?timeout=32s
```

是因为 OpenKruiseGame 的 helm chart 包中，默认的本地 APIServer 限速太低 (`values.yaml`):

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

## minecrafter-server 容器镜像

[docker-minecraft-server](https://github.com/itzg/docker-minecraft-server) 是我的世界这款游戏的服务端容器镜像的开源项目，可以部署在 Kubernetes 上。该镜像托管在 DockerHub 上，在 TKE 环境可以直接拉取，下面将会使用这个镜像进行部署。

## 使用 GameServerSet 部署 minecraft

```yaml
apiVersion: game.kruise.io/v1alpha1
kind: GameServerSet
metadata:
  name: minecraft
spec:
  replicas: 3
  updateStrategy:
    rollingUpdate:
      podUpdatePolicy: InPlaceIfPossible
  gameServerTemplate:
    spec:
      volumes:
        - name: script
          configMap:
            name: minecraft-script
            defaultMode: 0755
      containers:
        - image: itzg/minecraft-server:latest
          name: minecraft
          env:
            - name: EULA
              value: "TRUE"
            - name: ONLINE_MODE
              value: "FALSE"
```

* `EULA` 需要显式置为 `TRUE`，表示同意微软的条款。
* 如果不买正版 minecraft 来连游戏服，可将 `ONLINE_MODE` 需要置为 `FALSE`，可跳过微软的玩家认证。

## 参考资料

* [KruiseGame用户手册：部署游戏服](https://openkruise.io/zh/kruisegame/user-manuals/deploy-gameservers)

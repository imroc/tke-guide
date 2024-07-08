# 自定义游戏服状态

## 概述

游戏是有状态服务，OpenKruiseGame 允许定义游戏服的状态，开发者可以根据不同游戏服状态去设置对应的处理动作。比如在滚动更新时，需要等待游戏服空闲后(没有玩家在该服的房间内)再删除 Pod。

## 探测脚本

[docker-minecraft-server](https://github.com/itzg/docker-minecraft-server) 的容器镜像中提供了 `mc-health` 这个脚本，执行它可以探测 minecraft-server 的状态，其中包含在线玩家数量的统计：

```bash
$ mc-health
localhost:25565 : version=1.21 online=1 max=20 motd='A Minecraft Server'
```

我们可以再写个脚本包一层用来探测游戏服是否空闲，检测到 `online=0` 时，返回 0 退出码，表示游戏服空闲:

```bash title="idle.sh"
#!/bin/bash

result=$(mc-health | grep "online=0")

if [ "$result" != "" ]; then
  exit 0
fi

exit 1
```

最终需要将这个脚本放到 `ConfigMap` 中去，如果你使用 `kustomize` 部署，可以在 `kustomization.yaml` 中用 `configMapGenerator` 来引用该脚本文件生成对应的 `ConfigMap`:

```yaml title="kustomization.yaml"
configMapGenerator:
  - name: minecraft-script
    options:
      disableNameSuffixHash: true
    files:
      - idle.sh
```

## 在 GameServerSet 自定义服务质量

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
    volumeClaimTemplates:
      - metadata:
          name: minecraft
        spec:
          accessModes: ["ReadWriteOnce"]
          storageClassName: minecraft
          resources:
            requests:
              storage: 20Gi
    spec:
      # highlight-start
      volumes: # 引用 idle.sh 脚本文件的 ConfigMap
        - name: script
          configMap:
            name: minecraft-script
            defaultMode: 0755
      # highlight-end
      containers:
        - image: itzg/minecraft-server:latest
          name: minecraft
          volumeMounts:
            # highlight-start
            - name: script # 挂载 idle.sh 脚本文件
              mountPath: /idle.sh
              subPath: idle.sh
            # highlight-end
            - name: minecraft
              mountPath: /data
          env:
            - name: EULA
              value: "TRUE"
            - name: ONLINE_MODE
              value: "FALSE"
  # highlight-start
  serviceQualities:
    - name: idle
      containerName: minecraft
      permanent: false
      exec:
        command: ["bash", "/idle.sh"] # 用 idle.sh 探测来决定 opsState
      serviceQualityAction:
        - state: true
          opsState: WaitToBeDeleted # 当 idle.sh 返回 0 时，将 opsState 设置为 WaitToBeDeleted，滚动更新时检测到此状态才删除 Pod，实现“空闲时升级游戏服”
        - state: false
          opsState: None
  # highlight-end
```

## 测试并观察 opsState

我们用客户端连接游戏服后，执行以下命令可查看各个游戏服务的 `opsState`:

```bash
$ kubectl get gameserver
NAME          STATE   OPSSTATE          DP    UP    AGE
minecraft-0   Ready   WaitToBeDeleted   0     0     68m
minecraft-1   Ready   None              0     0     69m
minecraft-2   Ready   WaitToBeDeleted   0     0     70m
```

> 其中为 `None` 的表示有玩家正在该服游戏，`WaitToBeDeleted` 表示该服没有玩家，可以升级。

## 参考资料

* [KruiseGame用户手册：自定义服务质量](https://openkruise.io/zh/kruisegame/user-manuals/service-qualities)

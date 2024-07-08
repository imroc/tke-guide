# 游戏数据持久化

## 概述

minecraft-server 的数据存储在 `/data` 路径，我们可以通过为该路径挂盘来实现将游戏数据持久化存储。

## 创建 StorageClass

在 TKE 上持久化游戏数据可以 CBS（云硬盘），先创建一个 StorageClass：

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: minecraft
parameters:
  diskChargeType: POSTPAID_BY_HOUR
  diskType: CLOUD_HSSD # 高性能SSD
allowVolumeExpansion: true
provisioner: com.tencent.cloud.csi.cbs
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer # 等 Pod 第一次调度后再创建 CBS，避免 Pod 与 CBS 不在同一可用区导致无法绑定
```

## 在 GameServerSet 中声明 volume 并挂载

```yaml showLineNumbers
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
    # highlight-start
    volumeClaimTemplates:
      - metadata:
          name: minecraft
        spec:
          accessModes: ["ReadWriteOnce"]
          storageClassName: minecraft
          resources:
            requests:
              storage: 20Gi
    # highlight-end
    spec:
      containers:
        - image: itzg/minecraft-server:latest
          name: minecraft
          volumeMounts:
            # highlight-start
            - name: minecraft
              mountPath: /data
            # highlight-end
          env:
            - name: EULA
              value: "TRUE"
            - name: ONLINE_MODE
              value: "FALSE"
```


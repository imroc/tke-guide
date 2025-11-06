# Game Data Persistence

## Overview

minecraft-server data is stored in the `/data` path. We can mount a disk to this path to achieve persistent storage of game data.

## Creating StorageClass

To persist game data on TKE, you can use CBS (Cloud Block Storage). First create a StorageClass:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: minecraft
parameters:
  diskChargeType: POSTPAID_BY_HOUR
  diskType: CLOUD_HSSD # High-Performance SSD
allowVolumeExpansion: true
provisioner: com.tencent.cloud.csi.cbs
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer # Create CBS after the first Pod scheduling to avoid Pod and CBS being in different availability zones and unable to bind
```

## Declaring and Mounting Volume in GameServerSet

Focus on the highlighted sections:

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

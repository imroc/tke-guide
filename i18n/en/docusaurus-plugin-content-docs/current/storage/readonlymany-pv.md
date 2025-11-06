---
sidebar_position: 3
---

# Methods for Defining ReadOnlyMany Storage

## Overview

The prerequisite for implementing `ReadOnlyMany` (multi-machine read-only) is that the backend storage is shared storage. In Tencent Cloud, there are two types of shared storage: `COS` (Cloud Object Storage) and `CFS` (Cloud File Storage). This article describes how to define these two shared storage types as PVs for use in Tencent Cloud Container Service environments.

## COS

1. Specify `accessModes` as `ReadOnlyMany`.
2. Specify `-oro` in `csi.volumeAttributes.additional_args`.

YAML example:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: registry
spec:
  accessModes:
  - ReadOnlyMany
  capacity:
    storage: 1Gi
  csi:
    readOnly: true
    driver: com.tencent.cloud.csi.cosfs
    volumeHandle: registry
    volumeAttributes:
      additional_args: "-oro"
      url: "http://cos.ap-chengdu.myqcloud.com"
      bucket: "roc-**********"
      path: /test
    nodePublishSecretRef:
      name: cos-secret
      namespace: kube-system
```

## CFS

1. Specify `accessModes` as `ReadOnlyMany`.
2. Specify `ro` in `mountOptions`.

YAML example:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: test
spec:
  accessModes:
  - ReadOnlyMany
  capacity:
    storage: 10Gi
  storageClassName: cfs
  persistentVolumeReclaimPolicy: Retain
  volumeMode: Filesystem
  mountOptions:
  - ro
  csi:
    driver: com.tencent.cloud.csi.cfs
    volumeAttributes:
      host: 10.10.99.99
      path: /test
    volumeHandle: cfs-********
```
---
sidebar_position: 1
---

# Expanding CBS Type PVCs

## Overview

In TKE, PVCs are typically used to declare storage capacity and type, automatically bind PVs, and mount them to Pods. Cloud Block Storage (CBS) is commonly used. When CBS disk capacity becomes insufficient, how do you expand it? This article details two scenarios.

## Expansion Methods

If the TKE cluster version is 1.20 or above, the CSI plugin is definitely used. If below 1.20, but the CBS CSI extension component is installed, and the PVC references a CBS CSI type StorageClass with online expansion capability enabled, then you can directly modify the PVC capacity to automatically expand the PV capacity.

## How to Enable Online Expansion?

Since CBS CSI plugin expansion of PVCs is too simple (just one step of modifying PVC capacity), let's first explain how to ensure PVCs can be expanded online.

1. First, the `StorageClass` needs to enable the online expansion option:

<Tabs>
  <TabItem value="1" label="Enable via Console">

  If creating StorageClass via console, ensure 【Enable Online Expansion】 is checked (enabled by default):
  ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2023%2F09%2F25%2F20230925162024.png)

  </TabItem>
  <TabItem value="2" label="Enable via YAML">

  If using YAML to create, ensure `allowVolumeExpansion` is set to true:

  ```yaml showLineNumbers
  # highlight-next-line
  allowVolumeExpansion: true # This is key
  apiVersion: storage.k8s.io/v1
  kind: StorageClass
  metadata:
    name: sc-test
  parameters:
    diskType: CLOUD_PREMIUM
  provisioner: com.tencent.cloud.csi.cbs
  reclaimPolicy: Delete
  volumeBindingMode: WaitForFirstConsumer
  ```

  </TabItem>
</Tabs>

2. Then when creating PVC, remember to select a CBS CSI type StorageClass that has online expansion enabled:

<Tabs>
  <TabItem value="1" label="Create PVC via Console">

  ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2023%2F09%2F25%2F20230925162035.png)

  </TabItem>

  <TabItem value="2" label="Create PVC via YAML">

  ```yaml showLineNumbers
  apiVersion: v1
  kind: PersistentVolumeClaim
  metadata:
    name: data
    namespace: test
  spec:
    accessModes:
    - ReadWriteOnce
    resources:
      requests:
        storage: 10Gi
    # highlight-next-line
    storageClassName: sc-test
    volumeMode: Filesystem
  ```

  </TabItem>
</Tabs>

3. Finally, when you need to expand the PVC, directly modify the PVC capacity:

:::tip[Note]

After modification, the corresponding CBS disk capacity will automatically expand to the specified size (must be multiples of 10Gi). You can verify in the Cloud Disk console.

:::

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2023%2F09%2F25%2F20230925162045.png)

## FAQ

### Do I Need to Restart Pods?

You can expand without restarting pods, but in this case, the filesystem of the expanded cloud disk is mounted on the node. If there's frequent I/O, filesystem expansion errors may occur. To ensure filesystem stability, it's recommended to expand when the cloud disk filesystem is not mounted. You can scale Pod replicas to 0 or modify the PV to mark it with an invalid zone (`kubectl label pv pvc-xxx failure-domain.beta.kubernetes.io/zone=nozone`) to make Pods Pending after rebuild, then modify PVC capacity for online expansion, and finally restore Pods to Running to mount the expanded disk.

### How to Create a Safety Net for Expansion to Avoid Data Issues?

You can use snapshots to backup data before expansion to avoid data loss in case of expansion failure.
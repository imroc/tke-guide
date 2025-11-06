# 扩容 CBS 类型的 PVC

## 概述

TKE 中一般使用 PVC 来声明存储容量和类型，自动绑定 PV 并挂载到 Pod，通常都使用 CBS (云硬盘) 存储。当 CBS 的磁盘容量不够用了，如何进行扩容呢？分两种情况，本文会详细介绍。

## 扩容方法

如果 TKE 集群版本在 1.20 及其以上版本，一定是用的 CSI 插件；如果低于 1.20，安装了 CBS CSI 扩展组件，且 PVC 引用的 StorageClass 是 CBS CSI 类型的，开启了在线扩容能力，那么就可以直接修改 PVC 容量实现自动扩容 PV 的容量。

## 如何开启在线扩容？

所以 CBS CSI 插件扩容 PVC 过于简单，只有修改 PVC 容量一个步骤，这里就先讲下如何确保 PVC 能够在线扩容。

1. 首先需要 `StorageClass` 启用在线扩容的选项：

<Tabs>
  <TabItem value="1" label="通过控制台开启">

  如果用控制台创建 StorageClass ，确保勾选 【启用在线扩容】（默认就会勾选）:
  ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2023%2F09%2F25%2F20230925162024.png)

  </TabItem>
  <TabItem value="2" label="通过 YAML 开启">

  如果使用 YAML 创建，确保将 `allowVolumeExpansion` 设为 true:

  ```yaml showLineNumbers
  # highlight-next-line
  allowVolumeExpansion: true # 这里是关键
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


2. 然后在创建 PVC 时记得选择 CBS CSI 类型且开启了在线扩容的 StorageClass:

<Tabs>
  <TabItem value="1" label="通过控制台创建 PVC">

  ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2023%2F09%2F25%2F20230925162035.png)

  </TabItem>

  <TabItem value="2" label="通过 YAML 创建 PVC">

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


3. 最后当需要扩容 PVC 的时候，直接修改 PVC 的容量即可：

:::tip[说明]

修改完后对应的 CBS 磁盘容量会自动扩容到指定大小 (注意必须是 10Gi 的倍数)，可以自行到云硬盘控制台确认。

:::

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2023%2F09%2F25%2F20230925162045.png)

## FAQ

### 需要重启 Pod 吗?

可以不重启 pod 直接扩容，但，这种情况下被扩容的云盘的文件系统被 mount 在节点上，如果有频繁 I/O 的话，有可能会出现文件系统扩容错误。为了确保文件系统的稳定性，还是推荐先让云盘文件系统处于未 mount 情况下进行扩容，可以将 Pod 副本调为 0 或修改 PV 打上非法的 zone (`kubectl label pv pvc-xxx failure-domain.beta.kubernetes.io/zone=nozone`) 让 Pod 重建后 Pending，然后再修改 PVC 容量进行在线扩容，最后再恢复 Pod Running 以挂载扩容后的磁盘。

### 担心扩容导致数据出问题，如何兜底?

可以在扩容前使用快照来备份数据，避免扩容失败导致数据丢失。


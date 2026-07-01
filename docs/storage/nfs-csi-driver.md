# 使用 NFS CSI Driver 挂载外部 NFS 存储

## 背景

TKE 集群中如需使用 NFS 类型的共享存储，推荐方案取决于 NFS 来源：

- **本 VPC 下的腾讯云 CFS**：直接安装 [CFS 扩展组件](https://cloud.tencent.com/document/product/457/44233)，使用 CFS CSI Driver (`com.tencent.cloud.csi.cfs`) 挂载，支持动态创建、自动扩容等高级特性。
- **非 CFS 提供的 NFS 存储**（如自建 NFS 服务器、跨 VPC 甚至跨账号网络互通的对端 CFS）：需使用 [NFS CSI Driver](https://github.com/kubernetes-csi/csi-driver-nfs) (`nfs.csi.k8s.io`)。这是社区维护的通用 NFS CSI 驱动，不依赖节点宿主机的 `mount.nfs` 工具，兼容性好。

本文介绍在 TKE 集群中部署 NFS CSI Driver 并挂载外部 NFS 存储的实践方法。

:::caution[超级节点限制]

NFS CSI Driver 的 DaemonSet 需要运行在每个节点上，而超级节点是虚拟节点（每个 Pod 独占轻量虚机），不是传统的 Node 模型，无法运行 DaemonSet，因此 **NFS CSI Driver 方案不适用于超级节点**。

如果需要在超级节点上挂载 NFS 存储，可尝试使用 K8s 自带的 [in-tree NFS 插件](https://kubernetes.io/docs/concepts/storage/volumes/#nfs)（PV 的 `spec.nfs` 字段），但需要 Pod 所在的轻量虚机内自带 `mount.nfs` 工具，实际可用性取决于超级节点的 VM 镜像。

:::

## 为什么需要 CSI Driver？

K8s 原生的 in-tree NFS 插件（PV `spec.nfs` 字段）通过在节点上直接执行 `mount -t nfs` 命令来挂载 NFS 存储，这要求节点宿主机安装了 NFS 客户端工具（如 `nfs-common` 或 `nfs-utils`）。

TKE 集群的节点操作系统（如 Ubuntu 24.04、TencentOS Server 4 等）默认可能未安装 NFS 客户端工具，导致 in-tree NFS 插件挂载失败，报错如下：

```
MountVolume.SetUp failed for volume "xxx" : mount failed: exit status 32
Mounting command: mount
Mounting arguments: -t nfs 10.0.0.1:/data /var/lib/kubelet/pods/xxx/volumes/kubernetes.io~nfs/xxx
Output: mount: ...: bad option; for several filesystems (e.g. nfs, cifs) you might need a /sbin/mount.<type> helper program.
```

虽然可以手动在节点上安装 `nfs-common`（Ubuntu/Debian）或 `nfs-utils`（CentOS/RHEL），但这种方式存在维护成本：节点重建后需重新安装，且不同 OS 的包名不同。

NFS CSI Driver 通过在容器中自带 NFS 挂载工具来解决此问题，DaemonSet 中的 CSI 插件容器以特权模式运行，直接在容器内完成 NFS 挂载，不依赖宿主机的任何 NFS 工具。

## 部署 NFS CSI Driver

### 前置条件

- TKE 集群版本 >= 1.20
- 集群中有普通节点（非纯超级节点集群）

### 镜像准备

NFS CSI Driver 默认使用 `registry.k8s.io` 上的镜像，国内节点无法直接拉取。已有镜像同步到了 Docker Hub 的 `k8smirror` 组织下，TKE 节点可直接通过内网加速拉取，无需自行同步：

| 原始镜像 | k8smirror 同步镜像 |
|------|----------------|
| `registry.k8s.io/sig-storage/nfsplugin` | `docker.io/k8smirror/nfsplugin` |
| `registry.k8s.io/sig-storage/csi-provisioner` | `docker.io/k8smirror/csi-provisioner` |
| `registry.k8s.io/sig-storage/csi-resizer` | `docker.io/k8smirror/csi-resizer` |
| `registry.k8s.io/sig-storage/livenessprobe` | `docker.io/k8smirror/livenessprobe` |
| `registry.k8s.io/sig-storage/csi-node-driver-registrar` | `docker.io/k8smirror/csi-node-driver-registrar` |

:::tip[关于镜像拉取加速]

TKE 节点可通过内网加速拉取 Docker Hub 上的镜像，无需额外配置，本文使用的 `k8smirror` 镜像可直接拉取。

但需要注意，TKE 自带的 Docker Hub 加速**不提供 SLA，速度也无法保障**。生产环境建议将镜像同步到自己的 TCR 镜像仓库，以获得更稳定的镜像拉取体验。可使用 `skopeo` 工具同步：

```bash
skopeo copy -a docker://docker.io/k8smirror/nfsplugin:v4.13.3 docker://your-repo/nfsplugin:v4.13.3
```

:::

### 使用 Helm Chart 部署

官方提供了 Helm Chart，推荐使用此方式部署。使用预同步的 `k8smirror` 镜像，TKE 集群可直接一键安装：

```bash
# 添加 Helm 仓库
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm repo update

# 一键部署（使用 k8smirror 镜像）
helm upgrade --install csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
  --namespace kube-system \
  --set image.nfs.repository=docker.io/k8smirror/nfsplugin \
  --set image.csiProvisioner.repository=docker.io/k8smirror/csi-provisioner \
  --set image.csiResizer.repository=docker.io/k8smirror/csi-resizer \
  --set image.livenessProbe.repository=docker.io/k8smirror/livenessprobe \
  --set image.nodeDriverRegistrar.repository=docker.io/k8smirror/csi-node-driver-registrar \
  --set controller.enableSnapshotter=false
```

### 使用 Kustomize 部署

如果使用 GitOps（如 ArgoCD）管理集群配置，可通过 Kustomize 的 `helmCharts` 内联渲染 Helm Chart：

```yaml
# kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: kube-system

helmCharts:
- repo: https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
  name: csi-driver-nfs
  releaseName: csi-driver-nfs
  namespace: kube-system
  additionalValuesFiles:
  - values.yaml
  - image-values.yaml
```

```yaml
# values.yaml - 自定义配置
controller:
  enableSnapshotter: false  # 如不需要快照功能可关闭
```

```yaml
# image-values.yaml - 镜像替换（使用 k8smirror 预同步镜像）
image:
  nfs:
    repository: docker.io/k8smirror/nfsplugin
  csiProvisioner:
    repository: docker.io/k8smirror/csi-provisioner
  csiResizer:
    repository: docker.io/k8smirror/csi-resizer
  livenessProbe:
    repository: docker.io/k8smirror/livenessprobe
  nodeDriverRegistrar:
    repository: docker.io/k8smirror/csi-node-driver-registrar
```

### 验证部署

```bash
# 检查 Pod 是否正常运行
kubectl get pods -n kube-system -l app=csi-nfs-node
# 期望输出：每个普通节点一个 Pod，状态为 Running

# 检查 CSIDriver 是否注册
kubectl get csidriver nfs.csi.k8s.io
# 期望输出：NAME 存在，attachRequired 为 false

# 检查节点是否注册了 CSI 驱动
kubectl get csinode <node-name> -o jsonpath='{.spec.drivers[*].name}'
# 期望输出中包含 nfs.csi.k8s.io
```

## 挂载 NFS 存储

### 静态创建 PV/PVC

适用于已有 NFS 服务器和共享路径的场景，手动创建 PV 和 PVC 绑定到指定的 NFS 存储：

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-data
spec:
  accessModes:
  - ReadWriteMany
  capacity:
    storage: 10Gi
  csi:
    driver: nfs.csi.k8s.io
    volumeHandle: 10.0.0.1/data  # 唯一标识，通常用 <server>/<share> 格式
    volumeAttributes:
      server: 10.0.0.1    # NFS 服务器 IP
      share: /data         # NFS 共享路径
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  volumeMode: Filesystem
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-data
spec:
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 10Gi
  storageClassName: ""
  volumeMode: Filesystem
  volumeName: nfs-data  # 指定 PV 名称，手动绑定
```

关键参数说明：

| 参数 | 说明 |
|------|------|
| `csi.driver` | 固定为 `nfs.csi.k8s.io` |
| `csi.volumeHandle` | 全局唯一的卷标识，建议用 `<server>/<share>` 格式 |
| `csi.volumeAttributes.server` | NFS 服务器的 IP 地址或主机名 |
| `csi.volumeAttributes.share` | NFS 共享路径 |
| `storageClassName` | 必须设为空字符串 `""`，表示静态绑定 |
| `persistentVolumeReclaimPolicy` | 建议设为 `Retain`，防止误删 PV 时数据丢失 |

### 在 Pod 中使用

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        volumeMounts:
        - mountPath: /data
          name: data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: nfs-data
```

### 使用 StorageClass 动态创建

如果 NFS 服务器支持子目录创建（大多数 NFS 服务器都支持），可以使用 StorageClass 实现动态供给，每个 PVC 自动在 NFS 服务器上创建一个子目录：

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-csi
provisioner: nfs.csi.k8s.io
parameters:
  server: 10.0.0.1    # NFS 服务器 IP
  share: /data         # NFS 共享路径
  subDir: ${pvc.metadata.namespace}-${pvc.metadata.name}  # 子目录命名规则
reclaimPolicy: Delete
volumeBindingMode: Immediate
```

创建 PVC 时指定此 StorageClass 即可自动创建 PV 并挂载：

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dynamic-data
spec:
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 10Gi
  storageClassName: nfs-csi
```

## 从 in-tree NFS 迁移到 CSI

如果集群中已有使用 K8s 原生 in-tree NFS 插件（`spec.nfs`）的 PV，可按以下步骤迁移到 NFS CSI Driver：

:::warning[数据安全]

迁移过程不会删除 NFS 上的数据，但需要短暂停止使用该存储的 Pod。建议在业务低峰期操作。

:::

1. **确认 NFS CSI Driver 已部署**：参考前文「部署 NFS CSI Driver」。

2. **删除使用该 PV/PVC 的 Pod**（或将副本数缩为 0）。

3. **删除旧的 PV 和 PVC**（NFS 上的数据不受影响）：

```bash
# 移除 finalizer 避免 PVC 卡在 Terminating
kubectl patch pvc <pvc-name> -n <namespace> -p '{"metadata":{"finalizers":null}}'
kubectl patch pv <pv-name> -p '{"metadata":{"finalizers":null}}'

# 删除 PVC 和 PV
kubectl delete pvc <pvc-name> -n <namespace>
kubectl delete pv <pv-name>
```

4. **创建使用 CSI 的新 PV/PVC**：参考前文「静态创建 PV/PVC」，将 `spec.nfs` 替换为 `spec.csi`，保持 `server` 和 `share` 路径不变。

5. **恢复 Pod**：重新部署或扩容使用该 PVC 的 Pod，NFS 上的数据会原样挂载。

## 从 in-tree NFS 迁移示例

迁移前（in-tree NFS）：

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: data
spec:
  accessModes:
  - ReadWriteMany
  capacity:
    storage: 10Gi
  nfs:                    # in-tree NFS 插件
    path: /data
    server: 10.0.0.1
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
```

迁移后（NFS CSI）：

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: data
spec:
  accessModes:
  - ReadWriteMany
  capacity:
    storage: 10Gi
  csi:                    # NFS CSI Driver
    driver: nfs.csi.k8s.io
    volumeHandle: 10.0.0.1/data
    volumeAttributes:
      server: 10.0.0.1
      share: /data
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
```

只需将 `spec.nfs` 替换为 `spec.csi`，NFS 服务器的 IP 和共享路径保持不变，数据无需迁移。

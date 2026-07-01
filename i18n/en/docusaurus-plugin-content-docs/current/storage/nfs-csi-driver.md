# Mounting External NFS Storage with NFS CSI Driver

## Background

When you need to use NFS-type shared storage in a TKE cluster, the recommended approach depends on the NFS source:

- **Tencent Cloud CFS in the same VPC**: Install the [CFS extension component](https://cloud.tencent.com/document/product/457/44233) directly, and use the CFS CSI Driver (`com.tencent.cloud.csi.cfs`) for mounting. This supports advanced features like dynamic provisioning and auto-expansion.
- **Non-CFS NFS storage** (e.g., self-hosted NFS servers, or CFS from another VPC or account with network connectivity): Use the [NFS CSI Driver](https://github.com/kubernetes-csi/csi-driver-nfs) (`nfs.csi.k8s.io`). This is a community-maintained generic NFS CSI driver that does not depend on the host's `mount.nfs` utility and offers broad compatibility.

This guide covers deploying the NFS CSI Driver on a TKE cluster and mounting external NFS storage.

:::caution[Super Node Limitation]

The NFS CSI Driver runs as a DaemonSet on every node. Super Nodes are virtual nodes (each Pod occupies a lightweight VM), not traditional Node model, and cannot run DaemonSets. Therefore, **the NFS CSI Driver approach is not applicable to Super Nodes**.

If you need to mount NFS storage on Super Nodes, you can try the K8s built-in [in-tree NFS plugin](https://kubernetes.io/docs/concepts/storage/volumes/#nfs) (the `spec.nfs` field in PV), but this requires the `mount.nfs` utility to be present in the lightweight VM. Actual availability depends on the Super Node's VM image.

:::

## Why Do You Need a CSI Driver?

The K8s native in-tree NFS plugin (PV `spec.nfs` field) mounts NFS storage by directly executing the `mount -t nfs` command on the node, which requires the NFS client utilities (such as `nfs-common` or `nfs-utils`) to be installed on the host.

TKE cluster node operating systems (such as Ubuntu 24.04, TencentOS Server 4, etc.) may not have NFS client utilities installed by default, causing the in-tree NFS plugin to fail with an error like:

```
MountVolume.SetUp failed for volume "xxx" : mount failed: exit status 32
Mounting command: mount
Mounting arguments: -t nfs 10.0.0.1:/data /var/lib/kubelet/pods/xxx/volumes/kubernetes.io~nfs/xxx
Output: mount: ...: bad option; for several filesystems (e.g. nfs, cifs) you might need a /sbin/mount.<type> helper program.
```

While you could manually install `nfs-common` (Ubuntu/Debian) or `nfs-utils` (CentOS/RHEL) on the nodes, this approach has maintenance overhead: nodes need reinstallation after rebuild, and package names differ across OS distributions.

The NFS CSI Driver solves this by bundling NFS mount utilities within the container. The CSI plugin container in the DaemonSet runs in privileged mode and handles NFS mounting directly, without relying on any NFS utilities on the host.

## Deploying the NFS CSI Driver

### Prerequisites

- TKE cluster version >= 1.20
- The cluster has regular nodes (not a Super-Node-only cluster)

### Image Preparation

The NFS CSI Driver uses images from `registry.k8s.io` by default, which are not directly accessible from nodes in mainland China. Pre-synced images are available under the `k8smirror` organization on Docker Hub, which TKE nodes can pull via intranet acceleration:

| Image | Docker Hub Address |
|-------|-------------------|
| nfsplugin | `docker.io/k8smirror/nfsplugin` |
| csi-provisioner | `docker.io/k8smirror/csi-provisioner` |
| csi-resizer | `docker.io/k8smirror/csi-resizer` |
| livenessprobe | `docker.io/k8smirror/livenessprobe` |
| csi-node-driver-registrar | `docker.io/k8smirror/csi-node-driver-registrar` |

:::tip[About Image Pull Acceleration]

TKE nodes can pull Docker Hub images through intranet acceleration without additional configuration. The `k8smirror` images used in this guide can be pulled directly.

However, note that TKE's built-in Docker Hub acceleration **does not provide an SLA, and speed is not guaranteed**. For production environments, it is recommended to sync images to your own registry (such as TCR or CCR) for a more stable image pulling experience. You can use the `skopeo` tool to sync:

```bash
skopeo copy -a docker://docker.io/k8smirror/nfsplugin:v4.13.3 docker://your-repo/nfsplugin:v4.13.3
```

:::

### Deploying with Helm Chart

The official Helm Chart is the recommended deployment method. Using the pre-synced `k8smirror` images, TKE clusters can be installed with a single command:

```bash
# Add the Helm repository
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm repo update

# One-click deploy (using k8smirror images)
helm upgrade --install csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
  --namespace kube-system \
  --set image.nfs.repository=docker.io/k8smirror/nfsplugin \
  --set image.csiProvisioner.repository=docker.io/k8smirror/csi-provisioner \
  --set image.csiResizer.repository=docker.io/k8smirror/csi-resizer \
  --set image.livenessProbe.repository=docker.io/k8smirror/livenessprobe \
  --set image.nodeDriverRegistrar.repository=docker.io/k8smirror/csi-node-driver-registrar \
  --set controller.enableSnapshotter=false
```

### Deploying with Kustomize

If you use GitOps (such as ArgoCD) to manage cluster configurations, you can inline-render the Helm Chart through Kustomize's `helmCharts`:

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
# values.yaml - custom configuration
controller:
  enableSnapshotter: false  # Disable if snapshot functionality is not needed
```

```yaml
# image-values.yaml - image replacement (using k8smirror pre-synced images)
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

### Verifying the Deployment

```bash
# Check if Pods are running normally
kubectl get pods -n kube-system -l app=csi-nfs-node
# Expected output: one Pod per regular node, status Running

# Check if CSIDriver is registered
kubectl get csidriver nfs.csi.k8s.io
# Expected output: NAME exists, attachRequired is false

# Check if the CSI driver is registered on the node
kubectl get csinode <node-name> -o jsonpath='{.spec.drivers[*].name}'
# Expected output includes nfs.csi.k8s.io
```

## Mounting NFS Storage

### Static PV/PVC Creation

Suitable for scenarios where you already have an NFS server and share path. Manually create PV and PVC to bind to the specified NFS storage:

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
    volumeHandle: 10.0.0.1/data  # Unique identifier, typically <server>/<share> format
    volumeAttributes:
      server: 10.0.0.1    # NFS server IP
      share: /data         # NFS share path
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
  volumeName: nfs-data  # Specify PV name for manual binding
```

Key parameter descriptions:

| Parameter | Description |
|-----------|-------------|
| `csi.driver` | Fixed as `nfs.csi.k8s.io` |
| `csi.volumeHandle` | Globally unique volume identifier, recommended format: `<server>/<share>` |
| `csi.volumeAttributes.server` | NFS server IP address or hostname |
| `csi.volumeAttributes.share` | NFS share path |
| `storageClassName` | Must be set to empty string `""` for static binding |
| `persistentVolumeReclaimPolicy` | Recommended to set as `Retain` to prevent data loss from accidental PV deletion |

### Using in a Pod

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

### Dynamic Provisioning with StorageClass

If your NFS server supports subdirectory creation (most NFS servers do), you can use a StorageClass for dynamic provisioning. Each PVC automatically creates a subdirectory on the NFS server:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-csi
provisioner: nfs.csi.k8s.io
parameters:
  server: 10.0.0.1    # NFS server IP
  share: /data         # NFS share path
  subDir: ${pvc.metadata.namespace}-${pvc.metadata.name}  # Subdirectory naming rule
reclaimPolicy: Delete
volumeBindingMode: Immediate
```

Create a PVC referencing this StorageClass to automatically create a PV and mount it:

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

## Migrating from in-tree NFS to CSI

If your cluster already has PVs using the K8s native in-tree NFS plugin (`spec.nfs`), you can migrate to the NFS CSI Driver with the following steps:

:::warning[Data Safety]

The migration process does not delete data on the NFS server, but it does require briefly stopping Pods that use the storage. It is recommended to operate during off-peak hours.

:::

1. **Ensure NFS CSI Driver is deployed**: Refer to the "Deploying the NFS CSI Driver" section above.

2. **Delete Pods using the PV/PVC** (or scale replicas to 0).

3. **Delete the old PV and PVC** (data on NFS is not affected):

```bash
# Remove finalizers to prevent PVC from being stuck in Terminating
kubectl patch pvc <pvc-name> -n <namespace> -p '{"metadata":{"finalizers":null}}'
kubectl patch pv <pv-name> -p '{"metadata":{"finalizers":null}}'

# Delete PVC and PV
kubectl delete pvc <pvc-name> -n <namespace>
kubectl delete pv <pv-name>
```

4. **Create new PV/PVC using CSI**: Refer to "Static PV/PVC Creation" above, replacing `spec.nfs` with `spec.csi`, keeping the `server` and `share` paths unchanged.

5. **Restore Pods**: Redeploy or scale up Pods using the PVC. The NFS data will be mounted as-is.

## Migration Example

Before migration (in-tree NFS):

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
  nfs:                    # in-tree NFS plugin
    path: /data
    server: 10.0.0.1
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
```

After migration (NFS CSI):

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

Simply replace `spec.nfs` with `spec.csi`. The NFS server IP and share path remain unchanged — no data migration needed.

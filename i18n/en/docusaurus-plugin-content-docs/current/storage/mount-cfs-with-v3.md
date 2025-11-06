---
sidebar_position: 2
---

# Mounting CFS Using V3 Protocol

## Background

Tencent Cloud CFS (Cloud File Storage) supports both NFS V3 and V4 protocols. When mounting, if no protocol is specified, the client and server negotiate the version, which often defaults to NFS V4 protocol. However, using NFS V4 protocol with CFS currently has stability issues. It's recommended to explicitly specify using NFS V3 protocol for mounting.

This article describes how to explicitly specify using NFS V3 protocol for mounting in both TKE (Tencent Kubernetes Engine) and EKS (Elastic Kubernetes Service) clusters.

## Using CFS Plugin (TKE Clusters Only)

### StorageClass Auto-Creates CFS

If the TKE cluster has the CFS extension component installed, CFS storage can be automatically created and mounted. When creating StorageClass, select protocol version V3:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2023%2F09%2F25%2F20230925162117.png)

YAML example:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: cfs
parameters:
  vers: "3" # Key point: specify protocol version
  pgroupid: pgroup-mni3ng8n # Specify permission group ID for automatically created CFS
  storagetype: SD # Specify storage type for automatically created CFS. SD for standard storage, HP for performance storage
  subdir-share: "true" # Whether each PVC shares the same CFS instance
  vpcid: vpc-e8wtynjo # Specify VPC ID, ensure it matches the current cluster VPC
  subnetid: subnet-e7uo51yj # Specify subnet ID for automatically created CFS
provisioner: com.tencent.cloud.csi.tcfs.cfs
reclaimPolicy: Delete
volumeBindingMode: Immediate
```

Subsequent PVC usage can directly reference the previously created StorageClass.

### Static Creation Reusing Existing CFS Instance

If you already have a CFS instance and want to reuse it without auto-creation, use static creation.

YAML example:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: cfs-pv
spec:
  accessModes:
  - ReadWriteMany
  capacity:
    storage: 10Gi
  csi:
    driver: com.tencent.cloud.csi.cfs
    volumeAttributes:
      fsid: yemafcez # Specify fsid, found in NFS 3.0 mount command in CFS instance console mount point info
      host: 10.10.9.6 # CFS instance IP
      path: / # Specify directory to mount in CFS instance
      vers: "3" # Key point: specify protocol version
    volumeHandle: cfs-pv
  persistentVolumeReclaimPolicy: Retain
  storageClassName: "" # Specify empty StorageClass
  volumeMode: Filesystem
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cfs-pvc
spec:
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 10Gi
  storageClassName: "" # Specify empty StorageClass
  volumeMode: Filesystem
  volumeName: cfs-pv # PVC references PV name, manual binding relationship
```

### CSI Inline Method

If you don't want to use PVs, you can use CSI Inline method when defining Volumes. YAML example:

```yaml
---
apiVersion: storage.k8s.io/v1beta1
kind: CSIDriver
metadata:
  name: com.tencent.cloud.csi.cfs
spec:
  attachRequired: false
  podInfoOnMount: false
  volumeLifecycleModes:
  - Ephemeral # Inform CFS plugin to enable inline functionality for CSI Inline definition to work properly
  
---
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
        - mountPath: /test
          name: cfs
      volumes:
      - csi: # Define CSI Inline here
          driver: com.tencent.cloud.csi.cfs
          volumeAttributes:
            fsid: yemafcez
            host: 10.10.9.6
            path: /
            vers: "3"
            proto: tcp
        name: cfs
```

## PV Specifying mountOptions (Common for TKE Clusters and EKS Elastic Clusters)

K8S natively supports mounting NFS storage, and CFS is essentially NFS storage, so you can use K8S native methods. Just specify mount options (mountOptions) in the PV. For specific options, check the NFS 3.0 mount command in the CFS instance console mount point info.

This method requires manually creating the CFS instance in advance, then manually creating PV/PVC to associate with the CFS instance. YAML example:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: cfs-pv
spec:
  accessModes:
  - ReadWriteMany
  capacity:
    storage: 10Gi
  nfs:
    path: /yemafcez # For v3 protocol, path must start with fsid. Check NFS 3.0 mount command in CFS instance console mount point info for fsid
    server: 10.10.9.6 # CFS instance IP
  mountOptions: # Specify mount options, obtained from CFS instance console mount point info
  - vers=3 # Use v3 protocol
  - proto=tcp
  - nolock,noresvport
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""  # Specify empty StorageClass
  volumeMode: Filesystem

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cfs-pvc
spec:
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 10Gi
  storageClassName: ""  # Specify empty StorageClass
  volumeMode: Filesystem
  volumeName: cfs-pv # PVC references PV name, manual binding relationship
```
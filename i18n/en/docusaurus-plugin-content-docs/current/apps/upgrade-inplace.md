---
sidebar_position: 1
---

# In-Place Upgrade

## Requirements and Background

Kubernetes by default does not support in-place upgrades, and Tencent Cloud Container Service is no exception, nor does it integrate related plugins to support this feature. You can install open-source OpenKruise to achieve this. This article introduces how to use OpenKruise on Tencent Cloud Container Service to enable in-place upgrades for workloads.

## Benefits of In-Place Upgrade

The main benefits of in-place upgrades are faster updates and avoiding pending states after updates due to insufficient underlying resources:

* No need to rebuild Pods; for EKS, no need to rebuild virtual machines.
* In-place upgrades actually replace container images and restart containers; for EKS, they can avoid situations where Pods cannot be scheduled after rebuilding due to insufficient underlying resources.
* No need to pull the entire image again, only the changed layers need to be pulled.

## Operation Steps

### Installing OpenKruise

```bash
helm repo add openkruise https://openkruise.github.io/charts/
helm repo update
helm install kruise openkruise/kruise
```

> Reference [Official Installation Documentation](https://openkruise.io/zh/docs/installation)

### Creating Workloads Supporting In-Place Upgrade

OpenKruise has the following workload types that support in-place upgrades:

* CloneSet
* Advanced StatefulSet
* Advanced DaemonSet
* SidecarSet

> For more detailed in-place upgrade documentation, refer to [Official Documentation](https://openkruise.io/zh/docs/core-concepts/inplace-update/)

Below we demonstrate using `Advanced StatefulSet`, prepare `sts.yaml`:

```yaml
apiVersion: apps.kruise.io/v1beta1
kind: StatefulSet
metadata:
  name: sample
spec:
  replicas: 3
  serviceName: fake-service
  selector:
    matchLabels:
      app: sample
  template:
    metadata:
      labels:
        app: sample
    spec:
      readinessGates:
      # A new condition that ensures the pod remains at NotReady state while the in-place update is happening
      - conditionType: InPlaceUpdateReady
      containers:
      - name: main
        image: nginx:alpine
  podManagementPolicy: Parallel # allow parallel updates, works together with maxUnavailable
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      # Do in-place update if possible, currently only image update is supported for in-place update
      podUpdatePolicy: InPlaceIfPossible
      # Allow parallel updates with max number of unavailable instances equals to 2
      maxUnavailable: 2
```

Deploy to cluster:

```bash
$ kubectl apply -f sts.yaml
statefulset.apps.kruise.io/sample created
```

Check if pods are properly started:

```bash
$ kubectl get pod
NAME       READY   STATUS    RESTARTS   AGE
sample-0   1/1     Running   0          16s
sample-1   1/1     Running   0          16s
sample-2   1/1     Running   0          16s
```

### Updating Image

Modify the image in yaml to `nginx:latest`, then apply again:

```bash
$ kubectl apply -f sts.yaml
statefulset.apps.kruise.io/sample configured
```

Observe pods:

```bash
$ kubectl get pod
NAME       READY   STATUS    RESTARTS   AGE
sample-0   1/1     Running   1          2m47s
sample-1   1/1     Running   1          2m47s
sample-2   1/1     Running   1          2m47s
```

As you can see, the containers in the pods only restarted without rebuilding the pods. At this point, in-place upgrade verification is successful.
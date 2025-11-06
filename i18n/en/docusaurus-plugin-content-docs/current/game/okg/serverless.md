# Using OpenKruiseGame in TKE Serverless

## Background

If you use OpenKruiseGame in TKE Serverless and use the [Custom Service Quality](https://openkruise.io/kruisegame/user-manuals/service-qualities) feature, there are the following issues and required adjustments:

1. The [Custom Service Quality](https://openkruise.io/kruisegame/user-manuals/service-qualities) feature depends on the `kruise-daemon` component in OpenKruise, which is deployed as a `DaemonSet`. TKE Serverless (super nodes) does not follow the traditional node model, and the `kruise-daemon` component will not run by default in the virtual machines where Serverless Pods are located. However, you can declare through annotations to automatically inject the `kruise-daemon` container into Serverless Pods.
2. The current containerd version in TKE Serverless Pods is 1.4.3, which is incompatible with `kruise-daemon` and will cause `kruise-daemon` to panic and exit on startup. You can specify an annotation to use containerd version 1.6.9, which is compatible with `kruise-daemon`. It is expected that after the Lunar New Year, the default containerd version for TKE Serverless will change to 1.6.9, and then there will be no need to declare the containerd version through annotations.

## Installing OpenKruise and OpenKruiseGame from Application Marketplace

First, search for `kruise` in the [TKE Application Marketplace](https://console.cloud.tencent.com/tke2/helm), and you will see `kruise` and `kruise-game`. Install them to the cluster.

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F12%2F26%2F20241226161254.png)

## Adding Annotations to kruise-daemon

Edit the YAML of `kruise-daemon`:

```bash
kubectl edit ds kruise-daemon -n kruise-system
```

Add the following annotations:

```yaml showLineNumbers
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: kruise-daemon
  namespace: kruise-system
spec:
  template:
    metadata:
      annotations:
        # highlight-add-start
        eks.tke.cloud.tencent.com/ds-injection: "true"
        eks.tke.cloud.tencent.com/ds-inject-by-label: okg:true
        # highlight-add-end
```

- `eks.tke.cloud.tencent.com/ds-injection`: Declares that this DaemonSet needs to be injected into Serverless Pods.
- `eks.tke.cloud.tencent.com/ds-inject-by-label`: Declares that injection scope is limited to Pods with the `okg:true` label (avoiding injecting into all Pods to minimize impact scope).

If it's inconvenient to use kubectl, you can also edit the YAML through the TKE console:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F12%2F26%2F20241226184316.png)

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F12%2F26%2F20241226184348.png)

## Adding Labels and Annotations to Game Server Pods

`GameServerSet` example:

```yaml showLineNumbers
apiVersion: game.kruise.io/v1alpha1
kind: GameServerSet
metadata:
  name: minecraft
spec:
  replicas: 1
  updateStrategy:
    rollingUpdate:
      podUpdatePolicy: InPlaceIfPossible
  gameServerTemplate:
    metadata:
      labels:
        # Label for matching when kruise-daemon is injected into serverless
        # highlight-add-line
        okg: "true"
      annotations:
        # The following two annotations are used to declare using containerd 1.6.9
        # highlight-add-start
        eks.tke.cloud.tencent.com/eklet-version: latest-tkex-ts4
        eks.tke.cloud.tencent.com/not-reuse-cbs: "true"
        # highlight-add-end
    spec:
      terminationGracePeriodSeconds: 1
      nodeSelector:
        node.kubernetes.io/instance-type: eklet
      volumes:
        - name: script
          configMap:
            name: minecraft-script
            defaultMode: 0755
      containers:
        - image: itzg/minecraft-server:latest
          name: minecraft
          volumeMounts:
            - name: script
              mountPath: /idle.sh
              subPath: idle.sh
          env:
            - name: EULA
              value: "TRUE"
            - name: ONLINE_MODE
              value: "FALSE"
  serviceQualities:
    - name: idle
      containerName: minecraft
      permanent: false
      exec:
        command: ["bash", "/idle.sh"]
      serviceQualityAction:
        - state: true
          opsState: WaitToBeDeleted
        - state: false
          opsState: None
```

1. The two annotations `eks.tke.cloud.tencent.com/eklet-version: latest-tkex-ts4` and `eks.tke.cloud.tencent.com/not-reuse-cbs: "true"` are used to declare using containerd version 1.6.9, which is compatible with `kruise-daemon`.
2. Add the label `okg:true` to game server Pods so that `kruise-daemon` can be automatically injected into the Pods.

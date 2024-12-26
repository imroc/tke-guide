# 在 TKE Serverless 中使用 OpenKruiseGame

## 背景

如果 TKE Serverless 中使用 OpenKruiseGame，且用到了 [自定义服务质量](https://openkruise.io/zh/kruisegame/user-manuals/service-qualities) 的功能，会存在兼容性问题，需按照本文做一些调整来适配。

## 在应用市场安装 OpenKruise 和 OpenKruiseGame

首先在 [TKE 应用市场](https://console.cloud.tencent.com/tke2/helm) 中搜索 `kruise`, 可以看到 `kruise` 和 `kruise-game`, 将它们安装到集群中即可。

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F12%2F26%2F20241226161254.png)

## 为 kruise-daemon 增加注解

[自定义服务质量](https://openkruise.io/zh/kruisegame/user-manuals/service-qualities) 这个功能依赖了 OpenKruise 中的 `kruise-daemon` 组件，是以 `DaemonSet` 形式部署的，而 TKE Serverless（超级节点）并不是传统的 node 模型，`kruise-daemon` 组件默认不会运行在 Serverless Pod 所在虚拟机中，但可以通过注解声明让 `kruise-daemon` 容器自动注入到 Serverless 的 Pod 中。

编辑 `kruise-daemon` 的 YAML：

```bash
kubectl edit ds kruise-daemon -n kruise-system
```

增加以下注解：

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

- `eks.tke.cloud.tencent.com/ds-injection`: 声明该 DaemonSet 需要被注入到 Serverless Pod 中。
- `eks.tke.cloud.tencent.com/ds-inject-by-label`: 声明注入范围限制到带有 `okg:true` 标签的 Pod（避免全部注入，尽量减少影响范围）。


## 游戏服 Pod 增加标签和注解

1. 当前 TKE Serverless Pod 中的 containerd 版本是 1.4.3，与 `kruise-damon` 不兼容，会导致 `kruise-daemon` 启动时 panic 退出，可通过指定注解实现使用 containerd 1.6.9 版本，该版本兼容 `kruise-daemon`。
2. 为游戏服 Pod 增加标签 `okg:true`，以便 `kruise-daemon` 能自动注入到 Pod 中。

`GameServerSet` 示例：

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
        # 用于 kruise-daemon 注入到 serverless 时匹配的 label
        # highlight-add-line
        okg: "true"
      annotations:
        # 以下两个注解用于声明使用 containerd 1.6.9
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

# 高可用配置优化

## 概述

本文介绍 Nginx Ingress 的高可用部署配置方法。

## 调高副本数

配置自动扩缩容：

```yaml
controller:
  autoscaling:
    enabled: true
    minReplicas: 10
    maxReplicas: 100
    targetCPUUtilizationPercentage: 50
    targetMemoryUtilizationPercentage: 50
    behavior: # 快速扩容应对流量洪峰，缓慢缩容预留 buffer 避免流量异常
      scaleDown:
        stabilizationWindowSeconds: 300
        policies:
          - type: Percent
            value: 900
            periodSeconds: 15 # 每 15s 最多允许扩容 9 倍于当前副本数
      scaleUp:
        stabilizationWindowSeconds: 300
        policies:
          - type: Pods
            value: 1
            periodSeconds: 600 # 每 10 分钟最多只允许缩掉 1 个 Pod
```

如果希望固定副本数，直接配置 `replicaCount`:

```yaml
controller:
  replicaCount: 50
```

## 打散调度

使用拓扑分布约束将 Pod 打散以支持容灾，避免单点故障：

```yaml
controller:
  topologySpreadConstraints: # 尽量打散的策略
    - labelSelector:
        matchLabels:
          app.kubernetes.io/name: '{{ include "ingress-nginx.name" . }}'
          app.kubernetes.io/instance: '{{ .Release.Name }}'
          app.kubernetes.io/component: controller
      topologyKey: topology.kubernetes.io/zone
      maxSkew: 1
      whenUnsatisfiable: ScheduleAnyway
    - labelSelector:
        matchLabels:
          app.kubernetes.io/name: '{{ include "ingress-nginx.name" . }}'
          app.kubernetes.io/instance: '{{ .Release.Name }}'
          app.kubernetes.io/component: controller
      topologyKey: kubernetes.io/hostname
      maxSkew: 1
      whenUnsatisfiable: ScheduleAnyway
```

## 调度专用节点

通常 Nginx Ingress Controller 的负载跟流量成正比，而 Nginx Ingress Controller 作为网关又特别重要，可以考虑将其调度到专用的节点或者超级节点，避免干扰业务 Pod 或被业务 Pod 干扰。

调度到指定节点池：

```yaml
controller:
  nodeSelector:
    tke.cloud.tencent.com/nodepool-id: np-********
```

:::info

超级节点的效果更好，所有 Pod 独占虚拟机，不会相互干扰。如果使用的是 Serverless 集群，则不需要配这里的调度策略，只会调度到超级节点。

:::

## 合理设置 request limit

如果 Nginx Ingress 不是调度到超级节点，需合理设置下 request 和 limit，保证有足够的资源的同时，也保证不要用太多的资源导致节点负载过高:

```yaml
controller:
  resources:
    requests:
      cpu: 500m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 1Gi
```

如果是用的超级节点或 Serverless 集群，只需要定义下 requests，即声明每个 Pod 的虚拟机规格：

```yaml
controller:
  resources:
    requests:
      cpu: 1000m
      memory: 2Gi
```

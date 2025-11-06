# High Availability Configuration Optimization

## Overview

This article describes high availability deployment configuration methods for Nginx Ingress.

## Increasing Replica Count

Configure autoscaling:

```yaml
controller:
  autoscaling:
    enabled: true
    minReplicas: 10
    maxReplicas: 100
    targetCPUUtilizationPercentage: 50
    targetMemoryUtilizationPercentage: 50
    behavior: # Rapid scale-up to handle traffic spikes, slow scale-down to reserve buffer for traffic anomalies
      scaleUp:
        stabilizationWindowSeconds: 300
        policies:
          - type: Percent
            value: 900
            periodSeconds: 15 # Allow scaling up to 9 times the current replica count at most every 15s
      scaleDown:
        stabilizationWindowSeconds: 300
        policies:
          - type: Pods
            value: 1
            periodSeconds: 600 # Allow scaling down by at most 1 Pod every 10 minutes
```

If you want to fix the replica count, configure `replicaCount` directly:

```yaml
controller:
  replicaCount: 50
```

## Distributing Pods Across Nodes

Use topology spread constraints to distribute Pods for disaster recovery and avoid single points of failure:

```yaml
controller:
  topologySpreadConstraints: # Policy for distributing as much as possible
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

## Scheduling to Dedicated Nodes

Typically, the load on Nginx Ingress Controller is proportional to traffic volume. Since Nginx Ingress Controller serves as a gateway and is particularly important, consider scheduling it to dedicated nodes or super nodes to avoid interference with business Pods or being interfered with by business Pods.

Schedule to a specified node pool:

```yaml
controller:
  nodeSelector:
    tke.cloud.tencent.com/nodepool-id: np-********
```

:::info

Super nodes provide better results as all Pods occupy exclusive virtual machines without mutual interference. If using a Serverless cluster, there's no need to configure scheduling policies here, as they will only be scheduled to super nodes.

:::

## Setting Reasonable Request and Limit

If Nginx Ingress is not scheduled to super nodes, set request and limit reasonably to ensure sufficient resources while avoiding excessive resource usage that leads to high node load:

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

If using super nodes or Serverless clusters, only define requests to declare the VM specification for each Pod:

```yaml
controller:
  resources:
    requests:
      cpu: 1000m
      memory: 2Gi
```

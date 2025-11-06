---
sidebar_position: 1
---

# Horizontal Scaling Based on GPU Metrics

## Overview

This article explains how to implement horizontal scaling based on GPU metrics in TKE environments. GPU resources are critical for AI/ML workloads, and proper autoscaling ensures optimal resource utilization while meeting performance requirements.

## Prerequisites

- TKE cluster with GPU nodes
- GPU drivers and device plugins installed
- Monitoring system configured to collect GPU metrics

## GPU Metrics for Scaling

Key GPU metrics to monitor for autoscaling decisions:

### GPU Utilization
- **Metric**: `nvidia_gpu_duty_cycle` or `DCGM_FI_DEV_GPU_UTIL`
- **Description**: Percentage of time GPU was busy
- **Usage**: Scale out when utilization exceeds threshold for sustained period

### GPU Memory Usage
- **Metric**: `nvidia_gpu_memory_used_bytes` or `DCGM_FI_DEV_FB_USED`
- **Description**: Amount of GPU memory currently in use
- **Usage**: Scale out when memory usage approaches limits

### GPU Temperature
- **Metric**: `nvidia_gpu_temperature` or `DCGM_FI_DEV_GPU_TEMP`
- **Description**: Current GPU temperature
- **Usage**: Scale to prevent overheating and ensure hardware longevity

## Implementation Methods

### Using KEDA for GPU Scaling

KEDA (Kubernetes Event-driven Autoscaling) can be configured to scale based on GPU metrics:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: gpu-scaledobject
  namespace: default
spec:
  scaleTargetRef:
    name: gpu-workload
  triggers:
  - type: prometheus
    metadata:
      serverAddress: http://prometheus-service.monitoring.svc.cluster.local:9090
      metricName: nvidia_gpu_duty_cycle
      query: |
        avg(
          avg_over_time(nvidia_gpu_duty_cycle{gpu="0"}[5m])
        ) by (pod)
      threshold: "70"
      activationThreshold: "30"
```

### Custom Horizontal Pod Autoscaler

Create a custom HPA that uses GPU metrics:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: gpu-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: gpu-workload
  minReplicas: 1
  maxReplicas: 10
  metrics:
  - type: Pods
    pods:
      metric:
        name: gpu_utilization
      target:
        type: AverageValue
        averageValue: "70"
```

## GPU Metric Collection

### Using DCGM Exporter

DCGM (Data Center GPU Manager) exporter provides comprehensive GPU metrics:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: dcgm-exporter
  namespace: monitoring
spec:
  selector:
    matchLabels:
      name: dcgm-exporter
  template:
    metadata:
      labels:
        name: dcgm-exporter
    spec:
      containers:
      - name: dcgm-exporter
        image: nvidia/dcgm-exporter:latest
        resources:
          limits:
            nvidia.com/gpu: 1
        securityContext:
          runAsUser: 0
        env:
        - name: DCGM_EXPORTER_LISTEN
          value: ":9400"
```

### Prometheus Configuration

Configure Prometheus to scrape GPU metrics:

```yaml
- job_name: 'dcgm-exporter'
  scrape_interval: 15s
  static_configs:
  - targets: ['dcgm-exporter.monitoring.svc.cluster.local:9400']
```

## Best Practices

### Threshold Configuration

Set appropriate thresholds based on workload characteristics:

- **Training workloads**: Higher utilization thresholds (70-80%)
- **Inference workloads**: Lower utilization thresholds (50-60%)
- **Mixed workloads**: Adaptive thresholds based on priority

### Cooldown Periods

Configure appropriate cooldown periods to prevent rapid scaling:

```yaml
behavior:
  scaleDown:
    stabilizationWindowSeconds: 300
    policies:
    - type: Pods
      value: 1
      periodSeconds: 60
  scaleUp:
    stabilizationWindowSeconds: 60
    policies:
    - type: Pods
      value: 2
      periodSeconds: 60
```

### Resource Limits

Set appropriate resource limits for GPU workloads:

```yaml
resources:
  limits:
    nvidia.com/gpu: 1
    cpu: "2"
    memory: 8Gi
  requests:
    nvidia.com/gpu: 1
    cpu: "1"
    memory: 4Gi
```

## Monitoring and Alerting

### Key Metrics to Monitor

- GPU utilization trends
- Memory usage patterns
- Scaling events frequency
- Node GPU capacity utilization

### Alert Rules

Set up alerts for critical GPU conditions:

```yaml
groups:
- name: gpu.alerts
  rules:
  - alert: HighGPUUtilization
    expr: nvidia_gpu_duty_cycle > 90
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "GPU utilization is high"
      description: "GPU {{ $labels.gpu }} utilization is {{ $value }}%"
```

## Troubleshooting

### Common Issues

1. **Metric Collection Failures**
   - Verify DCGM exporter is running
   - Check Prometheus scrape configuration
   - Validate network connectivity

2. **Scaling Not Triggering**
   - Verify metric thresholds are appropriate
   - Check HPA configuration
   - Validate metric availability

3. **Resource Constraints**
   - Ensure GPU nodes have capacity
   - Check node selector and tolerations
   - Verify resource quotas

### Debug Commands

```bash
# Check GPU metrics
kubectl top pod -l app=gpu-workload

# Check HPA status
kubectl get hpa gpu-hpa

# Check GPU node status
kubectl get nodes -l nvidia.com/gpu.present=true

# Check DCGM exporter logs
kubectl logs -l name=dcgm-exporter -n monitoring
```

## Conclusion

GPU-based horizontal scaling ensures optimal resource utilization for AI/ML workloads. By monitoring key GPU metrics and implementing appropriate scaling strategies, you can maintain performance while controlling costs. Regular monitoring and adjustment of scaling parameters are essential for long-term success.
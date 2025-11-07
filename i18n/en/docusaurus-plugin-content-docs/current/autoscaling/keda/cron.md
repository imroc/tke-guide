# Scheduled Horizontal Scaling (Cron Trigger)

## Cron Trigger

KEDA supports Cron triggers, i.e., using Cron expressions to configure periodic scheduled scaling. For usage, refer to [KEDA Scalers: Cron](https://keda.sh/docs/latest/scalers/cron/).

Cron triggers are suitable for businesses with periodic characteristics, such as business traffic with fixed periodic peak and valley characteristics.

## Use Case: Daily Flash Sale Events at Fixed Times

Flash sale events have the characteristic of relatively fixed times. You can scale in advance before the event starts. The following shows a `ScaledObject` configuration example.

```yaml showLineNumbers
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: seckill
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: seckill
  pollingInterval: 15
  minReplicaCount: 2 # Keep at least 2 replicas
  maxReplicaCount: 1000
  advanced:
    horizontalPodAutoscalerConfig:
      behavior: # Control scaling behavior, using a conservative strategy: fast scale-up, slow scale-down
        scaleDown: # Slow scale-down: must cool down for at least 10 minutes before scaling down
          stabilizationWindowSeconds: 600
          selectPolicy: Min # 
        scaleUp: # Fast scale-up: allow up to 5x scaling every 15s
          policies:
            - type: Percent
              value: 500
              periodSeconds: 15
  triggers:
    # highlight-start
    - type: cron # Daily flash sale at 10 AM, ensure at least 200 replicas half hour before and after
      metadata:
        timezone: Asia/Shanghai
        start: 30 9 * * *
        end: 30 10 * * *
        desiredReplicas: "200"
    - type: cron # Daily flash sale at 6 PM, ensure at least 200 replicas half hour before and after
      metadata:
        timezone: Asia/Shanghai
        start: 30 17 * * *
        end: 30 18 * * *
        desiredReplicas: "200"
    # highlight-end
    - type: memory # Scale when CPU utilization exceeds 60%
      metricType: Utilization
      metadata:
        value: "60"
    - type: cpu # Scale when memory utilization exceeds 60%
      metricType: Utilization
      metadata:
        value: "60"
```

## Notes

Typically, triggers should not only configure Cron, but should be used in combination with other triggers. This is because during time periods outside the cron's start and end interval, if no other triggers are active, the replica count will drop to `minReplicaCount`, which may not be what we want.

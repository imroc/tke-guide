# Multi-tier Service Synchronized Horizontal Scaling (Workload Trigger)

## Workload Trigger

KEDA supports Kubernetes Workload triggers, i.e., it can scale based on the number of Pods in one or more workloads. This is very useful in multi-tier service invocation scenarios. For specific usage, refer to [KEDA Scalers: Kubernetes Workload](https://keda.sh/docs/2.13/scalers/kubernetes-workload/).

## Use Case: Multi-tier Service Simultaneous Scaling

For example, the following multi-tier microservice invocation:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F08%2F20240408084514.png)

* Services A, B, and C in this group usually have a relatively fixed quantity ratio.
* When pressure suddenly increases on A, forcing it to scale, B and C can also use KEDA's Kubernetes Workload trigger to scale almost simultaneously with A, without waiting for pressure to be transmitted level by level, which would cause slow forced scaling.

First, configure scaling for A based on CPU and memory pressure:

```yaml showLineNumbers
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: a
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: a
  pollingInterval: 15
  minReplicaCount: 10
  maxReplicaCount: 1000
  triggers:
    - type: memory
      metricType: Utilization
      metadata:
        value: "60"
    - type: cpu
      metricType: Utilization
      metadata:
        value: "60"
```


Then configure scaling for B and C, assuming a fixed ratio A:B:C = 3:3:2.

<Tabs>
  <TabItem value="B" label="B">

   ```yaml showLineNumbers
   apiVersion: keda.sh/v1alpha1
   kind: ScaledObject
   metadata:
     name: b
   spec:
     scaleTargetRef:
       apiVersion: apps/v1
       kind: Deployment
       name: b
     pollingInterval: 15
     minReplicaCount: 10
     maxReplicaCount: 1000
     triggers:
       # highlight-start
       - type: kubernetes-workload
         metadata:
           podSelector: 'app=a' # Select Service A
           value: '1' # A/B=3/3=1
       # highlight-end
   ```

  </TabItem>

  <TabItem value="C" label="C">

   ```yaml showLineNumbers
   apiVersion: keda.sh/v1alpha1
   kind: ScaledObject
   metadata:
     name: c
   spec:
     scaleTargetRef:
       apiVersion: apps/v1
       kind: Deployment
       name: c
     pollingInterval: 15
     minReplicaCount: 3
     maxReplicaCount: 340
     triggers:
       # highlight-start
       - type: kubernetes-workload
         metadata:
           podSelector: 'app=a' # Select Service A
           value: '1.5' # A/C=3/2=1.5
       # highlight-end
   ```

  </TabItem>
</Tabs>

With the above configuration, when pressure on A increases, A, B, and C will scale almost simultaneously without waiting for pressure to be transmitted level by level. This allows for faster adaptation to pressure changes and improves system elasticity and performance.

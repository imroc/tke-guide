# Elastic Scaling Based on Prometheus Custom Metrics

## Prometheus Trigger

KEDA supports `prometheus` type triggers, i.e., scaling based on Prometheus metric data queried through custom PromQL. For complete configuration parameters, refer to [KEDA Scalers: Prometheus](https://keda.sh/docs/latest/scalers/prometheus/). This article will provide use cases.

## Use Case: Scaling Based on Istio QPS Metrics

If you use Istio and business Pods have sidecars injected, they automatically expose some Layer 7 monitoring metrics. The most common is `istio_requests_total`, which can be used to calculate QPS.

Assume this scenario: Service A needs to scale based on the QPS handled by Service B.

```yaml showLineNumbers
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: b-scaledobject
  namespace: prod
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: a # Scale Service A
  pollingInterval: 15
  minReplicaCount: 1
  maxReplicaCount: 100
  triggers:
    # highlight-start
    - type: prometheus
      metadata:
        serverAddress: http://monitoring-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090 # Replace with Prometheus address
        query: | # PromQL to calculate Service B QPS
          sum(irate(istio_requests_total{reporter=~"destination",destination_workload_namespace=~"prod",destination_workload=~"b"}[1m]))
        threshold: "100" # Service A replica count = ceil(Service B QPS/100)
    # highlight-end
```

## Advantages Over prometheus-adapter

[prometheus-adapter](https://github.com/kubernetes-sigs/prometheus-adapter) also supports the same capability, i.e., scaling based on monitoring metric data in Prometheus, but compared to the KEDA solution, it has the following shortcomings:

* Every time a custom metric is added, the `prometheus-adapter` configuration must be modified, and the configuration is centrally managed and does not support management through CRDs. Configuration maintenance is cumbersome, while the KEDA solution only requires configuring `ScaledObject` or `ScaledJob` CRDs. Different businesses use different YAML files for maintenance, which is conducive to configuration maintenance.
* The `prometheus-adapter` configuration syntax is obscure and difficult to understand. You cannot write `PromQL` directly; you need to learn the `prometheus-adapter` configuration syntax, which has a certain learning cost. KEDA's prometheus configuration is very simple; metrics can be written directly using `PromQL` query statements, which is simple and clear.
* `prometheus-adapter` only supports scaling based on Prometheus monitoring data, while for KEDA, Prometheus is just one of many triggers.

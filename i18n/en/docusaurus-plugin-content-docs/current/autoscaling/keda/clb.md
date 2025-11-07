# Horizontal Scaling Based on CLB Monitoring Metrics

## Business Scenario

Business traffic on TKE is often accessed through CLB (Tencent Cloud Load Balancer). Sometimes, it's desirable for workloads to scale directly based on CLB monitoring metrics, for example:
1. For long connection scenarios like game rooms and online meetings, one connection corresponds to one user. Each Pod in the workload handles a relatively fixed upper limit of connections, so scaling can be based on CLB connection count metrics.
2. For online services using the HTTP protocol, where a single Pod in the workload can support a relatively fixed QPS, scaling can be based on CLB's QPS (requests per second) metric.

## Introduction to keda-tencentcloud-clb-scaler

KEDA has many built-in triggers, but not for Tencent Cloud CLB. However, KEDA supports external-type triggers to extend triggers. [keda-tencentcloud-clb-scaler](https://github.com/imroc/keda-tencentcloud-clb-scaler) is a KEDA External Scaler based on Tencent Cloud CLB monitoring metrics, enabling elastic scaling based on CLB metrics such as connections, QPS, and bandwidth.

## Prepare Access Keys

You need to prepare access keys (SecretID, SecretKey) for a Tencent Cloud account. Refer to [Sub-account Access Key Management](https://cloud.tencent.com/document/product/598/37140). The account must have at least the following permissions:

```json
{
    "version": "2.0",
    "statement": [
        {
            "effect": "allow",
            "action": [
                "clb.DescribeLoadBalancers",
                "monitor.DescribeProductList",
                "monitor.GetMonitorData",
                "monitor.DescribeBaseMetrics"
            ],
            "resource": [
                "*"
            ]
        }
    ]
}
```

## Install keda-tencentcloud-clb-scaler

```bash
helm repo add clb-scaler https://imroc.github.io/keda-tencentcloud-clb-scaler
helm upgrade --install clb-scaler clb-scaler/clb-scaler -n keda \
  --set region="ap-chengdu" \
  --set credentials.secretId="xxx" \
  --set credentials.secretKey="xxx"
```

* Modify `region` to the region where the CLB is located (usually the cluster's region). Region list: https://cloud.tencent.com/document/product/213/6091
* `credentials.secretId` and `credentials.secretKey` are the Tencent Cloud account access keys, used to call related cloud APIs to query CLB monitoring data.

## Deploy Workload

Below is a workload YAML example for testing:

```yaml showLineNumbers
apiVersion: v1
kind: Service
metadata:
  labels:
    app: httpbin
  name: httpbin
spec:
  ports:
    - port: 8080
      protocol: TCP
      targetPort: 80
  selector:
    app: httpbin
  type: LoadBalancer

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: httpbin
spec:
  replicas: 1
  selector:
    matchLabels:
      app: httpbin
  template:
    metadata:
      labels:
        app: httpbin
    spec:
      containers:
        - image: kennethreitz/httpbin:latest
          name: httpbin
```

After deployment, a corresponding public network CLB will be automatically created to receive traffic. Get the corresponding CLB ID with the following command:
```bash
$ kubectl get svc httpbin -o jsonpath='{.metadata.annotations.service\.kubernetes\.io/loadbalance-id}'
lb-********
```

Record the obtained CLB ID, as it will be needed for the subsequent KEDA scaling configuration.

## Configure Elastic Scaling Based on CLB Monitoring Metrics Using ScaledObject

### Configuration Method

Scaling based on CLB monitoring metrics is typically used for online services and usually configured with KEDA's `ScaledObject` for elastic scaling, configuring an `external` type trigger and passing in the required metadata, which mainly includes the following fields:
* `scalerAddress` is the address used by `keda-operator` when calling `keda-tencentcloud-clb-scaler`.
* `loadBalancerId` is the CLB instance ID.
* `metricName` is the CLB monitoring metric name. Most metrics for public and private networks are the same. Refer to the official documentation for specific metric lists: [Public Network Load Balancer Monitoring Metrics](https://cloud.tencent.com/document/product/248/51898) and [Private Network Load Balancer Monitoring Metrics](https://cloud.tencent.com/document/product/248/51899).
* `threshold` is the metric threshold for scaling, i.e., it decides whether to scale by comparing `metricValue / Pod count` with the `threshold` value.
* `listener` is the only optional configuration, specifying the CLB listener for monitoring metrics, format: `protocol/port`.

### Configuration Example 1: Elastic Scaling Based on CLB Connection Count Metric

```yaml showLineNumbers
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: httpbin
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: httpbin
  pollingInterval: 15
  minReplicaCount: 1
  maxReplicaCount: 100
  triggers:
    - type: external
      metadata:
        # highlight-start
        scalerAddress: clb-scaler.keda.svc.cluster.local:9000
        loadBalancerId: lb-xxxxxxxx
        metricName: ClientConnum # Connection count metric
        threshold: "100" # Each Pod handles 100 connections
        listener: "TCP/8080" # Optional, specify listener, format: protocol/port
        # highlight-end
```

### Configuration Example 2: Elastic Scaling Based on CLB QPS Metric

```yaml showLineNumbers
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: httpbin
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: httpbin
  pollingInterval: 15
  minReplicaCount: 1
  maxReplicaCount: 100
  triggers:
    - type: external
      metadata:
        # highlight-start
        scalerAddress: clb-scaler.keda.svc.cluster.local:9000
        loadBalancerId: lb-xxxxxxxx
        metricName: TotalReq # Requests per second metric
        threshold: "500" # Average of 500 QPS per Pod
        listener: "TCP/8080" # Optional, specify listener, format: protocol/port
        # highlight-end
```

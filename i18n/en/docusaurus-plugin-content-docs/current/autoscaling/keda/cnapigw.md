# Horizontal Scaling Based on Cloud Native API Gateway Monitoring Metrics

## Overview

[Cloud Native API Gateway](https://cloud.tencent.com/product/cngw) is a Kong-based managed gateway product on Tencent Cloud with rich Layer 7 traffic management capabilities, and it also supports forwarding requests to services on TKE clusters.

Cloud Native API Gateway provides rich `Prometheus` monitoring metrics. This article will use QPS metrics for specified services as an example to introduce how to use `KEDA` on TKE to implement horizontal scaling based on Cloud Native API Gateway monitoring metrics.

## Operation Steps

### Configure Prometheus Collection

You can use Tencent Cloud Prometheus or self-built `Prometheus` to collect monitoring data from Cloud Native API Gateway. On the [Cloud Native API Gateway - Observability](https://console.cloud.tencent.com/tse/monitor) page, select the gateway instance to use and switch to the [Prometheus] tab.

If using Tencent Cloud `Prometheus` service, you can directly [Associate Tencent Cloud Prometheus]. If using self-built Prometheus, you can view the list of private network addresses for gateway nodes under [Configure Self-built Prometheus]:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F05%2F16%2F20240516144818.png)

Copy these IP addresses and configure them in the self-built `Prometheus` collection configuration using `static_configs`:

```yaml
  - job_name: apigw
    honor_timestamps: true
    metrics_path: "/metrics"
    scheme: http
    static_configs:
      - targets: ["10.10.12.23:2100", "10.10.12.144:2100"]
```

> The metrics interface address for Cloud Native API Gateway is: `Node IP:2100/metrics`

If collection is normal, you can query monitoring metrics starting with `kong_`:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F05%2F16%2F20240516145927.png)

### Deploy Test Application to TKE Cluster

You can deploy a simple `nginx` application to the TKE cluster:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:latest

---

apiVersion: v1
kind: Service
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  type: ClusterIP
  ports:
    - port: 80
      protocol: TCP
      targetPort: 80
  selector:
    app: nginx
```

### Configure Cloud Native API Gateway

On the [Cloud Native API Gateway - Route Management](https://console.cloud.tencent.com/tse/route) page, create a new service source:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F05%2F16%2F20240516152033.png)

Add container service clusters according to your needs:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F05%2F16%2F20240516150544.png)

Then create a new service:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F05%2F16%2F20240516152140.png)

From [K8S Service], select the cluster, namespace, and service where the test application is deployed:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F05%2F16%2F20240516152341.png)

After creation, click into this service, and click [Create] in [Route Management]:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F05%2F16%2F20240516152529.png)

Configure the route according to your needs:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F05%2F16%2F20240516152633.png)

After configuration, you can access services in the TKE cluster through the Cloud Native Gateway. You can perform load testing for a period to check if the monitoring data in `Prometheus` is normal.

### Configure KEDA ScaledObject

With `KEDA` installed, we can create a `ScaledObject` similar to the following:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: nginx-scaledobject
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: nginx
  pollingInterval: 15
  minReplicaCount: 1
  maxReplicaCount: 100
  advanced:
    horizontalPodAutoscalerConfig:
      behavior:
        scaleUp:
          policies:
            - periodSeconds: 15
              type: Percent
              value: 900
  triggers:
    - type: prometheus
      metadata:
        serverAddress: http://monitoring-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090
        query: |
          sum(irate(kong_http_status{service="nginx"}[1m]))
        threshold: "300"
```

* `scaleTargetRef` specifies the workload to be automatically scaled, here it's the `nginx` workload.
* `serverAddress` specifies the `Prometheus` address, modify according to your actual situation.
* `query` specifies the PromQL to query metric data. The example queries the QPS value of the `nginx` service in the Cloud Native API Gateway.
* `threshold` represents the scaling threshold. 300 means each `nginx` pod has a threshold of bearing an average of 300 QPS. The actual average QPS is compared with this threshold to perform corresponding scaling operations.

## Configure Ingress

In addition to configuring routes in the console, Cloud Native API Gateway can also be configured via Ingress. After associating `Kong Ingress Controller` to the container cluster on the [Ingress page](https://console.cloud.tencent.com/tse/ingress), you can directly create Ingress in the cluster to configure rules. Example:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx
spec:
  ingressClassName: kong
  rules:
    - host: "example.com"
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nginx
                port:
                  number: 80
```

> `ingressClassName` should specify the IngressClass used by `Kong Ingress Controller`.

Then in KEDA's `ScaledObject`, the PromQL query statement also needs to be modified:

```promql
sum(irate(kong_http_status{service="test.nginx.pnum-80"}[1m]))
```

> The `service` format is `<Ingress namespace>.<referenced Service name>.pnum-<Service port>`

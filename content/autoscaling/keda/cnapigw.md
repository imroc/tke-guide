# 基于云原生 API 网关监控指标的水平伸缩

## 概述

[云原生 API 网关](https://cloud.tencent.com/product/cngw) 是腾讯云上基于 Kong 托管的网关产品，拥有丰富的七层流量管理功能，也支持将请求转发到 TKE 集群上的服务。

云原生网关提供了丰富的 `Prometheus` 监控指标，本文将以指定服务的 QPS 指标为例，介绍如何在 TKE 上利用 `KEDA` 实现基于云原生 API 网关监控指标的水平伸缩。

## 操作步骤

### 配置 `Prometheus` 采集

你可以使用腾讯云 Prometheus，也可以使用自建 `Prometheus` 来采集云原生 API 网关的监控数据，在 [云原生 API 网关-可观测性](https://console.cloud.tencent.com/tse/monitor) 页面选择使用的网关实例，并切换到 【Prometheus】页面。

如果使用的腾讯云 `Prometheus` 服务，可以直接 【关联腾讯云 Prometheus】，如果是自建的 Prometheus，可以在【配置自建 Prometheus】 下查看网关节点的内网地址列表：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F05%2F16%2F20240516144818.png)

将这些 IP 地址复制下来，通过 `static_configs` 配置到自建 `Prometheus` 的采集配置中：

```yaml
  - job_name: apigw
    honor_timestamps: true
    metrics_path: "/metrics"
    scheme: http
    static_configs:
      - targets: ["10.10.12.23:2100", "10.10.12.144:2100"]
```

> 云原生 API 网关的 metrics 接口地址是：`节点IP:2100/metrics`

如果正常采集，可以查到有 `kong_` 开头的监控指标：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F05%2F16%2F20240516145927.png)

### 部署测试应用到 TKE 集群

可以部署一个简单的 `nginx` 应用到 TKE 集群：

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

### 配置云原生 API 网关

在 [云原生 API 网关-路由管理](https://console.cloud.tencent.com/tse/route) 页面新建服务来源：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F05%2F16%2F20240516152033.png)

根据自己需求添加容器服务的集群：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F05%2F16%2F20240516150544.png)

然后新建服务：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F05%2F16%2F20240516152140.png)

从【K8S】服务中选择部署了测试应用的集群、命名空间以及服务：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F05%2F16%2F20240516152341.png)

创建好后，点进这个服务，在【路由管理】里点【新建】：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F05%2F16%2F20240516152529.png)

根据需要配置路由：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F05%2F16%2F20240516152633.png)

配置完成后，就可以通过云原生网关访问 TKE 集群中的服务了，可以压测一段时间，看下 `Prometheus` 中的监控数据是否正常。

### 配置 KEDA ScaledObject

在安装了 `KEDA` 的前提下，我们可以创建类似以下的 `ScaledObject`：

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

* `scaleTargetRef` 填要被自动扩缩容的工作负载，这里是对 `nginx` 这个工作负载进行自动扩缩容。
* `serverAddress` 填 `Prometheus` 的地址，根据实际情况进行修改。
* `query` 填查询指标数据的 PromQL，示例中是查 `nginx` 这个服务在云原生 API 网关中的 QPS 值。
* `threshold` 表示扩缩容阈值，300 表示每个 `nginx` pod 平均承受 300 QPS 的阈值，实际的平均 QPS 与这个阈值比较来进行相应的扩缩容操作。

## 配置 Ingress

云原生 API 网关除了能在控制台配置路由，还可以通过 Ingress 的方式来配置，在 [Ingress 页面](https://console.cloud.tencent.com/tse/ingress) 关联 `Kong Ingress Controller` 到容器集群后，就可以在集群里直接创建 Ingress 来配置规则了，示例：

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

> `ingressClassName` 要指定 `Kong Ingress Controller` 所使用的 IngressClass。

然后 `KEDA` 的 `ScaledObject` 里，PromQL 查询语句写法也需要改动下：

```promql
sum(irate(kong_http_status{service="test.nginx.pnum-80"}[1m]))
```

> `service` 的格式为 `<Ingress 所在命名空间>.<引用的 Service 名称>.pnum-<Service 端口>`

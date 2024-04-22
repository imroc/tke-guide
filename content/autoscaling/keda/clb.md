# 基于 CLB 监控指标伸缩

## 业务场景

TKE 上的业务流量往往是通过 CLB（腾讯云负载均衡器）接入的，有时候希望工作负载能够直接根据 CLB 的监控指标进行伸缩，比如：
1. 游戏房间、在线会议等长连接场景，一条连接对应一个用户，工作负载里的每个 Pod 处理的连接数上限比较固定，这时可以根据 CLB 连接数指标进行伸缩。
2. HTTP 协议的在线业务，工作负载里的单个 Pod 所能支撑的 QPS 比较固定，这时可以根据 CLB 的 QPS（每秒请求数） 指标进行伸缩。

## keda-tencentcloud-clb-scaler 介绍

KEDA 有很多内置的触发器，但没有腾讯云 CLB 的，不过 KEDA 支持 external 类型的触发器来对触发器进行扩展，[keda-tencentcloud-clb-scaler](https://github.com/imroc/keda-tencentcloud-clb-scaler) 是基于腾讯云 CLB 监控指标的 KEDA External Scaler，可实现基于 CLB 连接数、QPS 和带宽等指标的弹性伸缩。

## 安装 keda-tencentcloud-clb-scaler

```bash
helm repo add clb-scaler https://imroc.github.io/keda-tencentcloud-clb-scaler
helm upgrade --install clb-scaler clb-scaler/clb-scaler -n keda \
  --set region="ap-chengdu" \
  --set credentials.secretId="xxx" \
  --set credentials.secretKey="xxx"
```

* `region` 修改为CLB 所在地域（一般就是集群所在地域），地域列表: https://cloud.tencent.com/document/product/213/6091
* `credentials.secretId` 和 `credentials.secretKey`  是腾讯云账户密钥对，用于查 CLB 监控数据。

## 部署工作负载

下面给出一个用于测试的工作负载 YAML 实例：

```yaml
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

部署好后，会自动创建响应的公网 CLB 接入流量，通过以下命令获取对应的 CLB ID：
```bash
$ kubectl svc httpbin -o jsonpath='{.metadata.annotations.service\.kubernetes\.io/loadbalance-id}'
lb-********
```

记录下获取到的 CLB ID，后续 KEDA 的扩缩容配置需要用到。

## 使用 ScaledObject 配置基于 CLB 监控指标的弹性伸缩

### 配置方法

基于 CLB 的监控指标通常用于在线业务，通常使用 KEDA 的 `ScaledObject` 配置弹性伸缩，配置 `external` 类型的 trigger，并传入所需的 metadata，主要包含以下字段：
* `scalerAddress` 是 `keda-operator` 调用 `keda-tencentcloud-clb-scaler` 时使用的地址。
* `loadBalancerId` 是 CLB 的实例 ID。
* `metricName` 是 CLB 的监控指标名称，公网和内网的大部分指标相同，具体指标列表参考官方文档 [公网负载均衡监控指标](https://cloud.tencent.com/document/product/248/51898) 和 [内网负载均衡监控指标](https://cloud.tencent.com/document/product/248/51899)。
* `threshold` 是扩缩容的指标阈值，即会通过比较 `metricValue / Pod 数量` 与 `threshold` 的值来决定是否扩缩容。
* `listener` 是唯一可选的配置，指定监控指标的 CLB 监听器，格式：`协议/端口`。

### 配置示例一：基于 CLB 连接数指标的弹性伸缩

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
        metricName: ClientConnum # 连接数指标
        threshold: "100" # 每个 Pod 处理 100 条连接
        listener: "TCP/8080" # 可选，指定监听器，格式：协议/端口
        # highlight-end
```

### 配置示例二：基于 CLB QPS 指标的弹性伸缩

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
        metricName: TotalReq # 每秒连接数指标
        threshold: "500" # 平均每个 Pod 支撑 500 QPS
        listener: "TCP/8080" # 可选，指定监听器，格式：协议/端口
        # highlight-end
```

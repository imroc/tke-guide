# 基于 Apache Pulsar 消息队列的弹性伸缩

## 概述

KEDA 的触发器支持 Apache Pulsar，即根据 Pulsar 消息队列中的未消费的消息数量进行水平伸缩，用法参考 [KEDA Scalers: Apache Pulsar](https://keda.sh/docs/latest/scalers/pulsar/)。

腾讯云上也有商业版的 Pulsar 产品，即 [TDMQ for Pulsar](https://cloud.tencent.com/product/tpulsar)，本文举例介绍配置基于 `TDMQ for Pulsar` 消息队列中未消费的消息数量进行水平伸缩，当然如果你自建了开源的 Apache Pulsar，配置方法也是类似的。

## 操作步骤

下面使用 [pulsar-demo](https://github.com/imroc/pulsar-demo) 来模拟 Pulsar 生产者和消费者，再结合 KEDA 配置实现 Pulsar 消费者基于 Pulsar 消息数量的水平伸缩，在实际使用中，可根据自己的情况进行相应替换。

### 获取 Pulsar API 调用地址

在 [Pulsar 集群管理页面](https://console.cloud.tencent.com/tdmq/cluster) 找到需要使用的 Pulsar 集群，点击【接入地址】可获取 Pulsar 的 URL，通常使用 VPC 内网接入地址（解析出来是 169 保留网段的 IP，在任意 VPC 都可用）：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F22%2F20240422164318.png)

复制并记录一下这个 API 调用地址。

### 获取 Pulsar Topic

在 [Pulsar Topic 管理页面](https://console.cloud.tencent.com/tdmq/topic)，复制 Topic 名称。

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F22%2F20240422173032.png)

:::tip[注意]

只支持持久化类型的 Topic，配置所需的 Topic 是在这里复制的 Topic 名称前面加 `persistent://`。

:::

### 获取 Pulsar JWT Token

确保在 [Pulsar 角色管理](https://console.cloud.tencent.com/tdmq/role) 创建好需要的角色，并在 [Pulsar 命名空间](https://console.cloud.tencent.com/tdmq/env) 中【配置权限】，确保所需角色有相应的生产消息或消费消息的权限。

然后复制密钥，即 Pulsar 客户端所需的 JWT Token：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F22%2F20240422173700.png)

### 获取订阅名称

在 Topic 管理的的消费者页面，根据需要，查看已有的订阅，或者新建订阅，记录下需要使用的订阅名称：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F22%2F20240422174304.png)

### 部署生产者

1. 准备生产者配置，根据前面获取的 Pulsar 相关信息替换配置：
  ```yaml
  apiVersion: v1
  stringData:
    # highlight-start
    URL: http://pulsar-xxxxxxxxxxxx.tdmq.ap-cd.qcloud.tencenttdmq.com:5005 # 替换 API 调用地址
    TOPIC: persistent://pulsar-xxxxxxxxxxxx/test-ns/test-topic # 替换 Topic
    TOKEN: xxx # 替换角色密钥 (JWT Token)
    # highligh-end
  kind: Secret
  metadata:
    name: producer-secret
  type: Opaque
  ```
2. 部署生产者持续发送新消息：
  ```yaml
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: producer
  spec:
    replicas: 1
    selector:
      matchLabels:
        app: producer
    template:
      metadata:
        labels:
          app: producer
      spec:
        containers:
          - name: producer
            image: imroc/pulsar-demo:main
            imagePullPolicy: Always
            args:
              - producer
              - --produce-duration
              - 2s # 每 2s 生产一条消息
            envFrom:
              - secretRef:
                  name: producer-secret
        terminationGracePeriodSeconds: 1
  ```

### 部署消费者

1. 准备消费者配置，根据前面获取的 Pulsar 相关信息替换配置：
  ```yaml
  apiVersion: v1
  stringData:
    # highlight-start
    URL: http://pulsar-xxxxxxxxxxxx.tdmq.ap-cd.qcloud.tencenttdmq.com:5005 # 替换 API 调用地址
    TOPIC: persistent://pulsar-xxxxxxxxxxxx/test-ns/test-topic # 替换 Topic
    TOKEN: xxx # 替换角色密钥 (JWT Token)
    SUBSCRIPTION: xxx # 替换订阅名称
    # highligh-end
  kind: Secret
  metadata:
    name: consumer-secret
  type: Opaque
  ```
2. 通过 Deployment 部署消费者，持续消费消息：
  ```yaml
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: consumer
  spec:
    replicas: 1
    selector:
      matchLabels:
        app: consumer
    template:
      metadata:
        labels:
          app: consumer
      spec:
        containers:
        - args:
          - consumer
          - --consume-duration
          - 10s # 单个消费者每 10s 处理完一条消息
          envFrom:
          - secretRef:
              name: consumer-secret
          image: imroc/pulsar-demo:main
          imagePullPolicy: Always
          name: consumer
        terminationGracePeriodSeconds: 1
  ```

### 配置 ScaledObject

1. 先创建 `TriggerAuthentication` 并引用 `consumer-secret` 中的 TOKEN：
  ```yaml
  apiVersion: keda.sh/v1alpha1
  kind: TriggerAuthentication
  metadata:
    name: consumer-auth
  spec:
    secretTargetRef:
      # highlight-start
      - parameter: bearerToken
        name: consumer-secret
        key: TOKEN
      # highlight-end
  ```
2. 创建 ScaledObject（替换高亮行配置）：
  ```yaml
  apiVersion: keda.sh/v1alpha1
  kind: ScaledObject
  metadata:
    name: consumer-scaledobject
  spec:
    scaleTargetRef:
      apiVersion: apps/v1
      kind: Deployment
      name: consumer
    pollingInterval: 15
    idleReplicaCount: 0 # 没有消息时缩到 0
    minReplicaCount: 1
    maxReplicaCount: 100
    triggers:
      - type: pulsar
        metadata:
          adminURL: http://pulsar-xxxxxxxxxxxx.tdmq.ap-cd.qcloud.tencenttdmq.com:5005 # 替换 API 调用地址
          topic: persistent://pulsar-xxxxxxxxxxxx/test/persist-topic # 替换 Topic
          subscription: my-sub # 替换订阅名称
          isPartitionedTopic: "true" # 如果分区数大于 1，这里就置为 true
          msgBacklogThreshold: "5" # 伸缩阈值，副本数=CEIL(消息堆积数/msgBacklogThreshold)
          activationMsgBacklogThreshold: "1" # 如果当前副本数为 0，只要队列里来新消息了，就将副本置为 1 并启用伸缩
          authModes: bearer # 角色密钥（JWT Token）本质上是 bearer 的认证模式
        authenticationRef:
          name: consumer-auth # 引用前面创建的 TriggerAuthentication
  ```

### 查看 HPA

如果配置正确，会自动创建出对应的 HPA 资源，可以检查下：

```bash
$ kubectl get hpa
NAME                             REFERENCE             TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
keda-hpa-consumer-scaledobject   Deployment/consumer   4600m/5 (avg)   1         10        5          31m
```

> 可以通过 `TARGETS` 反推出当前消息堆积数量，以上面 get 到的结果为例：`堆积消息数=4.6*5=23`

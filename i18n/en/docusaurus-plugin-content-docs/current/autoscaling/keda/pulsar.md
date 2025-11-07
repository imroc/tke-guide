# Elastic Scaling Based on Apache Pulsar Message Queue

## Overview

KEDA's triggers support Apache Pulsar, i.e., horizontal scaling based on the number of unconsumed messages in the Pulsar message queue. For usage, refer to [KEDA Scalers: Apache Pulsar](https://keda.sh/docs/latest/scalers/pulsar/).

Tencent Cloud also has a commercial Pulsar product, i.e., [TDMQ for Pulsar](https://cloud.tencent.com/product/tpulsar). This article provides examples of configuring horizontal scaling based on the number of unconsumed messages in `TDMQ for Pulsar` message queues. Of course, if you have self-built open-source Apache Pulsar, the configuration method is similar.

## Operation Steps

Below we use [pulsar-demo](https://github.com/imroc/pulsar-demo) to simulate Pulsar producers and consumers, and combine KEDA configuration to implement horizontal scaling of Pulsar consumers based on Pulsar message count. In actual use, you can replace according to your own situation.

### Get Pulsar API Call Address

On the [Pulsar Cluster Management Page](https://console.cloud.tencent.com/tdmq/cluster), find the Pulsar cluster to use, click [Access Address] to get the Pulsar URL. Usually use the VPC private network access address (which resolves to IPs in the 169 reserved segment, usable in any VPC):

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F22%2F20240422164318.png)

Copy and record this API call address.

### Get Pulsar Topic

On the [Pulsar Topic Management Page](https://console.cloud.tencent.com/tdmq/topic), copy the Topic name.

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F22%2F20240422173032.png)

:::tip[Note]

Only persistent type Topics are supported. The Topic required for configuration is the Topic name copied here with `persistent://` added in front.

:::

### Get Pulsar JWT Token

Ensure the required role is created in [Pulsar Role Management](https://console.cloud.tencent.com/tdmq/role), and [Configure Permissions] in [Pulsar Namespace](https://console.cloud.tencent.com/tdmq/env) to ensure the required role has corresponding permissions to produce or consume messages.

Then copy the key, which is the JWT Token required by the Pulsar client:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F22%2F20240422173700.png)

### Get Subscription Name

On the consumer page of Topic management, according to your needs, view existing subscriptions or create new subscriptions, and record the subscription name to use:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F22%2F20240422174304.png)

### Deploy Producer

1. Prepare producer configuration, replacing the configuration according to the Pulsar information obtained earlier:
  ```yaml showLineNumbers
  apiVersion: v1
  stringData:
    # highlight-start
    URL: http://pulsar-xxxxxxxxxxxx.tdmq.ap-cd.qcloud.tencenttdmq.com:5005 # Replace API call address
    TOPIC: persistent://pulsar-xxxxxxxxxxxx/test-ns/test-topic # Replace Topic
    TOKEN: xxx # Replace role key (JWT Token)
    # highligh-end
  kind: Secret
  metadata:
    name: producer-secret
  type: Opaque
  ```
2. Deploy producer to continuously send new messages:
  ```yaml showLineNumbers
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
              - 2s # Produce one message every 2s
            envFrom:
              - secretRef:
                  name: producer-secret
        terminationGracePeriodSeconds: 1
  ```

### Deploy Consumer

1. Prepare consumer configuration, replacing the configuration according to the Pulsar information obtained earlier:
  ```yaml showLineNumbers
  apiVersion: v1
  stringData:
    # highlight-start
    URL: http://pulsar-xxxxxxxxxxxx.tdmq.ap-cd.qcloud.tencenttdmq.com:5005 # Replace API call address
    TOPIC: persistent://pulsar-xxxxxxxxxxxx/test-ns/test-topic # Replace Topic
    TOKEN: xxx # Replace role key (JWT Token)
    SUBSCRIPTION: xxx # Replace subscription name
    # highligh-end
  kind: Secret
  metadata:
    name: consumer-secret
  type: Opaque
  ```
2. Deploy consumer via Deployment to continuously consume messages:
  ```yaml showLineNumbers
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
          - 10s # Each consumer processes one message every 10s
          envFrom:
          - secretRef:
              name: consumer-secret
          image: imroc/pulsar-demo:main
          imagePullPolicy: Always
          name: consumer
        terminationGracePeriodSeconds: 1
  ```

### Configure ScaledObject

1. First create `TriggerAuthentication` and reference TOKEN from `consumer-secret`:
  ```yaml showLineNumbers
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
2. Create ScaledObject (replace highlighted configuration):
  ```yaml showLineNumbers
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
    idleReplicaCount: 0 # Scale to 0 when no messages
    minReplicaCount: 1
    maxReplicaCount: 100
    triggers:
      - type: pulsar
        metadata:
          adminURL: http://pulsar-xxxxxxxxxxxx.tdmq.ap-cd.qcloud.tencenttdmq.com:5005 # Replace API call address
          topic: persistent://pulsar-xxxxxxxxxxxx/test/persist-topic # Replace Topic
          subscription: my-sub # Replace subscription name
          isPartitionedTopic: "true" # If partition count > 1, set to true
          msgBacklogThreshold: "5" # Scaling threshold, replica count = CEIL(message backlog count/msgBacklogThreshold)
          activationMsgBacklogThreshold: "1" # If current replica count is 0, as soon as new messages come to the queue, set replicas to 1 and enable scaling
          authModes: bearer # Role key (JWT Token) is essentially bearer authentication mode
        authenticationRef:
          name: consumer-auth # Reference TriggerAuthentication created earlier
  ```

### Check HPA

If configured correctly, a corresponding HPA resource will be automatically created. You can check it:

```bash
$ kubectl get hpa
NAME                             REFERENCE             TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
keda-hpa-consumer-scaledobject   Deployment/consumer   4600m/5 (avg)   1         10        5          31m
```

> You can deduce the current message backlog count from `TARGETS`. Taking the above get result as an example: `Backlog message count = 4.6*5 = 23`

## ScaledJob + Super Nodes

If a single message takes a long time to process, but you need to get processing results as promptly as possible, you can configure ScaledJob. For each new message in the queue, a new Job is automatically created to consume it, and let the Job's Pod be scheduled to super nodes. This way, computing resources can be completely used on demand and billed by usage.

The trigger configuration is completely the same for ScaledObject and ScaledJob. If you need to configure ScaledJob, you can refer to the ScaledObject configuration.

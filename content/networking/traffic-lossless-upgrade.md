# 核心应用流量完全无损升级

## 概述

对于某些核心的应用（比如流量网关），不希望因升级导致故障，下面列举一些可能导致故障的情况：
1. 应用的优雅终止逻辑实现上的不够完善，导致 Pod 停止时部分存量连接异常。
2. 存量长连接迟迟不断开，可能超过 `terminationGracePeriodSeconds`，导致 Pod 停止时，存量连接异常关闭。
3. 新版应用可能引入隐藏 BUG 或不兼容改动，健康检查探测不到，等上线后一段时间才被动发现。
4. CLB 摘流和 Pod 停止两个过程异步并行执行，在极端的场景下，Pod 已经开始进入优雅终止流程，不接收增量连接，但在 CLB 这边还没来得及摘流（改权重），导致个别新连接调度到这个正在停止的 Pod 而不被处理。

在升级的时候希望采取非常保守的策略，确保待升级的 Pod 先完全被摘流，然后再手动重建 Pod 触发升级，持续经现网流量灰度一段时间后，如果没问题再逐渐继续扩大灰度范围，期间发现任何问题都可以回滚已升级的副本，让风险能够得到绝对可控。

这种场景可以使用 StatefulSet 部署核心应用，并配合 TKE 的 Service 注解来实现，本文介绍具体操作方法和最佳实践。

## 操作步骤

### 创建 StatefulSet

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: nginx
spec:
  replicas: 10
  podManagementPolicy: Parallel
  selector:
    matchLabels:
      app: nginx
  serviceName: nginx
  template:
    metadata:
      annotations:
        tke.cloud.tencent.com/networks: tke-route-eni # GlobalRouter 与 VPC-CNI 混用时显式声明使用 VPC-CNI
      labels:
        app: nginx
    spec:
      containers:
        - image: nginx:1.25.3
          imagePullPolicy: IfNotPresent
          name: nginx
          ports:
            - containerPort: 80
              name: http
              protocol: TCP
          resources: # GlobalRouter 与 VPC-CNI 混用时显式声明使用 VPC-CNI
            limits:
              tke.cloud.tencent.com/eni-ip: "1"
            requests:
              tke.cloud.tencent.com/eni-ip: "1"
  updateStrategy:
    type: OnDelete # 重要：使用手动重建触发升级而非滚动更新

---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: nginx
  annotations:
    service.cloud.tencent.com/direct-access: "true" # 重要：启用 CLB 直连 Pod
  name: nginx
spec:
  ports:
    - port: 80
      protocol: TCP
      targetPort: 80
  selector:
    app: nginx
  type: LoadBalancer
```

* StatefulSet 的 `updateStrategy` 使用 `OnDelete`。
* 确保 Pod 使用 VPC-CNI 网络或调度到超级节点（方便启用 CLB 直连）。
* 加 Service 注解启用 CLB 直连。

### 逐个升级

1. 首先将 StatefulSet 所使用的镜像替换为新的镜像（升级后期望使用的镜像版本）。
    ```bash
    kubectl set image statefulset/nginx nginx=nginx:1.25.4
    ```
2. 将 StatefulSet 副本数加 1，因为副本重建的过程中副本数会少 1 个，提前增加 1 个副本可避免升级过程中 Pod 的平均负载过高导致业务异常：
    ```bash
    kubectl scale --replicas=11 statefulset/nginx
    ```
3. 为 Service 加注解：
    ```yaml
        service.cloud.tencent.com/lb-rs-weight: '{"defaultWeight":10,"groups":[{"key":{"proto":"TCP","port":80},"statefulSets":[{"name":"nginx","weights":[{"weight":0,"podIndexes":[0]}]}]}]}'
    ```
    * `key` 里填入 Service 里声明的端口和协议，如果有多个端口，需在 `groups` 数组里再加一份配置（只有 `key` 不同），如：
        ```yaml
            service.cloud.tencent.com/lb-rs-weight: '{"defaultWeight":10,"groups":[{"key":{"proto":"TCP","port":80},"statefulSets":[{"name":"nginx","weights":[{"weight":0,"podIndexes":[0]}]}]},{"key":{"proto":"TCP","port":8080},"statefulSets":[{"name":"nginx","weights":[{"weight":0,"podIndexes":[0]}]}]}]}'
        ```
    * `statefulSets` 里的 `name` 填入 StatefulSet 的名称。
    * `podIndexes` 里填入接下来计划升级的 Pod 序号，一般从 0 开始。
    * `weight` 置为 0，即将该序号的 Pod 从 CLB 后端摘流（增量连接不再调度过去，等待存量连接结束）。
3. 在 CLB 控制台查看对应 CLB 的监听器绑定的后端服务，确认将要升级的 Pod IP 的流量权重为 0：
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F08%2F20240408172648.png)
4. 等待存量连接和流量完全归零，可在 CLB 的监控页面确认（输入对应的监听器和后端服务进行过滤）：
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F08%2F20240408173034.png)
5. 删除计划升级的 Pod，触发重建升级：
    ```bash
    kubectl delete pod nginx-0
    ```
6. 观察升级后的 Pod 运行状态、镜像和健康状态都符合预期（经现网流量验证一段时间，发现异常可回滚镜像版本并再次按照 3~5 的步骤回滚回去）：
    ```bash
    $ kubectl get pod -o wide nginx-0
    NAME      READY   STATUS    RESTARTS   AGE   IP           NODE         NOMINATED NODE   READINESS GATES
    nginx-0   1/1     Running   0          86s   10.10.2.28   10.10.11.3   <none>           1/1
    $ kubectl get pod nginx-0 -o yaml | grep image:
      - image: nginx:1.25.4
        image: docker.io/library/nginx:1.25.4
    ```
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F04%2F08%2F20240408180126.png)
7. 修改 Service 注解中的 `podIndexes`，准备升级下一个 Pod：
    ```yaml
        service.cloud.tencent.com/lb-rs-weight: '{"defaultWeight":10,"groups":[{"key":{"proto":"TCP","port":80},"statefulSets":[{"name":"nginx","weights":[{"weight":0,"podIndexes":[1]}]}]}]}'
    ```
8. 循环 3~7 的步骤，直到倒数第二个副本升级完成。
9. 删除 `service.cloud.tencent.com/lb-rs-weight` 这个 Service 注解，恢复所有 Pod 的流量权重。
10. 恢复 StatefulSet 的副本数（缩掉最后一个冗余的副本）：
    ```bash
    kubectl scale --replicas=10 statefulset/nginx
    ```
    至此，完成升级。

### 分批升级

如果副本数较多，嫌逐个升级太麻烦，可以分批升级，也就是从每次升级 1 个 Pod 变为每次升级多个 Pod，操作步骤与 [逐个升级](#逐个升级) 基本一致，只是每次操作的 Pod 数量的区别，主要体现在：
* 提前扩的副本数以及每次删除重建的副本数从 1 个变为多个。
* `service.cloud.tencent.com/lb-rs-weight` 注解里的 `podIndexes` 从 1 个变为多个，如（假设每次升 4 个 Pod）：
    ```yaml
        service.cloud.tencent.com/lb-rs-weight: '{"defaultWeight":10,"groups":[{"key":{"proto":"TCP","port":80},"statefulSets":[{"name":"nginx","weights":[{"weight":0,"podIndexes":[0,1,2,3]}]}]}]}'
    ```

# 按业务分账

## 概述

同一个集群中，可能会安装多个 Nginx Ingress 实例，不同业务也可能使用不同的 Nginx Ingress 实例来接入流量，如果希望按照业务维度对 Ingress 的费用进行分账，可参考本文的方法来实现。

## 使用云标签标记云资源

对于 Nginx Ingress 所产生的费用，主要在于以下两方面：
1. CLB（负载均衡）的费用。
2. Nginx Ingress 的 Pod 所占用计算资源的费用。

费用中心支持按标签分账，要按业务维度分账，可以对不同业务的 Nginx Ingress 的 CLB 和 Pod 打上不同的云标签。

## 新建云标签

假设代表业务的云标签的 key 为 `business`，value 为具体业务的名称，假设有 `A` 和 `B` 两个业务。

在 [标签列表](https://console.cloud.tencent.com/tag/taglist) 点击【新建标签】:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F05%2F21%2F20240521201634.png)

## 设置分账标签

在 [分账标签](https://console.cloud.tencent.com/expense/tag) 中设置 `business` 为分账标签：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F05%2F21%2F20240521204515.png)

## 通过 namespace 和云标签划分业务

集群中不同 namespace 可能用于不同业务，一个业务可能关联一个或多个 namespace，假设 ns1 和 ns2 属于 A 业务，ns3 属于 B 业务，对应的云标签分别是 `business: A` 和 `business: B`。

## 为 CLB 打云标签

建议安装 Nginx Ingress 的时候使用已有 CLB 的方式来关联 CLB，这样就可以在 CLB 控制台手动创建 CLB 并指定相应的云标签。

分别为 `A` 和 `B` 两个业务创建 CLB 并指定 `business` 云标签：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F05%2F21%2F20240521201856.png)

## 为 Pod 打云标签

要实现 Nginx Ingress 的 Pod 计算资源按业务分账，需要让 Nginx Ingress 的 Pod 调度到超级节点，或者使用 TKE Serverless 集群，再为 Pod 指定注解，打上相应的云标签。

另外还需要注意的是，不同 Nginx Ingress 实例需要使用不同的 IngressClass 和 Namespace 以避免冲突，参考[安装多个 Nginx Ingress Controller](./multi-ingress-controller.md) 。

假设 A 业务的 IngressClass 是 `a-ingress`，B 业务的 IngressClass 是 `b-ingress`，以下是安装 Nginx Ingress 时的 `values.yaml` 示例：

```yaml title="values.yaml"
controller:
  ingressClassName: a-ingress
  ingressClassResource:
    name: a-ingress
    controllerValue: k8s.io/a-ingress
  nodeSelector: # 如果不是 TKE Serverless 集群，加这个 nodeSelector 确保 Nginx Ingress 调度到超级节点上去
    node.kubernetes.io/instance-type: eklet
  podAnnotations:
    eks.tke.cloud.tencent.com/resource-tag: '{"business":"A"}'  # 为 Nginx Ingress 的 Pod 指定云标签
```

> Pod 支持云标签的注解参考 [TKE 官方文档](https://cloud.tencent.com/document/product/457/44173#d856d745-1797-4b19-b10a-9bce4c0bd54c)

## 安装 Nginx Ingress

安装的 Namespace 需要不同，安装时指定该业务的 Nginx Ingress 所使用的命名空间：

```bash
helm upgrade --install a-ingress ingress-nginx/ingress-nginx \
  --namespace a-ingress --create-namespace \
  -f values.yaml
```

## 创建 Ingress

ns1 和 ns2 命名空间属于 A 业务，创建相应的 Ingress：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
  namespace: ns2
spec:
  ingressClassName: a-ingress # 指定 A 业务的 IngressClass
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: a-test
                port:
                  number: 80
```

ns3 命名空间属于 B 业务，创建相应的 Ingress：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
  namespace: ns3
spec:
  ingressClassName: b-ingress # 指定 B 业务的 IngressClass
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: b-test
                port:
                  number: 80
```

## 费用分账查看

在 【费用中心】-【费用账单】-【账单查看】- 【多维度汇总账单】-【按标签】中，选择 `business` 作为分账标签：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F05%2F21%2F20240521204737.png)

这样就可以按业务展示费用账单了。

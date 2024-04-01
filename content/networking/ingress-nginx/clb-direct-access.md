# 启用 CLB 直连

流量从 CLB 转发到 Nginx Ingress 这段链路可以直连（不走 NodePort），带来更好的性能，也可以实现获取真实源 IP 的需求。

如果你使用的 TKE Serverless 集群或者能确保所有 Nginx Ingress Pod 调度到超级节点，这时本身就是直连的，不需要做什么。

其它情况下，这段链路中间默认会走 NodePort，以下是启用直连的方法（根据自己的集群环境对号入座）。

> 参考[使用 LoadBalancer 直连 Pod 模式 Service](https://cloud.tencent.com/document/product/457/41897)。

## GlobalRouter+VPC-CNI 网络模式启用直连

如果集群网络模式是 GlobalRouter，且启用了 VPC-CNI：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F21%2F20240321194833.png)

这种情况建议为 Nginx Ingress 声明用 VPC-CNI 网络，同时启用 CLB 直连，`values.yaml` 配置方法：

```yaml
controller:
  podAnnotations:
    tke.cloud.tencent.com/networks: tke-route-eni # 声明使用 VPC-CNI 网络
  resources: #  resources 里声明使用弹性网卡
    requests:
      tke.cloud.tencent.com/eni-ip: "1"
    limits:
      tke.cloud.tencent.com/eni-ip: "1"
  service:
    annotations:
      service.cloud.tencent.com/direct-access: "true" # 启用 CLB 直通
```

## GlobalRouter 网络模式启用直连

如果集群网络是 GlobalRouter，但没有启用 VPC-CNI，建议最好是为集群开启 VPC-CNI，然后按照上面的方法启用 CLB 直连。如果实在不好开启，且腾讯云账号是带宽上移类型（参考[账号类型说明](https://cloud.tencent.com/document/product/1199/49090)），也可以有方法启用直连，只是有一些限制 (具体参考 [这里的说明](https://cloud.tencent.com/document/product/457/41897#.E4.BD.BF.E7.94.A8.E9.99.90.E5.88.B62))。

如果确认满足条件且接受使用限制，参考以下步骤启用直连：

1. 修改 configmap 开启 GlobalRouter 集群维度的直连能力:

```bash
kubectl edit configmap tke-service-controller-config -n kube-system
```

将 `GlobalRouteDirectAccess` 置为 true:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F21%2F20240321200716.png)

2. 配置 `values.yaml` 启用 CLB 直连：

```yaml
controller:
  service:
    annotations:
      service.cloud.tencent.com/direct-access: "true" # 启用 CLB 直通
```

## VPC-CNI 网络模式启用直连

如果集群网络本身就是 VPC-CNI，那就比较简单了，直接配置 `values.yaml` 启用 CLB 直连即可：

```yaml
controller:
  service:
    annotations:
      service.cloud.tencent.com/direct-access: "true" # 启用 CLB 直通
```

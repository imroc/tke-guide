# Enabling CLB Direct Access

## Overview

The traffic link from CLB to Nginx Ingress can be direct (not going through NodePort), bringing better performance and meeting the requirement of obtaining the real source IP.

If you are using a TKE Serverless cluster or can ensure that all Nginx Ingress Pods are scheduled to super nodes, this link is already direct by default and no additional configuration is needed.

In other cases, this link goes through NodePort by default. Below are the methods to enable direct access (choose according to your cluster environment).

> Reference: [Using LoadBalancer Direct to Pod Mode Service](https://cloud.tencent.com/document/product/457/41897).

## Enabling Direct Access with GlobalRouter+VPC-CNI Network Mode

If the cluster network mode is GlobalRouter with VPC-CNI enabled:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F21%2F20240321194833.png)

In this case, it is recommended to declare VPC-CNI network for Nginx Ingress while enabling CLB direct access. Configuration method in `values.yaml`:

```yaml
controller:
  podAnnotations:
    tke.cloud.tencent.com/networks: tke-route-eni # Declare using VPC-CNI network
  resources: # Declare using elastic network interface in resources
    requests:
      tke.cloud.tencent.com/eni-ip: "1"
    limits:
      tke.cloud.tencent.com/eni-ip: "1"
  service:
    annotations:
      service.cloud.tencent.com/direct-access: "true" # Enable CLB direct access
```

## Enabling Direct Access with GlobalRouter Network Mode

If the cluster network is GlobalRouter but VPC-CNI is not enabled, it is recommended to enable VPC-CNI for the cluster first, then enable CLB direct access using the method above. If enabling VPC-CNI is not feasible and your Tencent Cloud account is of bandwidth upper shift type (refer to [Account Type Description](https://cloud.tencent.com/document/product/1199/49090)), there is also a method to enable direct access, but with some limitations (refer to [GlobalRouter Direct Access Usage Limitations](https://cloud.tencent.com/document/product/457/41897#.E4.BD.BF.E7.94.A8.E9.99.90.E5.88.B62) for details).

If you confirm that the conditions are met and accept the usage limitations, follow these steps to enable direct access:

1. Modify the configmap to enable GlobalRouter cluster-level direct access capability:

```bash
kubectl edit configmap tke-service-controller-config -n kube-system
```

Set `GlobalRouteDirectAccess` to true:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F21%2F20240321200716.png)

2. Configure `values.yaml` to enable CLB direct access:

```yaml
controller:
  service:
    annotations:
      service.cloud.tencent.com/direct-access: "true" # Enable CLB direct access
```

## Enabling Direct Access with VPC-CNI Network Mode

If the cluster network itself is VPC-CNI, it is quite simple. Just configure `values.yaml` to enable CLB direct access:

```yaml
controller:
  service:
    annotations:
      service.cloud.tencent.com/direct-access: "true" # Enable CLB direct access
```

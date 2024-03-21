# 在 TKE 自建 Nginx Ingress

## 使用 helm 安装

添加 helm repo:

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
```

查看默认配置:

```bash
helm show values ingress-nginx/ingress-nginx
```

Nginx Ingress 依赖的镜像在 `registry.k8s.io` 这个 registry 下，国内网络环境无法拉取，可替换为 docker hub 中的 mirror 镜像。

准备 `values.yaml`:

```yaml
controller: # 默认的镜像在境内无法拉取，可替换为 docker hub 上的 mirror 镜像
  image:
    registry: docker.io
    image: k8smirror/ingress-nginx-controller
  admissionWebhooks:
    patch:
      image:
        registry: docker.io
        image: k8smirror/ingress-nginx-kube-webhook-certgen
  defaultBackend:
    image:
      registry: docker.io
      image: k8smirror/defaultbackend-amd64
  opentelemetry:
    image:
      registry: docker.io
      image: k8smirror/ingress-nginx-opentelemetry
```

> 配置中的 mirror 镜像均使用 [image-porter](https://github.com/imroc/image-porter) 长期自动同步，可放心安装和升级。

安装：

```bash
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  -f values.yaml
```

> 后续如果需要修改 values 配置，或者升级版本，都可以用个命令。

查看流量入口(CLB VIP 或域名)：

```bash
$ kubectl get services -n ingress-nginx
NAME                                 TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)                      AGE
ingress-nginx-controller             LoadBalancer   172.16.145.161   162.14.91.101   80:30683/TCP,443:32111/TCP   53s
ingress-nginx-controller-admission   ClusterIP      172.16.166.237   <none>          443/TCP                      53s
```

> `LoadBalancer` 类型 Service 的 `EXTERNAL-IP` 就是 CLB 的 VIP 或域名，可以配置下 DNS 解析。如果是 VIP，就配 A 记录；如果是 CLB 域名，就配置 CNAME 记录。

## 版本与升级

Nginx Ingress 的版本需要与 Kubernetes 集群版本能够兼容，可参考官方 [Supported Versions table](https://github.com/kubernetes/ingress-nginx?tab=readme-ov-file#supported-versions-table) 确认下当前集群版本能否支持最新的 nginx ingress，如果不支持，安装的时候指定下 chart 版本。

比如当前的 TKE 集群版本是 1.24，chart 版本最高只能到 `4.7.*`，检查下有哪些可用版本：

```bash
$ helm search repo ingress-nginx/ingress-nginx --versions | grep 4.7.
ingress-nginx/ingress-nginx     4.7.5           1.8.5           Ingress controller for Kubernetes using NGINX a...
ingress-nginx/ingress-nginx     4.7.3           1.8.4           Ingress controller for Kubernetes using NGINX a...
ingress-nginx/ingress-nginx     4.7.2           1.8.2           Ingress controller for Kubernetes using NGINX a...
ingress-nginx/ingress-nginx     4.7.1           1.8.1           Ingress controller for Kubernetes using NGINX a...
ingress-nginx/ingress-nginx     4.7.0           1.8.0           Ingress controller for Kubernetes using NGINX a...
```

可以看到 `4.7.*` 版本最高是 `4.7.5`，安装的时候我们加上版本号：

```bash
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  # highlight-next-line
  --version 4.7.5 \
  --namespace ingress-nginx --create-namespace \
  -f values.yaml
```

**注意：** TKE 集群升级前，先检查下当前 Nginx Ingress 版本能否兼容升级后的集群版本，如果不能兼容，先升级下 Nginx Ingress（用上面的命令指定 chart 版本号）。

## 自定义 CLB

默认安装会自动创建出一个公网来 CLB 接入流量，你可以利用 Service 注解对 Nginx Ingress Controller 的 CLB 进行自定义，比如改成内网 CLB，在 `values.yaml` 中这样定义:

```yaml
controller:
  service:
    annotations:
      service.kubernetes.io/qcloud-loadbalancer-internal-subnetid: 'subnet-xxxxxx' # 内网 CLB 需指定 CLB 实例所在的子网 ID
```

你也可以直接在 [CLB 控制台](https://console.cloud.tencent.com/clb/instance) 根据自身需求创建一个 CLB （比如自定义实例规格、运营商类型、计费模式、带宽上限等），然后在 `values.yaml` 中用注解复用这个 CLB:

```yaml
controller:
  service:
    annotations:
      service.kubernetes.io/tke-existed-lbid: 'lb-xxxxxxxx' # 指定已有 CLB 的实例 ID
```

> 参考文档 [Service 使用已有 CLB](https://cloud.tencent.com/document/product/457/45491)。
>
> **注意:** 在 CLB 控制台创建 CLB 实例时，选择的 VPC 需与集群一致。

## 启用 CLB 直连

CLB --> Nginx Ingress 这段链路可以直连（不走 NodePort），带来更好的性能，也可以实现获取真实源 IP 的需求。

如果你使用的 TKE Serverless 集群或者能确保所有 Nginx Ingress Pod 调度到超级节点，这时本身就是直连的，不需要做什么。

其它情况下，这段链路中间会走 NodePort，以下是启用直连的方法（根据自己的集群环境对号入座）。

> 参考[使用 LoadBalancer 直连 Pod 模式 Service](https://cloud.tencent.com/document/product/457/41897)。

### GlobalRouter+VPC-CNI 网络模式启用直连

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

### GlobalRouter 网络模式启用直连

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

## 高并发场景优化

TODO

## 集成 Prometheus 监控

TODO

## 集成 Grafana 监控面板

TODO

## 集成 CLS 日志服务

TODO

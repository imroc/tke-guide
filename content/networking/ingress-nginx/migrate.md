# 从 TKE Nginx Ingress 插件迁移到自建 Nginx Ingress

## 迁移的好处

迁移到自建 Nginx Ingress 有什么好处？Nginx Ingress 提供的功能和配置都是非常多和灵活，可以满足各种使用场景，自建可以解锁 Nginx Ingress 的全部功能，可以根据自己需求，对配置进行自定义，还能够及时更新版本。

## 迁移思路

用本文中自建的方法创建一套新的 NginxIngress 实例，与旧的实例共享同一个 IngressClass，也就会共享相同的 Ingress 转发规则，两套流量入口共存，最后修改 DNS 指向新的入口地址完成平滑迁移。

## 确认已安装的 Nginx Ingress 相关信息

1. 先确认已安装的 Nginx Ingress 实例的 IngressClass 名称，比如：

```bash
$ kubectl get deploy -A | grep nginx
kube-system            extranet-ingress-nginx-controller           1/1     1            1           216d
```

本例子中只有一个实例，Deployment 名称是 `extranet-ingress-nginx-controller`，IngressClass 是 `-ingress-nginx-controller` 之前的部分，这里是 `extranet`。

2. 然后确认下当前使用的 nginx ingress 的镜像版本：

```yaml
$ kubectl -n kube-system get deploy extranet-ingress-nginx-controller -o yaml | grep image:
        image: ccr.ccs.tencentyun.com/tkeimages/nginx-ingress-controller:v1.9.5
```

本例中版本是 `v1.9.5`，看下对应哪个 chart 版本：

```bash
$ helm search repo ingress-nginx/ingress-nginx --versions  | grep 1.9.5
ingress-nginx/ingress-nginx     4.9.0           1.9.5           Ingress controller for Kubernetes using NGINX a...
```

这里看到是 `4.9.0`，记住这个版本，后面用 helm 安装新版渲染时需要指定这个 chart 版本。

## 准备 values.yaml

主要需要保证 helm 新创建的 Nginx Ingress 实例和 TKE 插件创建 Nginx Ingress 实例共用一个 IngressClass，即让 Ingress 规则在两边同时生效。

看下当前的 IngressClass 定义：

```bash
$ kubectl get ingressclass extranet -o yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  creationTimestamp: "2024-03-27T10:47:49Z"
  generation: 1
  labels:
    app.kubernetes.io/component: controller
  name: extranet
  resourceVersion: "27703380423"
  uid: 5e2de0d1-8eae-4b55-afde-25c8fe37d478
spec:
  # highlight-next-line
  controller: k8s.io/extranet
```

拿到 controller 的值 `k8s.io/extranet`，和 IngressClass 名称一起，配到 `values.yaml` 中：

```yaml
controller:
  ingressClassName: extranet # IngressClass 名称
  ingressClassResource:
    enabled: false # 不自动创建 IngressClass 资源，避免冲突
    controllerValue: k8s.io/extranet # 新 Nginx Ingress 复用已有的 IngressClass
```

## 安装新的 Nginx Ingress Controller

```bash
helm upgrade --install new-extranet-ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --version 4.9.0 \
  -f values.yaml
```

* 避免 release 名称加上 `-controller`  后缀后与已有的 Nginx Ingress Deployment 名称相同，主要是会有同名的 ClusterRole 存在导致 helm 安装失败。
* version 指定前面步骤得到的 chart 版本（当前 nginx ingress 实例版本对应的 chart 版本）。

拿到新的 Nginx Ingress 的流量入口：

```yaml
$ kubectl -n ingress-nginx get svc
NAME                                              TYPE           CLUSTER-IP       EXTERNAL-IP      PORT(S)                      AGE
new-extranet-ingress-nginx-controller             LoadBalancer   172.16.165.100   43.136.214.239   80:31507/TCP,443:31116/TCP   9m37s
```

`EXTERNAL-IP` 是新的流量入口，验证确认下能够正常转发。

## 切换 DNS

至此，新旧 Nginx Ingress 共存，不管走哪个流量入口都能正常转发。

接下来修改域名的 DNS 解析，指向新 Nginx Ingress 流量入口，在 DNS 解析完全生效前，两边流量入口均能正常转发，不管走哪边都没问题，所以这个过程会非常平滑，生产环境的流量不受影响。

## 删除旧 NginxIngress 实例和插件

最后等所有旧的 Nginx Ingress 实例完全没有流量的时候，再去 TKE 控制台先删除 Nginx Ingress 实例：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F28%2F20240328105512.png)

再去【组件管理】里删除 ingressnginx 彻底完成迁移:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F03%2F28%2F20240328104308.png)


# 从 TKE Nginx Ingress 插件迁移到自建 Nginx Ingress

## 操作步骤

### 确认已安装的 Nginx Ingress 相关信息

确认已安装的 Nginx Ingress 实例的 IngressClass 名称，比如：

```bash
$ kubectl get deploy -A | grep nginx
kube-system            extranet-ingress-nginx-controller           1/1     1            1           216d
```

本例子中只有一个实例，Deployment 名称是 `extranet-ingress-nginx-controller`，IngressClass 是 `-ingress-nginx-controller` 之前的部分，这里是 `extranet`。

另外再检查下当前使用的 nginx ingress 的镜像版本：

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

### 卸载 Operator

卸载 Nginx Ingress 插件的 Operator（避免后面被 helm 安装覆盖后又被 Operator 覆盖回去）：

```bash
kubectl -n kube-system delete deploy tke-ingress-nginx-controller-operator
```

### 操作迁移

首先要确认下当前 Nginx Ingress 实例所使用的 CLB 是复用的还是自动创建的，如果是复用的，我们需要为迁移后的 Service 注解也要加注解声明复用 CLB

首先配置 `values.yaml`（注意看注释）：

```yaml
controller:
  ingressClassName: extranet # IngressClass 名称
  service:
    enabled: false # 让 helm 渲染出来的 yaml 没有 Controller 的 Service，避免 LB 重建
```

> 另外也检查下当前副本数和 HPA 配置情况，跟之前也保持一致或调到更高，配置方法参考 [这里](ingress-nginx#调高副本数)。

然后用 helm 渲染 yaml 并用 kubectl 强制替换下（接入流量的 LB 类型 Service 除外）：

```bash
helm template prod ingress-nginx/ingress-nginx \
  --namespace kube-system  \
  --version 4.9.0 \
  -f values.yaml | kubectl replace --force -f -
```

* 先使用 template 渲染 yaml 再用 kubectl replace 进行替换（因为直接用 helm 安装会报错，渲染出来的 Pod Template 里会多一些 label，但这是不可修改的，只能重建）。
* namespace 与之前的命名空间保持一致。
* version 指定第一步中得到的 chart 版本（当前 nginx ingress 实例版本对应的 chart 版本）

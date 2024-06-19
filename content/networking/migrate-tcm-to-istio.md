# 从 TCM 迁移到自建 istio

## 概述

腾讯云服务网格（Tencent Cloud Mesh, TCM）是基于 TKE 的 istio 托管服务，未来将会下线，本文介绍如何从 TCM 迁移到自建 istio。

## 迁移思路

istio 架构分为控制面和数据面，控制面是 istiod，数据面是网关 (istio-ingressgateway/istio-egressgateway) 或 sidecar，数据面的本质上都是使用 Envoy 作为代理程序，控制面会将计算出的流量规则通过 `xDS` 下发给数据面：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F06%2F18%2F20240618150336.png)

TCM 主要托管的是 isitod，迁移的关键点就是使用自建的 istiod 替换 TCM 的 isitod，但由于根证书问题，两者无法共存，也就无法原地平滑迁移，只能新建一套环境来自建 istio，然后逐渐将业务迁移到新建的 istio 环境中，逐步切流量过来，完成全量迁移之前，两套环境还需共存：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F06%2F18%2F20240618170536.png)

## istio 安装原则

我们通过 `istioctl` 命令来安装和升级网格，每个集群都使用一个 `IstioOperator` 的声明式 YAML 来维护 istio 安装配置，主要包含控制面和 ingressgateway 这些组件的安装和配置。

> 同一个集群使用多个 `IstioOperator` 的 YAML 来维护容易导致更新升级时导致不相关的组件或配置被删除或覆盖。
## 下载 istio 发新版

参考 [istio 官方文档](https://istio.io/latest/zh/docs/setup/getting-started/#download) 下载 istio 发新版，如不希望迁移过程中引入太多兼容性问题，可以下载与 TCM 相同版本的 istio 发新版：

```bash
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.18.5 sh -
```

然后将 `istioctl` 安装到 `PATH`:

```bash
cp istio-1.18.5/bin/istioctl /usr/local/bin/istioctl
```

## 安装 istiod

选择一个 TKE 集群作为主集群来安装 istiod，准备部署配置 `master-cluster.yaml`：
```yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  components:
    ingressGateways:
    - enabled: false
      name: istio-ingressgateway
  values:
    pilot:
      env:
        EXTERNAL_ISTIOD: true
    global:
      meshID: mesh1
      multiCluster:
        clusterName: cls-dxgdg1rl
      network: main
```

* `meshID` 根据自己喜好填写。
* `clusterName` 可填当前 TKE 集群的集群 ID。

确保 kubeconfig 的 context 切换到安装 istiod 的集群（主集群），执行安装：

```bash
istioctl install -f master-cluster.yaml
```

安装完后，检查 istiod Pod 是否正常运行：

```bash
$ kubectl get pod -n istio-system
NAME                      READY   STATUS    RESTARTS   AGE
istiod-6b785b7b89-zblbw   1/1     Running   0          6m31s
```

## 暴露 istiod 控制面

如果需要让更多 TKE 集群加入这个网格，就需要将主集群的 istiod 通过东西向网关暴露出来，暴露的方法是在主集群创建一个东西向网关，在 `IstioOperator` 的 `components` 下新增一个 `ingressGateways` 配置：

```yaml showLineNumbers title="master-cluster.yaml"
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  name: eastwest
spec:
  # highlight-start
  components:
    ingressGateways:
      - name: istio-eastwestgateway
        label:
          istio: eastwestgateway
          app: istio-eastwestgateway
          topology.istio.io/network: main
        enabled: true
        k8s:
          env:
            - name: ISTIO_META_REQUESTED_NETWORK_VIEW
              value: main
          serviceAnnotations:
            service.kubernetes.io/tke-existed-lbid: "lb-lujb6a5a" # 指定手动创建的内网 CLB
            # service.kubernetes.io/qcloud-loadbalancer-internal-subnetid: "subnet-oz2k2du5" # 自动创建 CLB，需指定子网 ID
          service:
            ports:
              - name: status-port
                port: 15021
                targetPort: 15021
              - name: tls
                port: 15443
                targetPort: 15443
              - name: tls-istiod
                port: 15012
                targetPort: 15012
              - name: tls-webhook
                port: 15017
                targetPort: 15017
  # highlight-end
  values:
    pilot:
      env:
        EXTERNAL_ISTIOD: true
    global:
      meshID: mesh-mn8gnn1g
      multiCluster:
        clusterName: cls-dxgdg1rl
      network: main
```

东西向网关是通过 `LoadBalancer` 类型的 Service 来暴露流量的，而在 TKE 环境中，默认会创建公网类型的 CLB，我们的东西向网关要用内网 CLB 来暴露，在 TKE 上可以给 Service 加注解来指定创建内网 CLB：
* 通过 `serviceAnnotations` 给东西向网关的 Service 加注解。
* 指定内网CLB有两种方式，直接指定已有内网CLB的ID，或者指定自动创建CLB的子网ID，参考示例中的写法。

东西向网关配置准备好后，使用以下命令更新主集群 istio 的安装配置：

```bash
istioctl upgrade -f master-cluster.yaml
```

安装完之后，获取外部 IP 地址 (`EXTERNAL-IP`)：

```bash
$ kubectl get svc istio-eastwestgateway -n istio-system
NAME                    TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)                                                           AGE
istio-eastwestgateway   LoadBalancer   192.168.6.166   10.0.250.58   15021:31386/TCP,15443:31315/TCP,15012:30468/TCP,15017:30728/TCP   55s
```

最后，配置暴露 istiod 控制面的转发规则：

```bash
kubectl apply -n istio-system -f ./samples/multicluster/expose-istiod.yaml
```

## 纳管其它 TKE 集群

首先将 kubeconfig 的 context 切换到将要被纳管的 TKE 集群，然后准备 `member-cluster-1.yaml`:

```yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  profile: remote
  values:
    global:
      meshID: mesh1
      multiCluster:
        clusterName: cls-ne1cw84b
      network: main
      remotePilotAddress: 10.0.250.58
```

* `remotePilotAddress` 填写前面获取到的 `istio-eastwestgateway` 的内网 CLB IP 地址。
* `clusterName` 可以写当前将被纳管的集群 ID。

将此配置应用到将要被纳管的 TKE 集群中：

```bash
istioctl install -f member-cluster-1.yaml
```

> 这个操作是将当前集群设置为从集群，会向集群中下发 MutatingAdmissionWebhook (Sidecar 自动注入) 和 istiod 的 Service （指向主集群东西向网关的内网CLB）。

然后将 context 再切到主集群，执行以下命令完成最终的配置：

```bash
istioctl create-remote-secret --name=cls-ne1cw84b | kubectl apply -f -
```

> `name` 为当前将被纳管的 TKE 集群 ID。


## 部署 istio-ingressgateway

我们为每个集群都维护一个 `IstioOperator` 的 YAML 文件，想在哪个集群安装 Ingress Gateway 就在哪个集群对应的 `IstioOperator` 文件中的 `components` 增加 `ingressGateways` 配置即可，比如在从集群中部署，修改 `member-cluster-1.yaml`:

```yaml showLineNumbers title="member-cluster-1.yaml"
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  # highlight-start
  components:
    ingressGateways:
      - name: istio-ingressgateway
        enabled: true
      - name: istio-ingressgateway-staging
        namespace: staging # namespace 如果不存在，需自行提前创建
        enabled: true
      - name: istio-ingressgateway-intranet
        enabled: true
        k8s:
          serviceAnnotations:
            service.kubernetes.io/qcloud-loadbalancer-internal-subnetid: "subnet-19exjv5n"
  # highlight-end
  profile: remote
  values:
    global:
      meshID: mesh1
      multiCluster:
        clusterName: cls-ne1cw84b
      network: main
      remotePilotAddress: 10.0.250.110
```

使用 istioctl 来 upgrade 一下:

```bash
istioctl upgrade -f member-cluster-1.yaml
```

部署成功后，可以检查下对应的 CLB 和 Pod 装填是否正常：

```bash
$ kubectl get svc -A | grep ingressgateway
istio-system   istio-ingressgateway            LoadBalancer   192.168.6.172   111.231.152.197                  15021:32500/TCP,80:30148/TCP,443:31128/TCP   2m25s
istio-system   istio-ingressgateway-intranet   LoadBalancer   192.168.6.217   10.0.0.12                        15021:30839/TCP,80:30482/TCP,443:30576/TCP   2m25s
staging        istio-ingressgateway-staging    LoadBalancer   192.168.6.110   111.231.156.200                  15021:31773/TCP,80:31942/TCP,443:32631/TCP   2m8s

$ kubectl get pod -A | grep ingressgateway
istio-system   istio-ingressgateway-58889f648b-87gpq           1/1     Running             0          4m58s
istio-system   istio-ingressgateway-intranet-dc46f7b46-zx4rs   1/1     Running             0          4m58s
staging        istio-ingressgateway-staging-5fbf567984-fnvgf   1/1     Running             0          4m58s
```

## 启用 sidecar 自动注入

我们可以为需要开启 sidecar 自动注入的集群的 namespace 打上 `istio-injection=enabled` 的 label:

```bash
kubectl label namespace your-namespace istio-injection=enabled --overwrite
```

> 这与 TCM 有所不同，参考 [TCM 常见问题: 没有自动注入Sidecar](https://cloud.tencent.com/document/product/1261/63059)。


## 迁移 istio 配置

使用以下脚本将 TCM 相关的 istio 配置导出成 YAML (`kubedump.sh`):

```bash title="kubedump.sh"
#!/usr/bin/env bash

set -ex

DATA_DIR="data"
mkdir -p ${DATA_DIR}

NAMESPACES=$(kubectl get -o json namespaces | jq '.items[].metadata.name' | sed "s/\"//g")
RESOURCES="virtualservices gateways envoyfilters destinationrules sidecars peerauthentications authorizationpolicies requestauthentications telemetries proxyconfigs serviceentries"

for ns in ${NAMESPACES}; do
	for resource in ${RESOURCES}; do
		rsrcs=$(kubectl -n ${ns} get -o json ${resource} | jq '.items[].metadata.name' | sed "s/\"//g")
		for r in ${rsrcs}; do
			dir="${DATA_DIR}/${ns}/${resource}"
			mkdir -p "${dir}"
			kubectl -n ${ns} get -o yaml ${resource} ${r} | kubectl neat >"${dir}/${r}.yaml"
		done
	done
done
```

> 脚本依赖 jq, sed 命令，还依赖 [kubectl-neat 插件](https://github.com/itaysk/kubectl-neat)。

确保 context 切换到 TCM 所关联的任意集群中，执行这个脚本导出 TCM 中的 istio 配置：

```bash
bash kubedump.sh
```

脚本运行完成后会将 TCM 中的 istio 配置导出到 `data` 目录。

可以检查下导出的 YAML 文件，根据需求看是否需要调整，然后再将 YAML apply 到自建 istio 的主集群中即可完成 istio 配置的迁移。

## 迁移业务
istio 配置迁移后，可以尝试将 TCM 关联的生产集群中的业务逐渐往自建 istio 关联的 TKE 集群中迁移，然后逐渐切流量到自建 istio 环境中并观察，等所有 TCM 中所有业务都迁到了自建 isito 环境中后，再下线 TCM 的环境，最终删除 TCM 网格完成迁移。

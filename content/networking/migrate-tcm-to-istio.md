# 从 TCM 迁移到自建 istio

## 概述

腾讯云服务网格（Tencent Cloud Mesh, TCM）是基于 TKE 的 istio 托管服务，未来将会下线，本文介绍如何从 TCM 迁移到自建 istio。

## 迁移思路

istio 架构分为控制面和数据面，控制面是 istiod，数据面是网关 (istio-ingressgateway/istio-egressgateway) 或 sidecar，数据面的本质上都是使用 Envoy 作为代理程序，控制面会将计算出的流量规则通过 `xDS` 下发给数据面：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F06%2F18%2F20240618150336.png)

TCM 主要托管的是 isitod，迁移的关键点就是使用自建的 istiod 替换 TCM 的 isitod，但由于根证书问题，两者无法共存，也就无法原地平滑迁移，只能新建一套环境来自建 istio，然后逐渐将业务迁移到新建的 istio 环境中，逐步切流量过来，完成全量迁移之前，两套环境还需共存：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F06%2F18%2F20240618170536.png)

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

## 纳管其它 TKE 集群

如果需要让更多 TKE 集群加入这个网格，就需要将主集群的 istiod 通过东西向网关暴露出来。

进入下载的 istio 发新版目录，执行以下命令来生成东西向网关的安装配置：

```bash
./samples/multicluster/gen-eastwest-gateway.sh --network main > eastwest-gateway.yaml
```

东西向网关是通过 `LoadBalancer` 类型的 Service 来暴露流量的，而在 TKE 环境中，默认会创建公网类型的 CLB，我们的东西向网关要用内网 CLB 来暴露，在 TKE 上可以给 Service 加注解来指定创建内网 CLB，这里对生成的配置微调一下：

```yaml showLineNumbers title="eastwest-gateway.yaml"
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  name: eastwest
spec:
  revision: ""
  profile: empty
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
            # traffic through this gateway should be routed inside the network
            - name: ISTIO_META_REQUESTED_NETWORK_VIEW
              value: main
          # highlight-start
          serviceAnnotations:
            service.kubernetes.io/tke-existed-lbid: "lb-lujb6a5a" # 指定手动创建的内网 CLB
            # service.kubernetes.io/qcloud-loadbalancer-internal-subnetid: "subnet-oz2k2du5" # 自动创建 CLB，需指定子网 ID
          # highlight-end
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
  values:
    gateways:
      istio-ingressgateway:
        injectionTemplate: gateway
    global:
      network: main
```

* 通过 `serviceAnnotations` 给 Service 加注解。
* 指定内网CLB有两种方式，直接指定已有内网CLB的ID，或者指定自动创建CLB的子网ID，参考示例中的写法。

东西向网关配置准备好后，使用以下命令在主集群中安装：

```bash
istioctl install -f eastwest-gateway.yaml
```

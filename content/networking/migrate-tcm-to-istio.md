# 从 TCM 迁移到自建 istio

## 概述

腾讯云服务网格（Tencent Cloud Mesh, TCM）是基于 TKE 的 istio 托管服务，未来将会下线，本文介绍如何从 TCM 迁移到自建 istio。

## 迁移思路

istio 架构分为控制面和数据面，控制面是 istiod，数据面是网关 (istio-ingressgateway/istio-egressgateway) 或 sidecar，数据面的本质上都是使用 Envoy 作为代理程序，控制面会将计算出的流量规则通过 `xDS` 下发给数据面：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F06%2F18%2F20240618150336.png)

TCM 主要托管的是 isitod，迁移的关键点就是使用自建的 istiod 替换 TCM 的 isitod，但由于根证书问题，两者无法共存，也就无法原地平滑迁移，只能新建一套环境来自建 istio，然后逐渐将业务迁移到新建的 istio 环境中，逐步切流量过来，完成全量迁移之前，两套环境还需共存：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F06%2F18%2F20240618170536.png)

## 安装 istio

参考 [istio 官方文档](https://istio.io/latest/zh/docs/setup/getting-started/#download) 下载 istio 发新版，如不希望迁移过程中引入太多兼容性问题，可以下载与 TCM 相同版本的 istio 发新版：

```bash
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.18.5 sh -
```

然后将 `istioctl` 安装到 `PATH`:

```bash
mv istio-1.18.5/bin/istioctl /usr/local/bin/istioctl
```

选择一个 TKE 集群来部署 istiod，准备部署配置 `master-cluster.yaml`：

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

执行安装：

```bash
istioctl install --context="${CTX_MASTER_CLUSTER}" -f master-cluster.yaml
```

安装完后，检查 istiod Pod 是否正常运行：

```bash
$ kubectl get pod -n istio-system
NAME                      READY   STATUS    RESTARTS   AGE
istiod-6b785b7b89-zblbw   1/1     Running   0          6m31s
```

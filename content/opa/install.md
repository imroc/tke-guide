# 安装 OPA Gatekeeper

## 托管 gatekeeper

TKE 当前已经默认自带托管的 OPA Gatekeeper，无需自行安装。

由于 gatekeeper 是托管的，组件本身在集群中不可见，但可以看到相关 CRD 资源：

```bash
kubectl get crd | grep gatekeeper.sh
```

在集群页面的 `策略管理` 页面可以进行可视化管理。

## 自建 gatekeeper

如果想要完全自己掌控和自定义策略，可考虑提工单开白不要预装 gatekeeper，然后再新建集群自行安装社区版 gatekeeper。

由于 OPA Gatekeeper 使用的镜像都在 DockerHub，可以直接用官方的 YAML 一键安装到 TKE （TKE 集群有 DockerHub 镜像加速）。

参考 [官方安装文档：Deploying a Release using Prebuilt Image](https://open-policy-agent.github.io/gatekeeper/website/docs/install/#deploying-a-release-using-prebuilt-image) 

# 安装 OPA Gatekeeper

## 说明

TKE 未来将会自带托管的 OPA Gatekeeper，无需自行安装，可通过检查是否存在 crd 来确认是否已经预装：

```bash
kubectl get crd | grep gatekeeper.sh
```

如果想要完全自己掌控和自定义策略，可自行安装下面指引安装社区版。

## 在 TKE 上一键安装

由于 OPA Gatekeeper 使用的镜像都在 DockerHub，可以直接用官方的 YAML 一键安装到 TKE （TKE 集群有 DockerHub 镜像加速）。

参考 [官方安装文档：Deploying a Release using Prebuilt Image](https://open-policy-agent.github.io/gatekeeper/website/docs/install/#deploying-a-release-using-prebuilt-image) 


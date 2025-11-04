# 重建 endpoint 导致 cilium 无法启动

## 问题现象

cilium daemonset 的 pod 无法正常启动，其中 config 这个 init 容器报错：

```txt
time=2025-11-03T04:11:44.429596158Z level=info msg="Establishing connection to apiserver" subsys=cilium-dbg module=k8s-client ipAddr=https://sb2-gz1-testapi-a.ap-guangzhou.np-tencentcloud.hkjc:443
Error: Build config failed: failed to start: Get "https://sb2-gz1-testapi-a.ap-guangzhou.np-tencentcloud.hkjc:443/api/v1/namespaces/kube-system": dial tcp 10.48.0.33:443: connect: operation not permitted

time=2025-11-03T04:11:44.430375811Z level=error msg="Unable to contact k8s api-server" subsys=cilium-dbg module=k8s-client ipAddr=https://sb2-gz1-testapi-a.ap-guangzhou.np-tencentcloud.hkjc:443 error="Get \"https://sb2-gz1-testapi-a.ap-guangzhou.np-tencentcloud.hkjc:443/api/v1/namespaces/kube-system\": dial tcp 10.48.0.33:443: connect: operation not permitted"
time=2025-11-03T04:11:44.43040983Z level=error msg="Start hook failed" subsys=cilium-dbg function="client.(*compositeClientset).onStart (k8s-client)" error="Get \"https://sb2-gz1-testapi-a.ap-guangzhou.np-tencentcloud.hkjc:443/api/v1/namespaces/kube-system\": dial tcp 10.48.0.33:443: connect: operation not permitted"
time=2025-11-03T04:11:44.43042462Z level=error msg="Failed to start hive" subsys=cilium-dbg error="Get \"https://sb2-gz1-testapi-a.ap-guangzhou.np-tencentcloud.hkjc:443/api/v1/name
```

## 问题复现

1. 参考 [安装 cilium](../install.md) 中默认的方式安装 cilium，唯一区别在于 `k8sServiceHost` 的配置使用指向开启集群内网访问后的 CLB VIP 或域名而非 `169.254.x.x` 这个 APIServer 的 IP。
2. 备份 `default/kubernetes-intranet` 这个 endpoint，删除并重建这个 endpoint：
    ```bash
    kubectl -n default get endpoints kubernetes-intranet -o yaml | kubectl neat > ep.yaml
    kubectl -n default delete endpoints kubernetes-intranet
    kubectl apply -f ep.yaml
    ```

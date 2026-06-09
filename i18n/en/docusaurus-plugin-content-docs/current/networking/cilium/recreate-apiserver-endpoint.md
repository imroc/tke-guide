# Cilium fails to start due to endpoint recreation

## Symptom

The Cilium DaemonSet Pod fails to start, with the `config` init container reporting an error:

```txt
time=2025-11-03T04:11:44.429596158Z level=info msg="Establishing connection to apiserver" subsys=cilium-dbg module=k8s-client ipAddr=https://sb2-gz1-testapi-a.ap-guangzhou.np-tencentcloud.hkjc:443
Error: Build config failed: failed to start: Get "https://sb2-gz1-testapi-a.ap-guangzhou.np-tencentcloud.hkjc:443/api/v1/namespaces/kube-system": dial tcp 10.48.0.33:443: connect: operation not permitted

time=2025-11-03T04:11:44.430375811Z level=error msg="Unable to contact k8s api-server" subsys=cilium-dbg module=k8s-client ipAddr=https://sb2-gz1-testapi-a.ap-guangzhou.np-tencentcloud.hkjc:443 error="Get \"https://sb2-gz1-testapi-a.ap-guangzhou.np-tencentcloud.hkjc:443/api/v1/namespaces/kube-system\": dial tcp 10.48.0.33:443: connect: operation not permitted"
time=2025-11-03T04:11:44.43040983Z level=error msg="Start hook failed" subsys=cilium-dbg function="client.(*compositeClientset).onStart (k8s-client)" error="Get \"https://sb2-gz1-testapi-a.ap-guangzhou.np-tencentcloud.hkjc:443/api/v1/namespaces/kube-system\": dial tcp 10.48.0.33:443: connect: operation not permitted"
time=2025-11-03T04:11:44.43042462Z level=error msg="Failed to start hive" subsys=cilium-dbg error="Get \"https://sb2-gz1-testapi-a.ap-guangzhou.np-tencentcloud.hkjc:443/api/v1/namespaces/kube-system\": dial tcp 10.48.0.33:443: connect: operation not permitted"
```

## Reproduction

1. Install Cilium following the default method in the installation guide, with the only difference being that `k8sServiceHost` uses the CLB VIP or domain name pointing to the cluster's internal network access, instead of the `169.254.x.x` APIServer IP.
2. Backup the `default/kubernetes-intranet` endpoint, delete it, and recreate it:
    ```bash
    kubectl -n default get endpoints kubernetes-intranet -o yaml | kubectl neat > ep.yaml
    kubectl -n default delete endpoints kubernetes-intranet
    kubectl apply -f ep.yaml
    ```

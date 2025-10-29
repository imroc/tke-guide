# 使用 Egress Gateway 控制集群外部访问

## 启用 Egress Gateway

如果要启用 Egress Gateway，需要使用 cilium 替代 kube-proxy，另外还需要启用 bpf masquerade 功能，如果使用 [安装cilium](install.md) 中的默认安装参数，可通过以下方式启用 Egress Gateway:

```bash
helm upgrade cilium cilium/cilium --version 1.18.3 \
   --namespace kube-system \
   --reuse-values \
   --set egressGateway.enabled=true \
   --set bpf.masquerade=true 
```

然后重启 cilium 组件生效：

```bash
kubectl rollout restart ds cilium -n kube-system
kubectl rollout restart deploy cilium-operator -n kube-system
```

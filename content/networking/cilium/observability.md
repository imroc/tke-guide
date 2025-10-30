# 使用 Cilium 增强可观测性

:::info[注意]

本文正在起草中，请等完善后再参考。

:::

## 启用 Hubble

```bash
helm upgrade cilium cilium/cilium --version 1.18.3 \
   --namespace kube-system \
   --reuse-values \
   --set hubble.relay.image.repository=quay.tencentcloudcr.com/cilium/hubble-relay \
   --set hubble.relay.enabled=true
```

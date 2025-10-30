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

通过 `cilium status` 可验证 hubble 开启并正常运行：

```bash showLineNumbers
$ cilium status
    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    OK
               # highlight-next-line
 \__/¯¯\__/    Hubble Relay:       OK
    \__/       ClusterMesh:        disabled

DaemonSet              cilium                   Desired: 3, Ready: 3/3, Available: 3/3
DaemonSet              cilium-envoy             Desired: 3, Ready: 3/3, Available: 3/3
Deployment             cilium-operator          Desired: 2, Ready: 2/2, Available: 2/2
Deployment             hubble-relay             Desired: 1, Ready: 1/1, Available: 1/1
Containers:            cilium                   Running: 3
                       cilium-envoy             Running: 3
                       cilium-operator          Running: 2
                       clustermesh-apiserver
                       # highlight-next-line
                       hubble-relay             Running: 1
Cluster Pods:          4/4 managed by Cilium
Helm chart version:    1.18.3
Image versions         cilium             quay.tencentcloudcr.com/cilium/cilium:v1.18.3@sha256:5649db451c88d928ea585514746d50d91e6210801b300c897283ea319d68de15: 3
                       cilium-envoy       quay.tencentcloudcr.com/cilium/cilium-envoy:v1.34.10-1761014632-c360e8557eb41011dfb5210f8fb53fed6c0b3222@sha256:ca76eb4e9812d114c7f43215a742c00b8bf41200992af0d21b5561d46156fd15: 3
                       cilium-operator    quay.tencentcloudcr.com/cilium/operator-generic:v1.18.3@sha256:b5a0138e1a38e4437c5215257ff4e35373619501f4877dbaf92c89ecfad81797: 2
                       hubble-relay       quay.tencentcloudcr.com/cilium/hubble-relay:v1.18.3@sha256:e53e00c47fe4ffb9c086bad0c1c77f23cb968be4385881160683d9e15aa34dc3: 1
```

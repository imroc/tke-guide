# 使用 Cilium 构建多集群网络

## 概述

如果希望将多个集群的网络打通，实现跨集群 Pod 互访、Service 跨集群负载均衡（global Service）与基于身份的跨集群网络策略，可以使用 Cilium 的 ClusterMesh 能力将多个集群组成网格，本文介绍在 TKE 上如何操作。三种部署方案（Native Routing (VPC-CNI)、Overlay (VPC-CNI)、Overlay (GR)）均支持，基于 cilium 1.20.1 + TKE 1.32 验证，前提是集群间底层网络互通（见下节）。

## 网络前提

ClusterMesh 只负责在集群间同步 Pod、Service、安全身份等控制面信息，数据面能否互通取决于集群间底层网络本身。所有集群需满足：

1. **路由模式一致**：所有集群使用同一种路由模式（都是 Native Routing 或都是 Overlay），不能混用。
2. **版本差距小**：各集群 cilium 版本相差不超过一个 minor 版本（如 1.19.x 与 1.20.x 可互通）。
3. **网段不重叠**：所有集群的 Pod CIDR、Node IP 互不重叠（Overlay 模式需为每个集群规划不同的 Pod CIDR，如 `10.244.0.0/16`）。

<Tabs>
<TabItem value="native" label="Native Routing (VPC-CNI)" default>

Pod IP 就是 VPC IP，跨集群 Pod 通信等价于 VPC 内跨子网通信，能否互通取决于 VPC 网络本身：

- **同 VPC 的两个集群**：天然互通，无需额外配置。
- **跨 VPC 的两个集群**：需通过 [对等连接](https://cloud.tencent.com/document/product/553) 或 [云联网](https://cloud.tencent.com/document/product/877) 打通，并确保路由覆盖对端集群的 Pod 网段（VPC-CNI 的 Pod 子网）。
- **安全组**：需放行对端集群 Pod 网段到本集群节点的流量（Pod-to-Pod，任意端口），否则跨集群 Pod 互访不通。

</TabItem>
<TabItem value="overlay" label="Overlay (VPC-CNI / GR)">

Pod IP 在独立 CIDR 中（不是 VPC 可路由地址），跨集群 Pod 流量与集群内一样被封装进 VXLAN 隧道直达对端节点，因此只要求**节点网络互通**，Pod CIDR 无需在底层可路由：

- **同 VPC 的两个集群**：节点天然互通，无需额外配置。
- **跨 VPC 的两个集群**：通过对等连接或云联网打通节点网段路由即可。
- **安全组**：需放行对端节点网段到本集群节点的 UDP 8472 流量（cilium 默认 VXLAN 端口）。

</TabItem>
</Tabs>

:::note[放通 clustermesh-apiserver 的 2379 端口]

无论哪种方案，clustermesh-apiserver 都会通过内网 CLB（TCP 2379）把本集群 Cilium 控制面暴露给其它集群。cilium 1.20 默认开启 KVStoreMesh：各集群的 clustermesh-apiserver 主动连接对端 CLB 拉取数据，cilium-agent 只连本集群的 clustermesh-apiserver。因此需保证对端集群中运行 clustermesh-apiserver 的节点能访问该 CLB：同 VPC 天然可达；跨 VPC 时云联网/对等连接需覆盖 CLB 所在子网，且节点安全组放行来自对端的 TCP 2379。

:::

## 准备 kubeconfig

需将所有需要组建 ClusterMesh 的集群的 kubeconfig 合并到一个文件，通过 context 区分集群，context 名称为 TKE 集群 ID（cls-xxx），且确保当前使用的 kubeconfig 指向该文件。后文用环境变量指代两个集群，可先设置：`export CLUSTER1=cls-xxxxxxxx CLUSTER2=cls-yyyyyyyy`。

## 安装时指定集群名称、ID 与 clustermesh-apiserver 内网 CLB

在 [安装 Cilium](./install.md) 的基础上，为每个集群追加以下参数（各集群互不相同）：

```bash
helm --kube-context=$CLUSTER1 upgrade --install cilium cilium/cilium --version 1.20.1 \
  --namespace kube-system \
  --set cluster.name=$CLUSTER1 \
  --set cluster.id=1 \
  --set clustermesh.apiserver.service.annotations."service\.kubernetes\.io\/qcloud\-loadbalancer\-internal\-subnetid"="$CLUSTER1_SUBNET_ID" \
  # 省略其它参数
```

第二个集群同理：`cluster.name=$CLUSTER2`、`cluster.id=2`，CLB 子网换成 `$CLUSTER2_SUBNET_ID`。

参数说明：

- `cluster.name`：集群名称，全网唯一。可与 TKE 集群 ID 相同（格式 cls-xxx；只允许小写字母、数字与中划线，不超过 32 字符）。
- `cluster.id`：集群数字 ID（1-255），全网唯一。
- `clustermesh.apiserver.service.annotations`：clustermesh-apiserver 通过 LoadBalancer 类型 Service 暴露本集群 Cilium 控制面给其它集群，TKE 上会创建内网 CLB，需通过该注解指定 CLB 所在子网 ID（将 `$CLUSTERx_SUBNET_ID` 替换为该集群 VPC 内的子网 ID）。

**集群名称与 ID 应在安装时就指定**：二者参与安全身份的生成，集群运行后再修改需要重启所有工作负载重建身份。若要在已安装的集群上补充这些参数，执行 `helm upgrade cilium cilium/cilium --version 1.20.1 -n kube-system --reuse-values` 并追加上述 `--set` 参数即可。

## 启用 ClusterMesh

### 在第一个集群启用

```bash
cilium clustermesh enable --context $CLUSTER1 --service-type=LoadBalancer
```

该命令通过 helm 部署 clustermesh-apiserver（Deployment + LoadBalancer Service，即创建内网 CLB），并用 certgen Job 签发 mTLS 证书，之后由 CronJob 每 4 个月自动轮换。TKE 不在 cilium-cli 能自动识别的云厂商列表中，必须显式指定 `--service-type=LoadBalancer`。

### 共享 CA

cilium-cli 的 `clustermesh connect` 会校验两个集群的 CA 证书是否一致，不一致会直接报错（除非显式加 `--allow-mismatching-ca`，将对端 CA 加入信任列表）。因此标准做法是让所有集群共用同一个 CA：将第一个集群生成的 `cilium-ca` Secret 拷贝到其它集群：

```bash
kubectl --context=$CLUSTER1 -n kube-system get secret cilium-ca -o yaml > cilium-ca.yaml
kubectl --context=$CLUSTER2 -n kube-system delete secret cilium-ca --ignore-not-found
kubectl --context=$CLUSTER2 -n kube-system apply -f cilium-ca.yaml
```

此外，如果计划使用跨集群的 Hubble Relay（在任一集群观测全网格流量），也要求所有集群使用同一个 CA，跨集群 mTLS 才能正常工作。

:::warning[必须在目标集群启用 ClusterMesh 之前拷贝 CA]

启用 ClusterMesh 时，certgen 以 `--ca-reuse-secret` 方式运行：`cilium-ca` Secret 已存在则直接复用它签发 clustermesh 相关证书，不存在才新建 CA。因此拷贝 CA 必须发生在目标集群执行 `cilium clustermesh enable` 之前，否则证书不是同一个 CA 签发的。

如果集群已经用自己的 CA 启用过 ClusterMesh，事后仅替换 `cilium-ca` 并不会自动重签已有证书，运行中的组件也不会重新加载证书与 CA（cilium-agent / cilium-operator 的 etcd 客户端只热加载客户端证书，信任的 CA 在进程启动时加载），需要手工修复：

1. 替换 `cilium-ca`（同上面三条命令），并删除旧的叶证书 Secret：`clustermesh-apiserver-server-cert`、`clustermesh-apiserver-admin-cert`、`clustermesh-apiserver-remote-cert`、`clustermesh-apiserver-local-cert`。
2. 手动触发一次证书签发：`kubectl --context=$CLUSTER2 -n kube-system create job --from=cronjob/clustermesh-apiserver-generate-certs cert-regen`。
3. 重启该集群的 `clustermesh-apiserver`、`cilium-operator`（Deployment）与 `cilium`（DaemonSet），重新加载证书。

:::

### 在其余集群启用

拷贝 CA 后，在其余集群执行同样的启用命令（如 `cilium clustermesh enable --context $CLUSTER2 --service-type=LoadBalancer`）。更多集群加入网格时，对每个集群重复「共享 CA」与「启用」两步：`cluster.id` 与 `cluster.name` 保持全网唯一，CA 都从第一个集群拷贝。

## 连接集群

```bash
cilium clustermesh connect --context $CLUSTER1 --destination-context $CLUSTER2
```

只需在一个方向执行（默认 `--connection-mode=bidirectional`，cilium-cli 会同时配置两个集群，双向自动生效）。连接多个集群时，可一次传入逗号分隔的多个 `--destination-context`，或多次执行。

## 验证

```bash
cilium clustermesh status --context $CLUSTER1 --wait
cilium clustermesh status --context $CLUSTER2 --wait
```

输出类似：

```bash
✅ Cluster access information is available:
  - 10.168.0.89:2379
✅ Service "clustermesh-apiserver" of type "LoadBalancer" found
⌛ Waiting (12s) for clusters to be connected: 2 nodes are not ready
✅ All 2 nodes are connected to all clusters [min:1 / avg:1.0 / max:1]
🔌 Cluster Connections:
- cls-yyyyyyyy: 2/2 configured, 2/2 connected
```

出现 `✅ All N nodes are connected to all clusters`，且 Cluster Connections 中对端集群状态为 `connected`，即表示控制面连接正常。

再跑一次多集群连通性测试，验证跨集群 Pod 互访与 Service 转发（单集群用法详见 [Cilium 功能测试](./appendix/connectivity-test.md)，多集群模式额外加 `--multi-cluster`）：

```bash
cilium connectivity test --context $CLUSTER1 --multi-cluster $CLUSTER2
```

## global Service 示例

给 Service 加上 `service.cilium.io/global: "true"` 注解即可声明为全局 Service，Cilium 会自动同步两端后端 Endpoint 并跨集群负载均衡。需在**每个集群**中创建同名且同命名空间的 Service：

```yaml title="rebel-base.yaml"
apiVersion: v1
kind: Service
metadata:
  name: rebel-base
  annotations:
    service.cilium.io/global: "true" # 声明为全局 Service
spec:
  type: ClusterIP
  ports:
  - port: 80
  selector:
    name: rebel-base
```

两端都部署该 Service 与各自的后端（也可以只有一端有后端 Pod，此时另一端访问该 Service 会被转发到对端后端），从任一集群的 Pod 中访问 `rebel-base`，若两端都有后端，会看到两个集群的 Pod 都有响应。

- 默认本集群后端也会共享给对端（隐含 `service.cilium.io/shared: "true"`）；给某端 Service 加 `service.cilium.io/shared: "false"` 可禁止本集群后端被对端访问（本集群自己访问仍会负载均衡到两端）。
- 跨集群负载均衡默认不区分本地与远端后端；如需"本集群优先"的亲和性，参考官方 [Service Affinity](https://docs.cilium.io/en/stable/network/clustermesh/affinity/) 文档。

## 注意事项

### 确保跨集群 Pod 通信没有 SNAT

如果启用了 IP 伪装功能，应确保所有集群的 Pod 网段都不会被 SNAT：Native Routing 模式需将对端集群的 Pod 网段一并加入 `nonMasqueradeCIDRs`，具体配置方法参考 [配置 IP 伪装](./appendix/masquerading.md)。否则跨集群 Pod 流量的源 IP 会被 SNAT 成节点 IP，对端无法将流量还原回 Pod 的 Cilium 身份，基于身份的跨集群 NetworkPolicy 会失效。Overlay 模式的跨集群 Pod 流量走 VXLAN 封装（外层为节点 IP），不受 masquerade 影响，无需处理。

### 与 Egress Gateway、CiliumEndpointSlice 互斥

Egress Gateway 与 ClusterMesh 不兼容：CiliumEgressGatewayPolicy 选中的 egress 节点必须与命中策略的 Pod 在同一集群，而 ClusterMesh 的跨集群身份与端点同步会破坏该前提。Egress Gateway 与 CiliumEndpointSlice 同样不兼容（上游已知问题 [cilium#24833](https://github.com/cilium/cilium/issues/24833)）。因此已启用 Egress Gateway 的集群不要再加入 ClusterMesh，反之亦然，详见 [Egress Gateway 应用实践](./egress-gateway.md) 的「已知问题」。

## 参考资料

- [Multi-cluster Networking](https://docs.cilium.io/en/stable/network/clustermesh/)
- [Setting up Cluster Mesh](https://docs.cilium.io/en/stable/network/clustermesh/clustermesh/)
- [Global Services](https://docs.cilium.io/en/stable/network/clustermesh/global-services/)
- [Egress Gateway](https://docs.cilium.io/en/stable/network/egress-gateway/egress-gateway/)

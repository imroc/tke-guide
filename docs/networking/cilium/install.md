# 安装 Cilium

本文介绍如何在 TKE 集群中安装 cilium，支持以下网络模式：

- **Native Routing（原生路由）**：与 TKE CNI 共存，Pod 使用 TKE 分配的 IP，cilium 提供 NetworkPolicy、可观测性、kube-proxy 替代等增强能力。
- **Overlay（vxlan 隧道）**：完全替代 TKE 所有 CNI，Pod IP 不占用 underlay 的 IP，可用于 IP 申请困难的场景，也可用于替代 TKE 内置的 CiliumOverlay 网络模式以获得满血功能。

VPC-CNI 集群两种模式都支持；GR 集群仅支持 Overlay 模式。**推荐使用 VPC-CNI 集群**——性能更好、无节点数量限制，且不会像 GR 那样白白占用一段 VPC 辅助网段（详见 FAQ [为什么不推荐使用 GR 集群？](#为什么不推荐使用-gr-集群)）。

:::note[如何选择]

| 对比项               | Native Routing (VPC-CNI) ⭐ | Overlay (VPC-CNI) ⭐                       | Overlay (GR)                                                                                                                                                                           |
| -------------------- | --------------------------- | ------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 网络性能             | 最优                        | 略有开销（vxlan 封装）                     | 略有开销（vxlan 封装）                                                                                                                                                                 |
| Pod IP 范围          | VPC IP                      | 独立 CIDR，不占用 VPC IP                   | 独立 CIDR，不占用 VPC IP                                                                                                                                                               |
| VPC 辅助网段消耗     | ✅ 无                       | ✅ 无                                      | ⚠️ GR 集群创建时**强制绑定一段 VPC 辅助网段**作为 ClusterCIDR，即使 Overlay 模式下 Pod IP 来自独立 CIDR、不会真正用到这段，这段辅助网段仍被占住无法被其它资源使用（GR 集群本身的限制） |
| IP 容量扩容          | 给集群新增 VPC-CNI 子网     | 追加 CIDR 到 clusterPoolIPv4PodCIDRList    | 同左                                                                                                                                                                                   |
| 节点数量限制         | 无                          | 无                                         | 受 GR 集群的 ClusterCIDR 限制（GR 集群本身的限制）                                                                                                                                     |
| 集群外访问 Pod       | 可直接路由                  | 不可直接路由，需通过 Service/Ingress       | 不可直接路由                                                                                                                                                                           |
| CLB 直连 Pod         | ✅ 支持                     | ❌ 不支持（CLB 无法路由 Overlay Pod IP）   | ❌ 不支持（同左）                                                                                                                                                                      |
| L7/DNS NetworkPolicy | ✅ 完整支持                 | ✅ 完整支持                                | ✅ 完整支持                                                                                                                                                                            |
| 适用场景             | 常规场景（推荐）            | IP 资源紧张、纳管 IDC、满血 cilium（推荐） | 仅推荐已有 GR 集群的场景，不推荐为了装 cilium 新建 GR 集群                                                                                                                             |

:::

:::warning[GR 集群只用 Overlay，且不推荐为安装 cilium 新建 GR 集群]

GR 集群有两个**与 cilium 不太搭**的硬限制：

1. **GR + Native Routing 在 cilium chained CNI 下基本无法生产可用**：跨节点 Pod-to-Pod 流量不通、L7/DNS NetworkPolicy 不可用，本系列教程不再提供。完整试错记录见 [为什么不提供 GR Native Routing 部署方案？](./appendix/gr-native-not-recommended.md)。
2. **GR 集群创建时强制要求 ClusterCIDR**——这段网段从 VPC 辅助网段中划出来分配给集群，即使后续装了 cilium Overlay、Pod IP 完全来自独立 CIDR、这段 ClusterCIDR 一个 IP 都用不上，它仍然被这个 GR 集群占着，无法挪给同 VPC 下的其它资源使用。详见下方 FAQ [为什么不推荐使用 GR 集群？](#为什么不推荐使用-gr-集群)。

如果 GR 集群已存在，按本文 **Overlay (GR)** 路径安装即可；新建集群请直接选 **VPC-CNI 集群**。

:::

## 前期准备

### 准备 TKE 集群

:::info[注意]

安装 cilium 是对集群一个很重大的变更，不建议在有生产业务运行的集群中安装，否则安装过程中可能会影响线上业务的正常运行，建议在新创建的 TKE 集群中安装 cilium。

:::

在 [容器服务控制台](https://console.cloud.tencent.com/tke2/cluster) 创建 TKE 集群，注意以下关键选项：

- 容器网络插件：选择 **VPC-CNI 共享网卡多 IP**。GR 集群有 ClusterCIDR 强制占用 VPC 辅助网段、节点数受 ClusterCIDR 限制等问题，**不推荐**为安装 cilium 新建 GR 集群（详见 [为什么不推荐使用 GR 集群？](#为什么不推荐使用-gr-集群)）；已有 GR 集群可以按 Overlay (GR) 方案继续装，但本节后续示例统一以 VPC-CNI 集群为准。
- 集群类型：标准集群。
- Kubernetes 版本: 不低于 1.32，建议选择最新版（参考 [Cilium Kubernetes Compatibility](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/)）。
- 操作系统：推荐 **TencentOS 4** 或 **Ubuntu 24.04**。最低要求 Linux kernel >= 5.10（参考 [System Requirements](https://docs.cilium.io/en/stable/operations/system_requirements/)）。完整已验证 OS 列表参考 [已验证的节点操作系统](./appendix/verified-os.md)。
- 节点：**安装 cilium 前，集群必须没有任何普通节点或原生节点**——超级节点（eklet）除外。详见下方 warning 块。
- 基础组件：**保持勾选 ip-masq-agent**（默认勾选）。安装 cilium 时脚本会卸载 TKE 自带的 ip-masq-agent（避免和 cilium 内置 ipMasqAgent 冲突），但 Native Routing (VPC-CNI) 这种安装方案会**复用** TKE 安装它时自动写入的 `ip-masq-agent-config` ConfigMap——这份配置里已经按集群所在 VPC 自动列出了主网段 + 所有辅助网段，[一键安装脚本](#一键安装脚本) 会读取它作为 cilium ipMasqAgent 的 `nonMasqueradeCIDRs`，省去用户去控制台手动确认 VPC 网段的步骤。
- 增强组件：如果节点池希望使用 Karpenter 节点池，需勾选安装 Karpenter 组件，否则无需勾选（参考后文的节点池选型）。

:::warning[安装前不要向集群添加普通节点或原生节点]

cilium 必须在**空集群**（无节点 / 仅有超级节点）上安装。如果集群中已存在普通节点或原生节点：

- 这些节点上残留的 kube-proxy iptables 规则、tke-cni-agent CNI 配置会与 cilium 冲突，**导致安装后 Pod 网络不通、NetworkPolicy 失效**等难以排查的问题
- 即使先卸载 TKE 组件再安装 cilium，节点上残留的内核态规则也不会被清理

正确做法：

1. **新建集群**：在控制台 / terraform 创建集群时不要添加节点
2. **节点 → 安装 cilium → 加节点**：cilium 一键脚本安装完成后会暂停并提示加节点，等节点 Ready 后再继续

如果意外在 cilium 安装前向集群加了节点，**重启或重建这些节点**才能让 cilium 干净接管。

:::

集群创建成功后，需开启集群访问来暴露集群的 apiserver 提供后续使用 helm 安装 cilium 时，helm 命令能正常操作 TKE 集群，参考 [开启集群访问的方法](https://cloud.tencent.com/document/product/457/32191#.E6.93.8D.E4.BD.9C.E6.AD.A5.E9.AA.A4)。

根据自身情况，选择开启内网访问还是公网访问，主要取决于 helm 命令所在环境的网络是否与 TKE 集群所在 VPC 互通：

1. 如果可以互通就开启内网访问。
2. 如果不能互通就开启公网访问。当前开启公网访问需要向集群下发 `kubernetes-proxy` 组件作为中转，依赖集群中需要有节点存在（未来可能会取消该依赖，但当前现状是需要依赖），如果要使用公网访问方式，建议向集群先添加个超级节点，以便 `kubernetes-proxy` 的 pod 能够正常调度，等 cilium 安装完成后，再删除该超级节点。

如果使用 terraform 创建集群，参考以下代码片段：

```hcl
resource "tencentcloud_kubernetes_cluster" "tke_cluster" {
  # 标准集群
  cluster_deploy_type = "MANAGED_CLUSTER"
  # Kubernetes 版本 >= 1.32
  cluster_version = "1.34.1"
  # 节点默认操作系统（OsName），完整已验证 OS 列表见附录
  # 需要注意的是，节点的实际 OS 由节点池自身的 OS 属性决定，不受 cluster_os 的限制
  cluster_os = "tlinux4_x86_64_public"
  # 容器网络插件: 推荐 VPC-CNI（GR 集群有 ClusterCIDR 占用 VPC 辅助网段等限制，不推荐）
  network_type = "VPC-CNI"
  # 集群 APIServer 开启访问
  cluster_internet = true
  # 通过内网 CLB 暴露 APIServer，需指定 CLB 所在子网 ID
  cluster_intranet_subnet_id = "subnet-xxx"
  # ip-masq-agent 保持安装（terraform provider 默认就会装）。cilium 安装脚本会
  # 卸载它，但会复用它写入的 ip-masq-agent-config ConfigMap（包含 VPC 主网段
  # + 所有辅助网段）作为 cilium ipMasqAgent 的 nonMasqueradeCIDRs。
  # 如需使用 Karpenter 节点池，需安装 Karpenter 组件。（cluster-autoscaler 与 karpenter 互斥，
  # 启用此组件将不会安装 cluster-autoscaler，也就会禁用原生节点池和普通节点池的扩缩容功能，
  # 如不使用 Karpenter 节点池，可省略以下代码，具体节点池选型参考下文"新建节点池"一节）。
  extension_addon {
    name = "karpenter"
    param = jsonencode({
      "kind" : "App", "spec" : { "chart" : { "chartName" : "karpenter" } }
    })
  }
  # 省略其它必要但不相关配置
}
```

### 操作环境准备

安装 cilium 需要一台可以连接集群的操作机器（本地电脑或跳板机），确保安装以下工具：

1. **kubectl** — 连接集群执行 K8s 操作（参考 [安装 kubectl](https://kubernetes.io/zh-cn/docs/tasks/tools/install-kubectl-linux/)）。
2. **helm** — 安装 cilium chart（参考 [安装 helm](https://helm.sh/zh/docs/intro/install/)）。
3. **cilium CLI** — 使用一键安装脚本、一键测试脚本或手动运行 `cilium connectivity test` 时需要（参考 [安装 cilium CLI](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli)）。

配置好可以连接集群的 kubeconfig（参考 [连接集群](https://cloud.tencent.com/document/product/457/32191#a334f679-7491-4e40-9981-00ae111a9094)），然后添加 cilium 的 helm repo：

```bash
helm repo add cilium https://helm.cilium.io/
```

## 安装 cilium

### 一键安装脚本

可使用脚本自动检测集群环境并引导安装。一行命令直接执行（适用所有 shell，无需先下载）：

```bash
bash -c "$(curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh)" -- install
```

如果网络环境无法连接 GitHub，可使用站点地址：

```bash
bash -c "$(curl -sfL https://imroc.cc/tke/scripts/cilium.sh)" -- install
```

脚本会自动检测集群网络模式、引导选择安装方案和版本，然后执行安装。安装过程中还可选择是否启用 [Egress Gateway](egress-gateway.md) 和 [Nodelocal DNSCache](with-node-local-dns.md)。如需手动安装，参考后续步骤。

:::tip[为什么用 `bash -c "$(curl ...)"` 而不是 `curl ... \| bash`？]

`install` 子命令是交互式的（需要选择安装模式等）。如果用 `curl ... | bash`，bash 的 stdin 会被 curl 的输出占用，导致脚本中的 `read` 立即收到 EOF 而退出。

而 `bash -c "$(curl ...)"` 把脚本以**字符串**形式传给 bash，stdin 仍然是终端，`read` 可以正常读取键盘输入。该写法对交互/非交互子命令都适用。

如果想完全无交互，通过环境变量预先指定参数即可（`bash -c` 会继承当前 shell 环境变量）：

```bash
ROUTING_MODE=native CILIUM_VERSION=1.19.4 \
  bash -c "$(curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh)" -- install
```

:::

### 卸载 TKE 组件

所有方案都需要卸载 kube-proxy（由 cilium 替代）、tke-cni-agent（避免 CNI 配置冲突）和 ip-masq-agent（避免与 cilium 内置 ipMasqAgent 冲突）：

```bash
kubectl -n kube-system patch daemonset kube-proxy -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
kubectl -n kube-system patch daemonset tke-cni-agent -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
kubectl -n kube-system patch daemonset ip-masq-agent -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}' 2>/dev/null || true
```

:::tip[说明]

1. 通过加 nodeSelector 方式让 DaemonSet 不部署到任何节点，等同于卸载，同时也留个退路；当前 kube-proxy 也只能通过这种方式卸载，如果直接删除 kube-proxy，后续集群升级会被阻塞。
2. 上面已强调过：**cilium 必须在空集群上安装**。如果安装前误加了普通节点或原生节点，需重启或重建这些节点，避免残留 iptables / CNI 规则。
3. **不要删除 `ip-masq-agent-config` ConfigMap**——TKE 自带的 ip-masq-agent 在创建集群时会把 VPC 主网段 + 所有辅助网段写进这个 cm。后续配置 cilium 内置 ipMasqAgent 的 `nonMasqueradeCIDRs` 时会直接读取它，省去人工确认 VPC 网段的麻烦。一键安装脚本会自动复用，手工安装也可以 `kubectl -n kube-system get cm ip-masq-agent-config -o yaml` 查看。

:::

### 方案特定的前置操作

根据所选方案，执行对应的前置操作：

<Tabs>
<TabItem value="native-vpccni" label="Native Routing (VPC-CNI)" default>

创建 CNI 配置 ConfigMap，定义 VPC-CNI 与 cilium 的 chaining 关系：

```yaml title="cni-config.yaml"
apiVersion: v1
kind: ConfigMap
metadata:
  name: cni-config
  namespace: kube-system
data:
  cni-config: |-
    {
      "cniVersion": "0.3.1",
      "name": "generic-veth",
      "plugins": [
        {
          "type": "tke-route-eni",
          "routeTable": 1,
          "disableIPv6": true,
          "mtu": 1500,
          "ipam": {
            "type": "tke-eni-ipamc",
            "backend": "127.0.0.1:61677"
          }
        },
        {
          "type": "cilium-cni",
          "chaining-mode": "generic-veth"
        }
      ]
    }
```

```bash
kubectl apply -f cni-config.yaml
```

</TabItem>
<TabItem value="overlay-gr" label="Overlay (GR)">

无额外前置操作。

</TabItem>
<TabItem value="overlay-vpccni" label="Overlay (VPC-CNI)">

禁用 `add-pod-eni-ip-limit-webhook`（否则 Pod 会被自动注入 `tke.cloud.tencent.com/eni-ip` 资源请求，导致 ip-scheduler 拦截调度）：

```bash
kubectl delete mutatingwebhookconfiguration add-pod-eni-ip-limit-webhook
```

</TabItem>
</Tabs>

### 使用 helm 安装 cilium

:::info[注意]

`k8sServiceHost` 是 apiserver 地址，通过命令动态获取。

:::

<Tabs>
<TabItem value="native-vpccni" label="Native Routing (VPC-CNI)" default>

```bash
helm upgrade --install cilium cilium/cilium --version 1.19.4 \
  --namespace kube-system \
  --set image.repository=quay.tencentcloudcr.com/cilium/cilium \
  --set envoy.image.repository=quay.tencentcloudcr.com/cilium/cilium-envoy \
  --set operator.image.repository=quay.tencentcloudcr.com/cilium/operator \
  --set certgen.image.repository=quay.tencentcloudcr.com/cilium/certgen \
  --set hubble.relay.image.repository=quay.tencentcloudcr.com/cilium/hubble-relay \
  --set hubble.ui.backend.image.repository=quay.tencentcloudcr.com/cilium/hubble-ui-backend \
  --set hubble.ui.frontend.image.repository=quay.tencentcloudcr.com/cilium/hubble-ui \
  --set nodeinit.image.repository=quay.tencentcloudcr.com/cilium/startup-script \
  --set preflight.image.repository=quay.tencentcloudcr.com/cilium/cilium \
  --set preflight.envoy.image.repository=quay.tencentcloudcr.com/cilium/cilium-envoy \
  --set clustermesh.apiserver.image.repository=quay.tencentcloudcr.com/cilium/clustermesh-apiserver \
  --set authentication.mutual.spire.install.agent.image.repository=docker.io/k8smirror/spire-agent \
  --set authentication.mutual.spire.install.server.image.repository=docker.io/k8smirror/spire-server \
  --set operator.tolerations[0].key="node-role.kubernetes.io/control-plane",operator.tolerations[0].operator="Exists" \
  --set operator.tolerations[1].key="node-role.kubernetes.io/master",operator.tolerations[1].operator="Exists" \
  --set operator.tolerations[2].key="node.kubernetes.io/not-ready",operator.tolerations[2].operator="Exists" \
  --set operator.tolerations[3].key="node.cloudprovider.kubernetes.io/uninitialized",operator.tolerations[3].operator="Exists" \
  --set operator.tolerations[4].key="tke.cloud.tencent.com/uninitialized",operator.tolerations[4].operator="Exists" \
  --set operator.tolerations[5].key="tke.cloud.tencent.com/eni-ip-unavailable",operator.tolerations[5].operator="Exists" \
  --set routingMode=native \
  --set endpointRoutes.enabled=true \
  --set ipam.mode=delegated-plugin \
  --set enableIPv4Masquerade=false \
  --set devices=eth+ \
  --set cni.chainingMode=generic-veth \
  --set cni.customConf=true \
  --set cni.configMap=cni-config \
  --set cni.externalRouting=true \
  --set extraConfig.local-router-ipv4=169.254.32.16 \
  --set localRedirectPolicies.enabled=true \
  --set sysctlfix.enabled=false \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=$(kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}') \
  --set k8sServicePort=60002
```

</TabItem>
<TabItem value="overlay-gr" label="Overlay (GR)">

```bash
helm upgrade --install cilium cilium/cilium --version 1.19.4 \
  --namespace kube-system \
  --set image.repository=quay.tencentcloudcr.com/cilium/cilium \
  --set envoy.image.repository=quay.tencentcloudcr.com/cilium/cilium-envoy \
  --set operator.image.repository=quay.tencentcloudcr.com/cilium/operator \
  --set certgen.image.repository=quay.tencentcloudcr.com/cilium/certgen \
  --set hubble.relay.image.repository=quay.tencentcloudcr.com/cilium/hubble-relay \
  --set hubble.ui.backend.image.repository=quay.tencentcloudcr.com/cilium/hubble-ui-backend \
  --set hubble.ui.frontend.image.repository=quay.tencentcloudcr.com/cilium/hubble-ui \
  --set nodeinit.image.repository=quay.tencentcloudcr.com/cilium/startup-script \
  --set preflight.image.repository=quay.tencentcloudcr.com/cilium/cilium \
  --set preflight.envoy.image.repository=quay.tencentcloudcr.com/cilium/cilium-envoy \
  --set clustermesh.apiserver.image.repository=quay.tencentcloudcr.com/cilium/clustermesh-apiserver \
  --set authentication.mutual.spire.install.agent.image.repository=docker.io/k8smirror/spire-agent \
  --set authentication.mutual.spire.install.server.image.repository=docker.io/k8smirror/spire-server \
  --set operator.tolerations[0].key="node-role.kubernetes.io/control-plane",operator.tolerations[0].operator="Exists" \
  --set operator.tolerations[1].key="node-role.kubernetes.io/master",operator.tolerations[1].operator="Exists" \
  --set operator.tolerations[2].key="node.kubernetes.io/not-ready",operator.tolerations[2].operator="Exists" \
  --set operator.tolerations[3].key="node.cloudprovider.kubernetes.io/uninitialized",operator.tolerations[3].operator="Exists" \
  --set operator.tolerations[4].key="tke.cloud.tencent.com/uninitialized",operator.tolerations[4].operator="Exists" \
  --set routingMode=tunnel \
  --set tunnelProtocol=vxlan \
  --set ipam.mode=cluster-pool \
  --set ipam.operator.clusterPoolIPv4PodCIDRList="{10.244.0.0/16}" \
  --set ipam.operator.clusterPoolIPv4MaskSize=24 \
  --set enableIPv4Masquerade=true \
  --set bpf.masquerade=true \
  --set localRedirectPolicies.enabled=true \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=$(kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}') \
  --set k8sServicePort=60002
```

</TabItem>
<TabItem value="overlay-vpccni" label="Overlay (VPC-CNI)">

```bash
helm upgrade --install cilium cilium/cilium --version 1.19.4 \
  --namespace kube-system \
  --set image.repository=quay.tencentcloudcr.com/cilium/cilium \
  --set envoy.image.repository=quay.tencentcloudcr.com/cilium/cilium-envoy \
  --set operator.image.repository=quay.tencentcloudcr.com/cilium/operator \
  --set certgen.image.repository=quay.tencentcloudcr.com/cilium/certgen \
  --set hubble.relay.image.repository=quay.tencentcloudcr.com/cilium/hubble-relay \
  --set hubble.ui.backend.image.repository=quay.tencentcloudcr.com/cilium/hubble-ui-backend \
  --set hubble.ui.frontend.image.repository=quay.tencentcloudcr.com/cilium/hubble-ui \
  --set nodeinit.image.repository=quay.tencentcloudcr.com/cilium/startup-script \
  --set preflight.image.repository=quay.tencentcloudcr.com/cilium/cilium \
  --set preflight.envoy.image.repository=quay.tencentcloudcr.com/cilium/cilium-envoy \
  --set clustermesh.apiserver.image.repository=quay.tencentcloudcr.com/cilium/clustermesh-apiserver \
  --set authentication.mutual.spire.install.agent.image.repository=docker.io/k8smirror/spire-agent \
  --set authentication.mutual.spire.install.server.image.repository=docker.io/k8smirror/spire-server \
  --set operator.tolerations[0].key="node-role.kubernetes.io/control-plane",operator.tolerations[0].operator="Exists" \
  --set operator.tolerations[1].key="node-role.kubernetes.io/master",operator.tolerations[1].operator="Exists" \
  --set operator.tolerations[2].key="node.kubernetes.io/not-ready",operator.tolerations[2].operator="Exists" \
  --set operator.tolerations[3].key="node.cloudprovider.kubernetes.io/uninitialized",operator.tolerations[3].operator="Exists" \
  --set operator.tolerations[4].key="tke.cloud.tencent.com/uninitialized",operator.tolerations[4].operator="Exists" \
  --set operator.tolerations[5].key="tke.cloud.tencent.com/eni-ip-unavailable",operator.tolerations[5].operator="Exists" \
  --set routingMode=tunnel \
  --set tunnelProtocol=vxlan \
  --set ipam.mode=cluster-pool \
  --set ipam.operator.clusterPoolIPv4PodCIDRList="{10.244.0.0/16}" \
  --set ipam.operator.clusterPoolIPv4MaskSize=24 \
  --set enableIPv4Masquerade=true \
  --set bpf.masquerade=true \
  --set localRedirectPolicies.enabled=true \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=$(kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}') \
  --set k8sServicePort=60002
```

</TabItem>
</Tabs>

#### 配置参数说明（values.yaml 形式）

上面的 `--set` 命令式参数适合快速试验。**生产环境推荐改用 `values.yaml` 文件管理参数**：参数语义更清晰、可纳入 Git 版本管理、便于审阅与回滚。以下按「通用参数 + 模式专属参数 + 镜像/Egress/资源等可选参数」分块给出注释完整的示例。

<Tabs>
  <TabItem value="common" label="通用参数">

所有模式共用的配置参数：

```yaml showLineNumbers title="common-values.yaml"
# 替代 kube-proxy，包括 ClusterIP/NodePort/HostPort 转发
kubeProxyReplacement: "true"
# 注意替换为实际的 apiserver 地址
# 获取方法：kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}'
k8sServiceHost: 169.254.128.112
k8sServicePort: 60002
# 启用 CiliumLocalRedirectPolicy 的能力
# 参考：https://docs.cilium.io/en/stable/network/kubernetes/local-redirect-policy/
localRedirectPolicies:
  enabled: true
operator:
  tolerations:
  - key: "node-role.kubernetes.io/control-plane"
    operator: Exists
  - key: "node-role.kubernetes.io/master"
    operator: Exists
  - key: "node.kubernetes.io/not-ready"
    operator: Exists
  - key: "node.cloudprovider.kubernetes.io/uninitialized"
    operator: Exists
  # 容忍 TKE 的污点，避免首次安装时循环依赖
  - key: "tke.cloud.tencent.com/uninitialized"
    operator: Exists
```

  </TabItem>
  <TabItem value="native-vpccni" label="Native (VPC-CNI)">

Native Routing (VPC-CNI) 模式专属参数：

```yaml showLineNumbers title="native-vpccni-values.yaml"
# 使用 native routing，Pod 直接使用 VPC IP 路由，无需 overlay
routingMode: "native"
endpointRoutes:
  # native routing 必须置为 true，转发 Pod 流量直接路由到 veth 设备
  # 注意：这同时意味着 cilium 走 legacy host routing 而非 BPF host routing，
  # 详见附录《Cilium Host Routing：legacy vs BPF》
  enabled: true
ipam:
  # Pod IP 分配由 tke-eni-ipamd 负责，cilium 无需负责
  mode: "delegated-plugin"
# VPC-CNI 场景 Pod IP 就是 VPC IP，无需 IP 伪装
enableIPv4Masquerade: false
# TKE 节点中 eth 开头的网卡都可能出入流量（辅助网卡 eth1/eth2...）
# 用这个参数让所有 eth 开头的网卡都挂载 cilium ebpf 程序
devices: eth+
cni:
  # 使用 generic-veth 与 VPC-CNI 做 CNI Chaining
  chainingMode: generic-veth
  # CNI 配置完全自定义，使用下方 configMap 中预先创建的配置
  customConf: true
  configMap: cni-configuration
  # VPC-CNI 会自动配置 Pod 路由，cilium 无需配置
  externalRouting: true
extraConfig:
  # cilium 不负责 Pod IP 分配，需手动指定 cilium_host 虚拟网卡的 IP
  local-router-ipv4: 169.254.32.16
# 禁用 sysctlfix，避免重启 systemd-sysctl 导致 eth0 rp_filter 被重置，详见 FAQ
sysctlfix:
  enabled: false
operator:
  tolerations:
  # VPC-CNI 模式额外需要容忍此污点
  - key: "tke.cloud.tencent.com/eni-ip-unavailable"
    operator: Exists
```

  </TabItem>
  <TabItem value="overlay" label="Overlay (VPC-CNI/GR)">

Overlay (vxlan) 模式专属参数，VPC-CNI 和 GR 集群通用：

```yaml showLineNumbers title="overlay-values.yaml"
# 使用 vxlan tunnel 封装跨节点流量
routingMode: "tunnel"
tunnelProtocol: "vxlan"
ipam:
  mode: "cluster-pool"
  operator:
    # Pod CIDR，根据集群规模调整；不与 VPC CIDR 和 Service CIDR 冲突即可
    clusterPoolIPv4PodCIDRList:
    - "10.244.0.0/16"
    # 每节点子网掩码，/24 = 每节点 254 个 Pod IP
    clusterPoolIPv4MaskSize: "24"
# Overlay 模式需要 IP 伪装，Pod IP 访问集群外需 SNAT 为节点 IP
enableIPv4Masquerade: true
bpf:
  # 必须启用 BPF 实现的 masquerade，否则 cilium 默认走 iptables 实现，会让 host
  # routing 强制 fallback 到 legacy（无法启用 BPF host routing）。
  # 详见附录《Cilium Host Routing：legacy vs BPF》
  masquerade: true
# 不设置 sysctlfix（保持默认 true），确保 lxc 接口 rp_filter=0
```

VPC-CNI 集群额外需要的 operator toleration：

```yaml
operator:
  tolerations:
  - key: "tke.cloud.tencent.com/eni-ip-unavailable"
    operator: Exists
```

  </TabItem>
  <TabItem value="images" label="镜像相关">

将所有 cilium 依赖镜像替换为在 TKE 环境中能直接内网拉取 mirror 镜像，避免因网络问题导致镜像拉取失败：

```yaml title="image-values.yaml"
image:
  repository: quay.tencentcloudcr.com/cilium/cilium
envoy:
  image:
    repository: quay.tencentcloudcr.com/cilium/cilium-envoy
operator:
  image:
    repository: quay.tencentcloudcr.com/cilium/operator
certgen:
  image:
    repository: quay.tencentcloudcr.com/cilium/certgen
hubble:
  relay:
    image:
      repository: quay.tencentcloudcr.com/cilium/hubble-relay
  ui:
    backend:
      image:
        repository: quay.tencentcloudcr.com/cilium/hubble-ui-backend
    frontend:
      image:
        repository: quay.tencentcloudcr.com/cilium/hubble-ui
nodeinit:
  image:
    repository: quay.tencentcloudcr.com/cilium/startup-script
preflight:
  image:
    repository: quay.tencentcloudcr.com/cilium/cilium
  envoy:
    image:
      repository: quay.tencentcloudcr.com/cilium/cilium-envoy
clustermesh:
  apiserver:
    image:
      repository: quay.tencentcloudcr.com/cilium/clustermesh-apiserver
authentication:
  mutual:
    spire:
      install:
        agent:
          image:
            repository: docker.io/k8smirror/spire-agent
        server:
          image:
            repository: docker.io/k8smirror/spire-server
```

  </TabItem>
</Tabs>

生产环境部署建议将参数保存到 YAML 文件，然后在安装或更新时，都可以类似执行下面的命令（如果要升级版本，替换 `--version` 即可）：

```bash
helm upgrade --install cilium cilium/cilium --version 1.19.4 \
  --namespace=kube-system \
  -f tke-values.yaml \
  -f image-values.yaml
```

如果自定义的配置较多，建议拆成多个 yaml 文件维护，比如用于启用 Egress Gateway 的配置放到 `egress-values.yaml`，配置容器 request 与 limit 的放到 `resources-values.yaml`，更新配置时通过加多个 `-f` 参数来合并多个 yaml 文件：

```bash
helm upgrade --install cilium cilium/cilium --version 1.19.4 \
  --namespace=kube-system \
  -f tke-values.yaml \
  -f image-values.yaml \
  -f egress-values.yaml \
  -f resources-values.yaml
```

#### 验证安装结果

确保 cilium 相关 pod 正常运行：

```bash
$ kubectl --namespace=kube-system get pod -l app.kubernetes.io/part-of=cilium
NAME                              READY   STATUS    RESTARTS   AGE
cilium-5rfrk                      1/1     Running   0          1m
cilium-9mntb                      1/1     Running   0          1m
cilium-envoy-4r4x9                1/1     Running   0          1m
cilium-envoy-kl5cz                1/1     Running   0          1m
cilium-envoy-sgl5v                1/1     Running   0          1m
cilium-operator-896cdbf88-jlgt7   1/1     Running   0          1m
cilium-operator-896cdbf88-nj6jc   1/1     Running   0          1m
cilium-zrxwn                      1/1     Running   0          1m
```

### 配置 APF 限速

每台节点上都有 cilium-agent 运行，当集群规模较大时，可能会对 APIServer 造成较大压力，极端场景可能造成雪崩，导致整个集群不可用，所以需要配置 APF 来对 cilium 的组件进行限速。

保存以下内容到文件 `cilium-apf.yaml`：

:::tip[备注]

可根据集群规格修改 `nominalConcurrencyShares` 的值，参考注释。

:::

<FileBlock file="cilium/cilium-apf.yaml" showLineNumbers showFileName />

创建 APF 限速规则：

```bash
kubectl apply -f cilium-apf.yaml
```

## 新建节点池

:::tip[OS 兼容性说明]

Cilium 要求 Linux kernel >= 5.10。**推荐 OS**：Ubuntu 24.04 或 TencentOS 4 最新版。

**实测覆盖的 OS 列表**详见 [已验证的节点操作系统](./appendix/verified-os.md)。

:::

### 节点池选型

以下三种节点池类型能够适配 cilium:

- 原生节点池：基于原生节点，原生节点功能很丰富，也是 TKE 推荐的节点类型（参考 [原生节点 VS 普通节点](https://cloud.tencent.com/document/product/457/78197#.E5.8E.9F.E7.94.9F.E8.8A.82.E7.82.B9-vs-.E6.99.AE.E9.80.9A.E8.8A.82.E7.82.B9)），OS 固定使用 TencentOS。
- 普通节点池：基于普通节点（CVM），OS 镜像比较灵活。
- Karpenter 节点池：与原生节点池类似，基于原生节点，OS 固定使用 TencentOS，只是节点管理使用的功能更强大的 [Karpenter](https://karpenter.sh/) 而非普通节点池与原生节点池所使用的 [cluster-autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler) (CA)。

以下是这几种节点池的对比，根据自身情况选择合适的节点池类型：

| 节点池类型       | 节点类型        | 可用 OS 镜像                                      | 节点扩缩容组件     |
| ---------------- | --------------- | ------------------------------------------------- | ------------------ |
| 原生节点池       | 原生节点        | TencentOS                                         | cluster-autoscaler |
| 普通节点池       | 普通节点（CVM） | Ubuntu/TencentOS 等所有 CVM 公共镜像 + 自定义镜像 | cluster-autoscaler |
| Karpenter 节点池 | 原生节点        | TencentOS                                         | Karpenter          |

以下创建各种节点池的步骤。

### 新建 Karpenter 节点池

在新建 Karpenter 节点池之前，确保 Karpenter 组件已启用，参考 [tke-karpenter 说明](https://cloud.tencent.com/document/product/457/111805)。

准备用于配置 Karpenter 节点池的 `nodepool.yaml`，以下是示例:

```yaml title="nodepool.yaml"
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 5m
    budgets:
    - nodes: 10%
  template:
    metadata:
      annotations:
        # 原生节点默认安装 TencentOS 3，与最新 cilium 版本不兼容，指定该注解安装 TencentOS 4
        # 注意：当前使用该系统镜像还需要提工单申请
        beta.karpenter.k8s.tke.machine.spec/annotations: node.tke.cloud.tencent.com/image-label=ts4-public
    spec:
      requirements:
      - key: kubernetes.io/arch
        operator: In
        values: ["amd64"]
      - key: kubernetes.io/os
        operator: In
        values: ["linux"]
      - key: karpenter.k8s.tke/instance-family
        operator: In
        # 指定期望使用的机型列表，可在控制台先确认下集群所在地域和相关可用区实际售卖的机型有哪些
        # 完整列表参考: https://cloud.tencent.com/document/product/213/11518#INSTANCETYPE
        values: ["S5", "SA2"]
      - key: karpenter.sh/capacity-type
        operator: In
        values: ["on-demand"]
      - key: "karpenter.k8s.tke/instance-cpu"
        operator: Gt
        values: ["1"] # 指定扩容时最小的 CPU 核数
      nodeClassRef:
        group: karpenter.k8s.tke
        kind: TKEMachineNodeClass
        name: default # 引用 TKEMachineNodeClass
  limits:
    cpu: 100 # 限制节点池的最大 CPU 核数

---
apiVersion: karpenter.k8s.tke/v1beta1
kind: TKEMachineNodeClass
metadata:
  name: default
spec:
  subnetSelectorTerms: # 节点所属 VPC 子网
  - id: subnet-12sxk3z4
  - id: subnet-b8qyi2dk
  securityGroupSelectorTerms: # 节点绑定的安全组
  - id: sg-nok01xpa
  sshKeySelectorTerms: # 节点绑定的 ssh 密钥
  - id: skey-3t01mlvf
```

创建 Karpenter 节点池：

```bash
kubectl apply -f nodepool.yaml
```

### 新建原生节点池

以下是通过 [容器服务控制台](https://console.cloud.tencent.com/tke2) 新建原生节点池的步骤：

1. 在集群列表中，单击集群 ID，进入集群详情页。
2. 选择左侧菜单栏中的**节点管理**，点击**节点池**进入节点池列表页面。
3. 点击**新建**。
4. 选择 **原生节点**。
5. 在 **高级设置** 的 Annotations 点击 **新增**：`node.tke.cloud.tencent.com/image-label=ts4-public`（原生节点默认使用 TencentOS 3.1，与最新版的 cilium 不兼容，通过注解指定原生节点使用 TencentOS 4）。
6. 其余选项根据自身需求自行选择。
7. 点击 **创建节点池**。

如果你想通过 terraform 来创建原生节点池，参考以下代码片段：

```hcl
resource "tencentcloud_kubernetes_native_node_pool" "cilium" {
  name       = "cilium"
  cluster_id = tencentcloud_kubernetes_cluster.tke_cluster.id
  type       = "Native"
  annotations { # 添加注解指定原生节点使用 TencentOS 4，以便能够与 cilium 兼容，当前使用该系统镜像还需要提工单申请
    name  = "node.tke.cloud.tencent.com/image-label"
    value = "ts4-public"
  }
}
```

### 新建普通节点池

以下是通过 [容器服务控制台](https://console.cloud.tencent.com/tke2) 新建普通节点池的步骤：

1. 在集群列表中，单击集群 ID，进入集群详情页。
2. 选择左侧菜单栏中的**节点管理**，点击**节点池**进入节点池列表页面。
3. 点击**新建**。
4. 选择 **普通节点**。
5. **操作系统** 选择 [已验证的节点操作系统](./appendix/verified-os.md) 中的任一镜像（推荐 **TencentOS 4** 或 **Ubuntu 24.04**），也可以使用其他满足最低内核要求（kernel >= 5.10）的 CVM 公共镜像或自定义镜像（建议先单节点验证）。
6. 其余选项根据自身需求自行选择。
7. 点击**创建节点池**。

如果你想通过 terraform 来创建普通节点池，参考以下代码片段：

```hcl
resource "tencentcloud_kubernetes_node_pool" "cilium" {
  name       = "cilium"
  cluster_id = tencentcloud_kubernetes_cluster.tke_cluster.id
  node_os    = "tlinux4_x86_64_public" # OsName，完整已验证 OS 列表见附录

  # 确保 cilium agent 就绪后才调度业务 Pod
  taints {
    key    = "node.cilium.io/agent-not-ready"
    value  = "true"
    effect = "NoSchedule"
  }
}
```

## 升级与回滚

### 升级 cilium 版本

cilium 小版本升级（如 1.19.4 → 1.19.5）通常向后兼容，使用 helm 直接升级即可。**跨大版本升级（如 1.18 → 1.19）必须查阅官方 [Upgrade Guide](https://docs.cilium.io/en/stable/operations/upgrade/) 的版本对应章节**，确认 breaking change 与必需的参数调整。

升级步骤：

```bash
# 1. 备份当前 values
helm get values cilium -n kube-system > cilium-values-backup.yaml

# 2. 更新 helm repo
helm repo update cilium

# 3. 升级（保留现有 values）
helm upgrade cilium cilium/cilium \
  --namespace kube-system \
  --version <新版本> \
  --reuse-values

# 4. 滚动重启确保 datapath 使用新版本（cilium-agent 默认 RollingUpdate，无中断）
kubectl -n kube-system rollout status ds/cilium

# 5. 验证
bash -c "$(curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh)" -- test
```

:::warning[升级注意事项]

- **生产集群升级前先在测试集群验证**，确认业务无异常。
- **NetworkPolicy 行为可能在不同版本间有微调**，升级后回归核心策略效果。
- 跨大版本升级如涉及 ConfigMap / CRD 变更，按官方文档执行 `cilium upgrade --pre-flight` 检查或手动迁移。

:::

### 回滚到 TKE 内置 CNI

如需从 cilium 回退到 TKE 原生 CNI（VPC-CNI 或 GR），操作不可避免地会中断业务，建议在维护窗口执行。

**一键卸载脚本**（推荐，自动完成下列前 4 步）：

```bash
bash -c "$(curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh)" -- uninstall
```

脚本会卸载 cilium helm release、删除 cni-config / APF 限速规则、恢复 TKE 网络组件 DaemonSet 调度，最后打印剩余的手工动作。如需手动操作，按下列步骤执行：

1. **删除新的业务调度**：节点池打 cordon，避免回滚过程中有 Pod 新建。
2. **卸载 cilium**：
   ```bash
   helm uninstall cilium -n kube-system
   ```
3. **清理节点残留**：每个节点上手动清理 cilium 的 BPF 程序、CNI 配置与 iptables 规则：
   ```bash
   # 在每个节点执行
   sudo rm -f /etc/cni/net.d/05-cilium.conf /etc/cni/net.d/05-cilium.conflist
   sudo rm -f /etc/cni/net.d/*.cilium_bak  # 恢复被 cilium 重命名的原 CNI 配置
   sudo iptables-save | grep -i cilium | wc -l  # 检查残留规则，必要时手动 -D
   ```
4. **重新启用 TKE 组件**：控制台勾选回 `tke-cni-agent`、`kube-proxy`、`ip-masq-agent` 等被卸载的组件。
5. **重启或重建节点**：最稳妥的方式是直接重建所有节点，确保 datapath 干净（**这步无论用不用一键脚本都需要手工做**）。

:::warning

回滚是高风险操作，**强烈建议直接重建节点**而不是手动清理。如必须保留节点（如有状态业务），务必在测试集群完整演练后再操作。

:::

## 常见问题

### 如何验证 cilium 安装是否正常？

cilium 提供两类验证方式：

- **功能测试**（约 35 分钟，覆盖 NetworkPolicy / Hubble / KPR / DNS / FQDN 等 130+ 用例）：

  ```bash
  bash -c "$(curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh)" -- test
  ```

- **性能测试**（约 3 分钟，跑 TCP_RR / TCP_STREAM 等 netperf 测试）：

  ```bash
  bash -c "$(curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh)" -- perf
  ```

完整测试方法、运行环境前提、各方案实测结果参考 [Cilium 功能测试](./appendix/connectivity-test.md) 和 [Cilium 性能测试](./appendix/performance-test.md)。

### 如何查看 Cilium 全部的默认安装配置？

Cilium 的 helm 安装包提供了大量的自定义配置项，本文给出的只是 TKE 环境中安装 Cilium 的必要配置，实际可根据自身需求调整更多配置。

执行下面的命令可查看所有的安装配置项：

```bash
helm show values cilium/cilium --version 1.19.4
```

### 连不上 cilium 的 helm repo 怎么办？

使用 helm 安装 cilium 时，helm 会从 cilium 的 helm repo 获取 chart 相关信息并下载，如果连不上则会报错。

解决办法是在可以连上的环境下载 chart 压缩包：

```bash
$ helm pull cilium/cilium --version 1.19.4
$ ls cilium-*.tgz
cilium-1.19.4.tgz
```

然后将 chart 压缩包复制到执行 helm 安装的机器上，安装时指定下 chart 压缩包的路径：

```bash
helm upgrade --install cilium ./cilium-1.19.4.tgz \
  --namespace kube-system \
  -f values.yaml
```

### 大规模场景如何优化？

集群规模较大（数百节点 / 万级 Pod 以上）时，cilium 默认配置可能出现 apiserver 压力大、cilium-agent OOM、策略计算慢等问题，可从启用 CiliumEndpointSlice、APF 限速、调整 client QPS、精简 Identity 等多方面调优，详见 [大规模集群 Cilium 调优指南](./appendix/large-scale-tuning.md)。

### 为什么不推荐使用 GR 集群？

GR (GlobalRouter) 集群本身有几个限制，叠加 cilium 后体验也受影响。**已有 GR 集群可以继续按 Overlay (GR) 方案装 cilium 用**，但**不推荐为了装 cilium 而新建 GR 集群**：

1. **GR 集群创建时强制要求 ClusterCIDR，并占用 VPC 一段辅助网段**

   GR 集群创建时必须指定 ClusterCIDR，这段网段会从 VPC 辅助网段中划出来分配给该 GR 集群，写入 VPC 的辅助 CIDR 列表。
   - 如果选 Overlay (GR) 方案安装 cilium，**Pod IP 完全来自 cilium 自管的独立 CIDR（如 `10.244.0.0/16`），那段 ClusterCIDR 一个 IP 都不会被 Pod 用到**
   - 但这段 ClusterCIDR 仍然挂在 GR 集群上，**同 VPC 下的其它资源（CVM、其它集群、CLB 等）都不能用这个网段**——白白占住一段 VPC 辅助网段，相当于浪费

2. **节点数量受 ClusterCIDR 限制**

   GR 集群每个节点会从 ClusterCIDR 中切一个子网（默认 /24，254 个 IP）作为节点 Pod CIDR，节点数上限就是 `ClusterCIDR 总 IP 数 / 单节点子网大小`，而 ClusterCIDR 一旦创建很难扩展。VPC-CNI 集群没有这个限制（节点数与 VPC 子网容量相关，可加新子网扩容）。

3. **GR + Native Routing 在 cilium chained CNI 模式下存在严重兼容性问题**

   跨节点 Pod-to-Pod 流量不通、L7 / DNS / toFQDNs NetworkPolicy 不可用，本系列教程不再提供。详见 [为什么不提供 GR Native Routing 部署方案？](./appendix/gr-native-not-recommended.md)。

综合上述，**新装 cilium 一律推荐 VPC-CNI 集群**：

- 想 Pod IP 等于 VPC IP（被 VPC 路由 / CLB / 安全组 / CCN 原生识别）→ VPC-CNI + Native Routing
- 想节省 VPC IP 容量、纳管 IDC 或获得满血 cilium 能力 → VPC-CNI + Overlay（同时也避免了 GR 那段 ClusterCIDR 的浪费）

### VPC-CNI 集群创建时能否勾选 DataPlaneV2？

不能。

选择 VPC-CNI 网络插件时，有个 DataPlaneV2 选项：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F09%2F26%2F20250926092351.png)

勾选后，会部署 cilium 组件到集群中（替代 kube-proxy 组件），如果再自己安装 cilium 会造成冲突，而且 DataPlaneV2 所使用的 OS 与 cilium 最新版也不兼容，所以不能勾选此选项。

### Pod 如何访问公网？

不同网络方案的 Pod 出公网行为不一样，分情况说明。

**GR 与 VPC-CNI Overlay 模式**：cilium 默认就启用了 IP 伪装（`enableIPv4Masquerade=true`），Pod 出节点时会被 SNAT 成节点 IP，节点本身有公网能力（NAT 网关 / 节点 EIP / Egress Gateway）即可让 Pod 出公网。

**VPC-CNI Native 模式**：cilium 默认**关闭** IP 伪装（`enableIPv4Masquerade=false`），因为 Pod IP 本身就是合法 VPC IP，东西向流量直接路由即可。但这意味着 Pod 出公网时源 IP 是 Pod IP（来自节点辅助网卡的 IP 池），辅助网卡上没有 EIP，**节点即使绑了 EIP（EIP 只在主网卡）也无法让 Pod 出公网**。需要满足下列任一条件：

1. **VPC 配置 NAT 网关**：在集群所在 VPC 的路由表中新建路由规则，让访问外网的流量转发到公网 NAT 网关，并确保路由表关联到了集群使用的子网，参考 [通过 NAT 网关访问外网](https://cloud.tencent.com/document/product/457/48710)。
2. **启用 cilium 的 ip-masq-agent**：Pod 出 VPC 的流量 SNAT 成节点 IP，从节点主网卡 + 节点 EIP 出公网，适合"节点本身有公网，希望复用节点公网带宽"的场景。具体方法参考 [配置 IP 伪装](./masquerading.md)。
3. **启用 Cilium Egress Gateway**：适合需要按 namespace/pod 选择固定出口 IP 的高级场景，参考 [Egress Gateway 应用实践](./egress-gateway.md)。

### 镜像拉取失败？

cilium 依赖的大部分镜像在 `quay.io`，如果安装时没使用本文给的替换镜像地址的参数配置，可能导致 cilium 相关镜像拉取失败（比如节点没有访问公网的能力，或者集群在中国大陆）。

在 TKE 环境中，提供了 `quay.tencentcloudcr.com` 这个 mirror 仓库地址，用于下载 `quay.io` 域名下的镜像，直接将原镜像地址中 `quay.io` 域名替换为 `quay.tencentcloudcr.com` 即可，拉取时走内网，无需节点有公网能力，也没有地域限制。

如果你配置了更多安装的参数，可能会涉及更多的镜像依赖，没有配置镜像地址替换的话可能导致镜像拉取失败，用以下命令可将所有 cilium 依赖镜像一键替换为 TKE 环境中可直接内网拉取的 mirror 仓库地址：

```bash
helm upgrade cilium cilium/cilium --version 1.19.4 \
  --namespace kube-system \
  --reuse-values \
  --set image.repository=quay.tencentcloudcr.com/cilium/cilium \
  --set envoy.image.repository=quay.tencentcloudcr.com/cilium/cilium-envoy \
  --set operator.image.repository=quay.tencentcloudcr.com/cilium/operator \
  --set certgen.image.repository=quay.tencentcloudcr.com/cilium/certgen \
  --set hubble.relay.image.repository=quay.tencentcloudcr.com/cilium/hubble-relay \
  --set hubble.ui.backend.image.repository=quay.tencentcloudcr.com/cilium/hubble-ui-backend \
  --set hubble.ui.frontend.image.repository=quay.tencentcloudcr.com/cilium/hubble-ui \
  --set nodeinit.image.repository=quay.tencentcloudcr.com/cilium/startup-script \
  --set preflight.image.repository=quay.tencentcloudcr.com/cilium/cilium \
  --set preflight.envoy.image.repository=quay.tencentcloudcr.com/cilium/cilium-envoy \
  --set clustermesh.apiserver.image.repository=quay.tencentcloudcr.com/cilium/clustermesh-apiserver \
  --set authentication.mutual.spire.install.agent.image.repository=docker.io/k8smirror/spire-agent \
  --set authentication.mutual.spire.install.server.image.repository=docker.io/k8smirror/spire-server
```

如果你使用 yaml 管理配置，可以将镜像替换的配置保存到 `image-values.yaml`:

```yaml title="image-values.yaml"
image:
  repository: quay.tencentcloudcr.com/cilium/cilium
envoy:
  image:
    repository: quay.tencentcloudcr.com/cilium/cilium-envoy
operator:
  image:
    repository: quay.tencentcloudcr.com/cilium/operator
certgen:
  image:
    repository: quay.tencentcloudcr.com/cilium/certgen
hubble:
  relay:
    image:
      repository: quay.tencentcloudcr.com/cilium/hubble-relay
  ui:
    backend:
      image:
        repository: quay.tencentcloudcr.com/cilium/hubble-ui-backend
    frontend:
      image:
        repository: quay.tencentcloudcr.com/cilium/hubble-ui
nodeinit:
  image:
    repository: quay.tencentcloudcr.com/cilium/startup-script
preflight:
  image:
    repository: quay.tencentcloudcr.com/cilium/cilium
  envoy:
    image:
      repository: quay.tencentcloudcr.com/cilium/cilium-envoy
clustermesh:
  apiserver:
    image:
      repository: quay.tencentcloudcr.com/cilium/clustermesh-apiserver
authentication:
  mutual:
    spire:
      install:
        agent:
          image:
            repository: docker.io/k8smirror/spire-agent
        server:
          image:
            repository: docker.io/k8smirror/spire-server
```

更新 cilium 时追加一个 `-f image-values.yaml` 将镜像替换的配置加上：

```bash showLineNumbers
helm upgrade --install cilium cilium/cilium --version 1.19.4 \
  --namespace=kube-system \
  -f values.yaml \
  # highlight-add-line
  -f image-values.yaml
```

:::tip[说明]

使用 TKE 提供的 mirror 仓库地址拉取外部镜像，本身不提供 SLA 保障，某些时候可能也会拉取失败，通常最终会自动重试成功。

如果希望拉取镜像具备更高的可用性，可 [使用 TCR 托管 Cilium 镜像](./tcr.md) 将 cilium 依赖镜像同步到自己的 [TCR 镜像仓库](https://cloud.tencent.com/product/tcr)，然后参考这里的依赖镜像替换的配置，将相应镜像再替换为自己同步后的镜像地址。

:::

### cilium-operator 在超级节点无法就绪？

cilium-operator 使用 hostNetwork 并配置了就绪探针，在超级节点上使用 hostNetwork 时探测请求不通，所以 cilium-operator 无法就绪。

安装 cilium 的集群不建议使用超级节点，可以移除掉，如果一定要用，可给超级节点打上污点，再给需要调度到超级节点的 Pod 加上对应的容忍。

### cilium-agent 连 apiserver 报错 `operation not permitted`？

如果安装 cilium 时 `k8sServiceHost` 指向的是 CLB 地址（开启集群内网访问时使用的 CLB），地址为 CLB VIP 或最终解析到 CLB VIP 的域名，此时 cilium-agent 连接 apiserver 的链路会被 cilium 自身拦截并转发，不会真正到 CLB 转发。cilium 转发该地址最终是 ebpf 程序实现的，ebpf 程序转发该地址又是基于存放在内核中的 ebpf 数据（endpoint 列表），在某种触发条件下，ebpf 数据可能被刷新，刷新可能导致 endpoint 列表被临时清空，而一旦清空 cilium-agent 就再也连不上 apiserver（报错 `operation not permitted`），也就无法感知当前真实的 endpoint 列表来更新 ebpf 数据，形成循环依赖，重启节点后才会恢复正常。

所以建议是 `k8sServiceHost` 不要配置 apiserver 的 CLB 地址，而是使用集群 `169.254.x.x` 的 apiserver 地址（`kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}'`），该地址也是一个 VIP，但不会被 cilium 拦截转发，并且是自集群创建完后就再也不会变的，可以放心作为 `k8sServiceHost` 配置。如果希望使用辨识度更高的域名方式配置，也可以将域名解析到该地址然后再配置到 `k8sServiceHost`。

完整的根因分析、复现步骤和 cilium 上游 PR 链接，参见 [问题排查：连接 APIServer 报错 operation not permitted](./troubleshooting/connect-apiserver-operation-not-permitted.md)。

## 延伸阅读

设计原理与运维指南已拆分到独立文章，归入 [Cilium 附录](./appendix) 目录：

- [大规模集群 Cilium 调优指南](./appendix/large-scale-tuning.md)
- [已验证的节点操作系统](./appendix/verified-os.md)
- [Cilium 功能测试](./appendix/connectivity-test.md)
- [Cilium 性能测试](./appendix/performance-test.md)
- [为什么 Native Routing 模式要加 local-router-ipv4 配置？](./appendix/local-router-ipv4.md)
- [为什么 Native Routing 模式禁用 sysctlfix，Overlay 模式却启用？](./appendix/sysctlfix.md)
- [Cilium Host Routing：legacy vs BPF](./appendix/host-routing.md)
- [为什么不提供 GR Native Routing 部署方案？](./appendix/gr-native-not-recommended.md)

## 参考资料

- [Installation using Helm](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)
- [Generic Veth Chaining](https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/)
- [Kubernetes Without kube-proxy](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)

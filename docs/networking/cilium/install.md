# 安装 Cilium

本文介绍如何在 TKE 集群中安装 cilium，支持以下网络模式：

- **Native Routing（原生路由）**：与 TKE CNI 共存，Pod 使用 TKE 分配的 IP，cilium 提供 NetworkPolicy、可观测性、kube-proxy 替代等增强能力。
- **Overlay（vxlan 隧道）**：完全替代 TKE 所有 CNI，Pod IP 不占用 underlay 的 IP，可用于 IP 申请困难的场景，也可用于替代 TKE 内置的 CiliumOverlay 网络模式以获得满血功能。

每种模式都支持 VPC-CNI 和 GlobalRouter（GR）两种基础集群，共 4 种组合。**推荐使用 VPC-CNI 集群**，网络性能更好且无节点数量限制。

:::note[如何选择]

| 对比项               | Native Routing (VPC-CNI) ⭐ | Native Routing (GR)                   | Overlay (VPC-CNI) ⭐                       | Overlay (GR)                                       |
| -------------------- | --------------------------- | ------------------------------------- | ------------------------------------------ | -------------------------------------------------- |
| 网络性能             | 最优                        | 较优（多一层网桥转发）                | 略有开销（vxlan 封装）                     | 略有开销（vxlan 封装）                             |
| Pod IP 范围          | VPC IP                      | VPC 辅助网段 IP                       | 独立 CIDR，不占用 VPC IP                   | 独立 CIDR，不占用 VPC IP                           |
| IP 容量扩容          | 给集群新增 VPC-CNI 子网     | 给集群新增 GR 网段（VPC 辅助网段）    | 追加 CIDR 到 clusterPoolIPv4PodCIDRList    | 同左                                               |
| 节点数量限制         | 无                          | 受 ClusterCIDR 限制                   | 无                                         | 受 GR 集群的 ClusterCIDR 限制（GR 集群本身的限制） |
| 集群外访问 Pod       | 可直接路由                  | VPC 内可路由                          | 不可直接路由，需通过 Service/Ingress       | 不可直接路由                                       |
| L7/DNS NetworkPolicy | ✅ 完整支持                 | ⚠️ 不支持（cbr0 桥限制）              | ✅ 完整支持                                | ✅ 完整支持                                        |
| 节点池额外要求       | 无                          | ⚠️ 必须打 cilium agent-not-ready 污点 | 无                                         | 无                                                 |
| 适用场景             | 常规场景（推荐）            | 已有 GR 集群的场景                    | IP 资源紧张、纳管 IDC、满血 cilium（推荐） | 同左，但已有 GR 集群                               |

两点限制详见附录：

- ⚠️ Native Routing (GR) 不支持 L7/DNS NetworkPolicy → [为什么 GR Native Routing 不支持 L7/DNS NetworkPolicy？](./appendix/gr-no-l7-dns.md)
- ⚠️ Native Routing (GR) 节点池必须打 cilium agent-not-ready 污点 → [为什么 Native Routing (GR) 节点池必须打 cilium agent-not-ready 污点？](./appendix/gr-agent-not-ready-taint.md)

:::

## 前期准备

### 准备 TKE 集群

:::info[注意]

安装 cilium 是对集群一个很重大的变更，不建议在有生产业务运行的集群中安装，否则安装过程中可能会影响线上业务的正常运行，建议在新创建的 TKE 集群中安装 cilium。

:::

在 [容器服务控制台](https://console.cloud.tencent.com/tke2/cluster) 创建 TKE 集群，注意以下关键选项：

- 容器网络插件：根据上表选择 **VPC-CNI 共享网卡多 IP** 或 **GlobalRouter**。
- 集群类型：标准集群。
- Kubernetes 版本: 不低于 1.32，建议选择最新版（参考 [Cilium Kubernetes Compatibility](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/)）。
- 操作系统：推荐 **TencentOS 4** 或 **Ubuntu 24.04**。最低要求 Linux kernel >= 5.10（参考 [System Requirements](https://docs.cilium.io/en/stable/operations/system_requirements/)）。已验证的 OS 列表见本文末尾的 [已验证的节点操作系统](#已验证的节点操作系统)。
- 节点：安装前不要向集群添加任何普通节点或原生节点，避免残留相关规则和配置，等安装完成后再添加。
- 基础组件：取消勾选 **TKE 自带的 ip-masq-agent** 组件，避免与 cilium 内置的 ipMasqAgent 冲突。Native Routing (GR) 模式后续会启用 cilium 内置的 ipMasqAgent（两者是不同组件，不要混淆）。
- 增强组件：如果节点池希望使用 Karpenter 节点池，需勾选安装 Karpenter 组件，否则无需勾选（参考后文的节点池选型）。

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
  # 容器网络插件: VPC-CNI / GR
  network_type = "VPC-CNI"
  # 集群 APIServer 开启访问
  cluster_internet = true
  # 通过内网 CLB 暴露 APIServer，需指定 CLB 所在子网 ID
  cluster_intranet_subnet_id = "subnet-xxx"
  # 不安装 ip-masq-agent （disable_addons 要求 tencentcloud provider 版本 1.82.33+）
  disable_addons = ["ip-masq-agent"]
  # 如需使用 Karpenter 节点池，需安装 Karpenter 组件。（cluster-autoscaler 与 karpenter 互斥，
  # 启用此组件将不会安装 cluster-autoscaler，也就会禁用原生节点池和普通节点池的扩缩容功能，
  # 如不使用 Karpenter 节点池，可省略以下代码，具体节点池选型参考下文“新建节点池”一节）。
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

可使用脚本自动检测集群环境并引导安装。先下载脚本再执行：

```bash
curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh -o cilium.sh
chmod +x cilium.sh
./cilium.sh install-cilium
```

如果网络环境无法连接 GitHub，可使用站点地址：

```bash
curl -sfL https://imroc.cc/tke/scripts/cilium.sh -o cilium.sh
chmod +x cilium.sh
./cilium.sh install-cilium
```

脚本会自动检测集群网络模式、引导选择安装方案和版本，然后执行安装。安装过程中还可选择是否启用 [Egress Gateway](egress-gateway.md) 和 [Nodelocal DNSCache](with-node-local-dns.md)。如需手动安装，参考后续步骤。

:::tip[为什么不用 `curl ... | bash` 一行执行？]

本脚本 `install-cilium` 子命令是交互式的（需要选择安装模式等）。如果用 `curl ... | bash`，bash 的标准输入会被 curl 的输出占用，导致脚本中的 `read` 读不到键盘输入而立即退出（弹出选项后自动结束）。所以本文统一使用「先下载再执行」的写法。

如果你确实希望一行命令完成，可以通过环境变量预先指定参数跳过交互，此时不再需要 stdin（详见脚本注释中的非交互模式说明）：

```bash
ROUTING_MODE=native CILIUM_VERSION=1.19.4 \
  curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh | bash -s install-cilium
```

:::

### 卸载 TKE 组件

所有方案都需要卸载 kube-proxy（由 cilium 替代）：

```bash
kubectl -n kube-system patch daemonset kube-proxy -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
```

除 Native Routing (GR) 外，其余方案还需要卸载 tke-cni-agent（避免 CNI 配置冲突）：

```bash
kubectl -n kube-system patch daemonset tke-cni-agent -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
```

:::tip[说明]

1. 通过加 nodeSelector 方式让 DaemonSet 不部署到任何节点，等同于卸载，同时也留个退路；当前 kube-proxy 也只能通过这种方式卸载，如果直接删除 kube-proxy，后续集群升级会被阻塞。
2. Native Routing (GR) 模式需要保留 tke-cni-agent，因为它负责拷贝 bridge 等 CNI 二进制到节点。该模式下 cilium 通过 `cni.exclusive=true`（默认）自动将 multus 配置重命名为 `.cilium_bak` 使其失效，不会产生冲突。
3. 前面提到过安装 cilium 之前不建议添加节点，如果因某些原因导致在安装 cilium 前添加了普通节点或原生节点，需重启下存量节点，避免残留相关规则和配置。
4. 如果创建集群时忘记了取消勾选 ip-masq-agent，可以手动卸载下：
   ```bash
   kubectl -n kube-system patch daemonset ip-masq-agent -p '{"spec":{"template":{"spec":{"nodeSelector":{"label-not-exist":"node-not-exist"}}}}}'
   ```

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
<TabItem value="native-gr" label="Native Routing (GR)">

需要对 tke-bridge-agent 做两处修改：

1. **修改 CNI 配置输出目录**：从 multus 子目录改到 CNI 根目录，以便 cilium 能通过 `chainingTarget` 发现并追加到 bridge 配置。
2. **禁用 portmap 插件**（`--port-mapping=false`）：cilium 的 `kubeProxyReplacement=true` 已包含 HostPort 转发能力，而 portmap 插件依赖已被卸载的 kube-proxy 创建的 `KUBE-MARK-MASQ` iptables chain，不禁用会导致创建 hostPort 的 Pod 报错（CNI 调用 portmap 失败）。

```bash
# 获取当前完整 args
CURRENT_ARGS=$(kubectl -n kube-system get ds tke-bridge-agent -o jsonpath='{.spec.template.spec.containers[0].args}')
# 1. 替换 CNI 配置目录路径
PATCHED_ARGS=$(echo "$CURRENT_ARGS" | sed 's|/host/etc/cni/net.d/multus|/host/etc/cni/net.d|g')
# 2. 追加 --port-mapping=false 禁用 portmap 插件（如已存在则跳过）
if ! echo "$PATCHED_ARGS" | grep -q 'port-mapping=false'; then
  PATCHED_ARGS=$(echo "$PATCHED_ARGS" | sed 's/\]$/,"--port-mapping=false"]/')
fi
kubectl -n kube-system patch ds tke-bridge-agent --type='json' \
  -p="[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/args\",\"value\":${PATCHED_ARGS}}]"
```

等待 tke-bridge-agent 滚动重启完成：

```bash
kubectl -n kube-system rollout status ds/tke-bridge-agent --timeout=120s
```

:::tip[说明]

安装 cilium 后，cilium 的 `cni.exclusive=true`（默认）会自动将 `00-multus.conf` 重命名为 `00-multus.conf.cilium_bak`，无需手动删除。

:::

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
<TabItem value="native-gr" label="Native Routing (GR)">

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
  --set operator.tolerations[1].key="node.kubernetes.io/not-ready",operator.tolerations[1].operator="Exists" \
  --set operator.tolerations[2].key="node.cloudprovider.kubernetes.io/uninitialized",operator.tolerations[2].operator="Exists" \
  --set cni.chainingMode=generic-veth \
  --set cni.chainingTarget=tke-bridge \
  --set routingMode=native \
  --set endpointRoutes.enabled=true \
  --set ipam.mode=delegated-plugin \
  --set enableIPv4Masquerade=true \
  --set bpf.masquerade=true \
  --set ipMasqAgent.enabled=true \
  --set devices=eth+ \
  --set cni.externalRouting=true \
  --set extraConfig.local-router-ipv4=169.254.32.16 \
  --set localRedirectPolicies.enabled=true \
  --set sysctlfix.enabled=false \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=$(kubectl get ep kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}') \
  --set k8sServicePort=60002
```

安装完成后，还需创建 `ip-masq-agent` ConfigMap 配置哪些网段不做 SNAT。可参考 TKE 自动生成的 `ip-masq-agent-config` ConfigMap 中的 `NonMasqueradeCIDRs`（包含 VPC 网段及所有辅助网段）：

```bash
# 查看 TKE 自动生成的 NonMasqueradeCIDRs
kubectl -n kube-system get cm ip-masq-agent-config -o jsonpath='{.data.config}'
```

将其中的网段填入 cilium 的 `ip-masq-agent` ConfigMap：

```yaml title="ip-masq-agent.yaml"
apiVersion: v1
kind: ConfigMap
metadata:
  name: ip-masq-agent
  namespace: kube-system
data:
  config: |
    nonMasqueradeCIDRs:
    - <VPC CIDR>             # 如 10.0.0.0/16，Pod 访问 VPC 内地址保持源 IP
    - <VPC 辅助 CIDR (GR 网段)> # 如 172.16.0.0/16，Pod 间互访保持源 IP
    - 169.254.0.0/16         # TKE 元数据/apiserver VIP/COS/镜像仓库等保留段，必须保留源 IP
    masqLinkLocal: false     # masqLinkLocal=false 才允许 169.254.0.0/16 走 nonMasq 规则
```

:::tip[关于 169.254.0.0/16]

TKE 在该网段上承载了 apiserver VIP、元数据服务（如 csi-cbs 控制器要读 instance metadata）、COS、镜像仓库等关键能力，部分组件配置了 hostAlias 不经过 DNS 解析。Pod 访问这些地址若做了 SNAT 会丢失源 IP，可能导致部分服务（如有 IP 白名单的 COS bucket）异常。

:::

```bash
kubectl apply -f ip-masq-agent.yaml
```

:::tip[与 VPC-CNI chaining 的差异]

| 参数                                    | 说明                                                                             |
| --------------------------------------- | -------------------------------------------------------------------------------- |
| `cni.chainingTarget=tke-bridge`         | cilium 自动监视名为 `tke-bridge` 的 CNI 配置并追加自己，适配每节点不同的 PodCIDR |
| 无需 `cni.customConf` / `cni.configMap` | 不需要手动创建 CNI ConfigMap                                                     |
| `enableIPv4Masquerade=true`             | GR Pod IP 访问 CVM metadata 等公共服务需要 SNAT 为节点 IP                        |
| 不禁用 `tke-cni-agent`                  | 需要保留以拷贝 bridge 等 CNI 二进制到节点                                        |

:::

:::warning[GR 集群安装 cilium 后不支持动态启用 VPC-CNI]

GR 集群本身支持动态启用 VPC-CNI （GR 与 VPC-CNI 共存)，但**安装本文方案的 cilium 后此功能将不再可用**——cilium chaining 通过 multus 的 `defaultDelegates=tke-bridge` 接管所有 Pod 网络，即使创建带 `tke.cloud.tencent.com/networks: tke-route-eni` annotation 的 Pod，IP 也仍然来自 GR ClusterCIDR 而非 VPC-CNI 子网。如有 VPC-CNI 共存需求，请直接使用 VPC-CNI 集群。

:::

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
  <TabItem value="native-gr" label="Native (GR)">

Native Routing (GR) 模式专属参数：

```yaml showLineNumbers title="native-gr-values.yaml"
# 使用 native routing
routingMode: "native"
endpointRoutes:
  enabled: true
ipam:
  # Pod IP 分配由 tke-bridge-agent 负责
  mode: "delegated-plugin"
# GR Pod IP 访问 CVM metadata 等公共服务需要 SNAT 为节点 IP
enableIPv4Masquerade: true
bpf:
  masquerade: true
ipMasqAgent:
  enabled: true
# 所有 eth 开头的网卡挂载 cilium ebpf 程序
devices: eth+
cni:
  # 使用 generic-veth + chainingTarget 自动适配 tke-bridge 的 CNI 配置
  chainingMode: generic-veth
  chainingTarget: tke-bridge
  externalRouting: true
extraConfig:
  local-router-ipv4: 169.254.32.16
# 禁用 sysctlfix，详见 FAQ
sysctlfix:
  enabled: false
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

**实测覆盖的 OS 列表**详见本文末尾的 [已验证的节点操作系统](#已验证的节点操作系统)。

:::

:::warning[Native Routing (GR) 模式节点池必须配置 cilium taint]

使用 **Native Routing (GR)** 方案时，创建节点池**必须**给节点添加以下污点（控制台在**高级设置**中添加，terraform 参考下方代码片段）：

```
node.cilium.io/agent-not-ready=true:NoSchedule
```

原因详见 [为什么 Native Routing (GR) 节点池必须打 cilium agent-not-ready 污点？](./appendix/gr-agent-not-ready-taint.md)。

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
5. **操作系统** 选择 [已验证的节点操作系统](#已验证的节点操作系统) 中的任一镜像（推荐 **TencentOS 4** 或 **Ubuntu 24.04**），也可以使用其他满足最低内核要求（kernel >= 5.10）的 CVM 公共镜像或自定义镜像（建议先单节点验证）。
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

## 验证 Cilium 功能

安装完成并添加节点后，可通过以下方式验证 cilium 功能是否正常。

### 一键测试

使用脚本运行 cilium connectivity test（自动跳过公网测试，使用 TKE 可拉取的镜像）：

```bash
curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh -o cilium.sh
chmod +x cilium.sh
./cilium.sh e2e-test
```

如果网络环境无法连接 GitHub，可使用站点地址：

```bash
curl -sfL https://imroc.cc/tke/scripts/cilium.sh -o cilium.sh
chmod +x cilium.sh
./cilium.sh e2e-test
```

### 手动测试

需先安装 [cilium CLI](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli)，然后执行：

```bash
cilium connectivity test \
  --test '!/pod-to-world' \
  --test '!/pod-to-cidr' \
  --curl-image quay.tencentcloudcr.com/cilium/alpine-curl:v1.10.0 \
  --json-mock-image quay.tencentcloudcr.com/cilium/json-mock:v1.3.9 \
  --dns-test-server-image docker.io/k8smirror/coredns:v1.14.2 \
  --echo-image docker.io/k8smirror/echo-advanced:v20251204-v1.4.1
```

:::tip[说明]

- `--test '!/pod-to-world'` 和 `--test '!/pod-to-cidr'` 跳过公网连通性测试（节点可能没有公网带宽，且默认公网目标可能因 GFW 不通）。
- 镜像地址替换为 TKE 环境可内网拉取的地址（`quay.io` → `quay.tencentcloudcr.com`，`registry.k8s.io` / `gcr.io` → `docker.io/k8smirror`）。

:::

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
./cilium.sh e2e-test
```

:::warning[升级注意事项]

- **生产集群升级前先在测试集群验证**，确认业务无异常。
- **NetworkPolicy 行为可能在不同版本间有微调**，升级后回归核心策略效果。
- 跨大版本升级如涉及 ConfigMap / CRD 变更，按官方文档执行 `cilium upgrade --pre-flight` 检查或手动迁移。

:::

### 回滚到 TKE 内置 CNI

如需从 cilium 回退到 TKE 原生 CNI（VPC-CNI 或 GR），操作不可避免地会中断业务，建议在维护窗口执行：

1. **删除新的业务调度**：节点池打 cordon，避免回滚过程中有 Pod 新建。
2. **卸载 cilium**：
   ```bash
   helm uninstall cilium -n kube-system
   kubectl -n kube-system delete cm ip-masq-agent  # 如果用了 GR 模式
   ```
3. **清理节点残留**：每个节点上手动清理 cilium 的 BPF 程序、CNI 配置与 iptables 规则：
   ```bash
   # 在每个节点执行
   sudo rm -f /etc/cni/net.d/05-cilium.conf /etc/cni/net.d/05-cilium.conflist
   sudo rm -f /etc/cni/net.d/*.cilium_bak  # 恢复被 cilium 重命名的原 CNI 配置
   sudo iptables-save | grep -i cilium | wc -l  # 检查残留规则，必要时手动 -D
   ```
4. **重新启用 TKE 组件**：控制台勾选回 `tke-cni-agent`、`kube-proxy`、`ip-masq-agent` 等被卸载的组件。
5. **重启或重建节点**：最稳妥的方式是直接重建所有节点，确保 datapath 干净。

:::warning

回滚是高风险操作，**强烈建议直接重建节点**而不是手动清理。如必须保留节点（如有状态业务），务必在测试集群完整演练后再操作。

:::

## 已验证的节点操作系统

下表汇总本文 4 种安装模式（VPC-CNI/GR × Native/Overlay）均已实测通过的 OS 及内核。

**测试方法**：每种安装模式部署 cilium 1.19.4 + Egress Gateway + Nodelocal DNSCache，验证 `cilium-health status` 所有节点 reachable、`coredns` 与 `node-local-dns` 健康检查正常。

| OS                   | OsName                  | 内核版本 |
| -------------------- | ----------------------- | -------- |
| TencentOS Server 4   | `tlinux4_x86_64_public` | 6.6.117  |
| Ubuntu 24.04         | `ubuntu24.04x86_64`     | 6.8.0    |
| Ubuntu 22.04         | `ubuntu22.04x86_64`     | 5.15.0   |
| Debian 12 (bookworm) | `debian12.8x86_64`      | 6.1.0    |
| Debian 11 (bullseye) | `debian11.11x86_64`     | 5.10.0   |
| OpenCloudOS 9.4      | `opencloudos9.0x86_64`  | 6.6.119  |
| Rocky Linux 9.3      | `rockylinux9.3x86_64`   | 5.14.0   |
| RedHat 9.5           | `redhat9.5x86_64`       | 5.14.0   |

未在此列表的 OS 如需使用，建议自行验证。

## 延伸阅读

设计原理与常见问题已拆分到独立文章，归入 [Cilium 附录](./appendix) 目录：

- [常见问题](./appendix/faq.md)
- [为什么 Native Routing 模式要加 local-router-ipv4 配置？](./appendix/local-router-ipv4.md)
- [为什么 Native Routing 模式禁用 sysctlfix，Overlay 模式却启用？](./appendix/sysctlfix.md)
- [为什么 GR Native Routing 不支持 L7/DNS NetworkPolicy？](./appendix/gr-no-l7-dns.md)
- [为什么 Native Routing (GR) 节点池必须打 cilium agent-not-ready 污点？](./appendix/gr-agent-not-ready-taint.md)

## 参考资料

- [Installation using Helm](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)
- [Generic Veth Chaining](https://docs.cilium.io/en/stable/installation/cni-chaining-generic-veth/)
- [Kubernetes Without kube-proxy](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)

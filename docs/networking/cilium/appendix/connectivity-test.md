# Cilium 功能测试

本文介绍如何对在 TKE 集群上安装的 cilium 做连通性功能测试，并给出各推荐安装方案的实测结果。

cilium 官方提供了 [`cilium connectivity test`](https://docs.cilium.io/en/stable/contributing/testing/e2e/) 端到端测试套件，覆盖 Pod-to-Pod、Pod-to-Service、Pod-to-Host 同/跨节点连通性、ClusterIP/NodePort/HostPort 转发（kubeProxyReplacement）、L3/L4/L7 NetworkPolicy（含 deny/allow、ingress/egress、CIDR/Entity/ServiceAccount/L7 规则）、CiliumLocalRedirectPolicy 重定向、DNS 解析、`pod-to-world` / `pod-to-cidr` / `to-fqdns` 等公网用例。基于 cilium-cli v0.19.4 默认下发约 132 个测试用例 / ~600 个 action（数量随版本变化）。

## 测试方法

### 一键脚本

[一键安装脚本](../install.md#一键安装脚本) `cilium.sh` 提供了 `test` 子命令，会自动按节点地域选择外部目标、动态解析国内可用 IP，并使用 TKE 内网可拉取的 mirror 镜像。环境性失败的用例（如节点没公网）只打 WARN 提示用户，不自动跳过：

```bash
bash -c "$(curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh)" -- test
```

国内网络无法连接 GitHub 时改用站点镜像：

```bash
bash -c "$(curl -sfL https://imroc.cc/tke/scripts/cilium.sh)" -- test
```

脚本启动时会输出：

- 节点地域识别结果（国内/海外/混合/未知）
- 实际使用的外部目标（国内地域会动态解析 `npmmirror.com` 拿到当前公网 IP，并扫描其 `/16` 找到第二个可用 IP）
- 节点出公网探测结果（不通时打印警告，不强制跳过）
- `pod-to-cidr` 系列动态 IP 解析失败时的警告（不强制跳过）

### 手动测试

需先安装 [cilium CLI](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli)。命令分两种情况：

<Tabs>
<TabItem value="cn" label="国内地域（推荐）" default>

成都/北京/上海/深圳等国内地域，cilium 默认外部目标 `1.1.1.1` / `one.one.one.one.` / `k8s.io.` 受 GFW 限制不可达，需替换为国内可达地址。先动态解析 `npmmirror.com` 拿到当前公网 IP（IP 会随阿里云 ECS 后端变动），再传给 cilium：

```bash
# 1. 动态解析 npmmirror.com 当前的公网 IP
EXT_IP=$(kubectl run cn-resolve-tmp --image=quay.tencentcloudcr.com/cilium/alpine-curl:v1.10.0 \
  --restart=Never --attach --rm --quiet --command -- \
  /bin/sh -c 'dig +short npmmirror.com A | head -1')
EXT_OTHER_IP=$(echo "$EXT_IP" | awk -F. '{printf "%s.%s.%s.%d", $1, $2, $3, ($4 + 1)}')
EXT_CIDR=$(echo "$EXT_IP" | awk -F. '{printf "%s.%s.0.0/16", $1, $2}')
echo "EXT_IP=$EXT_IP, EXT_OTHER_IP=$EXT_OTHER_IP, EXT_CIDR=$EXT_CIDR"

# 2. 跑 connectivity test，注意 --curl-insecure 是必须的（CN 公网 HTTPS 无 IP 绑定证书）
cilium connectivity test \
  --external-ip "$EXT_IP" \
  --external-other-ip "$EXT_OTHER_IP" \
  --external-cidr "$EXT_CIDR" \
  --external-target npmmirror.com. \
  --external-other-target mirrors.aliyun.com. \
  --curl-insecure \
  --curl-image quay.tencentcloudcr.com/cilium/alpine-curl:v1.10.0 \
  --json-mock-image quay.tencentcloudcr.com/cilium/json-mock:v1.3.9 \
  --dns-test-server-image docker.io/k8smirror/coredns:v1.14.2 \
  --echo-image docker.io/k8smirror/echo-advanced:v20251204-v1.4.1
```

如果第二个 IP（`EXT_OTHER_IP`）实际不可达（443 不返回 2xx/3xx），`pod-to-cidr` 会失败。可加 `--test '!/pod-to-cidr' --test '!/to-cidr-external' --test '!/from-cidr'` 跳过 IP 类 CIDR 用例——更省心的做法是用一键脚本，它会自动扫 `/16` 范围找到能用的第二个 IP。

</TabItem>
<TabItem value="oversea" label="海外地域">

香港/新加坡/硅谷/东京等海外地域，可使用 cilium 默认的外部目标：

```bash
cilium connectivity test \
  --curl-image quay.tencentcloudcr.com/cilium/alpine-curl:v1.10.0 \
  --json-mock-image quay.tencentcloudcr.com/cilium/json-mock:v1.3.9 \
  --dns-test-server-image docker.io/k8smirror/coredns:v1.14.2 \
  --echo-image docker.io/k8smirror/echo-advanced:v20251204-v1.4.1
```

</TabItem>
</Tabs>

:::tip[补丁参数说明]

- **节点绑了 EIP？** pod-to-host 中的 `ping-ipv4-external-ip` 子动作会从 Pod ping 节点 EIP，若 EIP 安全组未放行公网 ICMP 入向（TKE 默认拒绝），该用例必失败；可放行 ICMP 或追加 `--test '!/pod-to-host$'` 跳过（`$` 用于精确匹配，避免误伤 `pod-to-hostport`）。
- **节点没有公网？** 追加 `--test '!/pod-to-world' --test '!/pod-to-cidr'` 跳过依赖公网的用例。
- 镜像地址替换为 TKE 环境可内网拉取的地址（`quay.io` → `quay.tencentcloudcr.com`，`registry.k8s.io` / `gcr.io` → `docker.io/k8smirror`）。

:::

## 运行环境前提

`cilium.sh test` **默认不禁用任何 cilium 测试用例**——脚本只在下列环境性场景下打 WARN，由用户根据自己的环境决定是否手动跳过：

| 警告场景                            | 触发条件            | 受影响 scenario                                                             | 说明                                                                                                                                                                                                                                                         |
| ----------------------------------- | ------------------- | --------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 国内地域 + 找不到可用 IP-only HTTPS | 动态解析 CN IP 失败 | `pod-to-cidr` / `to-cidr-external` / `from-cidr` / `client-egress-to-cidr*` | 国内公网无稳定的"纯 IP 直连 HTTPS"服务可用（无 SAN 含 IP 的证书）。可手动跳过：`--test '!/pod-to-cidr' --test '!/to-cidr-external' --test '!/from-cidr' --test '!/client-egress-to-cidr'`；CIDR 策略本身仍由 `to-entities-world`、`from-cidr` 等用例间接验证 |

另一种容易遇到的失败：节点绑了 EIP 时，cilium-cli 会在 `pod-to-host` scenario 里生成一个 `ping-ipv4-external-ip` 子动作（从 Pod ping 节点 EIP）。**在 TKE Native Routing 下这条 ping 恒定不通**，详见下一节《为什么 Native Routing 下 Pod ping 节点 EIP 永远不通》。要跳过该 scenario，可加 `--test '!/pod-to-host$'`（`$` 锚点避免误伤 `pod-to-hostport`）。

cilium-cli 的 `--test` 过滤器只支持 scenario 级别匹配（`/pod-to-host$` 用 `$` 锚点避免误伤 `pod-to-hostport`）；无法只禁用 scenario 内的单个 action。

### 为什么 Native Routing 下 Pod ping 节点 EIP 永远不通

实测因果链（在 cls-148r0kxp Native 集群、cls-qj0gbg3f Overlay 集群分别复现）：

A. **VPC-CNI Native 模式下 Pod IP 没有公网能力**。Pod IP 是从节点辅助 ENI 的 IP 池里分配的（如 `10.20.0.x`），但**辅助 ENI 上没有 EIP**——EIP 只绑在节点的主 ENI 上。VPC 路由表层面，辅助 ENI IP 段没有公网出口，**Pod 想访问任何公网目的都必须先 SNAT 成节点主 ENI IP**（再借节点主 ENI 的 EIP / NAT 网关 / Egress Gateway 出公网）。这是 TKE VPC-CNI Native 的固有约束，对 cilium / 任何 CNI 都成立。

B. **cilium-operator 把所有 Node 对象的 ExternalIP 登记成 `remote-node identity`**（数字 6）。`cilium-dbg bpf ipcache list` 可以看到节点 EIP `42.193.37.239 identity=6` —— cilium 在数据面里把节点 EIP 当成"集群成员节点的合法地址"。

C. **cilium 的 BPF masquerade 实现里有一道"目标 identity 是 cluster 内部就跳过 SNAT"的早退出**（保留 Pod identity 给 NetworkPolicy 用）。这道判断**先于 ipMasqAgent 的 `nonMasqueradeCIDRs` CIDR 匹配**，所以即使你把 ip-masq-agent 配上、节点 EIP 不在 `nonMasqueradeCIDRs` 列表里，也轮不到 CIDR 判断生效——目标 identity=remote-node 已经命中早退出，包不做 SNAT。

D. **包以 Pod IP 出节点，但 Pod IP 没有公网出口**——结合 A，这种从辅助 ENI IP 段出去的"目的为公网 IP"的包，要么被 VPC 路由表丢弃，要么进入网络后没有合法回程路径。所以 ping 不通。

> 抓包证据（源节点 10.10.21.26）：
>
> ```
> enie1f5...   In  ... 10.20.0.208 > 42.193.37.239: ICMP echo request
> eth1         Out ... 10.20.0.208 > 42.193.37.239: ICMP echo request   ← 源 IP 仍是 Pod IP，没 SNAT
> ```
>
> Pod IP `10.20.0.208` 来自辅助 ENI 的 IP 池，目的 `42.193.37.239` 是公网 IP——这条流量没有公网出口路径。

**为什么 ping 节点 VPC IP 通、ping 公网 EIP 不通？**

`Pod → 节点 VPC IP`（同 VPC 内私网通信）和 `Pod → 公网 EIP` 是两条性质不同的路径：

- 前者目的也是 VPC 内地址，无需 SNAT、无需公网出口，VPC 路由表直接转发，所以通；
- 后者目的是公网地址，必须先 SNAT 借主 ENI 的公网能力出去。Native 下 cilium 因 B/C 不做 SNAT，包带着 Pod IP 出去，没有公网出口路径。

**为什么 ping 真公网（如 223.5.5.5）反而通？**

实测 `Pod → 223.5.5.5` 通而 `Pod → 节点 EIP` 不通——区别就在 B/C：223.5.5.5 不是任何节点的 ExternalIP，identity 是 `world`，不命中 remote-node 早退出，cilium 正常按 ipMasqAgent CIDR 判断（目的不在 `nonMasqueradeCIDRs`）做 SNAT，于是包以节点主 ENI IP 出去走 EIP/NAT 网关，能通。**节点 EIP 唯一被 cilium 区别对待，就是因为它在 ipcache 里被打了 remote-node 标签**。

#### Overlay 模式为什么不受影响

| 维度                                | Native                                            | Overlay                                                                                                                |
| ----------------------------------- | ------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Pod IP 来源                         | 节点辅助 ENI 的 VPC IP 池（如 `10.20.0.x`）       | 独立 Overlay CIDR（如 `10.244.x.x`），**不在 VPC 网段**                                                                |
| Pod IP 是否有公网能力               | ❌ 无（辅助 ENI 不绑 EIP）                        | n/a（Pod IP 出节点前一定 SNAT，从不直接面对公网）                                                                      |
| `enableIPv4Masquerade`              | `false`（Pod IP 是 VPC 合法 IP，东西向无需 SNAT） | `true`                                                                                                                 |
| 节点 EIP identity                   | `remote-node`                                     | `remote-node`                                                                                                          |
| BPF masq 早退出（remote-node 跳过） | 命中——但 Native 整体没启用 masq，本来也不 SNAT    | 命中——cilium 把目标当集群内部，跳过 vxlan 解封后的 SNAT，**但内层 SNAT 已在 vxlan 封装前由 enableIPv4Masquerade 完成** |
| 出节点的源 IP                       | Pod IP（辅助 ENI IP，无公网能力）                 | **节点主 ENI VPC IP**（已 SNAT）                                                                                       |
| 能否到达公网 EIP                    | ❌ Pod IP 没有公网出口                            | ✅ 节点主 ENI IP 走主 ENI 的公网能力（EIP / NAT 网关）                                                                 |

简化一句话：**Native 的 Pod IP 来自不带 EIP 的辅助 ENI、本身没有公网能力，cilium 又因 remote-node identity 不肯 SNAT，于是访问公网 EIP 的路被堵死；Overlay 的 Pod IP 在 VPC 路由表里根本不存在，cilium 出节点前必 SNAT 成节点主 ENI IP，主 ENI 有公网能力，所以能到 EIP。**

#### 这是不是 cilium / TKE 的 bug？

都不是，是两个合理设计叠加：

- **TKE VPC-CNI Native 把 Pod IP 放在辅助 ENI、EIP 只绑主 ENI**，是为了让 Pod IP 与节点 IP 解耦、Pod 数量不受主 ENI 影响——成本是 Pod 出公网必须显式 SNAT。
- **cilium 把节点 EIP 当 remote-node 不 SNAT**，是为了保留 Pod identity 让 NetworkPolicy 在跨节点场景仍然按源 Pod label 生效。

两个设计单看都合理，叠在一起恰好让 cilium-cli 的 `pod-to-host:ping-ipv4-external-ip` 在 Native 下跑不通。生产业务里几乎不会出现"Pod 内主动 ping 集群另一节点的 EIP" 这种访问模式，所以没有实际影响——直接 `--test '!/pod-to-host$'` 跳过即可。

#### 为什么 ip-masq-agent 救不了

直觉上 "ip-masq-agent 不就是给 Native 做 SNAT 的吗，配上 EIP 段不就 SNAT 了？" —— 不行。cilium 的 ip-masq-agent 是 BPF 实现，与上面 C 点的 "目标 identity 是 remote-node 就早退出" 共用一套 BPF masq 判断。早退出在 ipMasqAgent CIDR 判断**之前**，节点 EIP 是 remote-node identity 直接被跳过，根本走不到 CIDR 那一步。用户层面**没有合法的 helm 配置开关**能把 remote-node identity 排除在早退出之外。

NAT 网关 / Egress Gateway 同理无效——它们只决定"已经决定 SNAT 后用什么源 IP"，决定不了"是否 SNAT"这一步。

此外，cilium-cli 自身会按以下条件**自动跳过**约 74 个用例（与 TKE 环境无关，是 cilium 测试套件设计如此）：

| 跳过原因                                              | 用例示例                                                                                                                  | 是否需要关注                                         |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| `unsafe test which can modify state of cluster nodes` | `no-policies-from-outside`、`all-ingress-deny-from-outside`、`echo-ingress-from-outside`、`from-cidr-host-netns` 等       | 否——这些会修改节点 iptables/路由，不适合在生产集群跑 |
| `skipped by condition`                                | `cluster-entity-multi-cluster`（依赖 cluster mesh）、依赖 ENI/IPv6/Multicast/`node-without-cilium` 等当前未启用特性的用例 | 否——按需启用对应特性后这些用例才会运行               |
| `skipped by user`                                     | 部分需要外部 host 配合的子用例                                                                                            | 否——这些用例需要预先准备外部资源，不适合默认跑       |

### 节点公网能力

测试涉及外部目标的用例（`pod-to-world` / `pod-to-cidr` / `to-fqdns` / `to-cidr-external` 等）需要 **Pod 能从节点出公网**。脚本启动时会做一次出公网探测，**不通时打印警告但不强制跳过**——是否跳过由用户决定。

如果节点没有公网，相关用例会失败，属于预期行为（与 cilium 无关），可手动追加 `--test '!/pod-to-world' --test '!/pod-to-cidr'` 等显式跳过。

## Native Routing (VPC-CNI) 测试结果

### 测试环境

| 项              | 值                                                                                                   |
| --------------- | ---------------------------------------------------------------------------------------------------- |
| Kubernetes 版本 | v1.34.1（containerd 1.7.28）                                                                         |
| Cilium 版本     | v1.19.4                                                                                              |
| Cilium CLI 版本 | v0.19.4                                                                                              |
| 节点 OS         | TencentOS Server 4 (kernel 6.6.117-45.7.3.tl4.x86_64)                                                |
| 节点机型        | S5.LARGE8（4C8G）                                                                                    |
| 节点数量        | 3 个节点                                                                                             |
| 节点公网        | 节点绑 EIP，VPC 配置了 NAT 网关（详见 [常见问题](#常见问题) 中的"为什么节点要配 NAT 网关"）          |
| 安装方式        | [一键安装脚本](../install.md#一键安装脚本) `cilium.sh install`，启用 Egress Gateway 与 ip-masq-agent |

> 启用 Egress Gateway 或 ip-masq-agent 都会让 cilium 开启 BPF masquerade，脚本会自动设置 `ipMasqAgent.config.nonMasqueradeCIDRs` 覆盖 RFC 1918 三段，避免跨节点 Pod-to-Pod 被 SNAT 破坏 NetworkPolicy；详见 [Native + ip-masq-agent / Egress Gateway 兼容性说明](#native--ip-masq-agent--egress-gateway-兼容性说明)。

### 测试结果

```text
❌ 1/77 tests failed (1/788 actions), 55 tests skipped, 0 scenarios skipped:
Test [local-redirect-policy]:
  🟥 local-redirect-policy/lrp-skip-redirect-from-backend:curl-0-ipv4:
     cilium-test-1/lrp-backend → 169.254.169.248:80/TCP succeeded while it should have failed
```

**1 个用例失败，不影响生产可用性**：唯一失败用例 `local-redirect-policy/lrp-skip-redirect-from-backend` 是 LRP 边缘场景，VPC-CNI Native 下固定失败，详细原因见 [常见问题 → 为什么 lrp-skip-redirect-from-backend 用例固定失败](#为什么-lrp-skip-redirect-from-backend-用例固定失败)。常规 LRP 使用（如 [Cilium 与 NodeLocal DNSCache 共存](../with-node-local-dns.md)）完全正常。

**实际可视为通过：76/77**，生产可放心使用。耗时约 35 分 37 秒。

#### 全量用例明细

cilium connectivity test 共下发 132 个用例，按功能分组列出每个用例的测试目标和本次运行状态：

##### 1. 无策略基线（Baseline，验证 cilium datapath 在无 NetworkPolicy 干扰下的连通性）

| #   | 用例                           | 状态    | 说明                                                                                                                     |
| --- | ------------------------------ | ------- | ------------------------------------------------------------------------------------------------------------------------ |
| 1   | `no-policies`                  | ✅ 通过 | 无策略下覆盖 `pod-to-pod` / `pod-to-service` / `pod-to-host` / `pod-to-cidr` / `pod-to-world` / `host-to-pod` 等基础场景 |
| 2   | `no-policies-from-outside`     | ⏭️ 跳过 | 需要外部主机（`node-without-cilium`），TKE 环境无此节点                                                                  |
| 3   | `no-policies-extra`            | ✅ 通过 | 额外的无策略场景（含 `pod-to-controlplane-host` 等）                                                                     |
| 4   | `allow-all-except-world`       | ✅ 通过 | 允许所有非 world 流量，验证 `entity: world` 选择器                                                                       |
| 7   | `allow-all-with-metrics-check` | ✅ 通过 | allow-all 策略 + 验证 cilium metrics 指标采集                                                                            |

##### 2. Ingress 策略（验证 ingress 方向的 allow / deny）

| #   | 用例                                         | 状态    | 说明                                                   |
| --- | -------------------------------------------- | ------- | ------------------------------------------------------ |
| 5   | `client-ingress`                             | ✅ 通过 | CiliumNetworkPolicy 仅允许特定 source label 的 ingress |
| 6   | `client-ingress-knp`                         | ✅ 通过 | 同 5，但用 K8s 原生 NetworkPolicy（KNP）               |
| 8   | `all-ingress-deny`                           | ✅ 通过 | 默认拒绝所有 ingress                                   |
| 9   | `all-ingress-deny-from-outside`              | ⏭️ 跳过 | unsafe 用例（修改节点状态）                            |
| 10  | `all-ingress-deny-knp`                       | ✅ 通过 | KNP 版本的 default-deny ingress                        |
| 17  | `host-entity-ingress`                        | ✅ 通过 | 允许 `entity: host` 的 ingress                         |
| 18  | `echo-ingress`                               | ✅ 通过 | 仅允许指定 source 的 echo ingress                      |
| 19  | `echo-ingress-from-outside`                  | ⏭️ 跳过 | unsafe 用例                                            |
| 20  | `echo-ingress-knp`                           | ✅ 通过 | KNP 版本                                               |
| 21  | `client-ingress-icmp`                        | ✅ 通过 | ICMP 协议匹配（`ICMPs:` 字段）                         |
| 37  | `echo-ingress-from-other-client-deny`        | ✅ 通过 | 拒绝来自特定 client 的 echo ingress                    |
| 38  | `client-ingress-from-other-client-icmp-deny` | ✅ 通过 | 拒绝来自特定 client 的 ICMP                            |

##### 3. Egress 策略（验证 egress 方向的 allow / deny）

| #   | 用例                                               | 状态    | 说明                                     |
| --- | -------------------------------------------------- | ------- | ---------------------------------------- |
| 11  | `all-egress-deny`                                  | ✅ 通过 | 默认拒绝所有 egress                      |
| 12  | `all-egress-deny-knp`                              | ✅ 通过 | KNP 版本                                 |
| 22  | `client-egress`                                    | ✅ 通过 | 仅允许特定 dst 的 egress                 |
| 23  | `client-egress-knp`                                | ✅ 通过 | KNP 版本                                 |
| 24  | `client-egress-expression`                         | ✅ 通过 | 用 `matchExpressions` 替代 `matchLabels` |
| 25  | `client-egress-expression-port-range`              | ✅ 通过 | 加端口范围匹配                           |
| 26  | `client-egress-expression-knp`                     | ✅ 通过 | KNP + matchExpressions                   |
| 27  | `client-egress-expression-knp-port-range`          | ✅ 通过 | KNP + matchExpressions + port range      |
| 39  | `client-egress-to-echo-deny`                       | ✅ 通过 | 拒绝到 echo 的 egress                    |
| 40  | `client-egress-to-echo-deny-port-range`            | ✅ 通过 | 端口范围拒绝                             |
| 41  | `client-ingress-to-echo-named-port-deny`           | ✅ 通过 | 命名端口的 deny                          |
| 42  | `client-egress-to-echo-expression-deny`            | ✅ 通过 | matchExpressions 拒绝                    |
| 43  | `client-egress-to-echo-expression-deny-port-range` | ✅ 通过 | matchExpressions + 端口范围              |

##### 4. ServiceAccount 策略（基于 Pod 的 ServiceAccount 标签做匹配）

| #   | 用例                                                         | 状态    | 说明                     |
| --- | ------------------------------------------------------------ | ------- | ------------------------ |
| 28  | `client-with-service-account-egress-to-echo`                 | ✅ 通过 | source 用 SA 选择，allow |
| 29  | `client-with-service-account-egress-to-echo-port-range`      | ✅ 通过 | + 端口范围               |
| 30  | `client-egress-to-echo-service-account`                      | ✅ 通过 | dst 用 SA 选择，allow    |
| 31  | `client-egress-to-echo-service-account-port-range`           | ✅ 通过 | + 端口范围               |
| 44  | `client-with-service-account-egress-to-echo-deny`            | ✅ 通过 | source SA 拒绝           |
| 45  | `client-with-service-account-egress-to-echo-deny-port-range` | ✅ 通过 | + 端口范围               |
| 46  | `client-egress-to-echo-service-account-deny`                 | ✅ 通过 | dst SA 拒绝              |
| 47  | `client-egress-to-echo-service-account-deny-port-range`      | ✅ 通过 | + 端口范围               |

##### 5. CIDR / Entity 策略

| #   | 用例                                       | 状态    | 说明                                                    |
| --- | ------------------------------------------ | ------- | ------------------------------------------------------- |
| 13  | `all-entities-deny`                        | ✅ 通过 | 拒绝所有 entity                                         |
| 14  | `cluster-entity`                           | ✅ 通过 | `entity: cluster` 匹配集群内流量                        |
| 15  | `cluster-entity-multi-cluster`             | ⏭️ 跳过 | 依赖 cluster mesh                                       |
| 16  | `host-entity-egress`                       | ✅ 通过 | 允许 egress 到 `entity: host`                           |
| 32  | `to-entities-world`                        | ✅ 通过 | 允许 egress 到 `entity: world`                          |
| 33  | `to-entities-world-port-range`             | ✅ 通过 | + 端口范围                                              |
| 34  | `to-cidr-external`                         | ✅ 通过 | 允许 egress 到 external CIDR（动态注入的 47.96.0.0/16） |
| 35  | `to-cidr-external-knp`                     | ✅ 通过 | KNP 版本                                                |
| 36  | `from-cidr-host-netns`                     | ⏭️ 跳过 | unsafe 用例                                             |
| 48  | `client-egress-to-cidr-deny`               | ✅ 通过 | 拒绝到 external CIDR                                    |
| 49  | `client-egress-to-cidrgroup-deny`          | ✅ 通过 | CiliumCIDRGroup 拒绝                                    |
| 50  | `client-egress-to-cidrgroup-deny-by-label` | ✅ 通过 | 通过 label 引用 CiliumCIDRGroup                         |
| 51  | `client-egress-to-cidr-deny-default`       | ✅ 通过 | 默认 deny CIDR                                          |

##### 6. 加密 / 节点间加密

| #   | 用例                                      | 状态    | 说明                                         |
| --- | ----------------------------------------- | ------- | -------------------------------------------- |
| 55  | `pod-to-pod-encryption`                   | ⏭️ 跳过 | 需要 cilium < 1.18，本测试用 1.19.4          |
| 56  | `pod-to-pod-with-l7-policy-encryption`    | ⏭️ 跳过 | 同上                                         |
| 57  | `pod-to-pod-encryption-v2`                | ✅ 通过 | 验证 v2 加密路径（未启用加密时只验证空抓包） |
| 58  | `pod-to-pod-with-l7-policy-encryption-v2` | ⏭️ 跳过 | Feature `encryption-pod` 未启用              |
| 59  | `node-to-node-encryption`                 | ✅ 通过 | 节点间加密路径（未启用时验证空抓包）         |
| 119 | `strict-mode-encryption`                  | ⏭️ 跳过 | unsafe 用例                                  |
| 120 | `strict-mode-encryption-v2`               | ⏭️ 跳过 | unsafe 用例                                  |
| 121 | `ipsec-key-derivation-validation`         | ⏭️ 跳过 | unsafe 用例                                  |
| 122 | `ztunnel-pod-to-pod-encryption`           | ⏭️ 跳过 | Feature `enable-ztunnel` 未启用              |

##### 7. Egress Gateway

| #   | 用例                            | 状态    | 说明                              |
| --- | ------------------------------- | ------- | --------------------------------- |
| 60  | `egress-gateway`                | ⏭️ 跳过 | unsafe 用例（修改节点状态）       |
| 61  | `egress-gateway-multigateway`   | ⏭️ 跳过 | unsafe 用例                       |
| 62  | `egress-gateway-excluded-cidrs` | ⏭️ 跳过 | 需要 `node-without-cilium`        |
| 63  | `egress-gateway-with-l7-policy` | ⏭️ 跳过 | unsafe 用例                       |
| 64  | `pod-to-node-cidrpolicy`        | ⏭️ 跳过 | Feature `cidr-match-nodes` 未启用 |

##### 8. LoadBalancer / Ingress（依赖 node-without-cilium 或 ingress-controller）

| #   | 用例                                                   | 状态    | 说明                                 |
| --- | ------------------------------------------------------ | ------- | ------------------------------------ |
| 53  | `health`                                               | ⏭️ 跳过 | Feature `health-checking` 未启用     |
| 54  | `north-south-loadbalancing`                            | ⏭️ 跳过 | 需要 `node-without-cilium`           |
| 65  | `north-south-loadbalancing-with-l7-policy`             | ⏭️ 跳过 | 同上                                 |
| 66  | `north-south-loadbalancing-with-l7-policy-port-range`  | ⏭️ 跳过 | 同上                                 |
| 92  | `pod-to-ingress-service`                               | ⏭️ 跳过 | Feature `ingress-controller` 未启用  |
| 93  | `pod-to-ingress-service-allow-ingress-identity`        | ⏭️ 跳过 | 同上                                 |
| 94  | `pod-to-ingress-service-deny-all`                      | ⏭️ 跳过 | 同上                                 |
| 95  | `pod-to-ingress-service-deny-backend-service`          | ⏭️ 跳过 | 同上                                 |
| 96  | `pod-to-ingress-service-deny-ingress-identity`         | ⏭️ 跳过 | 同上                                 |
| 97  | `pod-to-ingress-service-deny-source-egress-other-node` | ⏭️ 跳过 | 同上                                 |
| 98  | `outside-to-ingress-service`                           | ⏭️ 跳过 | 同上                                 |
| 99  | `outside-to-ingress-service-deny-all-ingress`          | ⏭️ 跳过 | 同上                                 |
| 100 | `outside-to-ingress-service-deny-cidr`                 | ⏭️ 跳过 | 同上                                 |
| 101 | `outside-to-ingress-service-deny-world-identity`       | ⏭️ 跳过 | 同上                                 |
| 102 | `pod-to-itself-via-service`                            | ✅ 通过 | Pod 通过 Service 访问自己（hairpin） |
| 103 | `l7-lb`                                                | ⏭️ 跳过 | Feature `loadbalancer-l7` 未启用     |

##### 9. L7 / HTTP NetworkPolicy

| #   | 用例                                               | 状态    | 说明                                |
| --- | -------------------------------------------------- | ------- | ----------------------------------- |
| 67  | `echo-ingress-l7`                                  | ✅ 通过 | L7 HTTP rules（path / method 匹配） |
| 68  | `echo-ingress-l7-via-hostport`                     | ✅ 通过 | L7 经 HostPort                      |
| 69  | `echo-ingress-from-client-tiered-wildcard-pass-l7` | ⏭️ 跳过 | 需要 cilium >= 1.20，本测试 1.19.4  |
| 70  | `echo-ingress-l7-named-port`                       | ✅ 通过 | L7 + 命名端口                       |
| 71  | `client-egress-l7-method`                          | ✅ 通过 | L7 method 限制                      |
| 72  | `client-egress-l7-method-port-range`               | ✅ 通过 | + 端口范围                          |
| 73  | `client-egress-l7`                                 | ✅ 通过 | L7 path 限制                        |
| 74  | `client-egress-l7-port-range`                      | ✅ 通过 | + 端口范围                          |
| 75  | `client-egress-l7-named-port`                      | ✅ 通过 | + 命名端口                          |
| 86  | `client-egress-l7-set-header`                      | ✅ 通过 | L7 header 注入                      |
| 87  | `client-egress-l7-set-header-port-range`           | ✅ 通过 | + 端口范围                          |

##### 10. TLS SNI / TLS Header（需要 client cert / external host）

| #   | 用例                                           | 状态    | 说明                                    |
| --- | ---------------------------------------------- | ------- | --------------------------------------- |
| 76  | `client-egress-tls-sni`                        | ✅ 通过 | TLS SNI 匹配（外部目标 npmmirror.com）  |
| 77  | `client-egress-tls-sni-denied`                 | ✅ 通过 | SNI 拒绝（外部目标 mirrors.aliyun.com） |
| 78  | `client-egress-tls-sni-wildcard`               | ⏭️ 跳过 | skipped by condition                    |
| 79  | `client-egress-tls-sni-wildcard-denied`        | ⏭️ 跳过 | 同上                                    |
| 80  | `client-egress-tls-sni-random-wildcard`        | ⏭️ 跳过 | 同上                                    |
| 81  | `client-egress-tls-sni-random-wildcard-denied` | ⏭️ 跳过 | 同上                                    |
| 82  | `client-egress-tls-sni-double-wildcard`        | ⏭️ 跳过 | 同上                                    |
| 83  | `client-egress-tls-sni-double-wildcard-denied` | ⏭️ 跳过 | 同上                                    |
| 84  | `client-egress-l7-tls-headers-sni`             | ✅ 通过 | L7 TLS + SNI + header                   |
| 85  | `client-egress-l7-tls-headers-other-sni`       | ✅ 通过 | 不同 SNI                                |
| 125 | `client-egress-l7-tls-deny-without-headers`    | ✅ 通过 | 缺 header 时拒绝                        |
| 126 | `client-egress-l7-tls-headers`                 | ✅ 通过 | L7 TLS + header                         |
| 127 | `client-egress-l7-extra-tls-headers`           | ✅ 通过 | 多 header                               |
| 128 | `client-egress-l7-tls-headers-port-range`      | ✅ 通过 | + 端口范围                              |

##### 11. 双向认证（Mutual Auth / SPIFFE）

| #   | 用例                                         | 状态    | 说明                                |
| --- | -------------------------------------------- | ------- | ----------------------------------- |
| 88  | `echo-ingress-auth-always-fail`              | ⏭️ 跳过 | Feature `mutual-auth-spiffe` 未启用 |
| 89  | `echo-ingress-auth-always-fail-port-range`   | ⏭️ 跳过 | 同上                                |
| 90  | `echo-ingress-mutual-auth-spiffe`            | ⏭️ 跳过 | 同上                                |
| 91  | `echo-ingress-mutual-auth-spiffe-port-range` | ⏭️ 跳过 | 同上                                |

##### 12. DNS / FQDN

| #   | 用例                          | 状态    | 说明                                |
| --- | ----------------------------- | ------- | ----------------------------------- |
| 104 | `dns-only`                    | ✅ 通过 | 仅 DNS L7 解析路径                  |
| 105 | `to-fqdns`                    | ✅ 通过 | toFQDN 策略（域名为 npmmirror.com） |
| 106 | `to-fqdns-with-proxy`         | ✅ 通过 | toFQDN + DNS proxy                  |
| 107 | `to-fqdns-with-ccec-listener` | ⏭️ 跳过 | 需要 cilium >= 1.20                 |

##### 13. ControlPlane / k8s API

| #   | 用例                              | 状态    | 说明                         |
| --- | --------------------------------- | ------- | ---------------------------- |
| 108 | `pod-to-controlplane-host`        | ⏭️ 跳过 | k8s localhost tests excluded |
| 109 | `pod-to-k8s-on-controlplane`      | ⏭️ 跳过 | 同上                         |
| 110 | `pod-to-controlplane-host-cidr`   | ⏭️ 跳过 | 同上                         |
| 111 | `pod-to-k8s-on-controlplane-cidr` | ⏭️ 跳过 | 同上                         |
| 112 | `policy-local-cluster-egress`     | ✅ 通过 | 限制 egress 仅本集群         |

##### 14. CiliumLocalRedirectPolicy（LRP）

| #   | 用例                                  | 状态        | 说明                                                                                                                                                 |
| --- | ------------------------------------- | ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| 113 | `local-redirect-policy`               | ❌ **失败** | LRP 主测试，唯一失败的子动作 `lrp-skip-redirect-from-backend` 是 LRP 边缘 case，详见 [常见问题](#为什么-lrp-skip-redirect-from-backend-用例固定失败) |
| 114 | `local-redirect-policy-with-node-dns` | ⏭️ 跳过     | unsafe 用例                                                                                                                                          |

##### 15. 路径相关（Pod-to-Pod 边界条件 / 集群网络）

| #   | 用例                         | 状态    | 说明                                   |
| --- | ---------------------------- | ------- | -------------------------------------- |
| 115 | `pod-to-pod-no-frag`         | ✅ 通过 | 不分片场景的 Pod-to-Pod                |
| 131 | `no-unexpected-packet-drops` | ✅ 通过 | 跑测期间没有未预期的丢包               |
| 132 | `check-log-errors`           | ✅ 通过 | cilium-agent 日志中没有 error 级别日志 |

##### 16. BGP / Multicast / Host Firewall（unsafe 类）

| #   | 用例                    | 状态    | 说明                                  |
| --- | ----------------------- | ------- | ------------------------------------- |
| 116 | `bgp-control-plane-v1`  | ⏭️ 跳过 | unsafe 用例（修改节点 BGP 配置）      |
| 117 | `bgp-control-plane-v2`  | ⏭️ 跳过 | unsafe 用例                           |
| 118 | `multicast`             | ⏭️ 跳过 | unsafe 用例（依赖 multicast feature） |
| 123 | `host-firewall-ingress` | ⏭️ 跳过 | unsafe 用例                           |
| 124 | `host-firewall-egress`  | ⏭️ 跳过 | unsafe 用例                           |

##### 17. ClusterMesh / CCNP / 其它

| #   | 用例                                   | 状态    | 说明                                      |
| --- | -------------------------------------- | ------- | ----------------------------------------- |
| 52  | `clustermesh-endpointslice-sync`       | ⏭️ 跳过 | skipped by condition（依赖 cluster mesh） |
| 129 | `egress-to-specific-namespace-ccnp`    | ✅ 通过 | CiliumClusterwideNetworkPolicy egress     |
| 130 | `ingress-from-specific-namespace-ccnp` | ✅ 通过 | CCNP ingress                              |

#### 跳过用例分类汇总

本次 55 个 skipped 用例可归为 4 类，均与 cilium 自身能力无关：

| 跳过原因                                                | 用例数 | 是否需要关注                                                                                             |
| ------------------------------------------------------- | ------ | -------------------------------------------------------------------------------------------------------- |
| `unsafe test which can modify state of cluster nodes`   | 14     | 否——会修改节点 BGP/iptables/路由配置，不适合在生产集群跑                                                 |
| `Feature ... is disabled`                               | 22     | 否——按需启用对应特性后这些用例才会运行（ingress-controller、mutual-auth-spiffe、node-without-cilium 等） |
| `requires Cilium version`                               | 4      | 否——不同 cilium 版本独有的用例                                                                           |
| `skipped by condition` / `k8s localhost tests excluded` | 15     | 否——条件性用例，需要预先准备外部资源或特定网络拓扑                                                       |

## Overlay (VPC-CNI) 测试结果

### 测试环境

| 项              | 值                                                             |
| --------------- | -------------------------------------------------------------- |
| Kubernetes 版本 | v1.34.1（containerd 1.7.28）                                   |
| Cilium 版本     | v1.19.4                                                        |
| Cilium CLI 版本 | v0.19.4                                                        |
| 节点 OS         | TencentOS Server 4 (kernel 6.6.117-45.7.3.tl4.x86_64)          |
| 节点机型        | S5.LARGE8（4C8G）                                              |
| 节点数量        | 3 个节点                                                       |
| 节点公网        | 节点绑 EIP，VPC 配置了 NAT 网关                                |
| 安装方式        | [一键安装脚本](../install.md#一键安装脚本) `cilium.sh install` |

### 测试结果

```text
✅ All 77 tests (791 actions) successful, 55 tests skipped, 0 scenarios skipped.
```

**全部用例通过，零失败**——Overlay (VPC-CNI) 是 cilium 在 TKE 上跑测最干净的方案。耗时约 36 分 15 秒。

#### 与 Native (VPC-CNI) 的差异

相比 Native 模式，Overlay 多了 BPF host routing、cilium 完全接管 Pod 网络（不依赖 chained CNI），所以：

- **`local-redirect-policy/lrp-skip-redirect-from-backend` 通过**：不再像 Native 那样卡在 chained CNI 模式下识别 backend 来源失败的边缘 case（详见 [常见问题 → 为什么 lrp-skip-redirect-from-backend 用例固定失败](#为什么-lrp-skip-redirect-from-backend-用例固定失败)）
- **`echo-ingress-l7-via-hostport` 跳过**（`skipped by condition`）：Overlay 默认未启用 HostPort feature；Native 默认启用了，所以 Native 下该用例通过
- **`health` 通过**：Overlay 启用了 cilium `health-checking`；Native 下 skipped（feature disabled）
- **`host-entity-egress` 与 `host-entity-ingress` 通过**：与 Native 一致

总用例数（77）和跳过数（55）与 Native 一致，主要差别在于"哪些用例落在 ✅ 通过 / ⏭️ 跳过 / ❌ 失败"上：

| 维度                             | Native (VPC-CNI)          | Overlay (VPC-CNI)         |
| -------------------------------- | ------------------------- | ------------------------- |
| 通过 test 数                     | 76 / 77                   | **77 / 77** ✅            |
| 失败 test 数                     | 1                         | **0**                     |
| 跳过 test 数                     | 55                        | 55                        |
| 总 actions                       | 788                       | 791                       |
| `lrp-skip-redirect-from-backend` | ❌ 失败                   | ✅ 通过                   |
| `echo-ingress-l7-via-hostport`   | ✅ 通过                   | ⏭️ 跳过（feature 未启用） |
| `health`                         | ⏭️ 跳过（feature 未启用） | ✅ 通过                   |

> 简单说：Overlay 模式下装出来 cilium 功能是"满血"的，Native 模式因为 chained CNI 必然受限于一些边缘 case，但生产业务能用的核心能力（NetworkPolicy / Hubble / KPR / Egress Gateway）两边完全一致。

## 常见问题

### 为什么 lrp-skip-redirect-from-backend 用例固定失败？

VPC-CNI Native（cilium chained CNI 模式）下这条用例**固定失败**，与具体集群、配置、cilium 版本无关。

**用例语义**：

`local-redirect-policy/lrp-skip-redirect-from-backend` 验证 cilium LRP 的 `skipRedirectFromBackend` 特性——backend Pod **自己**访问被重定向的 frontend 时，应该**绕过** LRP（不被重定向回自己），表现为 connection refused。

**实际行为**：

```text
[.] Action [local-redirect-policy/lrp-skip-redirect-from-backend:curl-0-ipv4:
    cilium-test-1/lrp-backend-... (10.20.0.17) -> 169.254.169.248:80/TCP]
❌ command "curl ... http://169.254.169.248:80" succeeded while it should have failed:
   10.20.0.17:39326 -> 169.254.169.248:80 = 200
```

backend Pod 访问 `169.254.169.248:80`（一个本不应有真实服务的地址）时**返回了 200**，意味着请求**仍然被 LRP 重定向回了 backend 自己**——`skipRedirectFromBackend` 没生效。

**根因**：

cilium 在 chained CNI 模式（VPC-CNI Native 必须用）下，LRP 的"识别请求来自 backend Pod"这步实现存在差异——chained 模式下 lxc 设备上的 BPF 程序拿不到完整的源 endpoint 信息，导致 backend 发出的请求**没有被识别为 backend 来源**，于是按普通流量走 LRP 重定向。

**影响范围（不影响生产）**：

- ✅ LRP 主能力 `local-redirect-policy/lrp` 完全正常——前向流量重定向工作正常
- ✅ [Cilium 与 NodeLocal DNSCache 共存](../with-node-local-dns.md) 这种典型 LRP 用法**完全不受影响**，因为 node-local-dns Pod 不会主动访问 kube-dns ClusterIP（它本来就是被重定向的目标）
- ❌ 仅影响"LRP backend Pod 主动访问被它自己提供服务的 frontend"这种特殊场景——生产业务里几乎不存在

如果不需要 `skipRedirectFromBackend` 这个边缘特性，可忽略此用例失败。要在测试报告里跳过，可以加 `--test '!/local-redirect-policy/lrp-skip-redirect-from-backend'`。

### 为什么节点要配 NAT 网关？

测试时节点除了绑 EIP，还在 VPC 路由表配置了公网 NAT 网关——这是为了让 `pod-to-host` scenario 中的 `ping-ipv4-external-ip` 子动作（从 Pod ping 节点 EIP）通过。

**没配 NAT 网关时的因果链**（详见上文 [为什么 Native Routing 下 Pod ping 节点 EIP 永远不通](#为什么-native-routing-下-pod-ping-节点-eip-永远不通)）：Pod IP 来自辅助 ENI、没有公网能力 → cilium 把节点 EIP 视为 remote-node 不 SNAT → 包以 Pod IP 出节点找不到公网路径 → ping 不通。

**配了 NAT 网关后**多了一段路径让流量绕回：

```
A. cilium 仍然不 SNAT（节点 EIP 是 remote-node identity）
B. 包以 Pod IP（10.20.0.x）出节点，目的为节点 EIP（公网地址）
C. VPC 路由表把"目的=公网"的流量送到 NAT 网关
D. NAT 网关把源 Pod IP SNAT 成 NAT 网关的公网 IP，包从 NAT 网关出公网
E. 经公网绕回到节点 EIP
F. 云网络层 DNAT 把目的 EIP 改写成节点 VPC IP，包到达节点主 ENI
```

功能上通了，但要走公网绕一圈，延迟比 `Pod → 节点 VPC IP` 直连高，会占 NAT 网关 / 节点 EIP 入向带宽。

如果不配 NAT 网关、节点也没其它公网出口，运行 `cilium.sh test` 时这条用例必失败，可加 `--test '!/pod-to-host$'` 跳过。

## Native + ip-masq-agent / Egress Gateway 兼容性说明

VPC-CNI Native 默认 `enableIPv4Masquerade=false`（Pod IP 即 VPC IP，东西向无需 SNAT），cilium 此时不开启任何 masquerade 路径，跨节点 Pod-to-Pod 始终保留原始 Pod IP，NetworkPolicy 的源 endpoint label 匹配正常工作。

但启用下面任一能力时，cilium 都会**强制开启 BPF masquerade**：

- **Egress Gateway**：cilium 源码强制要求 `enableIPv4Masquerade=true` + `bpf.masquerade=true`（[`pkg/egressgateway/manager.go`](https://github.com/cilium/cilium/blob/main/pkg/egressgateway/manager.go)）
- **ip-masq-agent**（让 Native Pod 借节点主 ENI EIP 出公网，参考 [配置 IP 伪装](../masquerading.md)）：脚本同样会同时设置 `enableIPv4Masquerade=true` + `bpf.masquerade=true` + `ipMasqAgent.enabled=true`

masquerade 一旦开启，**默认行为是把所有出 cluster CIDR 的流量做 SNAT**——在 Native 模式下，这意味着跨节点 Pod-to-Pod 也会被 SNAT（源 Pod IP 被替换成 link-local `169.254.x.x` 或节点 IP），接收端 cilium-agent 无法解析为正确的 endpoint identity，导致**所有"基于源 endpoint label 的 NetworkPolicy"在跨节点场景下失效**。

解决办法是配置 `ipMasqAgent.config.nonMasqueradeCIDRs` 把 VPC 网段加进白名单，让 Pod-to-Pod / Pod-to-VPC 流量保留原始 Pod IP，只对真正"出 VPC"（如公网）的流量做 SNAT。

`cilium.sh install` 在检测到 Native + 启用了 ip-masq-agent 或 Egress Gateway 时，会按以下优先级解析 `nonMasqueradeCIDRs` 并自动注入 helm 安装：

1. 环境变量 `NON_MASQ_CIDRS`（空格分隔的 CIDR 列表）
2. 集群中已存在的 TKE `ip-masq-agent-config` ConfigMap（TKE 自带 ip-masq-agent 组件会写入 VPC 主网段 + 辅助网段）
3. 交互式询问，默认 `10.0.0.0/8 172.16.0.0/12 192.168.0.0/16`（RFC 1918 三段全集，覆盖任意合法腾讯云 VPC 配置）

Overlay 模式不受此问题影响——vxlan 隧道封装时内层源 IP 始终是 Pod IP，cilium 在解封装后直接看到真实源 IP。

## 相关链接

- [安装 Cilium](../install.md)
- [Cilium 性能测试](./performance-test.md)
- [Cilium E2E Connectivity Testing](https://docs.cilium.io/en/stable/contributing/testing/e2e/)

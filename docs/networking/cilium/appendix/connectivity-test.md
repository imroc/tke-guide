# Cilium 功能测试

本文介绍如何对在 TKE 集群上安装的 cilium 做连通性功能测试，并给出各推荐安装方案的实测结果。

cilium 官方提供了 [`cilium connectivity test`](https://docs.cilium.io/en/stable/contributing/testing/e2e/) 端到端测试套件，覆盖 Pod-to-Pod、Pod-to-Service、Pod-to-Host 同/跨节点连通性、ClusterIP/NodePort/HostPort 转发（kubeProxyReplacement）、L3/L4/L7 NetworkPolicy（含 deny/allow、ingress/egress、CIDR/Entity/ServiceAccount/L7 规则）、CiliumLocalRedirectPolicy 重定向、DNS 解析、`pod-to-world` / `pod-to-cidr` / `to-fqdns` 等公网用例。基于 cilium-cli v0.19.4 默认下发约 132 个测试用例 / ~600 个 action（数量随版本变化）。

## 测试方法

### 一键脚本

[一键安装脚本](../install.md#一键安装脚本) `cilium.sh` 提供了 `test` 子命令，会自动按节点地域选择外部目标、动态解析国内可用 IP、跳过环境固有失败的用例，并使用 TKE 内网可拉取的 mirror 镜像：

```bash
curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh -o cilium.sh
chmod +x cilium.sh
./cilium.sh test
```

国内网络无法连接 GitHub 时改用站点镜像：

```bash
curl -sfL https://imroc.cc/tke/scripts/cilium.sh -o cilium.sh
chmod +x cilium.sh
./cilium.sh test
```

脚本启动时会输出：

- 节点地域识别结果（国内/海外/混合/未知）
- 实际使用的外部目标（国内地域会动态解析 `npmmirror.com` 拿到当前公网 IP，并扫描其 `/16` 找到第二个可用 IP）
- 节点出公网探测结果（不通时打印警告，不强制跳过）
- 是否自动跳过 `pod-to-host`（节点绑 EIP 时跳过，与 EIP 安全组拒绝公网 ICMP 入向有关）
- 是否自动跳过 `pod-to-cidr` 系列（动态解析 CN IP 失败时跳过）

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

- **节点绑了 EIP？** pod-to-host 中的 `ping-ipv4-external-ip` 子动作会因 TKE 节点 EIP 的安全组默认拒绝公网 ICMP 入向而失败，此时需追加 `--test '!/pod-to-host$'` 跳过该用例（`$` 用于精确匹配，避免误伤 `pod-to-hostport`）。一键脚本会自动检测并跳过。
- **节点没有公网？** 追加 `--test '!/pod-to-world' --test '!/pod-to-cidr'` 跳过依赖公网的用例。
- 镜像地址替换为 TKE 环境可内网拉取的地址（`quay.io` → `quay.tencentcloudcr.com`，`registry.k8s.io` / `gcr.io` → `docker.io/k8smirror`）。

:::

## 运行环境前提

`cilium.sh test` 默认 **不禁用任何 cilium 测试用例**，只在两种情况下做自动跳过——都是与 cilium 自身能力无关的环境/云厂商行为：

| 自动跳过场景                        | 触发条件                    | 跳过的 scenario                                                             | 原因                                                                                                                                                                                                 |
| ----------------------------------- | --------------------------- | --------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 节点绑了 EIP                        | 至少一个节点有 `ExternalIP` | `pod-to-host`                                                               | scenario 中的 `ping-ipv4-external-ip` 动作会把节点 EIP 当作 ping 目标。TKE 节点 EIP 默认安全组**不允许公网 ICMP 入向**——必失败。`Pod → 节点内网 IP` 的覆盖度已由 `pod-to-pod`、`pod-to-service` 提供 |
| 国内地域 + 找不到可用 IP-only HTTPS | 动态解析 CN IP 失败         | `pod-to-cidr` / `to-cidr-external` / `from-cidr` / `client-egress-to-cidr*` | 国内公网无稳定的"纯 IP 直连 HTTPS"服务可用（无 SAN 含 IP 的证书），脚本动态扫描失败时跳过；CIDR 策略本身仍由 `to-entities-world`、`from-cidr` 等用例间接验证                                         |

cilium-cli 的 `--test` 过滤器只支持 scenario 级别匹配（`/pod-to-host$` 用 `$` 锚点避免误伤 `pod-to-hostport`）；无法只禁用 scenario 内的单个 action。

此外，cilium-cli 自身会按以下条件**自动跳过**约 74 个用例（与 TKE 环境无关，是 cilium 测试套件设计如此）：

| 跳过原因                                              | 用例示例                                                                                                                  | 是否需要关注                                         |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| `unsafe test which can modify state of cluster nodes` | `no-policies-from-outside`、`all-ingress-deny-from-outside`、`echo-ingress-from-outside`、`from-cidr-host-netns` 等       | 否——这些会修改节点 iptables/路由，不适合在生产集群跑 |
| `skipped by condition`                                | `cluster-entity-multi-cluster`（依赖 cluster mesh）、依赖 ENI/IPv6/Multicast/`node-without-cilium` 等当前未启用特性的用例 | 否——按需启用对应特性后这些用例才会运行               |
| `skipped by user`                                     | TLS / `egress-gateway-excluded-cidrs` 等带 client cert 或外部 host 的子用例                                               | 否——这些用例需要预先准备外部资源，不适合默认跑       |

### 节点公网能力

测试涉及外部目标的用例（`pod-to-world` / `pod-to-cidr` / `to-fqdns` / `to-cidr-external` 等）需要 **Pod 能从节点出公网**。脚本启动时会做一次出公网探测，**不通时打印警告但不强制跳过**——是否跳过由用户决定。

如果节点没有公网，相关用例会失败，属于预期行为（与 cilium 无关），可手动追加 `--test '!/pod-to-world' --test '!/pod-to-cidr'` 等显式跳过。

## 测试环境

| 项              | 值                                                                    |
| --------------- | --------------------------------------------------------------------- |
| 地域            | 成都 ap-chengdu                                                       |
| Kubernetes 版本 | v1.34.1（containerd 1.7.28）                                          |
| Cilium 版本     | v1.19.4                                                               |
| Cilium CLI 版本 | v0.19.4                                                               |
| 节点 OS         | TencentOS Server 4 (kernel 6.6.117-45.7.3.tl4.x86_64)                 |
| 节点机型        | S5.MEDIUM4（2C4G）                                                    |
| 节点数量        | 每个集群 3 个节点，全部位于 ap-chengdu-1                              |
| 节点公网        | 节点绑 EIP（脚本会自动跳过 pod-to-host 用例）                         |
| 安装方式        | [一键安装脚本](../install.md#一键安装脚本) `cilium.sh install-cilium` |

## 测试结果

### Native Routing (VPC-CNI) ⭐

启用 `Egress Gateway`（脚本自动设置 `ipMasqAgent.config.nonMasqueradeCIDRs` 覆盖 RFC 1918 三段，避免跨节点 Pod-to-Pod 被 SNAT 破坏 NetworkPolicy；详见 [Native + Egress Gateway 兼容性说明](#native--egress-gateway-兼容性说明)）。

```text
❌ 1/76 tests failed (1/707 actions), 56 tests skipped, 2 scenarios skipped:
Test [local-redirect-policy]:
  🟥 local-redirect-policy/lrp-skip-redirect-from-backend:curl-0-ipv4:
     cilium-test-1/lrp-backend → 169.254.169.248:80/TCP succeeded while it should have failed
```

**1 个用例失败，不影响生产可用性**：

| 失败用例                                               | 失败原因                                                                                                                                                                                                                   | 影响                                                                                                                                     |
| ------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `local-redirect-policy/lrp-skip-redirect-from-backend` | LRP 的 `skipRedirectFromBackend` 行为：lrp-backend 自身访问 `169.254.169.248:80` 应该**绕过** LRP（不被重定向回自己），但在 chained CNI 模式下实际被重定向了。这是 cilium 在 chained CNI 模式下对 LRP 边缘 case 的实现差异 | 不影响常规 LRP 使用（比如 [Cilium 与 NodeLocal DNSCache 共存](../with-node-local-dns.md) 用的 LRP），仅影响 LRP backend 自调用的特殊场景 |

**实际可视为通过：75/76**，生产可放心使用。

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
| 16  | `host-entity-egress`                       | ⏭️ 跳过 | skipped by user                                         |
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

| #   | 用例                                  | 状态        | 说明                                                                                     |
| --- | ------------------------------------- | ----------- | ---------------------------------------------------------------------------------------- |
| 113 | `local-redirect-policy`               | ❌ **失败** | LRP 主测试，唯一失败的子动作 `lrp-skip-redirect-from-backend` 是 LRP 边缘 case，详见上文 |
| 114 | `local-redirect-policy-with-node-dns` | ⏭️ 跳过     | unsafe 用例                                                                              |

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

本次 56 个 skipped 用例可归为 4 类，均与 cilium 自身能力无关：

| 跳过原因                                                                    | 用例数 | 是否需要关注                                                                                             |
| --------------------------------------------------------------------------- | ------ | -------------------------------------------------------------------------------------------------------- |
| `unsafe test which can modify state of cluster nodes`                       | 14     | 否——会修改节点 BGP/iptables/路由配置，不适合在生产集群跑                                                 |
| `Feature ... is disabled`                                                   | 22     | 否——按需启用对应特性后这些用例才会运行（ingress-controller、mutual-auth-spiffe、node-without-cilium 等） |
| `requires Cilium version`                                                   | 4      | 否——不同 cilium 版本独有的用例                                                                           |
| `skipped by condition` / `skipped by user` / `k8s localhost tests excluded` | 16     | 否——条件性用例，需要预先准备外部资源或特定网络拓扑                                                       |

### Overlay (VPC-CNI) ⭐

> 待补充：在 Overlay (VPC-CNI) 集群上跑 `./cilium.sh test`，把输出结果填充到此处。

### Overlay (GR)

> 待补充：在 Overlay (GR) 集群上跑 `./cilium.sh test`，把输出结果填充到此处。

## Native + Egress Gateway 兼容性说明

Egress Gateway 启用时，cilium 源码强制要求 `enableIPv4Masquerade=true` + `bpf.masquerade=true`（[`pkg/egressgateway/manager.go`](https://github.com/cilium/cilium/blob/main/pkg/egressgateway/manager.go)）。在 Native Routing 模式下，如果不配置 `ipMasqAgent.config.nonMasqueradeCIDRs`，cilium 会把跨节点 Pod-to-Pod 流量当成"出 VPC"做 SNAT，源 Pod IP 被替换成 link-local（`169.254.x.x`）或节点 IP，接收端 cilium-agent 无法解析为正确的 endpoint identity，导致**所有"基于源 endpoint label 的 NetworkPolicy"在跨节点场景下失效**。

`cilium.sh install-cilium` 在检测到 `Native + Egress` 组合时，会按以下优先级解析 `nonMasqueradeCIDRs` 并自动注入 helm 安装：

1. 环境变量 `NON_MASQ_CIDRS`（空格分隔的 CIDR 列表）
2. 集群中已存在的 TKE `ip-masq-agent-config` ConfigMap（TKE 自带 ip-masq-agent 组件会写入 VPC 主网段 + 辅助网段）
3. 交互式询问，默认 `10.0.0.0/8 172.16.0.0/12 192.168.0.0/16`（RFC 1918 三段全集，覆盖任意合法腾讯云 VPC 配置）

Overlay 模式不受此问题影响——vxlan 隧道封装时内层源 IP 始终是 Pod IP，cilium 在解封装后直接看到真实源 IP。

## 相关链接

- [安装 Cilium](../install.md)
- [Cilium 性能测试](./performance-test.md)
- [Cilium E2E Connectivity Testing](https://docs.cilium.io/en/stable/contributing/testing/e2e/)

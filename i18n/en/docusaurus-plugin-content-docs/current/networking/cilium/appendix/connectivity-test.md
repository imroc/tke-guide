# Cilium Connectivity Test

This article describes how to perform connectivity functional testing for Cilium installed on a TKE cluster, and provides actual test results for each recommended installation method.

Cilium provides the official [`cilium connectivity test`](https://docs.cilium.io/en/stable/contributing/testing/e2e/) end-to-end test suite, covering Pod-to-Pod, Pod-to-Service, Pod-to-Host same/cross-node connectivity, ClusterIP/NodePort/HostPort forwarding (kubeProxyReplacement), L3/L4/L7 NetworkPolicy (including deny/allow, ingress/egress, CIDR/Entity/ServiceAccount/L7 rules), CiliumLocalRedirectPolicy redirection, DNS resolution, and public network test cases like `pod-to-world` / `pod-to-cidr` / `to-fqdns`. Based on cilium-cli v0.19.4, it deploys approximately 132 test cases / ~600 actions (the count varies by version).

## Test Methods

### One-Click Script

The [one-click install script](../install.md#one-click-install-script) `cilium.sh` provides the `test` subcommand, which wraps `cilium connectivity test`:

```bash
bash -c "$(curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh)" -- test
```

Use the site mirror when GitHub is inaccessible from mainland China:

```bash
bash -c "$(curl -sfL https://imroc.cc/tke/scripts/cilium.sh)" -- test
```

Compared to running `cilium connectivity test` directly, the script does the following additional work:

- **Image replacement**: All test images are replaced with mirror addresses pullable from within the TKE intranet (`quay.io` → `quay.tencentcloudcr.com`, `registry.k8s.io` / `gcr.io` → `docker.io/k8smirror`), so nodes do not need public network access to pull images
- **Mainland China region adaptation**: Automatically detects the node's region. For clusters in mainland China, external targets are replaced from `1.1.1.1` / `one.one.one.one.` / `k8s.io.` (blocked by GFW) to `npmmirror.com` / `mirrors.aliyun.com`, and dynamically resolves `npmmirror.com`'s current public IP to inject into `--external-ip` / `--external-other-ip` / `--external-cidr`, allowing `pod-to-cidr` type test cases to pass
- **Environment probing with WARN only, no forced skip**: Conditions such as whether Pods can access the public internet from nodes, or whether Pods can ping the node's EIP when both Native mode and node EIP are enabled, are tested first. WARN messages are only printed if they fail, with skip suggestions (e.g., `--test '!/pod-to-host$'`), leaving the decision to the user
- **Automatic cleanup of previous test artifacts**: Cleans up the `cilium-test-*` namespace left over from previous runs (cilium-cli preserves resources on test failure, and TKE Gatekeeper prevents namespace deletion while Pods are still running inside it; failing to clean up beforehand will cause subsequent perf tests to hang, see [Cilium Performance Testing → FAQ](./performance-test.md#why-clean-up-cilium-test--namespace-before-perf))
- **Duration tracking**: Prints the total elapsed time at the end of the test

### Manual Testing

First, install the [cilium CLI](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli). The commands differ depending on the region:

<Tabs>
<TabItem value="cn" label="Mainland China (Recommended)" default>

For mainland China regions such as Chengdu, Beijing, Shanghai, Shenzhen, etc., Cilium's default external targets `1.1.1.1` / `one.one.one.one.` / `k8s.io.` are blocked by the GFW and need to be replaced with locally reachable addresses. First, dynamically resolve `npmmirror.com` to get the current public IP (the IP changes with Alibaba Cloud ECS backends), then pass it to Cilium:

```bash
# 1. Dynamically resolve npmmirror.com's current public IP
EXT_IP=$(kubectl run cn-resolve-tmp --image=quay.tencentcloudcr.com/cilium/alpine-curl:v1.10.0 \
  --restart=Never --attach --rm --quiet --command -- \
  /bin/sh -c 'dig +short npmmirror.com A | head -1')
EXT_OTHER_IP=$(echo "$EXT_IP" | awk -F. '{printf "%s.%s.%s.%d", $1, $2, $3, ($4 + 1)}')
EXT_CIDR=$(echo "$EXT_IP" | awk -F. '{printf "%s.%s.0.0/16", $1, $2}')
echo "EXT_IP=$EXT_IP, EXT_OTHER_IP=$EXT_OTHER_IP, EXT_CIDR=$EXT_CIDR"

# 2. Run connectivity test. Note: --curl-insecure is required (CN public HTTPS has no IP-bound certificate)
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

If the second IP (`EXT_OTHER_IP`) is not actually reachable (443 does not return 2xx/3xx), `pod-to-cidr` will fail. You can add `--test '!/pod-to-cidr' --test '!/to-cidr-external' --test '!/from-cidr'` to skip IP-based CIDR test cases—a more convenient approach is to use the one-click script, which automatically scans the `/16` range to find a usable second IP.

</TabItem>
<TabItem value="oversea" label="Overseas Regions">

For overseas regions such as Hong Kong, Singapore, Silicon Valley, Tokyo, etc., Cilium's default external targets can be used:

```bash
cilium connectivity test \
  --curl-image quay.tencentcloudcr.com/cilium/alpine-curl:v1.10.0 \
  --json-mock-image quay.tencentcloudcr.com/cilium/json-mock:v1.3.9 \
  --dns-test-server-image docker.io/k8smirror/coredns:v1.14.2 \
  --echo-image docker.io/k8smirror/echo-advanced:v20251204-v1.4.1
```

</TabItem>
</Tabs>

:::tip[Patch Parameter Notes]

- **Node has an EIP?** The `ping-ipv4-external-ip` sub-action in `pod-to-host` will ping the node's EIP from the Pod. If the EIP's security group does not allow inbound public ICMP traffic (TKE denies by default), this test case will inevitably fail. Either allow ICMP inbound or add `--test '!/pod-to-host$'` to skip (the `$` anchor ensures exact matching, avoiding `pod-to-hostport`).
- **Nodes have no public network access?** Add `--test '!/pod-to-world' --test '!/pod-to-cidr'` to skip test cases that depend on public network access.
- Image addresses are replaced with addresses pullable from within the TKE intranet (`quay.io` → `quay.tencentcloudcr.com`, `registry.k8s.io` / `gcr.io` → `docker.io/k8smirror`).

:::

## Runtime Environment Prerequisites

`cilium.sh test` **does not disable any Cilium test cases by default**—the script only prints WARN messages in the following environment-specific scenarios, leaving the decision to manually skip tests to the user based on their environment:

| Warning Scenario                          | Trigger Condition            | Affected Scenarios                                                                   | Description                                                                                                                                                                                                                                                                                        |
| ----------------------------------------- | ---------------------------- | ------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Mainland China + no usable IP-only HTTPS  | Dynamic CN IP resolution failed | `pod-to-cidr` / `to-cidr-external` / `from-cidr` / `client-egress-to-cidr*` | No stable "direct IP HTTPS" service is available on mainland China's public internet (no certificate with SAN containing an IP). Can manually skip: `--test '!/pod-to-cidr' --test '!/to-cidr-external' --test '!/from-cidr' --test '!/client-egress-to-cidr'`; CIDR policy itself is still indirectly verified by `to-entities-world`, `from-cidr` and other test cases |

Another common failure: when a node has an EIP bound, cilium-cli generates a `ping-ipv4-external-ip` sub-action within the `pod-to-host` scenario (pinging the node's EIP from the Pod). **Under TKE Native Routing, this ping always fails**. See the next section for details. To skip this scenario, add `--test '!/pod-to-host$'` (the `$` anchor prevents accidentally matching `pod-to-hostport`).

cilium-cli's `--test` filter only supports scenario-level matching (`/pod-to-host$` uses the `$` anchor to avoid `pod-to-hostport`); it cannot disable individual actions within a scenario.

### Why Pod ping to node EIP never works under Native Routing

Actual causality chain (reproduced on cls-148r0kxp Native cluster and cls-qj0gbg3f Overlay cluster):

A. **Pod IPs have no public network capability under VPC-CNI Native mode**. Pod IPs are allocated from the node's auxiliary ENI IP pool (e.g., `10.20.0.x`), but **the auxiliary ENI does not have an EIP**—the EIP is only bound to the node's primary ENI. At the VPC routing table level, the auxiliary ENI IP range has no public network egress, **so any Pod attempting to reach a public destination must first be SNATed to the node's primary ENI IP** (then egress via the primary ENI's EIP / NAT Gateway / Egress Gateway). This is an inherent constraint of TKE VPC-CNI Native, applicable to Cilium and any other CNI.

B. **cilium-operator registers all Node objects' ExternalIPs as `remote-node identity`** (numeric 6). `cilium-dbg bpf ipcache list` shows the node EIP `42.193.37.239 identity=6`—Cilium treats the node EIP as a "legitimate address of a cluster member node" in the data plane.

C. **Cilium's BPF masquerade implementation has an early return that skips SNAT when the destination identity is internal to the cluster** (preserving Pod identity for NetworkPolicy use). This check **takes precedence over the ipMasqAgent's `nonMasqueradeCIDRs` matching**, so even if you configure ip-masq-agent and the node EIP is not in the `nonMasqueradeCIDRs` list, the CIDR check never takes effect—the destination identity=remote-node already triggers the early return, and the packet does not get SNATed.

D. **The packet leaves the node with the Pod IP, but the Pod IP has no public network egress**—combined with A, packets originating from the auxiliary ENI IP range destined for a public IP are either dropped by the VPC routing table or have no legitimate return path once they reach the network. Hence, the ping fails.

> Packet capture evidence (source node 10.10.21.26):
>
> ```
> enie1f5...   In  ... 10.20.0.208 > 42.193.37.239: ICMP echo request
> eth1         Out ... 10.20.0.208 > 42.193.37.239: ICMP echo request   ← source IP is still Pod IP, no SNAT
> ```
>
> Pod IP `10.20.0.208` comes from the auxiliary ENI IP pool, destination `42.193.37.239` is a public IP—this traffic has no public egress path.

**Why does ping to the node's VPC IP work, but ping to the public EIP does not?**

`Pod → Node VPC IP` (private communication within the same VPC) and `Pod → Public EIP` are two fundamentally different paths:

- The former targets a VPC-internal address, requires no SNAT and no public egress; the VPC route table forwards it directly, so it works;
- The latter targets a public address, and must first be SNATed to use the primary ENI's public capability. Under Native mode, Cilium skips SNAT due to B/C, so the packet leaves with the Pod IP and has no public egress path.

**Why does a ping to a truly public address (e.g., 223.5.5.5) work instead?**

Actual testing shows `Pod → 223.5.5.5` works while `Pod → Node EIP` does not—the difference lies in B/C: 223.5.5.5 is not any node's ExternalIP, its identity is `world`, it does not trigger the remote-node early return, Cilium correctly evaluates the ipMasqAgent CIDR rules (the destination is not in `nonMasqueradeCIDRs`) and performs SNAT, so the packet leaves via the node's primary ENI IP and goes through the EIP/NAT Gateway—it works. **Node EIPs are uniquely treated differently by Cilium because they carry the remote-node tag in the ipcache**.

#### Why Overlay mode is not affected

| Dimension                             | Native                                            | Overlay                                                                                                               |
| ------------------------------------- | ------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| Pod IP source                         | Node auxiliary ENI VPC IP pool (e.g., `10.20.0.x`) | Independent Overlay CIDR (e.g., `10.244.x.x`), **not in the VPC range**                                               |
| Pod IP public capability              | ❌ No (auxiliary ENI has no EIP)                  | n/a (Pod IP is always SNATed before leaving the node, never directly faces the public internet)                      |
| `enableIPv4Masquerade`                | `false` (Pod IP is a valid VPC IP, no SNAT needed for east-west traffic) | `true`                                                                                                                |
| Node EIP identity                     | `remote-node`                                     | `remote-node`                                                                                                         |
| BPF masq early return (remote-node skip) | Hit—but Native has masquerade disabled overall, so no SNAT happens anyway | Hit—Cilium treats the destination as internal to the cluster, skips SNAT after vxlan decapsulation, **but the inner SNAT was already done by enableIPv4Masquerade before vxlan encapsulation** |
| Source IP leaving the node            | Pod IP (auxiliary ENI IP, no public capability)   | **Node primary ENI VPC IP** (already SNATed)                                                                         |
| Can reach public EIP                  | ❌ Pod IP has no public egress                    | ✅ Node primary ENI IP uses the primary ENI's public capability (EIP / NAT Gateway)                                  |

In short: **Under Native mode, Pod IPs come from auxiliary ENIs without EIPs and have no public capability; Cilium refuses to SNAT due to the remote-node identity, so the path to the public EIP is blocked. Under Overlay mode, the Pod IP doesn't exist in the VPC route table at all; Cilium always SNATs it to the node's primary ENI IP before leaving the node, and the primary ENI has public capability, so it can reach the EIP.**

#### Is this a bug in Cilium / TKE?

Neither—it is the combination of two reasonable design decisions:

- **TKE VPC-CNI Native places Pod IPs on auxiliary ENIs and EIPs only on the primary ENI** to decouple Pod IPs from node IPs and prevent Pod count from being limited by the primary ENI—the trade-off is that Pods must explicitly use SNAT for public internet access.
- **Cilium treats node EIPs as remote-node and does not SNAT them** to preserve Pod identity so that NetworkPolicy can still work based on the source Pod label in cross-node scenarios.

Both designs are reasonable on their own, but together they cause cilium-cli's `pod-to-host:ping-ipv4-external-ip` to fail under Native mode. In production, the scenario of "a Pod actively pinging another node's EIP" is virtually non-existent, so there is no practical impact—simply use `--test '!/pod-to-host$'` to skip it.

#### Why ip-masq-agent cannot fix this

Intuitively, "ip-masq-agent is for SNAT in Native mode—just add the EIP range and it will SNAT, right?" — No. Cilium's ip-masq-agent is implemented in BPF and shares the same BPF masq logic as the "skip SNAT when destination identity is remote-node" early return described in point C above. The early return happens **before** the ipMasqAgent CIDR check, so node EIPs with remote-node identity are skipped directly and never reach the CIDR check step. There is **no legitimate Helm configuration option** to exclude the remote-node identity from the early return.

NAT Gateway / Egress Gateway similarly cannot help—they only determine "which source IP to use after SNAT has been decided", not the "whether to SNAT" decision itself.

Additionally, cilium-cli itself **automatically skips** approximately 74 test cases based on the following criteria (unrelated to the TKE environment, by design of the Cilium test suite):

| Skip reason                                          | Example test cases                                                                                                                                     | Requires attention?                                |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------- |
| `unsafe test which can modify state of cluster nodes` | `no-policies-from-outside`, `all-ingress-deny-from-outside`, `echo-ingress-from-outside`, `from-cidr-host-netns`, etc.                                | No—these modify node iptables/routing, unsuitable for production clusters |
| `skipped by condition`                                | `cluster-entity-multi-cluster` (requires cluster mesh), tests depending on ENI/IPv6/Multicast/`node-without-cilium` and other currently disabled features | No—these tests run only after enabling the corresponding features |
| `skipped by user`                                     | Some sub-cases requiring an external host                                                                                                              | No—these cases require pre-provisioned external resources, not suitable for default runs |

### Node Public Network Capability

Test cases involving external targets (`pod-to-world` / `pod-to-cidr` / `to-fqdns` / `to-cidr-external`, etc.) require **Pods to access the public internet through the node**. The script performs a public network reachability probe at startup—**if unreachable, it prints a warning but does not force skip**—the decision to skip is left to the user.

If nodes have no public network access, the relevant test cases will fail. This is expected behavior (unrelated to Cilium). You can manually add `--test '!/pod-to-world' --test '!/pod-to-cidr'` to explicitly skip them.

## Native Routing (VPC-CNI) Test Results

### Test Environment

| Item             | Value                                                                                                |
| ---------------- | ---------------------------------------------------------------------------------------------------- |
| Kubernetes       | v1.34.1 (containerd 1.7.28)                                                                         |
| Cilium           | v1.19.4                                                                                              |
| Cilium CLI       | v0.19.4                                                                                              |
| Node OS          | TencentOS Server 4 (kernel 6.6.117-45.7.3.tl4.x86_64)                                                |
| Instance Type    | S5.LARGE8 (4C8G)                                                                                    |
| Node Count       | 3 nodes                                                                                             |
| Node Public      | Nodes have EIP bound, VPC configured with NAT Gateway (see [FAQ](#faq) for "Why configure a NAT Gateway for nodes") |
| Installation     | [One-click install script](../install.md#one-click-install-script) `cilium.sh install`, with Egress Gateway and ip-masq-agent enabled |

> Enabling either Egress Gateway or ip-masq-agent causes Cilium to enable BPF masquerade. The script automatically sets `ipMasqAgent.config.nonMasqueradeCIDRs` to cover the three RFC 1918 ranges, preventing cross-node Pod-to-Pod traffic from being SNATed and breaking NetworkPolicy. See [Native + ip-masq-agent / Egress Gateway Compatibility Notes](#native--ip-masq-agent--egress-gateway-compatibility).

### Test Results

```text
❌ 1/77 tests failed (1/788 actions), 55 tests skipped, 0 scenarios skipped:
Test [local-redirect-policy]:
  🟥 local-redirect-policy/lrp-skip-redirect-from-backend:curl-0-ipv4:
     cilium-test-1/lrp-backend → 169.254.169.248:80/TCP succeeded while it should have failed
```

**1 test case failed, no impact on production usability**: The only failing test case `local-redirect-policy/lrp-skip-redirect-from-backend` is an LRP edge case that consistently fails under VPC-CNI Native mode. See [FAQ → Why does the lrp-skip-redirect-from-backend test case consistently fail](#why-does-the-lrp-skip-redirect-from-backend-test-case-consistently-fail). Standard LRP usage (e.g., [Cilium co-existing with NodeLocal DNSCache](./with-node-local-dns.md)) works perfectly.

**Effectively passable: 76/77**. Safe for production use. Duration: approximately 35 minutes 37 seconds.

#### Full Test Case Details

cilium connectivity test deploys a total of 132 test cases, grouped by function with each case's test objective and current run status:

##### 1. No Policy Baseline (verifies Cilium datapath connectivity without NetworkPolicy interference)

| #   | Test Case                       | Status      | Description                                                                                                                |
| --- | ------------------------------- | ----------- | -------------------------------------------------------------------------------------------------------------------------- |
| 1   | `no-policies`                   | ✅ Passed   | Covers basic scenarios under no policies: `pod-to-pod` / `pod-to-service` / `pod-to-host` / `pod-to-cidr` / `pod-to-world` / `host-to-pod` |
| 2   | `no-policies-from-outside`      | ⏭️ Skipped  | Requires external host (`node-without-cilium`), not available in TKE environment                                           |
| 3   | `no-policies-extra`             | ✅ Passed   | Additional no-policy scenarios (including `pod-to-controlplane-host`, etc.)                                                |
| 4   | `allow-all-except-world`        | ✅ Passed   | Allow all non-world traffic, verifies the `entity: world` selector                                                         |
| 7   | `allow-all-with-metrics-check`  | ✅ Passed   | Allow-all policy + verify Cilium metrics collection                                                                        |

##### 2. Ingress Policy (verifies ingress allow/deny)

| #   | Test Case                                    | Status      | Description                                              |
| --- | -------------------------------------------- | ----------- | -------------------------------------------------------- |
| 5   | `client-ingress`                             | ✅ Passed   | CiliumNetworkPolicy allows only specific source label ingress |
| 6   | `client-ingress-knp`                         | ✅ Passed   | Same as 5, but with K8s native NetworkPolicy (KNP)       |
| 8   | `all-ingress-deny`                           | ✅ Passed   | Default deny all ingress                                 |
| 9   | `all-ingress-deny-from-outside`              | ⏭️ Skipped  | Unsafe case (modifies node state)                        |
| 10  | `all-ingress-deny-knp`                       | ✅ Passed   | KNP version of default-deny ingress                      |
| 17  | `host-entity-ingress`                        | ✅ Passed   | Allow ingress from `entity: host`                        |
| 18  | `echo-ingress`                               | ✅ Passed   | Allow echo ingress from specific source                  |
| 19  | `echo-ingress-from-outside`                  | ⏭️ Skipped  | Unsafe case                                              |
| 20  | `echo-ingress-knp`                           | ✅ Passed   | KNP version                                              |
| 21  | `client-ingress-icmp`                        | ✅ Passed   | ICMP protocol matching (`ICMPs:` field)                  |
| 37  | `echo-ingress-from-other-client-deny`        | ✅ Passed   | Deny echo ingress from a specific client                 |
| 38  | `client-ingress-from-other-client-icmp-deny` | ✅ Passed   | Deny ICMP from a specific client                         |

##### 3. Egress Policy (verifies egress allow/deny)

| #   | Test Case                                          | Status      | Description                                        |
| --- | -------------------------------------------------- | ----------- | -------------------------------------------------- |
| 11  | `all-egress-deny`                                  | ✅ Passed   | Default deny all egress                            |
| 12  | `all-egress-deny-knp`                              | ✅ Passed   | KNP version                                        |
| 22  | `client-egress`                                    | ✅ Passed   | Allow only specific dst egress                     |
| 23  | `client-egress-knp`                                | ✅ Passed   | KNP version                                        |
| 24  | `client-egress-expression`                         | ✅ Passed   | Using `matchExpressions` instead of `matchLabels`  |
| 25  | `client-egress-expression-port-range`              | ✅ Passed   | With port range matching                           |
| 26  | `client-egress-expression-knp`                     | ✅ Passed   | KNP + matchExpressions                             |
| 27  | `client-egress-expression-knp-port-range`          | ✅ Passed   | KNP + matchExpressions + port range                |
| 39  | `client-egress-to-echo-deny`                       | ✅ Passed   | Deny egress to echo                                |
| 40  | `client-egress-to-echo-deny-port-range`            | ✅ Passed   | Deny with port range                               |
| 41  | `client-ingress-to-echo-named-port-deny`           | ✅ Passed   | Named port deny                                    |
| 42  | `client-egress-to-echo-expression-deny`            | ✅ Passed   | matchExpressions deny                              |
| 43  | `client-egress-to-echo-expression-deny-port-range` | ✅ Passed   | matchExpressions + port range                      |

##### 4. ServiceAccount Policy (matching based on Pod's ServiceAccount label)

| #   | Test Case                                                    | Status      | Description                        |
| --- | ------------------------------------------------------------ | ----------- | ---------------------------------- |
| 28  | `client-with-service-account-egress-to-echo`                 | ✅ Passed   | Source uses SA selector, allow     |
| 29  | `client-with-service-account-egress-to-echo-port-range`      | ✅ Passed   | + port range                       |
| 30  | `client-egress-to-echo-service-account`                      | ✅ Passed   | Dst uses SA selector, allow        |
| 31  | `client-egress-to-echo-service-account-port-range`           | ✅ Passed   | + port range                       |
| 44  | `client-with-service-account-egress-to-echo-deny`            | ✅ Passed   | Source SA deny                     |
| 45  | `client-with-service-account-egress-to-echo-deny-port-range` | ✅ Passed   | + port range                       |
| 46  | `client-egress-to-echo-service-account-deny`                 | ✅ Passed   | Dst SA deny                        |
| 47  | `client-egress-to-echo-service-account-deny-port-range`      | ✅ Passed   | + port range                       |

##### 5. CIDR / Entity Policy

| #   | Test Case                                  | Status      | Description                                                   |
| --- | ------------------------------------------ | ----------- | ------------------------------------------------------------- |
| 13  | `all-entities-deny`                        | ✅ Passed   | Deny all entities                                             |
| 14  | `cluster-entity`                           | ✅ Passed   | `entity: cluster` matches intra-cluster traffic               |
| 15  | `cluster-entity-multi-cluster`             | ⏭️ Skipped  | Requires cluster mesh                                         |
| 16  | `host-entity-egress`                       | ✅ Passed   | Allow egress to `entity: host`                                |
| 32  | `to-entities-world`                        | ✅ Passed   | Allow egress to `entity: world`                               |
| 33  | `to-entities-world-port-range`             | ✅ Passed   | + port range                                                  |
| 34  | `to-cidr-external`                         | ✅ Passed   | Allow egress to external CIDR (dynamically injected 47.96.0.0/16) |
| 35  | `to-cidr-external-knp`                     | ✅ Passed   | KNP version                                                   |
| 36  | `from-cidr-host-netns`                     | ⏭️ Skipped  | Unsafe case                                                   |
| 48  | `client-egress-to-cidr-deny`               | ✅ Passed   | Deny to external CIDR                                         |
| 49  | `client-egress-to-cidrgroup-deny`          | ✅ Passed   | CiliumCIDRGroup deny                                          |
| 50  | `client-egress-to-cidrgroup-deny-by-label` | ✅ Passed   | Reference CiliumCIDRGroup by label                            |
| 51  | `client-egress-to-cidr-deny-default`       | ✅ Passed   | Default deny CIDR                                             |

##### 6. Encryption / Node-to-Node Encryption

| #   | Test Case                                 | Status      | Description                                        |
| --- | ----------------------------------------- | ----------- | -------------------------------------------------- |
| 55  | `pod-to-pod-encryption`                   | ⏭️ Skipped  | Requires Cilium < 1.18, this test uses 1.19.4      |
| 56  | `pod-to-pod-with-l7-policy-encryption`    | ⏭️ Skipped  | Same as above                                      |
| 57  | `pod-to-pod-encryption-v2`                | ✅ Passed   | Verify v2 encryption path (validates empty capture when encryption is not enabled) |
| 58  | `pod-to-pod-with-l7-policy-encryption-v2` | ⏭️ Skipped  | Feature `encryption-pod` not enabled               |
| 59  | `node-to-node-encryption`                 | ✅ Passed   | Node-to-node encryption path (validates empty capture when not enabled) |
| 119 | `strict-mode-encryption`                  | ⏭️ Skipped  | Unsafe case                                        |
| 120 | `strict-mode-encryption-v2`               | ⏭️ Skipped  | Unsafe case                                        |
| 121 | `ipsec-key-derivation-validation`         | ⏭️ Skipped  | Unsafe case                                        |
| 122 | `ztunnel-pod-to-pod-encryption`           | ⏭️ Skipped  | Feature `enable-ztunnel` not enabled               |

##### 7. Egress Gateway

| #   | Test Case                           | Status      | Description                                |
| --- | ----------------------------------- | ----------- | ------------------------------------------ |
| 60  | `egress-gateway`                    | ⏭️ Skipped  | Unsafe case (modifies node state)          |
| 61  | `egress-gateway-multigateway`       | ⏭️ Skipped  | Unsafe case                                |
| 62  | `egress-gateway-excluded-cidrs`     | ⏭️ Skipped  | Requires `node-without-cilium`             |
| 63  | `egress-gateway-with-l7-policy`     | ⏭️ Skipped  | Unsafe case                                |
| 64  | `pod-to-node-cidrpolicy`            | ⏭️ Skipped  | Feature `cidr-match-nodes` not enabled     |

##### 8. LoadBalancer / Ingress (requires node-without-cilium or ingress-controller)

| #   | Test Case                                              | Status      | Description                                |
| --- | ------------------------------------------------------ | ----------- | ------------------------------------------ |
| 53  | `health`                                               | ⏭️ Skipped  | Feature `health-checking` not enabled      |
| 54  | `north-south-loadbalancing`                            | ⏭️ Skipped  | Requires `node-without-cilium`             |
| 65  | `north-south-loadbalancing-with-l7-policy`             | ⏭️ Skipped  | Same as above                              |
| 66  | `north-south-loadbalancing-with-l7-policy-port-range`  | ⏭️ Skipped  | Same as above                              |
| 92  | `pod-to-ingress-service`                               | ⏭️ Skipped  | Feature `ingress-controller` not enabled   |
| 93  | `pod-to-ingress-service-allow-ingress-identity`        | ⏭️ Skipped  | Same as above                              |
| 94  | `pod-to-ingress-service-deny-all`                      | ⏭️ Skipped  | Same as above                              |
| 95  | `pod-to-ingress-service-deny-backend-service`          | ⏭️ Skipped  | Same as above                              |
| 96  | `pod-to-ingress-service-deny-ingress-identity`         | ⏭️ Skipped  | Same as above                              |
| 97  | `pod-to-ingress-service-deny-source-egress-other-node` | ⏭️ Skipped  | Same as above                              |
| 98  | `outside-to-ingress-service`                           | ⏭️ Skipped  | Same as above                              |
| 99  | `outside-to-ingress-service-deny-all-ingress`          | ⏭️ Skipped  | Same as above                              |
| 100 | `outside-to-ingress-service-deny-cidr`                 | ⏭️ Skipped  | Same as above                              |
| 101 | `outside-to-ingress-service-deny-world-identity`       | ⏭️ Skipped  | Same as above                              |
| 102 | `pod-to-itself-via-service`                            | ✅ Passed   | Pod accesses itself via Service (hairpin)  |
| 103 | `l7-lb`                                                | ⏭️ Skipped  | Feature `loadbalancer-l7` not enabled      |

##### 9. L7 / HTTP NetworkPolicy

| #   | Test Case                                          | Status      | Description                               |
| --- | -------------------------------------------------- | ----------- | ----------------------------------------- |
| 67  | `echo-ingress-l7`                                  | ✅ Passed   | L7 HTTP rules (path / method matching)    |
| 68  | `echo-ingress-l7-via-hostport`                     | ✅ Passed   | L7 via HostPort                           |
| 69  | `echo-ingress-from-client-tiered-wildcard-pass-l7` | ⏭️ Skipped  | Requires Cilium >= 1.20, this test uses 1.19.4 |
| 70  | `echo-ingress-l7-named-port`                       | ✅ Passed   | L7 + named port                           |
| 71  | `client-egress-l7-method`                          | ✅ Passed   | L7 method restriction                     |
| 72  | `client-egress-l7-method-port-range`               | ✅ Passed   | + port range                              |
| 73  | `client-egress-l7`                                 | ✅ Passed   | L7 path restriction                       |
| 74  | `client-egress-l7-port-range`                      | ✅ Passed   | + port range                              |
| 75  | `client-egress-l7-named-port`                      | ✅ Passed   | + named port                              |
| 86  | `client-egress-l7-set-header`                      | ✅ Passed   | L7 header injection                       |
| 87  | `client-egress-l7-set-header-port-range`           | ✅ Passed   | + port range                              |

##### 10. TLS SNI / TLS Header (requires client cert / external host)

| #   | Test Case                                      | Status      | Description                                   |
| --- | ---------------------------------------------- | ----------- | --------------------------------------------- |
| 76  | `client-egress-tls-sni`                        | ✅ Passed   | TLS SNI matching (external target npmmirror.com) |
| 77  | `client-egress-tls-sni-denied`                 | ✅ Passed   | SNI denied (external target mirrors.aliyun.com) |
| 78  | `client-egress-tls-sni-wildcard`               | ⏭️ Skipped  | Skipped by condition                          |
| 79  | `client-egress-tls-sni-wildcard-denied`        | ⏭️ Skipped  | Same as above                                 |
| 80  | `client-egress-tls-sni-random-wildcard`        | ⏭️ Skipped  | Same as above                                 |
| 81  | `client-egress-tls-sni-random-wildcard-denied` | ⏭️ Skipped  | Same as above                                 |
| 82  | `client-egress-tls-sni-double-wildcard`        | ⏭️ Skipped  | Same as above                                 |
| 83  | `client-egress-tls-sni-double-wildcard-denied` | ⏭️ Skipped  | Same as above                                 |
| 84  | `client-egress-l7-tls-headers-sni`             | ✅ Passed   | L7 TLS + SNI + header                         |
| 85  | `client-egress-l7-tls-headers-other-sni`       | ✅ Passed   | Different SNI                                 |
| 125 | `client-egress-l7-tls-deny-without-headers`    | ✅ Passed   | Denied without headers                        |
| 126 | `client-egress-l7-tls-headers`                 | ✅ Passed   | L7 TLS + header                               |
| 127 | `client-egress-l7-extra-tls-headers`           | ✅ Passed   | Multiple headers                              |
| 128 | `client-egress-l7-tls-headers-port-range`      | ✅ Passed   | + port range                                  |

##### 11. Mutual Auth / SPIFFE

| #   | Test Case                                    | Status      | Description                               |
| --- | -------------------------------------------- | ----------- | ----------------------------------------- |
| 88  | `echo-ingress-auth-always-fail`              | ⏭️ Skipped  | Feature `mutual-auth-spiffe` not enabled  |
| 89  | `echo-ingress-auth-always-fail-port-range`   | ⏭️ Skipped  | Same as above                             |
| 90  | `echo-ingress-mutual-auth-spiffe`            | ⏭️ Skipped  | Same as above                             |
| 91  | `echo-ingress-mutual-auth-spiffe-port-range` | ⏭️ Skipped  | Same as above                             |

##### 12. DNS / FQDN

| #   | Test Case                     | Status      | Description                               |
| --- | ----------------------------- | ----------- | ----------------------------------------- |
| 104 | `dns-only`                    | ✅ Passed   | DNS-only L7 resolution path               |
| 105 | `to-fqdns`                    | ✅ Passed   | toFQDN policy (domain: npmmirror.com)     |
| 106 | `to-fqdns-with-proxy`         | ✅ Passed   | toFQDN + DNS proxy                        |
| 107 | `to-fqdns-with-ccec-listener` | ⏭️ Skipped  | Requires Cilium >= 1.20                   |

##### 13. ControlPlane / k8s API

| #   | Test Case                             | Status      | Description                        |
| --- | ------------------------------------- | ----------- | ---------------------------------- |
| 108 | `pod-to-controlplane-host`            | ⏭️ Skipped  | k8s localhost tests excluded       |
| 109 | `pod-to-k8s-on-controlplane`          | ⏭️ Skipped  | Same as above                      |
| 110 | `pod-to-controlplane-host-cidr`       | ⏭️ Skipped  | Same as above                      |
| 111 | `pod-to-k8s-on-controlplane-cidr`     | ⏭️ Skipped  | Same as above                      |
| 112 | `policy-local-cluster-egress`         | ✅ Passed   | Restrict egress to local cluster   |

##### 14. CiliumLocalRedirectPolicy (LRP)

| #   | Test Case                                 | Status       | Description                                                                                                                |
| --- | ----------------------------------------- | ------------ | -------------------------------------------------------------------------------------------------------------------------- |
| 113 | `local-redirect-policy`                   | ❌ **Failed** | LRP main test. The only failing sub-action `lrp-skip-redirect-from-backend` is an LRP edge case. See [FAQ](#why-does-the-lrp-skip-redirect-from-backend-test-case-consistently-fail) |
| 114 | `local-redirect-policy-with-node-dns`     | ⏭️ Skipped    | Unsafe case                                                                                                                |

##### 15. Path Related (Pod-to-Pod edge cases / cluster networking)

| #   | Test Case                    | Status      | Description                                  |
| --- | ---------------------------- | ----------- | -------------------------------------------- |
| 115 | `pod-to-pod-no-frag`         | ✅ Passed   | Pod-to-Pod without fragmentation             |
| 131 | `no-unexpected-packet-drops` | ✅ Passed   | No unexpected packet drops during the test   |
| 132 | `check-log-errors`           | ✅ Passed   | No error-level logs in cilium-agent logs     |

##### 16. BGP / Multicast / Host Firewall (unsafe category)

| #   | Test Case               | Status      | Description                                  |
| --- | ----------------------- | ----------- | -------------------------------------------- |
| 116 | `bgp-control-plane-v1`  | ⏭️ Skipped  | Unsafe case (modifies node BGP configuration)|
| 117 | `bgp-control-plane-v2`  | ⏭️ Skipped  | Unsafe case                                  |
| 118 | `multicast`             | ⏭️ Skipped  | Unsafe case (requires multicast feature)     |
| 123 | `host-firewall-ingress` | ⏭️ Skipped  | Unsafe case                                  |
| 124 | `host-firewall-egress`  | ⏭️ Skipped  | Unsafe case                                  |

##### 17. ClusterMesh / CCNP / Others

| #   | Test Case                              | Status      | Description                                      |
| --- | -------------------------------------- | ----------- | ------------------------------------------------ |
| 52  | `clustermesh-endpointslice-sync`       | ⏭️ Skipped  | Skipped by condition (requires cluster mesh)     |
| 129 | `egress-to-specific-namespace-ccnp`    | ✅ Passed   | CiliumClusterwideNetworkPolicy egress            |
| 130 | `ingress-from-specific-namespace-ccnp` | ✅ Passed   | CCNP ingress                                     |

#### Skipped Test Case Summary

The 55 skipped test cases in this run can be categorized into 4 groups, all unrelated to Cilium's own capabilities:

| Skip reason                                                | Count | Requires attention?                                                                                                        |
| ---------------------------------------------------------- | ----- | --------------------------------------------------------------------------------------------------------------------------- |
| `unsafe test which can modify state of cluster nodes`      | 14    | No—would modify node BGP/iptables/routing configuration, unsuitable for production clusters                                 |
| `Feature ... is disabled`                                  | 22    | No—these tests run only after enabling the corresponding features (ingress-controller, mutual-auth-spiffe, node-without-cilium, etc.) |
| `requires Cilium version`                                  | 4     | No—test cases specific to different Cilium versions                                                                         |
| `skipped by condition` / `k8s localhost tests excluded`    | 15    | No—conditional cases requiring pre-provisioned external resources or specific network topology                              |

## Overlay (VPC-CNI) Test Results

### Test Environment

| Item             | Value                                                            |
| ---------------- | ---------------------------------------------------------------- |
| Kubernetes       | v1.34.1 (containerd 1.7.28)                                     |
| Cilium           | v1.19.4                                                          |
| Cilium CLI       | v0.19.4                                                          |
| Node OS          | TencentOS Server 4 (kernel 6.6.117-45.7.3.tl4.x86_64)            |
| Instance Type    | S5.LARGE8 (4C8G)                                                 |
| Node Count       | 3 nodes                                                          |
| Node Public      | Nodes have EIP bound, VPC configured with NAT Gateway            |
| Installation     | [One-click install script](../install.md#one-click-install-script) `cilium.sh install` |

### Test Results

```text
✅ All 77 tests (791 actions) successful, 55 tests skipped, 0 scenarios skipped.
```

**All test cases passed, zero failures**—Overlay (VPC-CNI) is the cleanest Cilium deployment option on TKE. Duration: approximately 36 minutes 15 seconds.

#### Differences from Native (VPC-CNI)

Compared to Native mode, Overlay mode has BPF host routing and Cilium fully manages the Pod network (without relying on chained CNI). Therefore:

- **`local-redirect-policy/lrp-skip-redirect-from-backend` passes**: Unlike Native mode, Overlay is not stuck at the edge case where chained CNI mode fails to identify the backend source (see [FAQ → Why does the lrp-skip-redirect-from-backend test case consistently fail](#why-does-the-lrp-skip-redirect-from-backend-test-case-consistently-fail))
- **`echo-ingress-l7-via-hostport` skipped** (`skipped by condition`): Overlay mode does not enable the HostPort feature by default; Native mode enables it by default, so this case passes under Native
- **`health` passes**: Overlay mode enables Cilium `health-checking`; skipped under Native (feature disabled)
- **`host-entity-egress` and `host-entity-ingress` pass**: Same as Native

The total test count (77) and skip count (55) are the same as Native; the main differences lie in which cases fall under ✅ Passed / ⏭️ Skipped / ❌ Failed:

| Dimension                          | Native (VPC-CNI)           | Overlay (VPC-CNI)          |
| ---------------------------------- | -------------------------- | -------------------------- |
| Tests passed                       | 76 / 77                    | **77 / 77** ✅             |
| Tests failed                       | 1                          | **0**                      |
| Tests skipped                      | 55                         | 55                         |
| Total actions                      | 788                        | 791                        |
| `lrp-skip-redirect-from-backend`   | ❌ Failed                  | ✅ Passed                  |
| `echo-ingress-l7-via-hostport`     | ✅ Passed                  | ⏭️ Skipped (feature not enabled) |
| `health`                           | ⏭️ Skipped (feature not enabled) | ✅ Passed                  |

> In short: Cilium installed in Overlay mode delivers its "full capabilities". Native mode, due to chained CNI, has certain edge case limitations, but the core capabilities for production workloads (NetworkPolicy / Hubble / KPR / Egress Gateway) are identical between both modes.

## FAQ

### Why does the lrp-skip-redirect-from-backend test case consistently fail?

Under VPC-CNI Native (Cilium chained CNI mode), this test case **consistently fails**, regardless of the specific cluster, configuration, or Cilium version.

**Test case semantics**:

`local-redirect-policy/lrp-skip-redirect-from-backend` verifies the `skipRedirectFromBackend` feature of Cilium LRP—when a backend Pod **itself** accesses the frontend that is being redirected, it should **bypass** the LRP (not be redirected back to itself), resulting in a connection refused.

**Actual behavior**:

```text
[.] Action [local-redirect-policy/lrp-skip-redirect-from-backend:curl-0-ipv4:
    cilium-test-1/lrp-backend-... (10.20.0.17) -> 169.254.169.248:80/TCP]
❌ command "curl ... http://169.254.169.248:80" succeeded while it should have failed:
   10.20.0.17:39326 -> 169.254.169.248:80 = 200
```

When the backend Pod accesses `169.254.169.248:80` (an address where there should be no real service), it **returned 200**, meaning the request **was still redirected back to the backend itself by the LRP**—`skipRedirectFromBackend` did not take effect.

**Root cause**:

Under chained CNI mode (required for VPC-CNI Native), Cilium's implementation of "identifying that a request comes from the backend Pod" differs—the BPF program on the lxc device in chained mode cannot obtain the complete source endpoint information, so requests from the backend **are not recognized as originating from the backend**, and are thus treated as regular traffic subject to LRP redirection.

**Impact scope (no production impact)**:

- ✅ Core LRP functionality `local-redirect-policy/lrp` works perfectly—forward traffic redirection works correctly
- ✅ [Cilium co-existing with NodeLocal DNSCache](./with-node-local-dns.md), a typical LRP use case, **is completely unaffected** because node-local-dns Pods do not actively access the kube-dns ClusterIP (they are the redirection target)
- ❌ Only affects the specific scenario of "LRP backend Pod actively accessing the frontend it serves"—virtually non-existent in production workloads

If you do not need the `skipRedirectFromBackend` edge feature, you can ignore this test failure. To skip it in the test report, add `--test '!/local-redirect-policy/lrp-skip-redirect-from-backend'`.

### Why configure a NAT Gateway for nodes?

During testing, in addition to binding EIPs to nodes, a public NAT Gateway was configured in the VPC route table—this was to allow the `ping-ipv4-external-ip` sub-action (pinging the node's EIP from the Pod) within the `pod-to-host` scenario to pass.

**Causality chain without NAT Gateway** (see above [Why Pod ping to node EIP never works under Native Routing](#why-pod-ping-to-node-eip-never-works-under-native-routing)): Pod IPs come from auxiliary ENIs with no public capability → Cilium treats node EIPs as remote-node and does not SNAT → packets leave the node with the Pod IP and find no public path → ping fails.

**With NAT Gateway configured**, an additional path is introduced to route traffic back:

```
A. Cilium still does not SNAT (node EIP has remote-node identity)
B. Packet leaves with Pod IP (10.20.0.x), destination is node EIP (public address)
C. VPC route table sends traffic destined for "public" to the NAT Gateway
D. NAT Gateway SNATs the source Pod IP to the NAT Gateway's public IP, the packet exits to the public internet via the NAT Gateway
E. Travels through the public internet and loops back to the node EIP
F. Cloud network layer DNATs the destination EIP back to the node's VPC IP, the packet reaches the node's primary ENI
```

Functionally it works, but the traffic takes a round trip through the public internet, with higher latency than direct `Pod → Node VPC IP`, and it consumes inbound bandwidth on the NAT Gateway / node EIP.

If no NAT Gateway is configured and the node has no other public egress, this test case will inevitably fail when running `cilium.sh test`. Add `--test '!/pod-to-host$'` to skip.

## Native + ip-masq-agent / Egress Gateway Compatibility Notes

VPC-CNI Native mode defaults to `enableIPv4Masquerade=false` (Pod IPs are VPC IPs, so east-west traffic does not need SNAT). Cilium does not enable any masquerade path, cross-node Pod-to-Pod traffic always retains the original Pod IP, and NetworkPolicy source endpoint label matching works correctly.

However, enabling any of the following capabilities will **force Cilium to enable BPF masquerade**:

- **Egress Gateway**: Cilium source code mandates `enableIPv4Masquerade=true` + `bpf.masquerade=true` ([`pkg/egressgateway/manager.go`](https://github.com/cilium/cilium/blob/main/pkg/egressgateway/manager.go))
- **ip-masq-agent** (allows Native Pods to egress to the public internet via the node's primary ENI EIP, see [Configuring IP Masquerade](../masquerading.md)): The script also sets `enableIPv4Masquerade=true` + `bpf.masquerade=true` + `ipMasqAgent.enabled=true`

Once masquerade is enabled, the **default behavior is to SNAT all traffic leaving the cluster CIDR**—in Native mode, this means cross-node Pod-to-Pod traffic will also be SNATed (the source Pod IP is replaced with a link-local `169.254.x.x` or the node IP), causing the receiving Cilium agent to be unable to resolve the correct endpoint identity, resulting in **all NetworkPolicy rules based on source endpoint labels failing in cross-node scenarios**.

The solution is to configure `ipMasqAgent.config.nonMasqueradeCIDRs` to add the VPC CIDR to the allowlist, so Pod-to-Pod / Pod-to-VPC traffic retains the original Pod IP, and only traffic that truly "leaves the VPC" (e.g., public internet) is SNATed.

When `cilium.sh install` detects Native mode with ip-masq-agent or Egress Gateway enabled, it resolves `nonMasqueradeCIDRs` using the following priority order and automatically injects them into the Helm installation:

1. Environment variable `NON_MASQ_CIDRS` (space-separated CIDR list)
2. Existing TKE `ip-masq-agent-config` ConfigMap in the cluster (the built-in TKE ip-masq-agent component writes the primary and auxiliary VPC CIDRs)
3. Interactive prompt, default `10.0.0.0/8 172.16.0.0/12 192.168.0.0/16` (full RFC 1918 ranges, covering any valid Tencent Cloud VPC configuration)

Overlay mode is not affected by this issue—vxlan tunnel encapsulation always uses the Pod IP as the inner source IP, and Cilium sees the real source IP directly after decapsulation.

## Related Links

- [Installing Cilium](../install.md)
- [Cilium Performance Testing](./performance-test.md)
- [Cilium E2E Connectivity Testing](https://docs.cilium.io/en/stable/contributing/testing/e2e/)

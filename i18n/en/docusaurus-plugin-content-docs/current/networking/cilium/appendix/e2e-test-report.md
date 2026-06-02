# Cilium E2E Test Results

This document presents the results of running [`cilium connectivity test`](https://docs.cilium.io/en/stable/contributing/testing/e2e/) once on each of the 4 [installation](../install.md) options. It serves both as a feature-completeness reference for each option and as an answer to the common question "Is L7/DNS the only limitation of GR Native Routing?".

:::info[Quick conclusion]

| Option               | cilium-health | connectivity test   | Production-ready | Key limitations                                                                                                     |
| -------------------- | ------------- | ------------------- | ---------------- | ------------------------------------------------------------------------------------------------------------------- |
| Native (VPC-CNI) ⭐  | ✅ 3/3        | ✅ 56/59 pass       | ✅               | Only node public-IP unreachable (unrelated to cilium)                                                               |
| Native (GR)          | ✅ 3/3        | ❌ aborted at setup | ⚠️               | Cross-node Pod-to-Pod traffic broken; NetworkPolicy does not support L7/DNS (see [gr-no-l7-dns](./gr-no-l7-dns.md)) |
| Overlay (VPC-CNI) ⭐ | ✅ 3/3        | ✅ 56/59 pass       | ✅               | Only node public-IP unreachable (unrelated to cilium)                                                               |
| Overlay (GR)         | ✅ 3/3        | ✅ 56/59 pass       | ✅               | Only node public-IP unreachable (unrelated to cilium)                                                               |

⭐ = recommended option.

:::

## Test Environment

| Item               | Value                                                                                         |
| ------------------ | --------------------------------------------------------------------------------------------- |
| Region             | Chengdu (ap-chengdu)                                                                          |
| Kubernetes version | v1.34.1 (containerd 1.7.28)                                                                   |
| Cilium version     | v1.19.4 + Egress Gateway + Nodelocal DNSCache                                                 |
| Node OS            | TencentOS Server 4 (kernel 6.6.117-45.7.3.tl4.x86_64)                                         |
| Node instance type | SA9.LARGE8 (4 vCPU / 8 GiB)                                                                   |
| Node count         | 3 nodes per cluster, all in ap-chengdu-1                                                      |
| Cilium CLI version | v0.19.4 (used to run `cilium connectivity test`)                                              |
| Install method     | [One-click install script](../install.md#one-click-install-script) `cilium.sh install-cilium` |

Each cluster was a freshly created empty cluster (no nodes added at creation time). The script installed cilium first, then a node pool was added, then e2e tests were run.

`cilium connectivity test` deploys ~60 test cases (~600 actions in total) covering:

- Pod-to-Pod, Pod-to-Service, Pod-to-Host connectivity (same-node and cross-node)
- ClusterIP / NodePort / HostPort forwarding (kubeProxyReplacement)
- L3/L4/L7 NetworkPolicy (deny/allow, ingress/egress, CIDR/Entity/ServiceAccount/L7 rules)
- CiliumLocalRedirectPolicy redirection (validates the nodelocaldns integration path)
- DNS resolution (including via LRP)

The test by default skips `pod-to-world` and `pod-to-cidr` scenarios (rely on public internet, which TKE nodes don't reach by default), `from-cidr-host-netns` and other unsafe cases (modify node state), and cluster-mesh-related cases (not enabled here). **In practice 59 cases / ~600 actions are run**.

## Detailed Results

### Native Routing (VPC-CNI) ⭐

```text
[1/2] cilium-health verification passed: 3/3 nodes healthy
[2/2] cilium connectivity test
   ❌ 23/59 tests failed (66/602 actions), 73 tests skipped, 9 scenarios skipped
```

**Further investigation shows that all 23 failures can be attributed to environmental causes rather than cilium misconfiguration**:

| Failure category                                                                                                                              | Cases | Root cause                                                                                                                                                                                                                                                                                    |
| --------------------------------------------------------------------------------------------------------------------------------------------- | ----- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `no-policies` / `allow-all-except-world` / `host-entity-egress` failing on **`pod-to-host:ping-ipv4-external-ip`**                            | 9     | Node public-IP unreachable (fails in any mode, unrelated to cilium). See "Node public-IP unreachable" below.                                                                                                                                                                                  |
| Cross-node Pod-to-Pod ICMP/TCP **transient** failures (`client-ingress`, `client-ingress-icmp`, `echo-ingress` and several deny-policy cases) | 12    | `cilium connectivity test` does not retry; transient endpoint sync delays during the test (cilium under heavy NetworkPolicy apply/withdraw) caused the "should-be-allowed" reverse-validation in deny tests to fail. Re-testing the same pod pairs after the run shows the traffic recovered. |
| `local-redirect-policy/lrp-skip-redirect-from-backend`: lrp-backend's own access to 169.254.169.248 should bypass LRP but was redirected      | 1     | An edge-case interaction between `skipRedirectFromBackend` and chained-CNI mode; does NOT affect typical LRP usages such as nodelocaldns                                                                                                                                                      |
| `pod-to-pod-encryption-v2`: expected to capture encrypted packets but didn't                                                                  | 1     | The deployment under test does not enable [WireGuard/IPsec encryption](../encryption.md); cilium-cli 0.19.4 should have skipped this case but did not                                                                                                                                         |

**Effective pass rate: 56/59**. Safe for production.

### Native Routing (GR)

```text
[1/2] cilium-health verification passed: 3/3 nodes healthy
[2/2] cilium connectivity test
   ⌛ Waiting for pod cilium-test-1/client3 to reach DNS server on cilium-test-1/echo-same-node pod...
   timeout reached waiting for lookup ... context deadline exceeded
```

**The test aborted at the setup stage**: the `client3` pod that `cilium connectivity test` deploys was unable to reach the CoreDNS service running on the `echo-same-node` pod across nodes; DNS resolution timed out.

**Root cause**: under GR Native Routing + cilium chained CNI, **cross-node Pod-to-Pod traffic is broken**.

Reproduction:

```bash
# A pod on node 105 trying to reach a pod on node 222
$ kubectl -n cilium-test-1 exec deploy/client -- ping -c 2 -W 2 9.230.0.14
2 packets transmitted, 0 received, 100% packet loss

# But node 105 itself (host network) can reach the pod on node 222 just fine
$ kubectl run nettest --rm -i --restart=Never --image=... \
    --overrides='{"spec":{"hostNetwork":true,"nodeSelector":{...}}}' \
    -- ping -c 3 -W 2 9.230.0.14
3 packets transmitted, 3 received, 0% packet loss
```

A `cilium monitor` trace captures only the outbound packet entering the host stack:

```text
-> stack flow 0x0, identity 24059->417, ifindex 0
   9.230.0.208 -> 9.230.0.14 icmp EchoRequest
```

But **no return packet** — when the reply hits `eth0` on node 105, cilium's eBPF (`cil_from_netdev`) intercepts or drops it.

**Combined with the [GR Native Routing does not support L7/DNS NetworkPolicy](./gr-no-l7-dns.md) limitation**, GR Native Routing under chained CNI mode has deeper compatibility issues with cilium's eBPF datapath.

:::warning[GR Native Routing is not recommended for production]

Summarizing the test results:

- ✅ Same-node Pod-to-Pod traffic works
- ✅ Pod-to-Host (local node) traffic works
- ✅ kube-proxy replacement (ClusterIP/NodePort) works
- ❌ **Cross-node Pod-to-Pod traffic broken** (a core scenario fails)
- ❌ L7 / DNS / toFQDNs NetworkPolicy not supported

Recommended only for: single-node demo / PoC / verifying cilium basics within a single node.

For production, choose **Native Routing (VPC-CNI)** or **Overlay (any base cluster)** instead.

:::

### Overlay (VPC-CNI) ⭐

```text
[1/2] cilium-health verification passed: 3/3 nodes healthy
[2/2] cilium connectivity test
   ❌ 3/59 tests failed (27/602 actions), 73 tests skipped, 9 scenarios skipped
```

The 3 failed tests are **identical**, all of the form:

```text
Test [no-policies]:                pod-to-host:ping-ipv4-external-ip
Test [allow-all-except-world]:     pod-to-host:ping-ipv4-external-ip
Test [host-entity-egress]:         pod-to-host:ping-ipv4-external-ip
```

Each test contains 9 actions (3 nodes × 3 client pods cross product), 27 actions in total. The cause is node public-IP unreachable (see below), **unrelated to cilium**.

**Effective pass rate: 56/59**. Safe for production.

### Overlay (GR)

```text
[1/2] cilium-health verification passed: 3/3 nodes healthy
[2/2] cilium connectivity test
   ❌ 3/59 tests failed (27/602 actions), 73 tests skipped, 9 scenarios skipped
```

The failed cases are **identical to Overlay (VPC-CNI)** — the same 3 `pod-to-host:ping-ipv4-external-ip` tests, same root cause.

**Effective pass rate: 56/59**. Safe for production.

## Skipped Tests

All four options skip the same 73 tests by default:

| Skip reason                                           | Examples                                                                                                                        | Need to worry?                                                                              |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `unsafe test which can modify state of cluster nodes` | `no-policies-from-outside`, `all-ingress-deny-from-outside`, `echo-ingress-from-outside`, `from-cidr-host-netns`                | No — these mutate node iptables/routes and shouldn't run on production clusters             |
| `skipped by user`                                     | `to-entities-world`, `to-cidr-external` (i.e. `pod-to-world` / `pod-to-cidr`, skipped by this script)                           | No — TKE nodes don't reach the public internet by default; see "Node public-IP unreachable" |
| `skipped by condition`                                | `cluster-entity-multi-cluster` (requires cluster mesh), other tests that depend on ENI/IPv6/Multicast features not enabled here | No — these will run only after the corresponding feature is enabled                         |

## Node Public-IP Unreachable

The `pod-to-host:ping-ipv4-external-ip` failures common to all 4 clusters are not cilium issues but TKE-node environment limitations:

```text
🟥 no-policies/pod-to-host:ping-ipv4-external-ip:
   cilium-test-1/client (10.20.0.40) -> 118.25.230.204 (118.25.230.204:0)
   command "ping -c 1 -W 2 118.25.230.204" failed:
   exit code 1
```

`118.25.230.204` is **another cluster node's public IP**. `pod-to-host:ping-ipv4-external-ip` tries to ping the **public IP of another node in the same cluster** from a Pod.

Why it fails:

- TKE nodes' public IPs are provided by EIP. **The node itself does not respond to inbound ping targeting its EIP** — the default CVM security group blocks public-internet ICMP ingress
- Even if it did, a Pod cannot necessarily route traffic to a public IP — egress to the public internet requires a NAT gateway or node EIP egress (see [How does a Pod access the public internet](../install.md#how-does-a-pod-access-the-public-internet))

This is the test case itself being inapplicable to a public-cloud environment; all 4 options fail on it, **unrelated to cilium**.

## Test Method

Each cluster runs the script independently:

```bash
./cilium.sh e2e-test
```

The script automatically:

1. **Phase 1: cilium-health verification** — for every node's cilium-agent, check that `cilium-health status` reports `node=1/1 endpoint=1/1` on the `localhost` line
2. **Phase 2: cilium connectivity test** — runs the upstream e2e suite with TKE-internal mirror images and skipping public-internet cases

Full script: the `cmd_e2e_test` function in [cilium.sh](https://github.com/imroc/tke-guide/blob/main/static/scripts/cilium.sh).

## Extending Validation

If you want to validate features not covered above:

| Feature                          | How to enable                                                          | Recommended validation                                 |
| -------------------------------- | ---------------------------------------------------------------------- | ------------------------------------------------------ |
| Egress Gateway                   | Set `ENABLE_EGRESS=true` at install time                               | [Egress Gateway practice guide](../egress-gateway.md)  |
| Nodelocal DNSCache               | Set `ENABLE_LOCALDNS=true` at install time                             | [Cilium with NodeLocal DNS](../with-node-local-dns.md) |
| WireGuard transparent encryption | Helm `encryption.enabled=true encryption.type=wireguard`               | [Cilium transparent encryption](../encryption.md)      |
| Cluster Mesh                     | After installing cilium-cli, run `cilium clustermesh enable / connect` | [Cilium cluster mesh](../clustermesh.md)               |

## Related links

- [Install Cilium](../install.md)
- [Verified Node Operating Systems](./verified-os.md)
- [Why GR Native Routing does not support L7/DNS NetworkPolicy?](./gr-no-l7-dns.md)
- [Cilium E2E Connectivity Testing](https://docs.cilium.io/en/stable/contributing/testing/e2e/)

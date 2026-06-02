# Cilium E2E Test Results

This document presents the results of running [`cilium connectivity test`](https://docs.cilium.io/en/stable/contributing/testing/e2e/) once on each of the 3 recommended [installation](../install.md) options.

> The 4th combination — **Native Routing (GR)** — has severe compatibility issues (cross-node Pod-to-Pod traffic broken, L7/DNS NetworkPolicy unusable) and is no longer offered by this guide. See [Why this guide does not offer GR Native Routing](./gr-native-not-recommended.md).

:::info[Quick conclusion]

| Option               | cilium-health | connectivity test | Production-ready |
| -------------------- | ------------- | ----------------- | ---------------- |
| Native (VPC-CNI) ⭐  | ✅ 3/3        | ✅ All passed     | ✅               |
| Overlay (VPC-CNI) ⭐ | ✅ 3/3        | ✅ All passed     | ✅               |
| Overlay (GR)         | ✅ 3/3        | ✅ All passed     | ✅               |

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

`cilium connectivity test` deploys 132 test cases / ~600 actions by default, covering Pod-to-Pod, Pod-to-Service, Pod-to-Host same-/cross-node connectivity, ClusterIP/NodePort/HostPort forwarding (kubeProxyReplacement), L3/L4/L7 NetworkPolicy (deny/allow, ingress/egress, CIDR/Entity/ServiceAccount/L7), CiliumLocalRedirectPolicy, DNS, etc.

`cilium.sh e2e-test` filters out the following cases before running (see "[Skipped tests](#skipped-tests)" below):

- `pod-to-world` / `pod-to-cidr`: depend on the public internet, which TKE nodes don't reach by default
- `pod-to-host`: uses the node's ExternalIP (EIP) as the ping target by default; TKE node security groups deny inbound public ICMP, so this always fails and is unrelated to cilium
- Other `unsafe` / disabled-feature cases: skipped conditionally by cilium-cli itself

In the end **58 tests / 521 actions** actually run.

## Detailed Results

### Native Routing (VPC-CNI) ⭐

```text
[1/2] cilium-health verification passed: 3/3 nodes healthy
[2/2] cilium connectivity test
   ✅ All 58 tests (521 actions) successful, 74 tests skipped, 11 scenarios skipped
```

All passed. Safe for production.

### Overlay (VPC-CNI) ⭐

```text
[1/2] cilium-health verification passed: 3/3 nodes healthy
[2/2] cilium connectivity test
   ✅ All 58 tests (521 actions) successful, 74 tests skipped, 11 scenarios skipped
```

All passed. Safe for production.

### Overlay (GR)

```text
[1/2] cilium-health verification passed: 3/3 nodes healthy
[2/2] cilium connectivity test
   ✅ All 58 tests (521 actions) successful, 74 tests skipped, 11 scenarios skipped
```

All passed. Safe for production.

## Skipped tests

`cilium.sh e2e-test` uses `--test '!...'` filters to skip the following scenarios that cannot pass on TKE nodes for reasons unrelated to cilium itself:

| Skipped scenario | Why skipped                                                                                                                                                                                                                                                                                                                                                         |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pod-to-world`   | Default target is `one.one.one.one`; nodes in mainland China have restricted/blocked public internet access                                                                                                                                                                                                                                                         |
| `pod-to-cidr`    | Same as above — depends on public-internet CIDRs                                                                                                                                                                                                                                                                                                                    |
| `pod-to-host`    | The `ping-ipv4-external-ip` action in this scenario uses each node's ExternalIP (the EIP / public IP) as the target. TKE node EIPs **deny inbound public ICMP by default** in the security group — every TKE deployment fails this 100%, and the packets never reach cilium's datapath, so passing or failing this case wouldn't validate cilium one way or another |

> The Pod-to-node-internal-IP path is already covered by other scenarios such as `pod-to-pod` and `pod-to-service`, so dropping `pod-to-host` doesn't reduce real coverage.

In addition to the 3 above, cilium-cli **automatically skips** another 74 tests:

| Skip reason                                           | Examples                                                                                                                           | Need to worry?                                                                  |
| ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `unsafe test which can modify state of cluster nodes` | `no-policies-from-outside`, `all-ingress-deny-from-outside`, `echo-ingress-from-outside`, `from-cidr-host-netns`, etc.             | No — these mutate node iptables/routes and shouldn't run on production clusters |
| `skipped by condition`                                | `cluster-entity-multi-cluster` (cluster mesh), tests depending on ENI/IPv6/Multicast/`node-without-cilium` features that aren't on | No — these will run only after the corresponding feature is enabled             |
| `skipped by user`                                     | TLS / `egress-gateway-excluded-cidrs` and similar that require pre-provisioned client certs or external hosts                      | No — they need external resources prepared in advance, not suitable by default  |

## Test Method

Each cluster runs the script independently:

```bash
./cilium.sh e2e-test
```

The script automatically:

1. **Phase 1: cilium-health verification** — for every node's cilium-agent, check that `cilium-health status` reports `node=1/1 endpoint=1/1` on the `localhost` line
2. **Phase 2: cilium connectivity test** — runs the upstream cilium e2e suite using TKE-internal mirror images, with `--test '!...'` filters to skip the 3 case types listed above

Full implementation: the `cmd_e2e_test` function in [cilium.sh](https://github.com/imroc/tke-guide/blob/main/static/scripts/cilium.sh).

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
- [Why this guide does not offer GR Native Routing](./gr-native-not-recommended.md)
- [Cilium E2E Connectivity Testing](https://docs.cilium.io/en/stable/contributing/testing/e2e/)

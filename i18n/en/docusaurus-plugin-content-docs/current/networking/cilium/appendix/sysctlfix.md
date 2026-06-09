# Why Disable sysctlfix in Native Routing Mode but Enable It in Overlay Mode?

## Background

By default, cilium enables a feature called `sysctlfix`: it uses an init container to write the following on each node:

```text
/etc/sysctl.d/99-zzz-override_cilium.conf
```

This sets `rp_filter` to 0 for lxc interfaces (the veth cilium creates for Pods) and **restarts `systemd-sysctl.service`** to apply the configuration.

`rp_filter` (Reverse Path Filtering) is a Linux kernel security mechanism: when a packet arrives on a network interface, the kernel performs a reverse routing lookup to verify "if I were to send a reply to this source IP, would it go out through the same interface?" If not, the packet is dropped, preventing IP spoofing.

Cilium adjusts the `rp_filter` of lxc interfaces to allow return traffic from the host to local Pods. However, in different TKE installation modes, enabling sysctlfix has very different effects.

## Behavior Comparison Between the Two Modes

### Native Routing (VPC-CNI): Must Be Disabled

- **Data path**: Cilium co-exists with VPC-CNI; Pod IPs come from VPC, so **return packets enter through eth0**.
- **Risk**: sysctlfix restarts `systemd-sysctl.service`, which re-applies the OS default configuration. In TKE's OS images, `eth0`'s `rp_filter` defaults to `1` (strict mode). Under strict validation, Pod IPs on eth0 won't match and will be dropped, causing network failures.
- **Conclusion**: **Must disable** sysctlfix:

  ```bash
  --set sysctlfix.enabled=false
  ```

### Overlay: Must Be Enabled (Enabled by Default)

- **Data path**: Pod IPs come from cilium's own CIDR. Cross-node traffic goes through vxlan tunnels; Pod IPs are not visible on eth0, so `eth0`'s `rp_filter=1` does not cause issues.
- **Risk point**: Return traffic from the host to local Pods goes through lxc interfaces, requiring `lxc*.rp_filter=0` — otherwise packets are dropped.
- **Conclusion**: Overlay mode **must enable** sysctlfix (enabled by default, no explicit setting required).

## Decision Summary

| Mode                     | sysctlfix Status | Key Reason                              |
| ------------------------ | ---------------- | --------------------------------------- |
| Native Routing (VPC-CNI) | ❌ Must disable  | Restarting systemd-sysctl resets eth0 configuration |
| Overlay (VPC-CNI / GR)   | ✅ Must enable   | Host → Pod return traffic needs lxc rp_filter=0 |

GR clusters only support Overlay mode; see [Why Not Provide a GR Native Routing Deployment Scheme?](./gr-native-not-recommended.md).

## Troubleshooting

If `cilium-health status` shows localhost endpoint 0/1 (host → Pod unreachable) in Overlay mode, sysctlfix may not have taken effect:

```bash
# Check if all lxc interfaces (including cilium health check interface lxc_health
# and Pod-related lxcXXXX) have rp_filter set to 0
sysctl -a 2>/dev/null | grep 'conf\.lxc.*rp_filter'

# If any entry is not 0, check if the cilium sysctlfix init container ran successfully
kubectl -n kube-system get pod -l k8s-app=cilium -o jsonpath='{.items[0].status.initContainerStatuses}'
```

Troubleshooting approach:

1. If all `lxc*.rp_filter` values are 0 but connectivity still fails → the issue is not with sysctlfix; continue troubleshooting from other paths.
2. If any value is not 0 → the sysctlfix init container may not have run successfully; check init container logs.
3. If init container logs are normal but the sysctl values haven't taken effect → systemd-sysctl.service may have been overridden by another process or script; try `sysctl -w` manually.

## Related Links

- [Installing Cilium](../install.md)
- [Cilium Source - sysctlfix](https://github.com/cilium/cilium/blob/main/daemon/cmd/sysctlfix.go)
- [Linux Kernel rp_filter Documentation](https://www.kernel.org/doc/Documentation/networking/ip-sysctl.txt)

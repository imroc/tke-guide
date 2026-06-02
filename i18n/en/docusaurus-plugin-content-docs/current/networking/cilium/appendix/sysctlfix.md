# Why Native Routing disables sysctlfix while Overlay enables it

## Background

cilium enables a feature called `sysctlfix` by default. It uses an init container to write:

```text
/etc/sysctl.d/99-zzz-override_cilium.conf
```

setting lxc interface `rp_filter` to 0, and **restarts `systemd-sysctl.service`** to apply the change.

`rp_filter` (Reverse Path Filtering) is a Linux kernel security mechanism: when a packet arrives on an interface, the kernel does a reverse route lookup on the source IP to check whether the return path would go out the same interface. If not, the packet is dropped — preventing IP spoofing.

cilium adjusts lxc `rp_filter` so that host → same-node-Pod return traffic isn't blocked. But on TKE, enabling sysctlfix has different consequences across modes.

## Mode-by-mode behavior

### Native Routing (VPC-CNI): Must disable

- **Data path**: cilium coexists with VPC-CNI; Pod IPs come from the VPC, **return packets enter via eth0**.
- **Risk**: sysctlfix restarts `systemd-sysctl.service`, which re-applies OS defaults. TKE OS images default eth0 `rp_filter` to `1` (strict mode) — under which Pod IPs not matching on eth0 are dropped, breaking the network.
- **Decision**: **must disable** sysctlfix:

  ```bash
  --set sysctlfix.enabled=false
  ```

### Overlay: Must enable (enabled by default)

- **Data path**: Pod IPs come from cilium's own CIDR; cross-node traffic goes through vxlan tunnels; Pod IPs are never seen on eth0, so eth0 `rp_filter=1` is fine.
- **Risk point**: host → same-node-Pod return traffic goes through the lxc interface, which requires `lxc*.rp_filter=0` or packets get dropped.
- **Decision**: Overlay mode **must enable** sysctlfix (enabled by default, no explicit setting needed).

## Decision summary

| Mode                     | sysctlfix       | Key reason                                   |
| ------------------------ | --------------- | -------------------------------------------- |
| Native Routing (VPC-CNI) | ❌ Must disable | Restarting systemd-sysctl resets eth0 config |
| Overlay (VPC-CNI / GR)   | ✅ Must enable  | host → Pod return needs lxc rp_filter=0      |

GR clusters only support Overlay mode — see [Why this guide does not offer GR Native Routing](./gr-native-not-recommended.md).

## Troubleshooting

If Overlay mode shows localhost endpoint 0/1 in `cilium-health status` (host → Pod unreachable), sysctlfix likely didn't take effect:

```bash
# Check rp_filter on all lxc interfaces (including cilium's health-check interface lxc_health and Pod interfaces lxcXXXX)
sysctl -a 2>/dev/null | grep 'conf\.lxc.*rp_filter'

# If any are non-zero, check whether the cilium sysctlfix init container ran successfully
kubectl -n kube-system get pod -l k8s-app=cilium -o jsonpath='{.items[0].status.initContainerStatuses}'
```

Diagnosis flow:

1. If all `lxc*.rp_filter` are 0 but still unreachable → not a sysctlfix issue; investigate elsewhere.
2. If non-zero values exist → sysctlfix init container may have failed; check its logs.
3. If init container logs look fine but sysctl values still aren't applied → something else (systemd-sysctl.service or a script) may be overriding it. Test with `sysctl -w` manually.

## See also

- [Install Cilium](../install.md)
- [Cilium Source - sysctlfix](https://github.com/cilium/cilium/blob/main/daemon/cmd/sysctlfix.go)
- [Linux kernel rp_filter docs](https://www.kernel.org/doc/Documentation/networking/ip-sysctl.txt)

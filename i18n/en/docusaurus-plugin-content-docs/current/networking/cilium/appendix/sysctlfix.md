# sysctlfix and rp_filter Deep Dive

Cilium's default-enabled `sysctlfix` causes two classes of problems on TKE, which is why **both installation modes in this guide (Native Routing and Overlay) disable it** (`sysctlfix.enabled=false`). However, the reason for disabling it — and whether a compensation step is needed afterwards — differs per mode:

| Mode                     | Reason for disabling                                            | Compensation needed after disabling?               |
| ------------------------ | --------------------------------------------------------------- | --------------------------------------------------- |
| Native Routing (VPC-CNI) | systemd-sysctl restart resets eth0 to strict, breaking networking outright | No (symmetric routing; lxc rp_filter value is irrelevant) |
| Overlay (VPC-CNI / GR)   | Same (replay clobbers runtime sysctl changes)                   | **Yes**: deploy the `cilium-sysctl-override` DaemonSet |

This article explains the complete mechanism behind these conclusions.

## What sysctlfix does

Cilium enables a feature called `sysctlfix` by default (helm `sysctlfix.enabled`, default `true`): an init container `apply-sysctl-overwrites` performs **two actions** on each node:

1. Writes `/etc/sysctl.d/99-zzz-override_cilium.conf`, setting `rp_filter` to 0 on lxc interfaces (the veths cilium creates for Pods) and friends:

   ```text
   -net.ipv4.conf.lxc*.rp_filter = 0
   -net.ipv4.conf.cilium_*.rp_filter = 0
   net.ipv4.conf.all.rp_filter = 0
   ```

2. **Restarts the host's `systemd-sysctl.service`** to apply the change immediately.

`rp_filter` (Reverse Path Filtering) is a Linux kernel security mechanism: when a packet arrives on an interface, the kernel performs a reverse route lookup to verify "if I were to reply to this source IP, would it go out the same interface?" If not, the packet is dropped to prevent IP spoofing. The **effective rp_filter value = `max(conf.all, conf.<iface>)`** — the larger of the interface's own value and the `all` value.

Writing the file itself is a valuable protection (details below). **The problem is the second action**.

## Problem 1: restarting systemd-sysctl replays ALL distro defaults

Every time `systemd-sysctl.service` starts, it applies **all** `.conf` files under `/usr/lib/sysctl.d/` and `/etc/sysctl.d/` in filename order. The cilium init container runs on every cilium pod start, which means **every cilium pod recreation (node reboot, DS update, pod rescheduling) triggers a full replay** of distro defaults over runtime values.

The TencentOS 4 distro baseline (`/usr/lib/sysctl.d/`):

```text
50-default.conf:  net.ipv4.conf.default.rp_filter = 2 / net.ipv4.conf.*.rp_filter = 2
50-tencentos.conf: net.ipv4.conf.default.rp_filter = 1 / net.ipv4.conf.*.rp_filter = 1
```

The replay harms in two ways:

- **Native Routing (VPC-CNI): outright network outage.** In VPC-CNI shared-ENI multi-IP mode, `tke-eni-agent` sets the NIC's `rp_filter` to `2` (loose, allowing asymmetric routing with policy routing). The sysctlfix-triggered replay resets eth0 back to `1` (strict); asymmetric traffic for auxiliary-ENI IPs is then dropped by strict reverse-path validation and Pod networking breaks. This is why Native mode **must disable** sysctlfix.
- **All modes: runtime sysctl changes are lost.** Any runtime modification not persisted in sysctl.d files (node-pool scripts using `sysctl -w`, manually tuned `nf_conntrack_max`, `somaxconn`, ...) is reset to distro defaults on every replay. Cilium's own interfaces survive thanks to the 99-zzz file (sorted after the distro files), but **sysctl changes made by other components and operators on the node are all clobbered** — and this failure mode is "fine right now, breaks on the next pod restart", which makes it notoriously hard to debug.

## Problem 2: Overlay can't simply turn it off either

Given the harmful restart, can Overlay mode just set `sysctlfix.enabled=false`? **No** — testing shows host → Pod traffic breaks, caused by the combination of two mechanisms:

**Mechanism A: systemd distros' udev rule replays sysctl on every new interface.**

TencentOS 4 (and mainstream systemd distros) ships this udev rule:

```text
ACTION=="add", SUBSYSTEM=="net", KERNEL!="lo",
RUN+="/usr/lib/systemd/systemd-sysctl --prefix=/net/ipv4/conf/$name ..."
```

That is, **whenever a new network interface is created**, udev asynchronously runs `systemd-sysctl --prefix`, applying every sysctl.d entry matching that interface — and the `net.ipv4.conf.*.rp_filter = 1` glob matches every new lxc interface.

The cilium CNI plugin does write `lxc.rp_filter = 0` when creating the Pod veth (source: `DisableRpFilter` in `pkg/datapath/connector/veth.go`), **but the udev application runs afterwards and asynchronously, overriding the 0 back to 1**. Without the 99-zzz file, every new Pod's lxc interface ends up with rp_filter=1.

A cilium-internal detail worth knowing: interfaces created by the **cilium-agent itself** (`cilium_host`, `cilium_net`, `cilium_vxlan`, `lxc_health`) are managed by the agent's internal reconciler, which re-applies desired values every 10 minutes and can self-heal after a udev override. But **Pod veths are created by the CNI plugin process, which writes once and exits** — after a udev override the value **never self-heals**. Restarting the cilium pod doesn't help; only recreating the business Pod triggers another write.

**Mechanism B: Overlay's routing topology makes lxc rp_filter=1 drop packets by design.**

In Overlay mode (without endpointRoutes), Pod IP routes on the node are **aggregated to `cilium_host`**:

```text
$ ip route get 10.244.1.246
10.244.1.246 dev cilium_host src 10.244.1.217
```

When a host → Pod reply packet enters the kernel stack via the lxc interface, rp_filter reverse-looks-up the source IP (the Pod IP) and finds the egress interface is `cilium_host`, not the ingress `lxc` — **the asymmetry is structural, so strict mode drops the packet**. That's why lxc rp_filter **must be 0** in Overlay mode.

This also explains why **Native mode has no such dependency**: Native always enables `endpointRoutes`, giving each Pod IP a per-endpoint `dev lxcXXX scope link` route — the reverse lookup's egress interface is the lxc itself, so **routing is symmetric and rp_filter=1 drops nothing** (the full connectivity-test pass on Native mode in this guide confirms this).

| Mode                   | Pod IP routing                        | host→Pod under lxc rp_filter=1 | Depends on lxc rp_filter=0? |
| ---------------------- | ------------------------------------- | ------------------------------ | ---------------------------- |
| Overlay (VPC-CNI / GR) | aggregated route via `cilium_host`   | ❌ reply dropped (asymmetric)  | **Yes**                      |
| Native (VPC-CNI)       | per-endpoint route via `lxcXXX`      | ✅ works (symmetric)           | No                           |

## Final solution: disable sysctlfix + cilium-sysctl-override DaemonSet

Conclusion: **disable sysctlfix in both modes** (removing the trigger of "every cilium start replays the node's sysctl"), and in Overlay mode let the `cilium-sysctl-override` DaemonSet provide the 99-zzz file protection instead (already built into the [installation guide](../install.md)'s pre-install steps):

| Mode                     | sysctlfix    | 99-zzz override file                  | Notes                                                        |
| ------------------------ | ------------ | ------------------------------------- | ------------------------------------------------------------ |
| Native Routing (VPC-CNI) | ❌ disabled  | not needed                            | symmetric routing; lxc rp_filter=1 is harmless                |
| Overlay (VPC-CNI / GR)   | ❌ disabled  | ✅ maintained by cilium-sysctl-override DaemonSet | identical file content to sysctlfix's, but no systemd-sysctl restart |

This DaemonSet approach gets the best of both worlds:

- **New-interface protection**: once the file exists, udev's per-interface application (Mechanism A) applies `50-*.conf` (=1) first and `99-zzz` (=0) second — every newly created lxc ends up at 0.
- **Replay protection**: any `systemd-sysctl` trigger (node reboot, OS upgrade, manual `sysctl --system`) applies `99-zzz` last thanks to filename ordering, so existing interfaces keep the value 0.
- **No side effects**: `systemd-sysctl.service` is never restarted, no full replay happens, runtime sysctl changes are untouched.
- **Self-healing and scale-out**: the DaemonSet rewrites the file every 60 seconds (survives accidental deletion) and automatically covers newly added nodes.

The only case needing manual attention is migrating an **existing cluster from the old sysctlfix=true setup**: lxc interfaces already on the node may be stuck at the replayed value 1 (the agent doesn't manage rp_filter of existing Pod veths). Fix by rolling-restarting business Pods or running `sudo systemctl restart systemd-sysctl` once on the node (the 99-zzz file now wins the replay).

## Troubleshooting

**Symptom: `cilium-health status` shows localhost endpoint 0/1 (host → local Pod unreachable)**, or kubelet probes (HTTP/TCP) failing en masse, or node processes unable to reach Pod IPs.

In Overlay mode this almost always means some lxc interface has non-zero `rp_filter` (Pod ↔ Pod, ClusterIP and cross-node traffic are unaffected — they use BPF host routing, which forwards directly at the tc layer and bypasses the kernel rp_filter check):

```bash
# 1. Check that every lxc interface's rp_filter is 0 (run on the node or via a hostNetwork pod)
sysctl -a 2>/dev/null | grep 'conf\.lxc.*rp_filter'

# 2. If non-zero, check whether the 99-zzz file exists
ls -l /etc/sysctl.d/ | grep 99-zzz

# 3. Check the cilium-sysctl-override DaemonSet is running
kubectl -n kube-system get pod -l app=cilium-sysctl-override -o wide
```

Flow:

1. **99-zzz file missing** → the cilium-sysctl-override DaemonSet isn't deployed or not ready; deploy it per the [installation guide](../install.md) and wait 60 seconds.
2. **File exists but value still 1** → existing interfaces stuck at a replayed value (typical when migrating from sysctlfix=true); run `sudo systemctl restart systemd-sysctl` on the node so the 99-zzz replay wins, or roll the business Pods.
3. **All zero but still unreachable** → the issue is not rp_filter; continue with other paths (`cilium-health status --verbose`, `hubble observe`).

## References

- [Installing Cilium](../install.md)
- [VPC-CNI Native Routing Details](./native-routing.md)
- [Cilium Source - sysctlfix](https://github.com/cilium/cilium/blob/main/tools/sysctlfix/main.go)
- [Cilium Source - DisableRpFilter](https://github.com/cilium/cilium/blob/main/pkg/datapath/connector/add.go)
- [Linux kernel rp_filter documentation](https://www.kernel.org/doc/Documentation/networking/ip-sysctl.txt)

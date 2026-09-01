# sysctlfix and rp_filter Deep Dive

Cilium's default-enabled `sysctlfix` causes two classes of problems on TKE, which is why **both installation modes in this guide (Native Routing and Overlay) disable it** (`sysctlfix.enabled=false`). However, the reason for disabling it — and whether a compensation step is needed afterwards — differs per mode:

| Mode                     | Reason for disabling                                            | Compensation needed after disabling?               |
| ------------------------ | --------------------------------------------------------------- | --------------------------------------------------- |
| Native Routing (VPC-CNI) | systemd-sysctl restart resets eth0 to strict, breaking networking outright | No (symmetric routing; lxc rp_filter value is irrelevant) |
| Overlay (VPC-CNI / GR)   | Same (replay clobbers runtime sysctl changes)                   | **Yes**: deploy the `cilium-sysctl-override` DaemonSet |

Regardless of mode, if the node runs **other components that depend on non-default sysctl values** — a typical example being the bond NIC in AI-inference RDMA setups, which requires `rp_filter=0` — the full replay triggered by sysctlfix resets them to distro defaults and breaks the workload (see the [victim list](#problem-1-restarting-systemd-sysctl-replays-all-distro-defaults) below).

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

What does the replay break? **The 99-zzz file only protects the three key families cilium writes (lxc*, cilium_*, all); everything else is left exposed** — any setting not persisted in a sysctl.d file is reset to the distro default:

| Victim                            | Typical example                                                                                   | Consequence                                  |
| --------------------------------- | ------------------------------------------------------------------------------------------------- | -------------------------------------------- |
| **NIC settings made by other components** | Native mode's eth0: `tke-eni-agent` sets `rp_filter=2` for VPC-CNI policy routing           | Reset to 1 (strict), **networking breaks**   |
|                                   | AI-inference RDMA bond NIC: multi-node training/inference depends on `bond.rp_filter=0`            | Reset to 1, **RDMA traffic breaks**          |
| **Global sysctl tuning by operators/scripts** | Node-pool scripts using `sysctl -w`: `nf_conntrack_max`, `somaxconn`, `tcp_*`, ...      | Reset to defaults; silent performance regression |

Cilium's own interfaces (lxc*, cilium_*, all) survive because the 99-zzz file sorts after the distro files — **sysctlfix protects itself at the cost of breaking everyone else on the node**.

The full causal chain, using the first row as an example: eth0 reset to `1` (strict) → traffic on asymmetric routes (VPC-CNI auxiliary-ENI policy routing, RDMA bond multipath) fails reverse-path validation → the kernel drops the packets → networking breaks. This is why Native mode **must disable** sysctlfix — and why Overlay + RDMA setups must disable it too.

This failure class is notoriously hard to debug: the trigger is "cilium pod recreation" (node reboot, DS update, pod rescheduling), which has no obvious causal link to the symptom — typically "fine right now, suddenly broken after some cilium update".

## Problem 2: Overlay can't simply turn it off either

Given the harmful restart, can Overlay mode just set `sysctlfix.enabled=false`? **No** — testing shows host → Pod traffic breaks, caused by the combination of two mechanisms:

**Mechanism A: systemd distros' udev rule replays sysctl on every new interface.**

TencentOS 4 (and mainstream systemd distros) ships this udev rule:

```text
ACTION=="add", SUBSYSTEM=="net", KERNEL!="lo",
RUN+="/usr/lib/systemd/systemd-sysctl --prefix=/net/ipv4/conf/$name ..."
```

That is, **whenever a new network interface is created**, udev asynchronously runs `systemd-sysctl --prefix`, applying every sysctl.d entry matching that interface — and the `net.ipv4.conf.*.rp_filter = 1` glob matches every new lxc interface.

The cilium CNI plugin does write `lxc.rp_filter = 0` when creating the Pod veth (source: `DisableRpFilter` in `pkg/datapath/connector/veth.go`), **but the udev application runs afterwards and asynchronously, overriding the 0 back to 1**. Without any override file, every new Pod's lxc interface ends up with rp_filter=1.

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

Conclusion: **disable sysctlfix in both modes** (removing the trigger of "every cilium start replays the node's sysctl"), and in Overlay mode let the `cilium-sysctl-override` DaemonSet provide the rp_filter protection instead — with even broader coverage than sysctlfix's own file (already built into the [installation guide](../install.md)'s pre-install steps):

| Mode                     | sysctlfix    | cilium-sysctl-override DaemonSet      | Notes                                       |
| ------------------------ | ------------ | ------------------------------------- | ------------------------------------------- |
| Native Routing (VPC-CNI) | ❌ disabled  | not needed (optional, see below)      | symmetric routing; lxc rp_filter=1 is harmless |
| Overlay (VPC-CNI / GR)   | ❌ disabled  | ✅ required: rp_filter=0 on ALL interfaces | no systemd-sysctl restart, no replay side effects |

**The DaemonSet goes one step further than sysctlfix: instead of a cilium-specific override (lxc*/cilium_*), it pins `rp_filter=0` on ALL node interfaces** (three keys: `all`/`default`/`*`). Cilium interfaces, VPC-CNI policy-routing eth*, and AI-inference RDMA bond NICs are all covered in one shot, with three layers of protection:

1. **Persisted file** (`/etc/sysctl.d/99-zzz-rp-filter.conf`): the filename sorts after the distro configs (`50-*.conf`), so every sysctl replay trigger (node reboot, OS upgrade, manual `sysctl --system`) ends with 0 winning; the udev per-interface application on every new interface (Mechanism A) also ends with this file — and new interfaces additionally inherit `default=0` as their kernel initial value. Double coverage.
2. **Immediate application** (direct writes to `/proc/sys`): the file alone only takes effect on the next systemd-sysctl run, so every DaemonSet loop also writes existing interfaces (including bond, eth*) to 0 immediately.
3. **Periodic self-healing** (every 60 seconds): externally changed values and deleted files are corrected on the next loop; newly added nodes are covered automatically.

The DaemonSet also cleans up the legacy `99-zzz-override_cilium.conf` left by the old sysctlfix (its content is subsumed by the all-interfaces version).

Disabling rp_filter node-wide is a safe convention on K8s nodes (cilium's own recommendation for kube-proxy-free mode): multi-interface routing (veth/vxlan/policy routes/bond) is inherently asymmetric and strict rp_filter only causes collateral damage; source validation is handled by cilium's BPF layer and VPC security groups.

Native mode doesn't depend on this DaemonSet (symmetric routing), but if the node runs components requiring `rp_filter=0` (e.g. RDMA bond NICs), deploying the same DaemonSet provides the same all-interface immunity (verified that `tke-eni-agent` does not periodically rewrite eth0, so there is no override fight).

The only case needing manual attention is migrating an **existing cluster from the old sysctlfix=true setup**: lxc interfaces already on the node may be stuck at the replayed value 1 (the agent doesn't manage rp_filter of existing Pod veths). Fix by rolling-restarting business Pods or running `sudo systemctl restart systemd-sysctl` once on the node (the 99-zzz file now wins the replay).

:::tip[AI-inference RDMA scenarios (bond NICs requiring rp_filter=0)]

The `cilium-sysctl-override` DaemonSet deployed in Overlay mode already pins **all node interfaces** to 0, so bond NICs are covered natively — when a bond is created, the udev application ends with `99-zzz-rp-filter.conf` (verified: a freshly created bond0 lands on 0 immediately), the value survives external replays, and the "cilium replay breaks the bond NIC" problem is eliminated at the root.

The full matrix verified on TencentOS 4.4 + cilium 1.20.1: existing interfaces zeroed immediately; newly created bond and Pod lxc both 0; all values held at 0 after a manual `systemctl restart systemd-sysctl`; manual corruption self-healed within 60 seconds; after a node reboot all interfaces were 0 with the file intact; host→Pod / cross-node / cilium-health all green.

:::

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
2. **File exists but value still 1** → the DaemonSet self-heals by writing `/proc/sys` every 60 seconds, so a persistent 1 means the DS pod isn't running properly: check `kubectl -n kube-system get pod -l app=cilium-sysctl-override` (Running? configured with `privileged: true`? otherwise `/proc/sys` is read-only and the pod CrashLoops).
3. **All zero but still unreachable** → the issue is not rp_filter; continue with other paths (`cilium-health status --verbose`, `hubble observe`).

## References

- [Installing Cilium](../install.md)
- [VPC-CNI Native Routing Details](./native-routing.md)
- [Cilium Source - sysctlfix](https://github.com/cilium/cilium/blob/main/tools/sysctlfix/main.go)
- [Cilium Source - DisableRpFilter](https://github.com/cilium/cilium/blob/main/pkg/datapath/connector/add.go)
- [Linux kernel rp_filter documentation](https://www.kernel.org/doc/Documentation/networking/ip-sysctl.txt)

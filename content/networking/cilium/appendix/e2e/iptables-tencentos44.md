# iptables 模式 + TencentOS 4.4

## 功能测试

- 测试命令：`cilium connectivity test`
- 耗时：58m
- 测试报告：11/77 tests failed (39/794 actions), 46 tests skipped, 2 scenarios skipped

```bash
╰─ time cilium connectivity test
ℹ  Monitor aggregation detected, will skip some flow validation steps
ℹ  Skipping tests that require a node Without Cilium
⌛ [cls-cj61w10e] Waiting for deployment cilium-test-1/client to become ready...
⌛ [cls-cj61w10e] Waiting for deployment cilium-test-1/client2 to become ready...
⌛ [cls-cj61w10e] Waiting for deployment cilium-test-1/echo-same-node to become ready...
⌛ [cls-cj61w10e] Waiting for deployment cilium-test-1/client3 to become ready...
⌛ [cls-cj61w10e] Waiting for deployment cilium-test-1/echo-other-node to become ready...
⌛ [cls-cj61w10e] Waiting for pod cilium-test-1/client-645b68dcf7-w7kcn to reach DNS server on cilium-test-1/echo-same-node-798cc5d967-jh4jv pod...
⌛ [cls-cj61w10e] Waiting for pod cilium-test-1/client2-66475877c6-bghj6 to reach DNS server on cilium-test-1/echo-same-node-798cc5d967-jh4jv pod...
⌛ [cls-cj61w10e] Waiting for pod cilium-test-1/client3-795488bf5-68xdx to reach DNS server on cilium-test-1/echo-same-node-798cc5d967-jh4jv pod...
⌛ [cls-cj61w10e] Waiting for pod cilium-test-1/client-645b68dcf7-w7kcn to reach DNS server on cilium-test-1/echo-other-node-689b8c9477-rvkw4 pod...
⌛ [cls-cj61w10e] Waiting for pod cilium-test-1/client2-66475877c6-bghj6 to reach DNS server on cilium-test-1/echo-other-node-689b8c9477-rvkw4 pod...
⌛ [cls-cj61w10e] Waiting for pod cilium-test-1/client3-795488bf5-68xdx to reach DNS server on cilium-test-1/echo-other-node-689b8c9477-rvkw4 pod...
⌛ [cls-cj61w10e] Waiting for pod cilium-test-1/client-645b68dcf7-w7kcn to reach default/kubernetes service...
⌛ [cls-cj61w10e] Waiting for pod cilium-test-1/client2-66475877c6-bghj6 to reach default/kubernetes service...
⌛ [cls-cj61w10e] Waiting for pod cilium-test-1/client3-795488bf5-68xdx to reach default/kubernetes service...
⌛ [cls-cj61w10e] Waiting for Service cilium-test-1/echo-other-node to become ready...
⌛ [cls-cj61w10e] Waiting for Service cilium-test-1/echo-other-node to be synchronized by Cilium pod kube-system/cilium-nrksx
⌛ [cls-cj61w10e] Waiting for Service cilium-test-1/echo-other-node to be synchronized by Cilium pod kube-system/cilium-w8fc7
⌛ [cls-cj61w10e] Waiting for Service cilium-test-1/echo-same-node to become ready...
⌛ [cls-cj61w10e] Waiting for Service cilium-test-1/echo-same-node to be synchronized by Cilium pod kube-system/cilium-nrksx
⌛ [cls-cj61w10e] Waiting for Service cilium-test-1/echo-same-node to be synchronized by Cilium pod kube-system/cilium-w8fc7
⌛ [cls-cj61w10e] Waiting for NodePort 172.22.48.37:32291 (cilium-test-1/echo-other-node) to become ready...
⌛ [cls-cj61w10e] Waiting for NodePort 172.22.48.37:31722 (cilium-test-1/echo-same-node) to become ready...
⌛ [cls-cj61w10e] Waiting for NodePort 172.22.48.29:32291 (cilium-test-1/echo-other-node) to become ready...
⌛ [cls-cj61w10e] Waiting for NodePort 172.22.48.29:31722 (cilium-test-1/echo-same-node) to become ready...
⌛ [cls-cj61w10e] Waiting for NodePort 172.22.48.43:32291 (cilium-test-1/echo-other-node) to become ready...
⌛ [cls-cj61w10e] Waiting for NodePort 172.22.48.43:31722 (cilium-test-1/echo-same-node) to become ready...
⌛ [cls-cj61w10e] Waiting for DaemonSet cilium-test-1/host-netns-non-cilium to become ready...
⌛ [cls-cj61w10e] Waiting for DaemonSet cilium-test-1/host-netns to become ready...
ℹ  Skipping IPCache check
🔭 Enabling Hubble telescope...
⚠  Unable to contact Hubble Relay, disabling Hubble telescope and flow validation: rpc error: code = Unavailable desc = connection error: desc = "transport: Error while dialing: dial tcp [::1]:4245: connect: connection refused"
ℹ  Expose Relay locally with:
   cilium hubble enable
   cilium hubble port-forward&
ℹ  Cilium version: 1.18.2
🏃[cilium-test-1] Running 123 tests ...
[=] [cilium-test-1] Test [no-policies] [1/123]
..................................................................
[=] [cilium-test-1] Skipping test [no-policies-from-outside] [2/123] (skipped by condition)
[=] [cilium-test-1] Test [no-policies-extra] [3/123]
........................................................................
[=] [cilium-test-1] Test [allow-all-except-world] [4/123]
.............................................
[=] [cilium-test-1] Test [client-ingress] [5/123]
......
[=] [cilium-test-1] Test [client-ingress-knp] [6/123]
......
[=] [cilium-test-1] Test [allow-all-with-metrics-check] [7/123]
......
[=] [cilium-test-1] Test [all-ingress-deny] [8/123]
............
[=] [cilium-test-1] Skipping test [all-ingress-deny-from-outside] [9/123] (skipped by condition)
[=] [cilium-test-1] Test [all-ingress-deny-knp] [10/123]
............
[=] [cilium-test-1] Test [all-egress-deny] [11/123]
........................
[=] [cilium-test-1] Test [all-egress-deny-knp] [12/123]
........................
[=] [cilium-test-1] Test [all-entities-deny] [13/123]
............
[=] [cilium-test-1] Test [cluster-entity] [14/123]
...
[=] [cilium-test-1] Skipping test [cluster-entity-multi-cluster] [15/123] (skipped by condition)
[=] [cilium-test-1] Test [host-entity-egress] [16/123]
...........................
[=] [cilium-test-1] Test [host-entity-ingress] [17/123]
......
[=] [cilium-test-1] Test [echo-ingress] [18/123]
......
[=] [cilium-test-1] Skipping test [echo-ingress-from-outside] [19/123] (skipped by condition)
[=] [cilium-test-1] Test [echo-ingress-knp] [20/123]
......
[=] [cilium-test-1] Test [client-ingress-icmp] [21/123]
......
[=] [cilium-test-1] Test [client-egress] [22/123]
......
[=] [cilium-test-1] Test [client-egress-knp] [23/123]
......
[=] [cilium-test-1] Test [client-egress-expression] [24/123]
......
[=] [cilium-test-1] Test [client-egress-expression-port-range] [25/123]
......
[=] [cilium-test-1] Test [client-egress-expression-knp] [26/123]
......
[=] [cilium-test-1] Test [client-egress-expression-knp-port-range] [27/123]
......
[=] [cilium-test-1] Test [client-with-service-account-egress-to-echo] [28/123]
......
[=] [cilium-test-1] Test [client-with-service-account-egress-to-echo-port-range] [29/123]
......
[=] [cilium-test-1] Test [client-egress-to-echo-service-account] [30/123]
......
[=] [cilium-test-1] Test [client-egress-to-echo-service-account-port-range] [31/123]
......
[=] [cilium-test-1] Test [to-entities-world] [32/123]
.........
[=] [cilium-test-1] Test [to-entities-world-port-range] [33/123]
.........
[=] [cilium-test-1] Test [to-cidr-external] [34/123]
......
[=] [cilium-test-1] Test [to-cidr-external-knp] [35/123]
......
[=] [cilium-test-1] Skipping test [seq-from-cidr-host-netns] [36/123] (skipped by condition)
[=] [cilium-test-1] Test [echo-ingress-from-other-client-deny] [37/123]
..........
[=] [cilium-test-1] Test [client-ingress-from-other-client-icmp-deny] [38/123]
............
[=] [cilium-test-1] Test [client-egress-to-echo-deny] [39/123]
............
[=] [cilium-test-1] Test [client-egress-to-echo-deny-port-range] [40/123]
............
[=] [cilium-test-1] Test [client-ingress-to-echo-named-port-deny] [41/123]
....
[=] [cilium-test-1] Test [client-egress-to-echo-expression-deny] [42/123]
....
[=] [cilium-test-1] Test [client-egress-to-echo-expression-deny-port-range] [43/123]
....
[=] [cilium-test-1] Test [client-with-service-account-egress-to-echo-deny] [44/123]
....
[=] [cilium-test-1] Test [client-with-service-account-egress-to-echo-deny-port-range] [45/123]
....
[=] [cilium-test-1] Test [client-egress-to-echo-service-account-deny] [46/123]
..
[=] [cilium-test-1] Test [client-egress-to-echo-service-account-deny-port-range] [47/123]
..
[=] [cilium-test-1] Test [client-egress-to-cidr-deny] [48/123]
......
[=] [cilium-test-1] Test [client-egress-to-cidrgroup-deny] [49/123]
I1011 14:31:05.410336  195734 warnings.go:110] "Warning: cilium.io/v2alpha1 CiliumCIDRGroup is deprecated; use cilium.io/v2 CiliumCIDRGroup"
I1011 14:31:05.588550  195734 warnings.go:110] "Warning: cilium.io/v2alpha1 CiliumCIDRGroup is deprecated; use cilium.io/v2 CiliumCIDRGroup"
......
I1011 14:31:28.210833  195734 warnings.go:110] "Warning: cilium.io/v2alpha1 CiliumCIDRGroup is deprecated; use cilium.io/v2 CiliumCIDRGroup"
[=] [cilium-test-1] Test [client-egress-to-cidrgroup-deny-by-label] [50/123]
I1011 14:31:34.333033  195734 warnings.go:110] "Warning: cilium.io/v2alpha1 CiliumCIDRGroup is deprecated; use cilium.io/v2 CiliumCIDRGroup"
I1011 14:31:34.672421  195734 warnings.go:110] "Warning: cilium.io/v2alpha1 CiliumCIDRGroup is deprecated; use cilium.io/v2 CiliumCIDRGroup"
......
I1011 14:31:47.502301  195734 warnings.go:110] "Warning: cilium.io/v2alpha1 CiliumCIDRGroup is deprecated; use cilium.io/v2 CiliumCIDRGroup"
[=] [cilium-test-1] Test [client-egress-to-cidr-deny-default] [51/123]
......
[=] [cilium-test-1] Skipping test [clustermesh-endpointslice-sync] [52/123] (skipped by condition)
[=] [cilium-test-1] Skipping test [health] [53/123] (Feature health-checking is disabled)
[=] [cilium-test-1] Skipping test [north-south-loadbalancing] [54/123] (Feature node-without-cilium is disabled)
[=] [cilium-test-1] Skipping test [pod-to-pod-encryption] [55/123] (skipped by condition)
[=] [cilium-test-1] Skipping test [pod-to-pod-with-l7-policy-encryption] [56/123] (skipped by condition)
[=] [cilium-test-1] Test [pod-to-pod-encryption-v2] [57/123]
.
[=] [cilium-test-1] Skipping test [pod-to-pod-with-l7-policy-encryption-v2] [58/123] (Feature encryption-pod is disabled)
[=] [cilium-test-1] Test [node-to-node-encryption] [59/123]
...
[=] [cilium-test-1] Skipping test [seq-egress-gateway] [60/123] (skipped by condition)
[=] [cilium-test-1] Skipping test [seq-egress-gateway-multigateway] [61/123] (skipped by condition)
[=] [cilium-test-1] Skipping test [egress-gateway-excluded-cidrs] [62/123] (Feature enable-egress-gateway is disabled)
[=] [cilium-test-1] Skipping test [seq-egress-gateway-with-l7-policy] [63/123] (skipped by condition)
[=] [cilium-test-1] Skipping test [pod-to-node-cidrpolicy] [64/123] (Feature cidr-match-nodes is disabled)
[=] [cilium-test-1] Skipping test [north-south-loadbalancing-with-l7-policy] [65/123] (Feature node-without-cilium is disabled)
[=] [cilium-test-1] Skipping test [north-south-loadbalancing-with-l7-policy-port-range] [66/123] (Feature node-without-cilium is disabled)
[=] [cilium-test-1] Test [echo-ingress-l7] [67/123]
..................
[=] [cilium-test-1] Test [echo-ingress-l7-via-hostport] [68/123]

[=] [cilium-test-1] Test [echo-ingress-l7-named-port] [69/123]
..................
[=] [cilium-test-1] Test [client-egress-l7-method] [70/123]
..................
[=] [cilium-test-1] Test [client-egress-l7-method-port-range] [71/123]
..................
[=] [cilium-test-1] Test [client-egress-l7] [72/123]
.......
  ℹ  curl stdout:
  172.22.48.13:54458 -> 1.1.1.1:80 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-only-dns' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-l7-http' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  [-] Scenario [client-egress-l7/pod-to-pod]
  [.] Action [client-egress-l7/pod-to-pod:curl-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> cilium-test-1/echo-other-node-689b8c9477-rvkw4 (172.22.48.12:8080)]
  [.] Action [client-egress-l7/pod-to-pod:curl-ipv4-1: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> cilium-test-1/echo-same-node-798cc5d967-jh4jv (172.22.48.14:8080)]
  [.] Action [client-egress-l7/pod-to-pod:curl-ipv4-2: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> cilium-test-1/echo-other-node-689b8c9477-rvkw4 (172.22.48.12:8080)]
  [.] Action [client-egress-l7/pod-to-pod:curl-ipv4-3: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> cilium-test-1/echo-same-node-798cc5d967-jh4jv (172.22.48.14:8080)]
  [.] Action [client-egress-l7/pod-to-pod:curl-ipv4-4: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> cilium-test-1/echo-other-node-689b8c9477-rvkw4 (172.22.48.12:8080)]
  [.] Action [client-egress-l7/pod-to-pod:curl-ipv4-5: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> cilium-test-1/echo-same-node-798cc5d967-jh4jv (172.22.48.14:8080)]
  [-] Scenario [client-egress-l7/pod-to-world]
  [.] Action [client-egress-l7/pod-to-world:http-to-one.one.one.one.-ipv4-0: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-http (one.one.one.one.:80)]
  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --retry 3 --retry-all-errors --retry-delay 3 http://one.one.one.one.:80" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
  [.] Action [client-egress-l7/pod-to-world:https-to-one.one.one.one.-ipv4-0: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443)]
.  [.] Action [client-egress-l7/pod-to-world:https-to-one.one.one.one.-index-ipv4-0: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  [.] Action [client-egress-l7/pod-to-world:http-to-one.one.one.one.-ipv4-1: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-http (one.one.one.one.:80)]
.  [.] Action [client-egress-l7/pod-to-world:https-to-one.one.one.one.-ipv4-1: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443)]
.  [.] Action [client-egress-l7/pod-to-world:https-to-one.one.one.one.-index-ipv4-1: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  [.] Action [client-egress-l7/pod-to-world:http-to-one.one.one.one.-ipv4-2: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-http (one.one.one.one.:80)]
.  [.] Action [client-egress-l7/pod-to-world:https-to-one.one.one.one.-ipv4-2: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443)]
.  [.] Action [client-egress-l7/pod-to-world:https-to-one.one.one.one.-index-ipv4-2: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-only-dns' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-l7-http' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
[=] [cilium-test-1] Test [client-egress-l7-port-range] [73/123]
..........
  ℹ  curl stdout:
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-only-dns' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-l7-http-port-range' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  [-] Scenario [client-egress-l7-port-range/pod-to-pod]
  [.] Action [client-egress-l7-port-range/pod-to-pod:curl-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> cilium-test-1/echo-other-node-689b8c9477-rvkw4 (172.22.48.12:8080)]
  [.] Action [client-egress-l7-port-range/pod-to-pod:curl-ipv4-1: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> cilium-test-1/echo-same-node-798cc5d967-jh4jv (172.22.48.14:8080)]
  [.] Action [client-egress-l7-port-range/pod-to-pod:curl-ipv4-2: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> cilium-test-1/echo-other-node-689b8c9477-rvkw4 (172.22.48.12:8080)]
  [.] Action [client-egress-l7-port-range/pod-to-pod:curl-ipv4-3: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> cilium-test-1/echo-same-node-798cc5d967-jh4jv (172.22.48.14:8080)]
  [.] Action [client-egress-l7-port-range/pod-to-pod:curl-ipv4-4: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> cilium-test-1/echo-other-node-689b8c9477-rvkw4 (172.22.48.12:8080)]
  [.] Action [client-egress-l7-port-range/pod-to-pod:curl-ipv4-5: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> cilium-test-1/echo-same-node-798cc5d967-jh4jv (172.22.48.14:8080)]
  [-] Scenario [client-egress-l7-port-range/pod-to-world]
  [.] Action [client-egress-l7-port-range/pod-to-world:http-to-one.one.one.one.-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-http (one.one.one.one.:80)]
  [.] Action [client-egress-l7-port-range/pod-to-world:https-to-one.one.one.one.-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443)]
  [.] Action [client-egress-l7-port-range/pod-to-world:https-to-one.one.one.one.-index-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https-index (one.one.one.one.:443)]
  [.] Action [client-egress-l7-port-range/pod-to-world:http-to-one.one.one.one.-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-http (one.one.one.one.:80)]
  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --retry 3 --retry-all-errors --retry-delay 3 http://one.one.one.one.:80" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
  172.22.48.13:44398 -> 1.1.1.1:80 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  [.] Action [client-egress-l7-port-range/pod-to-world:https-to-one.one.one.one.-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443)]
.  [.] Action [client-egress-l7-port-range/pod-to-world:https-to-one.one.one.one.-index-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  [.] Action [client-egress-l7-port-range/pod-to-world:http-to-one.one.one.one.-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-http (one.one.one.one.:80)]
.  [.] Action [client-egress-l7-port-range/pod-to-world:https-to-one.one.one.one.-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443)]
.  [.] Action [client-egress-l7-port-range/pod-to-world:https-to-one.one.one.one.-index-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-only-dns' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-l7-http-port-range' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
[=] [cilium-test-1] Test [client-egress-l7-named-port] [74/123]
..........
  ℹ  curl stdout:
    ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-only-dns' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-l7-http-named-port' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  [-] Scenario [client-egress-l7-named-port/pod-to-pod]
  [.] Action [client-egress-l7-named-port/pod-to-pod:curl-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> cilium-test-1/echo-other-node-689b8c9477-rvkw4 (172.22.48.12:8080)]
  [.] Action [client-egress-l7-named-port/pod-to-pod:curl-ipv4-1: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> cilium-test-1/echo-same-node-798cc5d967-jh4jv (172.22.48.14:8080)]
  [.] Action [client-egress-l7-named-port/pod-to-pod:curl-ipv4-2: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> cilium-test-1/echo-other-node-689b8c9477-rvkw4 (172.22.48.12:8080)]
  [.] Action [client-egress-l7-named-port/pod-to-pod:curl-ipv4-3: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> cilium-test-1/echo-same-node-798cc5d967-jh4jv (172.22.48.14:8080)]
  [.] Action [client-egress-l7-named-port/pod-to-pod:curl-ipv4-4: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> cilium-test-1/echo-same-node-798cc5d967-jh4jv (172.22.48.14:8080)]
  [.] Action [client-egress-l7-named-port/pod-to-pod:curl-ipv4-5: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> cilium-test-1/echo-other-node-689b8c9477-rvkw4 (172.22.48.12:8080)]
  [-] Scenario [client-egress-l7-named-port/pod-to-world]
  [.] Action [client-egress-l7-named-port/pod-to-world:http-to-one.one.one.one.-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-http (one.one.one.one.:80)]
  [.] Action [client-egress-l7-named-port/pod-to-world:https-to-one.one.one.one.-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443)]
  [.] Action [client-egress-l7-named-port/pod-to-world:https-to-one.one.one.one.-index-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https-index (one.one.one.one.:443)]
  [.] Action [client-egress-l7-named-port/pod-to-world:http-to-one.one.one.one.-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-http (one.one.one.one.:80)]
  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --retry 3 --retry-all-errors --retry-delay 3 http://one.one.one.one.:80" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
172.22.48.13:49008 -> 1.1.1.1:80 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  [.] Action [client-egress-l7-named-port/pod-to-world:https-to-one.one.one.one.-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443)]
.  [.] Action [client-egress-l7-named-port/pod-to-world:https-to-one.one.one.one.-index-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  [.] Action [client-egress-l7-named-port/pod-to-world:http-to-one.one.one.one.-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-http (one.one.one.one.:80)]
.  [.] Action [client-egress-l7-named-port/pod-to-world:https-to-one.one.one.one.-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443)]
.  [.] Action [client-egress-l7-named-port/pod-to-world:https-to-one.one.one.one.-index-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-only-dns' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-l7-http-named-port' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
[=] [cilium-test-1] Test [client-egress-tls-sni] [75/123]
..
  ℹ  curl stdout:
  172.22.48.13:33556 -> 1.1.1.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-tls-sni' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-only-dns' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  [-] Scenario [client-egress-tls-sni/pod-to-world]
  [.] Action [client-egress-tls-sni/pod-to-world:http-to-one.one.one.one.-ipv4-0: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-http (one.one.one.one.:80)]
  [.] Action [client-egress-tls-sni/pod-to-world:https-to-one.one.one.one.-ipv4-0: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443)]
  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 28
  [.] Action [client-egress-tls-sni/pod-to-world:https-to-one.one.one.one.-index-ipv4-0: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.13:33562 -> 1.1.1.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  [.] Action [client-egress-tls-sni/pod-to-world:http-to-one.one.one.one.-ipv4-1: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-http (one.one.one.one.:80)]
.  [.] Action [client-egress-tls-sni/pod-to-world:https-to-one.one.one.one.-ipv4-1: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.11:42242 -> 1.1.1.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  [.] Action [client-egress-tls-sni/pod-to-world:https-to-one.one.one.one.-index-ipv4-1: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.11:42252 -> 1.1.1.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  [.] Action [client-egress-tls-sni/pod-to-world:http-to-one.one.one.one.-ipv4-2: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-http (one.one.one.one.:80)]
.  [.] Action [client-egress-tls-sni/pod-to-world:https-to-one.one.one.one.-ipv4-2: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.10:37478 -> 1.1.1.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  [.] Action [client-egress-tls-sni/pod-to-world:https-to-one.one.one.one.-index-ipv4-2: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.10:53780 -> 1.0.0.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-tls-sni' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-only-dns' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
[=] [cilium-test-1] Test [client-egress-tls-sni-denied] [76/123]
.........
[=] [cilium-test-1] Test [client-egress-tls-sni-wildcard] [77/123]
..
  ℹ  curl stdout:
  172.22.48.10:56068 -> 1.1.1.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  [.] Action [client-egress-tls-sni-wildcard/pod-to-world:https-to-one.one.one.one.-index-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https-index (one.one.one.one.:443)]
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-tls-sni-wildcard' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-only-dns' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  [-] Scenario [client-egress-tls-sni-wildcard/pod-to-world]
  [.] Action [client-egress-tls-sni-wildcard/pod-to-world:http-to-one.one.one.one.-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-http (one.one.one.one.:80)]
  [.] Action [client-egress-tls-sni-wildcard/pod-to-world:https-to-one.one.one.one.-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443)]
  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 28
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.10:56072 -> 1.1.1.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  [.] Action [client-egress-tls-sni-wildcard/pod-to-world:http-to-one.one.one.one.-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-http (one.one.one.one.:80)]
.  [.] Action [client-egress-tls-sni-wildcard/pod-to-world:https-to-one.one.one.one.-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.13:53212 -> 1.0.0.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  [.] Action [client-egress-tls-sni-wildcard/pod-to-world:https-to-one.one.one.one.-index-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.13:35972 -> 1.0.0.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  [.] Action [client-egress-tls-sni-wildcard/pod-to-world:http-to-one.one.one.one.-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-http (one.one.one.one.:80)]
.  [.] Action [client-egress-tls-sni-wildcard/pod-to-world:https-to-one.one.one.one.-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.11:34798 -> 1.1.1.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  [.] Action [client-egress-tls-sni-wildcard/pod-to-world:https-to-one.one.one.one.-index-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.11:34426 -> 1.0.0.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-tls-sni-wildcard' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-only-dns' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
[=] [cilium-test-1] Test [client-egress-tls-sni-wildcard-denied] [78/123]
...
[=] [cilium-test-1] Test [client-egress-tls-sni-double-wildcard] [79/123]
..
  ℹ  curl stdout:
  172.22.48.11:49042 -> 1.1.1.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-tls-sni-double-wildcard' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-only-dns' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  [-] Scenario [client-egress-tls-sni-double-wildcard/pod-to-world]
  [.] Action [client-egress-tls-sni-double-wildcard/pod-to-world:http-to-one.one.one.one.-ipv4-0: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-http (one.one.one.one.:80)]
  [.] Action [client-egress-tls-sni-double-wildcard/pod-to-world:https-to-one.one.one.one.-ipv4-0: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443)]
  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 28
  [.] Action [client-egress-tls-sni-double-wildcard/pod-to-world:https-to-one.one.one.one.-index-ipv4-0: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.11:38042 -> 1.0.0.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  [.] Action [client-egress-tls-sni-double-wildcard/pod-to-world:http-to-one.one.one.one.-ipv4-1: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-http (one.one.one.one.:80)]
.  [.] Action [client-egress-tls-sni-double-wildcard/pod-to-world:https-to-one.one.one.one.-ipv4-1: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.10:58520 -> 1.1.1.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  [.] Action [client-egress-tls-sni-double-wildcard/pod-to-world:https-to-one.one.one.one.-index-ipv4-1: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.10:47244 -> 1.0.0.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  [.] Action [client-egress-tls-sni-double-wildcard/pod-to-world:http-to-one.one.one.one.-ipv4-2: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-http (one.one.one.one.:80)]
.  [.] Action [client-egress-tls-sni-double-wildcard/pod-to-world:https-to-one.one.one.one.-ipv4-2: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.13:56600 -> 1.1.1.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  [.] Action [client-egress-tls-sni-double-wildcard/pod-to-world:https-to-one.one.one.one.-index-ipv4-2: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.13:42362 -> 1.0.0.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-tls-sni-double-wildcard' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-only-dns' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
[=] [cilium-test-1] Test [client-egress-tls-sni-double-wildcard-denied] [80/123]
...
[=] [cilium-test-1] Test [client-egress-l7-tls-headers-sni] [81/123]
.
  ℹ  curl stdout:
  172.22.48.10:44424 -> 1.0.0.1:443 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503

  [.] Action [client-egress-l7-tls-headers-sni/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443)]
  ℹ  📜 Applying secret 'externaltarget-tls' to namespace 'cilium-test-1'..
  ℹ  📜 Applying secret 'cabundle' to namespace 'cilium-test-1'..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-l7-tls-sni' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-only-dns' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  [-] Scenario [client-egress-l7-tls-headers-sni/pod-to-world-with-tls-intercept]
  [.] Action [client-egress-l7-tls-headers-sni/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443)]
  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 22
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
  ℹ  curl stdout:
  172.22.48.13:43900 -> 1.1.1.1:443 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503

  [.] Action [client-egress-l7-tls-headers-sni/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 22
  ℹ  curl stdout:
  172.22.48.11:48990 -> 1.0.0.1:443 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503

  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-l7-tls-sni' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-only-dns' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Deleting secret 'cabundle' from namespace 'cilium-test-1'..
  ℹ  📜 Deleting secret 'externaltarget-tls' from namespace 'cilium-test-1'..
[=] [cilium-test-1] Test [client-egress-l7-tls-headers-other-sni] [82/123]
...
[=] [cilium-test-1] Test [client-egress-l7-set-header] [83/123]
......
[=] [cilium-test-1] Test [client-egress-l7-set-header-port-range] [84/123]
......
[=] [cilium-test-1] Skipping test [echo-ingress-auth-always-fail] [85/123] (Feature mutual-auth-spiffe is disabled)
[=] [cilium-test-1] Skipping test [echo-ingress-auth-always-fail-port-range] [86/123] (Feature mutual-auth-spiffe is disabled)
[=] [cilium-test-1] Skipping test [echo-ingress-mutual-auth-spiffe] [87/123] (Feature mutual-auth-spiffe is disabled)
[=] [cilium-test-1] Skipping test [echo-ingress-mutual-auth-spiffe-port-range] [88/123] (Feature mutual-auth-spiffe is disabled)
[=] [cilium-test-1] Skipping test [pod-to-ingress-service] [89/123] (Feature ingress-controller is disabled)
[=] [cilium-test-1] Skipping test [pod-to-ingress-service-allow-ingress-identity] [90/123] (Feature ingress-controller is disabled)
[=] [cilium-test-1] Skipping test [pod-to-ingress-service-deny-all] [91/123] (Feature ingress-controller is disabled)
[=] [cilium-test-1] Skipping test [pod-to-ingress-service-deny-backend-service] [92/123] (Feature ingress-controller is disabled)
[=] [cilium-test-1] Skipping test [pod-to-ingress-service-deny-ingress-identity] [93/123] (Feature ingress-controller is disabled)
[=] [cilium-test-1] Skipping test [pod-to-ingress-service-deny-source-egress-other-node] [94/123] (Feature ingress-controller is disabled)
[=] [cilium-test-1] Skipping test [outside-to-ingress-service] [95/123] (Feature ingress-controller is disabled)
[=] [cilium-test-1] Skipping test [outside-to-ingress-service-deny-all-ingress] [96/123] (Feature ingress-controller is disabled)
[=] [cilium-test-1] Skipping test [outside-to-ingress-service-deny-cidr] [97/123] (Feature ingress-controller is disabled)
[=] [cilium-test-1] Skipping test [outside-to-ingress-service-deny-world-identity] [98/123] (Feature ingress-controller is disabled)
[=] [cilium-test-1] Skipping test [l7-lb] [99/123] (Feature loadbalancer-l7 is disabled)
[=] [cilium-test-1] Test [dns-only] [100/123]
...^...........
[=] [cilium-test-1] Test [to-fqdns] [101/123]
............
[=] [cilium-test-1] Test [to-fqdns-with-proxy] [102/123]
.
  ℹ  curl stdout:
  172.22.48.11:46982 -> 1.0.0.1:80 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  [.] Action [to-fqdns-with-proxy/pod-to-world:https-to-one.one.one.one.-ipv4-0: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443)]
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-to-fqdns-one.one.one.one' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-only-dns' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  [-] Scenario [to-fqdns-with-proxy/pod-to-world]
  [.] Action [to-fqdns-with-proxy/pod-to-world:http-to-one.one.one.one.-ipv4-0: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-http (one.one.one.one.:80)]
  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --retry 3 --retry-all-errors --retry-delay 3 http://one.one.one.one.:80" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 22
.  [.] Action [to-fqdns-with-proxy/pod-to-world:https-to-one.one.one.one.-index-ipv4-0: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  [.] Action [to-fqdns-with-proxy/pod-to-world:http-to-one.one.one.one.-ipv4-1: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-http (one.one.one.one.:80)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --retry 3 --retry-all-errors --retry-delay 3 http://one.one.one.one.:80" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 22
  ℹ  curl stdout:
  172.22.48.10:51000 -> 1.0.0.1:80 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  [.] Action [to-fqdns-with-proxy/pod-to-world:https-to-one.one.one.one.-ipv4-1: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443)]
.  [.] Action [to-fqdns-with-proxy/pod-to-world:https-to-one.one.one.one.-index-ipv4-1: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  [.] Action [to-fqdns-with-proxy/pod-to-world:http-to-one.one.one.one.-ipv4-2: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-http (one.one.one.one.:80)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --retry 3 --retry-all-errors --retry-delay 3 http://one.one.one.one.:80" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
  ℹ  curl stdout:
  172.22.48.13:56188 -> 1.0.0.1:80 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  [.] Action [to-fqdns-with-proxy/pod-to-world:https-to-one.one.one.one.-ipv4-2: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443)]
.  [.] Action [to-fqdns-with-proxy/pod-to-world:https-to-one.one.one.one.-index-ipv4-2: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  [-] Scenario [to-fqdns-with-proxy/pod-to-world-2]
  [.] Action [to-fqdns-with-proxy/pod-to-world-2:https-k8s.io.-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> k8s.io.-https (k8s.io.:443)]
.  [.] Action [to-fqdns-with-proxy/pod-to-world-2:https-k8s.io.-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> k8s.io.-https (k8s.io.:443)]
.  [.] Action [to-fqdns-with-proxy/pod-to-world-2:https-k8s.io.-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> k8s.io.-https (k8s.io.:443)]
.  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-to-fqdns-one.one.one.one' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-only-dns' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
[=] [cilium-test-1] Skipping test [pod-to-controlplane-host] [103/123] (skipped by condition)
[=] [cilium-test-1] Skipping test [pod-to-k8s-on-controlplane] [104/123] (skipped by condition)
[=] [cilium-test-1] Skipping test [pod-to-controlplane-host-cidr] [105/123] (skipped by condition)
[=] [cilium-test-1] Skipping test [pod-to-k8s-on-controlplane-cidr] [106/123] (skipped by condition)
[=] [cilium-test-1] Test [policy-local-cluster-egress] [107/123]
......
[=] [cilium-test-1] Skipping test [local-redirect-policy] [108/123] (Feature enable-local-redirect-policy is disabled)
[=] [cilium-test-1] Skipping test [local-redirect-policy-with-node-dns] [109/123] (skipped by condition)
[=] [cilium-test-1] Test [pod-to-pod-no-frag] [110/123]
.
[=] [cilium-test-1] Skipping test [seq-bgp-control-plane-v1] [111/123] (skipped by condition)
[=] [cilium-test-1] Skipping test [seq-bgp-control-plane-v2] [112/123] (skipped by condition)
[=] [cilium-test-1] Skipping test [multicast] [113/123] (skipped by condition)
[=] [cilium-test-1] Skipping test [strict-mode-encryption] [114/123] (skipped by condition)
[=] [cilium-test-1] Skipping test [strict-mode-encryption-v2] [115/123] (skipped by condition)
[=] [cilium-test-1] Skipping test [host-firewall-ingress] [116/123] (skipped by condition)
[=] [cilium-test-1] Skipping test [host-firewall-egress] [117/123] (skipped by condition)
[=] [cilium-test-1] Test [seq-client-egress-l7-tls-deny-without-headers] [118/123]
...
[=] [cilium-test-1] Test [seq-client-egress-l7-tls-headers] [119/123]
.
  ℹ  curl stdout:
  172.22.48.10:58872 -> 1.0.0.1:443 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  ℹ  📜 Applying secret 'cabundle' to namespace 'cilium-test-1'..
  ℹ  📜 Applying secret 'externaltarget-tls' to namespace 'cilium-test-1'..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-l7-tls' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-only-dns' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  [-] Scenario [seq-client-egress-l7-tls-headers/pod-to-world-with-tls-intercept]
  [.] Action [seq-client-egress-l7-tls-headers/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443)]
  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 22
  [.] Action [seq-client-egress-l7-tls-headers/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
  ℹ  curl stdout:
  172.22.48.13:59446 -> 1.1.1.1:443 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  [.] Action [seq-client-egress-l7-tls-headers/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 22
  ℹ  curl stdout:
  172.22.48.11:51698 -> 1.1.1.1:443 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-l7-tls' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-only-dns' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Deleting secret 'cabundle' from namespace 'cilium-test-1'..
  ℹ  📜 Deleting secret 'externaltarget-tls' from namespace 'cilium-test-1'..
[=] [cilium-test-1] Test [seq-client-egress-l7-extra-tls-headers] [120/123]
.
  ℹ  curl stdout:
  172.22.48.10:37894 -> 1.0.0.1:443 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  ℹ  📜 Applying secret 'cabundle' to namespace 'cilium-test-1'..
  ℹ  📜 Applying secret 'externaltarget-tls' to namespace 'cilium-test-1'..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-l7-tls' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-only-dns' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  [-] Scenario [seq-client-egress-l7-extra-tls-headers/pod-to-world-with-extra-tls-intercept]
  ℹ  📜 Appending secret 'externaltarget-tls' to namespace 'cilium-test-1'..
  [.] Action [seq-client-egress-l7-extra-tls-headers/pod-to-world-with-extra-tls-intercept:https-to-one.one.one.one.-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443)]
  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 22
  [.] Action [seq-client-egress-l7-extra-tls-headers/pod-to-world-with-extra-tls-intercept:https-to-k8s.io.-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> k8s.io.-https (k8s.io.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: k8s.io -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://k8s.io.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 22
  ℹ  curl stdout:
  172.22.48.10:47692 -> 34.107.204.206:443 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  [.] Action [seq-client-egress-l7-extra-tls-headers/pod-to-world-with-extra-tls-intercept:https-to-one.one.one.one.-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
  ℹ  curl stdout:
  172.22.48.13:35352 -> 1.0.0.1:443 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  [.] Action [seq-client-egress-l7-extra-tls-headers/pod-to-world-with-extra-tls-intercept:https-to-k8s.io.-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> k8s.io.-https (k8s.io.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: k8s.io -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://k8s.io.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
  ℹ  curl stdout:
  172.22.48.13:53010 -> 34.107.204.206:443 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  [.] Action [seq-client-egress-l7-extra-tls-headers/pod-to-world-with-extra-tls-intercept:https-to-one.one.one.one.-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 22
  ℹ  curl stdout:
  172.22.48.11:52112 -> 1.0.0.1:443 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  [.] Action [seq-client-egress-l7-extra-tls-headers/pod-to-world-with-extra-tls-intercept:https-to-k8s.io.-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> k8s.io.-https (k8s.io.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: k8s.io -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://k8s.io.:443" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 22
  ℹ  curl stdout:
  172.22.48.11:60892 -> 34.107.204.206:443 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-l7-tls' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-only-dns' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Deleting secret 'externaltarget-tls' from namespace 'cilium-test-1'..
  ℹ  📜 Deleting secret 'cabundle' from namespace 'cilium-test-1'..
[=] [cilium-test-1] Test [seq-client-egress-l7-tls-headers-port-range] [121/123]
.
  ℹ  curl stdout:
  172.22.48.11:49932 -> 1.0.0.1:443 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  ℹ  📜 Applying secret 'cabundle' to namespace 'cilium-test-1'..
  ℹ  📜 Applying secret 'externaltarget-tls' to namespace 'cilium-test-1'..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-l7-tls-port-range' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-only-dns' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  [-] Scenario [seq-client-egress-l7-tls-headers-port-range/pod-to-world-with-tls-intercept]
  [.] Action [seq-client-egress-l7-tls-headers-port-range/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-0: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443)]
  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 22
  [.] Action [seq-client-egress-l7-tls-headers-port-range/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-1: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 22
  ℹ  curl stdout:
  172.22.48.10:43888 -> 1.1.1.1:443 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  [.] Action [seq-client-egress-l7-tls-headers-port-range/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-2: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
  ℹ  curl stdout:
  172.22.48.13:41804 -> 1.1.1.1:443 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-l7-tls-port-range' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-only-dns' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Deleting secret 'cabundle' from namespace 'cilium-test-1'..
  ℹ  📜 Deleting secret 'externaltarget-tls' from namespace 'cilium-test-1'..
[=] [cilium-test-1] Test [no-unexpected-packet-drops] [122/123]
...
[=] [cilium-test-1] Test [check-log-errors] [123/123]
..........................

📋 Test Report [cilium-test-1]
❌ 11/77 tests failed (39/794 actions), 46 tests skipped, 2 scenarios skipped:
Test [client-egress-l7]:
  🟥 client-egress-l7/pod-to-world:http-to-one.one.one.one.-ipv4-0: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-http (one.one.one.one.:80): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --retry 3 --retry-all-errors --retry-delay 3 http://one.one.one.one.:80" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
Test [client-egress-l7-port-range]:
  🟥 client-egress-l7-port-range/pod-to-world:http-to-one.one.one.one.-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-http (one.one.one.one.:80): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --retry 3 --retry-all-errors --retry-delay 3 http://one.one.one.one.:80" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
Test [client-egress-l7-named-port]:
  🟥 client-egress-l7-named-port/pod-to-world:http-to-one.one.one.one.-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-http (one.one.one.one.:80): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --retry 3 --retry-all-errors --retry-delay 3 http://one.one.one.one.:80" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
Test [client-egress-tls-sni]:
  🟥 client-egress-tls-sni/pod-to-world:https-to-one.one.one.one.-ipv4-0: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 28
  🟥 client-egress-tls-sni/pod-to-world:https-to-one.one.one.one.-index-ipv4-0: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https-index (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 28
  🟥 client-egress-tls-sni/pod-to-world:https-to-one.one.one.one.-ipv4-1: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 28
  🟥 client-egress-tls-sni/pod-to-world:https-to-one.one.one.one.-index-ipv4-1: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https-index (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 28
  🟥 client-egress-tls-sni/pod-to-world:https-to-one.one.one.one.-ipv4-2: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 28
  🟥 client-egress-tls-sni/pod-to-world:https-to-one.one.one.one.-index-ipv4-2: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https-index (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 28
Test [client-egress-tls-sni-wildcard]:
  🟥 client-egress-tls-sni-wildcard/pod-to-world:https-to-one.one.one.one.-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 28
  🟥 client-egress-tls-sni-wildcard/pod-to-world:https-to-one.one.one.one.-index-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https-index (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 28
  🟥 client-egress-tls-sni-wildcard/pod-to-world:https-to-one.one.one.one.-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 28
  🟥 client-egress-tls-sni-wildcard/pod-to-world:https-to-one.one.one.one.-index-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https-index (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 28
  🟥 client-egress-tls-sni-wildcard/pod-to-world:https-to-one.one.one.one.-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 28
  🟥 client-egress-tls-sni-wildcard/pod-to-world:https-to-one.one.one.one.-index-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https-index (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 28
Test [client-egress-tls-sni-double-wildcard]:
  🟥 client-egress-tls-sni-double-wildcard/pod-to-world:https-to-one.one.one.one.-ipv4-0: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 28
  🟥 client-egress-tls-sni-double-wildcard/pod-to-world:https-to-one.one.one.one.-index-ipv4-0: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https-index (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 28
  🟥 client-egress-tls-sni-double-wildcard/pod-to-world:https-to-one.one.one.one.-ipv4-1: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 28
  🟥 client-egress-tls-sni-double-wildcard/pod-to-world:https-to-one.one.one.one.-index-ipv4-1: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https-index (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 28
  🟥 client-egress-tls-sni-double-wildcard/pod-to-world:https-to-one.one.one.one.-ipv4-2: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 28
  🟥 client-egress-tls-sni-double-wildcard/pod-to-world:https-to-one.one.one.one.-index-ipv4-2: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https-index (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 28
Test [client-egress-l7-tls-headers-sni]:
  🟥 client-egress-l7-tls-headers-sni/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 22
  🟥 client-egress-l7-tls-headers-sni/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
  🟥 client-egress-l7-tls-headers-sni/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 22
Test [to-fqdns-with-proxy]:
  🟥 to-fqdns-with-proxy/pod-to-world:http-to-one.one.one.one.-ipv4-0: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-http (one.one.one.one.:80): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --retry 3 --retry-all-errors --retry-delay 3 http://one.one.one.one.:80" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 22
  🟥 to-fqdns-with-proxy/pod-to-world:http-to-one.one.one.one.-ipv4-1: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-http (one.one.one.one.:80): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --retry 3 --retry-all-errors --retry-delay 3 http://one.one.one.one.:80" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 22
  🟥 to-fqdns-with-proxy/pod-to-world:http-to-one.one.one.one.-ipv4-2: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-http (one.one.one.one.:80): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --retry 3 --retry-all-errors --retry-delay 3 http://one.one.one.one.:80" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
Test [seq-client-egress-l7-tls-headers]:
  🟥 seq-client-egress-l7-tls-headers/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 22
  🟥 seq-client-egress-l7-tls-headers/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
  🟥 seq-client-egress-l7-tls-headers/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 22
Test [seq-client-egress-l7-extra-tls-headers]:
  🟥 seq-client-egress-l7-extra-tls-headers/pod-to-world-with-extra-tls-intercept:https-to-one.one.one.one.-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 22
  🟥 seq-client-egress-l7-extra-tls-headers/pod-to-world-with-extra-tls-intercept:https-to-k8s.io.-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> k8s.io.-https (k8s.io.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: k8s.io -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://k8s.io.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 22
  🟥 seq-client-egress-l7-extra-tls-headers/pod-to-world-with-extra-tls-intercept:https-to-one.one.one.one.-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
  🟥 seq-client-egress-l7-extra-tls-headers/pod-to-world-with-extra-tls-intercept:https-to-k8s.io.-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> k8s.io.-https (k8s.io.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: k8s.io -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://k8s.io.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
  🟥 seq-client-egress-l7-extra-tls-headers/pod-to-world-with-extra-tls-intercept:https-to-one.one.one.one.-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 22
  🟥 seq-client-egress-l7-extra-tls-headers/pod-to-world-with-extra-tls-intercept:https-to-k8s.io.-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> k8s.io.-https (k8s.io.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: k8s.io -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://k8s.io.:443" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 22
Test [seq-client-egress-l7-tls-headers-port-range]:
  🟥 seq-client-egress-l7-tls-headers-port-range/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-0: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 22
  🟥 seq-client-egress-l7-tls-headers-port-range/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-1: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 22
  🟥 seq-client-egress-l7-tls-headers-port-range/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-2: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
[cilium-test-1] 11 tests failed

________________________________________________________
Executed in   58.64 mins    fish           external
   usr time   14.73 secs    1.78 millis   14.73 secs
   sys time    5.38 secs    0.52 millis    5.38 secs
```


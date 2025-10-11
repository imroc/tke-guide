# iptables 模式 + TencentOS 4.4

## 功能测试

- 耗时：80m
- 测试报告：16/77 tests failed (39/781 actions), 46 tests skipped, 2 scenarios skipped

```bash
$ time cilium connectivity test

ℹ  Monitor aggregation detected, will skip some flow validation steps
✨ [cls-cj61w10e] Creating namespace cilium-test-1 for connectivity check...
✨ [cls-cj61w10e] Deploying echo-same-node service...
✨ [cls-cj61w10e] Deploying DNS test server configmap...
✨ [cls-cj61w10e] Deploying same-node deployment...
✨ [cls-cj61w10e] Deploying client deployment...
✨ [cls-cj61w10e] Deploying client2 deployment...
✨ [cls-cj61w10e] Deploying client3 deployment...
✨ [cls-cj61w10e] Deploying echo-other-node service...
✨ [cls-cj61w10e] Deploying other-node deployment...
✨ [host-netns] Deploying cls-cj61w10e daemonset...
✨ [host-netns-non-cilium] Deploying cls-cj61w10e daemonset...
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
⌛ [cls-cj61w10e] Waiting for NodePort 172.22.48.37:31722 (cilium-test-1/echo-same-node) to become ready...
⌛ [cls-cj61w10e] Waiting for NodePort 172.22.48.37:32291 (cilium-test-1/echo-other-node) to become ready...
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

  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-to-echo' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  Cilium agent kube-system/cilium-79m9s logs since 2025-10-10 18:30:45.081766352 +0800 CST m=+795.441628845:

  ℹ  Cilium agent kube-system/cilium-nrksx logs since 2025-10-10 18:30:45.081766352 +0800 CST m=+795.441628845:

  ℹ  Cilium agent kube-system/cilium-w8fc7 logs since 2025-10-10 18:30:45.081766352 +0800 CST m=+795.441628845:

  🟥 [cilium-test-1] test client-egress failed: setting up test: applying network policies: failed to apply CiliumNetworkPolicy 'client-egress-to-echo' to namespace 'cilium-test-1' on cluster cls-cj61w10e: failed to create / update CiliumNetworkPolicy cilium-test-1/client-egress-to-echo: Patch "https://43.163.27.230:443/apis/cilium.io/v2/namespaces/cilium-test-1/ciliumnetworkpolicies/client-egress-to-echo?fieldManager=cilium-cli&force=true": http2: client connection lost
[=] [cilium-test-1] Test [client-egress-knp] [23/123]
......

  ℹ  📜 Applying NetworkPolicy 'client-egress-to-echo' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  [-] Scenario [client-egress-knp/pod-to-pod]
  [.] Action [client-egress-knp/pod-to-pod:curl-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> cilium-test-1/echo-other-node-689b8c9477-rvkw4 (172.22.48.12:8080)]
  [.] Action [client-egress-knp/pod-to-pod:curl-ipv4-1: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> cilium-test-1/echo-same-node-798cc5d967-jh4jv (172.22.48.14:8080)]
  [.] Action [client-egress-knp/pod-to-pod:curl-ipv4-2: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> cilium-test-1/echo-other-node-689b8c9477-rvkw4 (172.22.48.12:8080)]
  [.] Action [client-egress-knp/pod-to-pod:curl-ipv4-3: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> cilium-test-1/echo-same-node-798cc5d967-jh4jv (172.22.48.14:8080)]
  [.] Action [client-egress-knp/pod-to-pod:curl-ipv4-4: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> cilium-test-1/echo-other-node-689b8c9477-rvkw4 (172.22.48.12:8080)]
  [.] Action [client-egress-knp/pod-to-pod:curl-ipv4-5: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> cilium-test-1/echo-same-node-798cc5d967-jh4jv (172.22.48.14:8080)]
  ℹ  📜 Deleting NetworkPolicy 'client-egress-to-echo' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  Cilium agent kube-system/cilium-79m9s logs since 2025-10-10 18:31:33.247498445 +0800 CST m=+843.607360938:
2025-10-10T18:31:36.514787575+08:00 time=2025-10-10T10:31:36.514640592Z level=info msg="NetworkPolicy successfully added" module=agent.controlplane.policy-k8s-watcher k8sNetworkPolicyName=client-egress-to-echo k8sApiVersion=""
2025-10-10T18:31:36.522685272+08:00 time=2025-10-10T10:31:36.522539355Z level=info msg="Processing policy updates" module=agent.controlplane.policy count=1
2025-10-10T18:31:36.522956796+08:00 time=2025-10-10T10:31:36.522692008Z level=info msg="Upserted policy to repository" module=agent.controlplane.policy resource=netpol/cilium-test-1/client-egress-to-echo policyRevision=30 deletedRules=0 identity="[14347 51264 61642]"
2025-10-10T18:31:36.522968570+08:00 time=2025-10-10T10:31:36.522810308Z level=info msg="Policy repository updates complete, triggering endpoint updates" module=agent.controlplane.policy policyRevision=30
2025-10-10T18:31:49.449405918+08:00 time=2025-10-10T10:31:49.449252094Z level=info msg="NetworkPolicy successfully removed" module=agent.controlplane.policy-k8s-watcher k8sNetworkPolicyName=client-egress-to-echo k8sNamespace=cilium-test-1 k8sApiVersion="" labels="[k8s:io.cilium.k8s.policy.derived-from=NetworkPolicy k8s:io.cilium.k8s.policy.name=client-egress-to-echo k8s:io.cilium.k8s.policy.namespace=cilium-test-1 k8s:io.cilium.k8s.policy.uid=47521c31-9a79-4e80-b007-bac59a75ded6]"
2025-10-10T18:31:49.453463541+08:00 time=2025-10-10T10:31:49.453337569Z level=info msg="Processing policy updates" module=agent.controlplane.policy count=1
2025-10-10T18:31:49.453524258+08:00 time=2025-10-10T10:31:49.453470208Z level=info msg="Deleted policy from repository" module=agent.controlplane.policy resource=netpol/cilium-test-1/client-egress-to-echo policyRevision=31 deletedRules=1 identity="[14347 51264 61642]"
2025-10-10T18:31:49.453672941+08:00 time=2025-10-10T10:31:49.45358515Z level=info msg="Policy repository updates complete, triggering endpoint updates" module=agent.controlplane.policy policyRevision=31
  ℹ  Cilium agent kube-system/cilium-nrksx logs since 2025-10-10 18:31:33.247498445 +0800 CST m=+843.607360938:
2025-10-10T18:31:36.514075811+08:00 time=2025-10-10T10:31:36.51390768Z level=info msg="NetworkPolicy successfully added" module=agent.controlplane.policy-k8s-watcher k8sNetworkPolicyName=client-egress-to-echo k8sApiVersion=""
2025-10-10T18:31:36.514824197+08:00 time=2025-10-10T10:31:36.514740076Z level=info msg="Processing policy updates" module=agent.controlplane.policy count=1
2025-10-10T18:31:36.515481062+08:00 time=2025-10-10T10:31:36.514863794Z level=info msg="Upserted policy to repository" module=agent.controlplane.policy resource=netpol/cilium-test-1/client-egress-to-echo policyRevision=30 deletedRules=0 identity="[14347 51264 61642]"
2025-10-10T18:31:36.515509447+08:00 time=2025-10-10T10:31:36.514910577Z level=info msg="Policy repository updates complete, triggering endpoint updates" module=agent.controlplane.policy policyRevision=30
2025-10-10T18:31:36.557961148+08:00 time=2025-10-10T10:31:36.557809493Z level=info msg="Updated link for program" module=agent.datapath.loader link=/sys/fs/bpf/cilium/endpoints/398/links/cil_from_container progName=cil_from_container
<...>
2025-10-10T18:31:49.455682439+08:00 time=2025-10-10T10:31:49.455616553Z level=info msg="Deleted policy from repository" module=agent.controlplane.policy resource=netpol/cilium-test-1/client-egress-to-echo policyRevision=31 deletedRules=1 identity="[14347 51264 61642]"
2025-10-10T18:31:49.455744290+08:00 time=2025-10-10T10:31:49.455688084Z level=info msg="Policy repository updates complete, triggering endpoint updates" module=agent.controlplane.policy policyRevision=31
2025-10-10T18:31:49.495727056+08:00 time=2025-10-10T10:31:49.495557628Z level=info msg="Updated link for program" module=agent.datapath.loader link=/sys/fs/bpf/cilium/endpoints/398/links/cil_from_container progName=cil_from_container
2025-10-10T18:31:49.495820465+08:00 time=2025-10-10T10:31:49.495701434Z level=info msg="Updated link for program" module=agent.datapath.loader link=/sys/fs/bpf/cilium/endpoints/398/links/cil_to_container progName=cil_to_container
2025-10-10T18:31:49.496229902+08:00 time=2025-10-10T10:31:49.496116924Z level=info msg="Reloaded endpoint BPF program" identity=51264 ciliumEndpointName=cilium-test-1/client3-795488bf5-68xdx containerInterface="" ipv4=172.22.48.11 containerID=f29029cfa0 endpointID=398 k8sPodName=cilium-test-1/client3-795488bf5-68xdx datapathPolicyRevision=30 ipv6="" desiredPolicyRevision=31 subsys=endpoint
  ℹ  Cilium agent kube-system/cilium-w8fc7 logs since 2025-10-10 18:31:33.247498445 +0800 CST m=+843.607360938:
2025-10-10T18:31:36.513931203+08:00 time=2025-10-10T10:31:36.513782534Z level=info msg="NetworkPolicy successfully added" module=agent.controlplane.policy-k8s-watcher k8sNetworkPolicyName=client-egress-to-echo k8sApiVersion=""
2025-10-10T18:31:36.520914660+08:00 time=2025-10-10T10:31:36.520792415Z level=info msg="Processing policy updates" module=agent.controlplane.policy count=1
2025-10-10T18:31:36.521152676+08:00 time=2025-10-10T10:31:36.521004308Z level=info msg="Upserted policy to repository" module=agent.controlplane.policy resource=netpol/cilium-test-1/client-egress-to-echo policyRevision=30 deletedRules=0 identity="[14347 51264 61642]"
2025-10-10T18:31:36.521505508+08:00 time=2025-10-10T10:31:36.52110581Z level=info msg="Policy repository updates complete, triggering endpoint updates" module=agent.controlplane.policy policyRevision=30
2025-10-10T18:31:36.585730918+08:00 time=2025-10-10T10:31:36.585581267Z level=info msg="Updated link for program" module=agent.datapath.loader link=/sys/fs/bpf/cilium/endpoints/1729/links/cil_from_container progName=cil_from_container
<...>
2025-10-10T18:31:49.513827089+08:00 time=2025-10-10T10:31:49.513477838Z level=info msg="Updated link for program" module=agent.datapath.loader link=/sys/fs/bpf/cilium/endpoints/1729/links/cil_to_container progName=cil_to_container
2025-10-10T18:31:49.513946436+08:00 time=2025-10-10T10:31:49.51385374Z level=info msg="Reloaded endpoint BPF program" datapathPolicyRevision=30 ciliumEndpointName=cilium-test-1/client-645b68dcf7-w7kcn ipv4=172.22.48.10 containerID=20589a3efb ipv6="" k8sPodName=cilium-test-1/client-645b68dcf7-w7kcn endpointID=1729 desiredPolicyRevision=31 identity=61642 containerInterface="" subsys=endpoint
2025-10-10T18:31:49.516771477+08:00 time=2025-10-10T10:31:49.516671206Z level=info msg="Updated link for program" module=agent.datapath.loader link=/sys/fs/bpf/cilium/endpoints/896/links/cil_from_container progName=cil_from_container
2025-10-10T18:31:49.516999881+08:00 time=2025-10-10T10:31:49.516941592Z level=info msg="Updated link for program" module=agent.datapath.loader link=/sys/fs/bpf/cilium/endpoints/896/links/cil_to_container progName=cil_to_container
2025-10-10T18:31:49.517431185+08:00 time=2025-10-10T10:31:49.517356308Z level=info msg="Reloaded endpoint BPF program" ipv6="" ciliumEndpointName=cilium-test-1/client2-66475877c6-bghj6 endpointID=896 ipv4=172.22.48.13 containerID=d22dae0af3 datapathPolicyRevision=30 identity=14347 desiredPolicyRevision=31 containerInterface="" k8sPodName=cilium-test-1/client2-66475877c6-bghj6 subsys=endpoint
  ❌ Error finalizing 'client-egress-knp': timed out waiting for policy updates to be processed on Cilium agents: command failed (pod=kube-system/cilium-w8fc7, container=cilium-agent): error sending request: Post "https://43.163.27.230:443/api/v1/namespaces/kube-system/pods/cilium-w8fc7/exec?command=cilium&command=policy&command=wait&command=31&command=--max-wait-time&command=30&container=cilium-agent&stderr=true&stdout=true": http: server gave HTTP response to HTTPS client
[=] [cilium-test-1] Test [client-egress-expression] [24/123]
......
[=] [cilium-test-1] Test [client-egress-expression-port-range] [25/123]
......
[=] [cilium-test-1] Test [client-egress-expression-knp] [26/123]

  ℹ  📜 Applying NetworkPolicy 'client-egress-to-echo-expression' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  Cilium agent kube-system/cilium-w8fc7 logs since 2025-10-10 18:32:40.505886892 +0800 CST m=+910.865749385:
2025-10-10T18:32:46.124852560+08:00 time=2025-10-10T10:32:46.124694987Z level=info msg="NetworkPolicy successfully added" module=agent.controlplane.policy-k8s-watcher k8sNetworkPolicyName=client-egress-to-echo-expression k8sApiVersion=""
2025-10-10T18:32:46.130961369+08:00 time=2025-10-10T10:32:46.130840329Z level=info msg="Processing policy updates" module=agent.controlplane.policy count=1
2025-10-10T18:32:46.131089829+08:00 time=2025-10-10T10:32:46.130981537Z level=info msg="Upserted policy to repository" module=agent.controlplane.policy resource=netpol/cilium-test-1/client-egress-to-echo-expression policyRevision=36 deletedRules=0 identity="[14347 15923 51264]"
2025-10-10T18:32:46.131116282+08:00 time=2025-10-10T10:32:46.131059668Z level=info msg="Policy repository updates complete, triggering endpoint updates" module=agent.controlplane.policy policyRevision=36
2025-10-10T18:32:46.197694397+08:00 time=2025-10-10T10:32:46.197561472Z level=info msg="Updated link for program" module=agent.datapath.loader link=/sys/fs/bpf/cilium/endpoints/847/links/cil_from_container progName=cil_from_container
2025-10-10T18:32:46.198195763+08:00 time=2025-10-10T10:32:46.198037811Z level=info msg="Updated link for program" module=agent.datapath.loader link=/sys/fs/bpf/cilium/endpoints/847/links/cil_to_container progName=cil_to_container
2025-10-10T18:32:46.198788960+08:00 time=2025-10-10T10:32:46.198664407Z level=info msg="Reloaded endpoint BPF program" endpointID=847 containerID=33a411a369 containerInterface="" desiredPolicyRevision=36 datapathPolicyRevision=35 identity=15923 ipv4=172.22.48.14 ipv6="" k8sPodName=cilium-test-1/echo-same-node-798cc5d967-jh4jv ciliumEndpointName=cilium-test-1/echo-same-node-798cc5d967-jh4jv subsys=endpoint
2025-10-10T18:32:46.198816679+08:00 time=2025-10-10T10:32:46.198662968Z level=info msg="Updated link for program" module=agent.datapath.loader link=/sys/fs/bpf/cilium/endpoints/896/links/cil_from_container progName=cil_from_container
2025-10-10T18:32:46.199029528+08:00 time=2025-10-10T10:32:46.198958834Z level=info msg="Updated link for program" module=agent.datapath.loader link=/sys/fs/bpf/cilium/endpoints/896/links/cil_to_container progName=cil_to_container
2025-10-10T18:32:46.199367051+08:00 time=2025-10-10T10:32:46.199251524Z level=info msg="Reloaded endpoint BPF program" ipv6="" ciliumEndpointName=cilium-test-1/client2-66475877c6-bghj6 endpointID=896 ipv4=172.22.48.13 containerID=d22dae0af3 datapathPolicyRevision=35 identity=14347 desiredPolicyRevision=36 containerInterface="" k8sPodName=cilium-test-1/client2-66475877c6-bghj6 subsys=endpoint
  ℹ  Cilium agent kube-system/cilium-79m9s logs since 2025-10-10 18:32:40.505886892 +0800 CST m=+910.865749385:
2025-10-10T18:32:46.125132474+08:00 time=2025-10-10T10:32:46.125004452Z level=info msg="NetworkPolicy successfully added" module=agent.controlplane.policy-k8s-watcher k8sNetworkPolicyName=client-egress-to-echo-expression k8sApiVersion=""
2025-10-10T18:32:46.133309687+08:00 time=2025-10-10T10:32:46.133207682Z level=info msg="Processing policy updates" module=agent.controlplane.policy count=1
2025-10-10T18:32:46.133535166+08:00 time=2025-10-10T10:32:46.13334594Z level=info msg="Upserted policy to repository" module=agent.controlplane.policy resource=netpol/cilium-test-1/client-egress-to-echo-expression policyRevision=36 deletedRules=0 identity="[14347 15923 51264]"
2025-10-10T18:32:46.133558435+08:00 time=2025-10-10T10:32:46.133418019Z level=info msg="Policy repository updates complete, triggering endpoint updates" module=agent.controlplane.policy policyRevision=36
  ℹ  Cilium agent kube-system/cilium-nrksx logs since 2025-10-10 18:32:40.505886892 +0800 CST m=+910.865749385:
2025-10-10T18:32:46.125158096+08:00 time=2025-10-10T10:32:46.125013269Z level=info msg="NetworkPolicy successfully added" module=agent.controlplane.policy-k8s-watcher k8sNetworkPolicyName=client-egress-to-echo-expression k8sApiVersion=""
2025-10-10T18:32:46.135381566+08:00 time=2025-10-10T10:32:46.135251849Z level=info msg="Processing policy updates" module=agent.controlplane.policy count=1
2025-10-10T18:32:46.135733590+08:00 time=2025-10-10T10:32:46.135504203Z level=info msg="Upserted policy to repository" module=agent.controlplane.policy resource=netpol/cilium-test-1/client-egress-to-echo-expression policyRevision=36 deletedRules=0 identity="[14347 15923 51264]"
2025-10-10T18:32:46.135748427+08:00 time=2025-10-10T10:32:46.13555271Z level=info msg="Policy repository updates complete, triggering endpoint updates" module=agent.controlplane.policy policyRevision=36
2025-10-10T18:32:46.175681533+08:00 time=2025-10-10T10:32:46.175534473Z level=info msg="Updated link for program" module=agent.datapath.loader link=/sys/fs/bpf/cilium/endpoints/398/links/cil_from_container progName=cil_from_container
2025-10-10T18:32:46.175821732+08:00 time=2025-10-10T10:32:46.175656612Z level=info msg="Updated link for program" module=agent.datapath.loader link=/sys/fs/bpf/cilium/endpoints/398/links/cil_to_container progName=cil_to_container
2025-10-10T18:32:46.176100496+08:00 time=2025-10-10T10:32:46.175982077Z level=info msg="Reloaded endpoint BPF program" identity=51264 ciliumEndpointName=cilium-test-1/client3-795488bf5-68xdx containerInterface="" ipv4=172.22.48.11 containerID=f29029cfa0 endpointID=398 k8sPodName=cilium-test-1/client3-795488bf5-68xdx datapathPolicyRevision=35 ipv6="" desiredPolicyRevision=36 subsys=endpoint
  ℹ  📜 Deleting NetworkPolicy 'client-egress-to-echo-expression' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  🟥 [cilium-test-1] test client-egress-expression-knp failed: setting up test: applying network policies: policies were not applied on all Cilium nodes in time: command failed (pod=kube-system/cilium-79m9s, container=cilium-agent): error sending request: Post "https://43.163.27.230:443/api/v1/namespaces/kube-system/pods/cilium-79m9s/exec?command=cilium&command=policy&command=wait&command=36&command=--max-wait-time&command=30&container=cilium-agent&stderr=true&stdout=true": http: server gave HTTP response to HTTPS client
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
I1010 18:57:48.385632  191013 warnings.go:110] "Warning: cilium.io/v2alpha1 CiliumCIDRGroup is deprecated; use cilium.io/v2 CiliumCIDRGroup"
I1010 18:57:48.447026  191013 warnings.go:110] "Warning: cilium.io/v2alpha1 CiliumCIDRGroup is deprecated; use cilium.io/v2 CiliumCIDRGroup"
......
I1010 18:58:03.189031  191013 warnings.go:110] "Warning: cilium.io/v2alpha1 CiliumCIDRGroup is deprecated; use cilium.io/v2 CiliumCIDRGroup"
[=] [cilium-test-1] Test [client-egress-to-cidrgroup-deny-by-label] [50/123]
I1010 18:58:06.462433  191013 warnings.go:110] "Warning: cilium.io/v2alpha1 CiliumCIDRGroup is deprecated; use cilium.io/v2 CiliumCIDRGroup"
I1010 18:58:06.523839  191013 warnings.go:110] "Warning: cilium.io/v2alpha1 CiliumCIDRGroup is deprecated; use cilium.io/v2 CiliumCIDRGroup"
......
I1010 18:58:18.173891  191013 warnings.go:110] "Warning: cilium.io/v2alpha1 CiliumCIDRGroup is deprecated; use cilium.io/v2 CiliumCIDRGroup"
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
  [-] Scenario [node-to-node-encryption/node-to-node-encryption]
  [.] Action [node-to-node-encryption/node-to-node-encryption:ping-ipv4: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> cilium-test-1/host-netns-5h8c4 (172.22.48.29:0)]
  [.] Action [node-to-node-encryption/node-to-node-encryption:ping-ipv4: cilium-test-1/host-netns-pmhl7 (172.22.48.43) -> cilium-test-1/host-netns-5h8c4 (172.22.48.29:0)]
  [.] Action [node-to-node-encryption/node-to-node-encryption:curl-ipv4: cilium-test-1/host-netns-pmhl7 (172.22.48.43) -> cilium-test-1/echo-other-node-689b8c9477-rvkw4 (172.22.48.12:8080)]
  🟥 Failed to stop tcpdump on cilium-test-1/host-netns-pmhl7 (172.22.48.43): command failed (pod=cilium-test-1/host-netns-pmhl7, container=): context deadline exceeded
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
..........
  ℹ  curl stdout:
  172.22.48.13:53760 -> 1.0.0.1:80 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  [.] Action [client-egress-l7/pod-to-world:https-to-one.one.one.one.-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443)]
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-only-dns' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-l7-http' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  [-] Scenario [client-egress-l7/pod-to-pod]
  [.] Action [client-egress-l7/pod-to-pod:curl-ipv4-0: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> cilium-test-1/echo-same-node-798cc5d967-jh4jv (172.22.48.14:8080)]
  [.] Action [client-egress-l7/pod-to-pod:curl-ipv4-1: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> cilium-test-1/echo-other-node-689b8c9477-rvkw4 (172.22.48.12:8080)]
  [.] Action [client-egress-l7/pod-to-pod:curl-ipv4-2: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> cilium-test-1/echo-other-node-689b8c9477-rvkw4 (172.22.48.12:8080)]
  [.] Action [client-egress-l7/pod-to-pod:curl-ipv4-3: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> cilium-test-1/echo-same-node-798cc5d967-jh4jv (172.22.48.14:8080)]
  [.] Action [client-egress-l7/pod-to-pod:curl-ipv4-4: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> cilium-test-1/echo-other-node-689b8c9477-rvkw4 (172.22.48.12:8080)]
  [.] Action [client-egress-l7/pod-to-pod:curl-ipv4-5: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> cilium-test-1/echo-same-node-798cc5d967-jh4jv (172.22.48.14:8080)]
  [-] Scenario [client-egress-l7/pod-to-world]
  [.] Action [client-egress-l7/pod-to-world:http-to-one.one.one.one.-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-http (one.one.one.one.:80)]
  [.] Action [client-egress-l7/pod-to-world:https-to-one.one.one.one.-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443)]
  [.] Action [client-egress-l7/pod-to-world:https-to-one.one.one.one.-index-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https-index (one.one.one.one.:443)]
  [.] Action [client-egress-l7/pod-to-world:http-to-one.one.one.one.-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-http (one.one.one.one.:80)]
  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --retry 3 --retry-all-errors --retry-delay 3 http://one.one.one.one.:80" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
.  [.] Action [client-egress-l7/pod-to-world:https-to-one.one.one.one.-index-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  [.] Action [client-egress-l7/pod-to-world:http-to-one.one.one.one.-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-http (one.one.one.one.:80)]
.  [.] Action [client-egress-l7/pod-to-world:https-to-one.one.one.one.-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443)]
.  [.] Action [client-egress-l7/pod-to-world:https-to-one.one.one.one.-index-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-only-dns' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-l7-http' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
[=] [cilium-test-1] Test [client-egress-l7-port-range] [73/123]
..........
  ℹ  curl stdout:
  172.22.48.13:59080 -> 1.1.1.1:80 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  [.] Action [client-egress-l7-port-range/pod-to-world:https-to-one.one.one.one.-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443)]
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-only-dns' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-l7-http-port-range' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  [-] Scenario [client-egress-l7-port-range/pod-to-pod]
  [.] Action [client-egress-l7-port-range/pod-to-pod:curl-ipv4-0: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> cilium-test-1/echo-other-node-689b8c9477-rvkw4 (172.22.48.12:8080)]
  [.] Action [client-egress-l7-port-range/pod-to-pod:curl-ipv4-1: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> cilium-test-1/echo-same-node-798cc5d967-jh4jv (172.22.48.14:8080)]
  [.] Action [client-egress-l7-port-range/pod-to-pod:curl-ipv4-2: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> cilium-test-1/echo-other-node-689b8c9477-rvkw4 (172.22.48.12:8080)]
  [.] Action [client-egress-l7-port-range/pod-to-pod:curl-ipv4-3: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> cilium-test-1/echo-same-node-798cc5d967-jh4jv (172.22.48.14:8080)]
  [.] Action [client-egress-l7-port-range/pod-to-pod:curl-ipv4-4: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> cilium-test-1/echo-other-node-689b8c9477-rvkw4 (172.22.48.12:8080)]
  [.] Action [client-egress-l7-port-range/pod-to-pod:curl-ipv4-5: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> cilium-test-1/echo-same-node-798cc5d967-jh4jv (172.22.48.14:8080)]
  [-] Scenario [client-egress-l7-port-range/pod-to-world]
  [.] Action [client-egress-l7-port-range/pod-to-world:http-to-one.one.one.one.-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-http (one.one.one.one.:80)]
  [.] Action [client-egress-l7-port-range/pod-to-world:https-to-one.one.one.one.-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443)]
  [.] Action [client-egress-l7-port-range/pod-to-world:https-to-one.one.one.one.-index-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https-index (one.one.one.one.:443)]
  [.] Action [client-egress-l7-port-range/pod-to-world:http-to-one.one.one.one.-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-http (one.one.one.one.:80)]
  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --retry 3 --retry-all-errors --retry-delay 3 http://one.one.one.one.:80" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
.  [.] Action [client-egress-l7-port-range/pod-to-world:https-to-one.one.one.one.-index-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  [.] Action [client-egress-l7-port-range/pod-to-world:http-to-one.one.one.one.-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-http (one.one.one.one.:80)]
.  [.] Action [client-egress-l7-port-range/pod-to-world:https-to-one.one.one.one.-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443)]
.  [.] Action [client-egress-l7-port-range/pod-to-world:https-to-one.one.one.one.-index-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-only-dns' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-l7-http-port-range' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
[=] [cilium-test-1] Test [client-egress-l7-named-port] [74/123]
.
  ℹ  curl stdout:
  172.22.48.13:47014 -> 1.0.0.1:80 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-only-dns' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-l7-http-named-port' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  [-] Scenario [client-egress-l7-named-port/pod-to-world]
  [.] Action [client-egress-l7-named-port/pod-to-world:http-to-one.one.one.one.-ipv4-0: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-http (one.one.one.one.:80)]
  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --retry 3 --retry-all-errors --retry-delay 3 http://one.one.one.one.:80" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
  [.] Action [client-egress-l7-named-port/pod-to-world:https-to-one.one.one.one.-ipv4-0: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443)]
.  [.] Action [client-egress-l7-named-port/pod-to-world:https-to-one.one.one.one.-index-ipv4-0: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  [.] Action [client-egress-l7-named-port/pod-to-world:http-to-one.one.one.one.-ipv4-1: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-http (one.one.one.one.:80)]
.  [.] Action [client-egress-l7-named-port/pod-to-world:https-to-one.one.one.one.-ipv4-1: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443)]
.  [.] Action [client-egress-l7-named-port/pod-to-world:https-to-one.one.one.one.-index-ipv4-1: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  [.] Action [client-egress-l7-named-port/pod-to-world:http-to-one.one.one.one.-ipv4-2: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-http (one.one.one.one.:80)]
.  [.] Action [client-egress-l7-named-port/pod-to-world:https-to-one.one.one.one.-ipv4-2: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443)]
.  [.] Action [client-egress-l7-named-port/pod-to-world:https-to-one.one.one.one.-index-ipv4-2: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  [-] Scenario [client-egress-l7-named-port/pod-to-pod]
  [.] Action [client-egress-l7-named-port/pod-to-pod:curl-ipv4-0: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> cilium-test-1/echo-other-node-689b8c9477-rvkw4 (172.22.48.12:8080)]
.  [.] Action [client-egress-l7-named-port/pod-to-pod:curl-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> cilium-test-1/echo-same-node-798cc5d967-jh4jv (172.22.48.14:8080)]
.  [.] Action [client-egress-l7-named-port/pod-to-pod:curl-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> cilium-test-1/echo-other-node-689b8c9477-rvkw4 (172.22.48.12:8080)]
.  [.] Action [client-egress-l7-named-port/pod-to-pod:curl-ipv4-3: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> cilium-test-1/echo-same-node-798cc5d967-jh4jv (172.22.48.14:8080)]
.  [.] Action [client-egress-l7-named-port/pod-to-pod:curl-ipv4-4: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> cilium-test-1/echo-other-node-689b8c9477-rvkw4 (172.22.48.12:8080)]
.  [.] Action [client-egress-l7-named-port/pod-to-pod:curl-ipv4-5: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> cilium-test-1/echo-same-node-798cc5d967-jh4jv (172.22.48.14:8080)]
.  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-only-dns' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-l7-http-named-port' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
[=] [cilium-test-1] Test [client-egress-tls-sni] [75/123]
..
  ℹ  curl stdout:
  172.22.48.10:55516 -> 1.0.0.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  [.] Action [client-egress-tls-sni/pod-to-world:https-to-one.one.one.one.-index-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https-index (one.one.one.one.:443)]
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-tls-sni' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-only-dns' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  [-] Scenario [client-egress-tls-sni/pod-to-world]
  [.] Action [client-egress-tls-sni/pod-to-world:http-to-one.one.one.one.-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-http (one.one.one.one.:80)]
  [.] Action [client-egress-tls-sni/pod-to-world:https-to-one.one.one.one.-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443)]
  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 28
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.10:53162 -> 1.1.1.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  [.] Action [client-egress-tls-sni/pod-to-world:http-to-one.one.one.one.-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-http (one.one.one.one.:80)]
.  [.] Action [client-egress-tls-sni/pod-to-world:https-to-one.one.one.one.-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.13:51198 -> 1.0.0.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  [.] Action [client-egress-tls-sni/pod-to-world:https-to-one.one.one.one.-index-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.13:51210 -> 1.0.0.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  [.] Action [client-egress-tls-sni/pod-to-world:http-to-one.one.one.one.-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-http (one.one.one.one.:80)]
.  [.] Action [client-egress-tls-sni/pod-to-world:https-to-one.one.one.one.-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.11:41394 -> 1.0.0.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  [.] Action [client-egress-tls-sni/pod-to-world:https-to-one.one.one.one.-index-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.11:46596 -> 1.1.1.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-tls-sni' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-only-dns' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
[=] [cilium-test-1] Test [client-egress-tls-sni-denied] [76/123]
.........
[=] [cilium-test-1] Test [client-egress-tls-sni-wildcard] [77/123]
..
  ℹ  curl stdout:
  172.22.48.10:48796 -> 1.1.1.1:443 = 000
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
  172.22.48.10:51824 -> 1.0.0.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  [.] Action [client-egress-tls-sni-wildcard/pod-to-world:http-to-one.one.one.one.-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-http (one.one.one.one.:80)]
.  [.] Action [client-egress-tls-sni-wildcard/pod-to-world:https-to-one.one.one.one.-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.13:41450 -> 1.1.1.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  [.] Action [client-egress-tls-sni-wildcard/pod-to-world:https-to-one.one.one.one.-index-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.13:40784 -> 1.0.0.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  [.] Action [client-egress-tls-sni-wildcard/pod-to-world:http-to-one.one.one.one.-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-http (one.one.one.one.:80)]
.  [.] Action [client-egress-tls-sni-wildcard/pod-to-world:https-to-one.one.one.one.-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.11:40436 -> 1.1.1.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  [.] Action [client-egress-tls-sni-wildcard/pod-to-world:https-to-one.one.one.one.-index-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.11:40444 -> 1.1.1.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-tls-sni-wildcard' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-only-dns' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
[=] [cilium-test-1] Test [client-egress-tls-sni-wildcard-denied] [78/123]
...
[=] [cilium-test-1] Test [client-egress-tls-sni-double-wildcard] [79/123]
..
  ℹ  curl stdout:
  172.22.48.13:53000 -> 1.1.1.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-tls-sni-double-wildcard' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-only-dns' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  [-] Scenario [client-egress-tls-sni-double-wildcard/pod-to-world]
  [.] Action [client-egress-tls-sni-double-wildcard/pod-to-world:http-to-one.one.one.one.-ipv4-0: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-http (one.one.one.one.:80)]
  [.] Action [client-egress-tls-sni-double-wildcard/pod-to-world:https-to-one.one.one.one.-ipv4-0: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443)]
  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 28
  [.] Action [client-egress-tls-sni-double-wildcard/pod-to-world:https-to-one.one.one.one.-index-ipv4-0: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.13:53008 -> 1.1.1.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  [.] Action [client-egress-tls-sni-double-wildcard/pod-to-world:http-to-one.one.one.one.-ipv4-1: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-http (one.one.one.one.:80)]
.  [.] Action [client-egress-tls-sni-double-wildcard/pod-to-world:https-to-one.one.one.one.-ipv4-1: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.11:52058 -> 1.1.1.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  [.] Action [client-egress-tls-sni-double-wildcard/pod-to-world:https-to-one.one.one.one.-index-ipv4-1: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.11:48682 -> 1.1.1.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  [.] Action [client-egress-tls-sni-double-wildcard/pod-to-world:http-to-one.one.one.one.-ipv4-2: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-http (one.one.one.one.:80)]
.  [.] Action [client-egress-tls-sni-double-wildcard/pod-to-world:https-to-one.one.one.one.-ipv4-2: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.10:43854 -> 1.1.1.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  [.] Action [client-egress-tls-sni-double-wildcard/pod-to-world:https-to-one.one.one.one.-index-ipv4-2: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 28
  ℹ  curl stdout:
  172.22.48.10:40710 -> 1.0.0.1:443 = 000
  ℹ  curl stderr:
  curl: (28) SSL connection timeout

  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-tls-sni-double-wildcard' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-only-dns' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
[=] [cilium-test-1] Test [client-egress-tls-sni-double-wildcard-denied] [80/123]
...
[=] [cilium-test-1] Test [client-egress-l7-tls-headers-sni] [81/123]
.
  ℹ  curl stdout:
  172.22.48.13:37638 -> 1.1.1.1:443 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503

  [.] Action [client-egress-l7-tls-headers-sni/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-1: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443)]
  ℹ  📜 Applying secret 'cabundle' to namespace 'cilium-test-1'..
  ℹ  📜 Applying secret 'externaltarget-tls' to namespace 'cilium-test-1'..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-l7-tls-sni' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-only-dns' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  [-] Scenario [client-egress-l7-tls-headers-sni/pod-to-world-with-tls-intercept]
  [.] Action [client-egress-l7-tls-headers-sni/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-0: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443)]
  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 22
  ℹ  curl stdout:
  172.22.48.11:46088 -> 1.1.1.1:443 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503

  [.] Action [client-egress-l7-tls-headers-sni/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-2: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 22
  ℹ  curl stdout:
  172.22.48.10:36832 -> 1.1.1.1:443 = 503
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

  ℹ  📜 Applying secret 'header-match' to namespace 'cilium-test-1'..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-l7-http-matchheader-secret' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  [-] Scenario [client-egress-l7-set-header/pod-to-pod-with-endpoints]
  [.] Action [client-egress-l7-set-header/pod-to-pod-with-endpoints:curl-ipv4-0-auth-header-required: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> curl-ipv4-0-auth-header-required (172.22.48.14:8080)]
  [.] Action [client-egress-l7-set-header/pod-to-pod-with-endpoints:curl-ipv4-1-auth-header-required: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> curl-ipv4-1-auth-header-required (172.22.48.14:8080)]
  [.] Action [client-egress-l7-set-header/pod-to-pod-with-endpoints:curl-ipv4-2-auth-header-required: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> curl-ipv4-2-auth-header-required (172.22.48.14:8080)]
  [-] Scenario [client-egress-l7-set-header/pod-to-pod-with-endpoints]
  [.] Action [client-egress-l7-set-header/pod-to-pod-with-endpoints:curl-ipv4-0-auth-header-required: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> curl-ipv4-0-auth-header-required (172.22.48.12:8080)]
  [.] Action [client-egress-l7-set-header/pod-to-pod-with-endpoints:curl-ipv4-1-auth-header-required: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> curl-ipv4-1-auth-header-required (172.22.48.12:8080)]
  [.] Action [client-egress-l7-set-header/pod-to-pod-with-endpoints:curl-ipv4-2-auth-header-required: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> curl-ipv4-2-auth-header-required (172.22.48.12:8080)]
  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-l7-http-matchheader-secret' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Deleting secret 'header-match' from namespace 'cilium-test-1'..
  ℹ  Cilium agent kube-system/cilium-79m9s logs since 2025-10-10 19:11:12.126479091 +0800 CST m=+3222.486341584:
2025-10-10T19:11:14.732905469+08:00 time=2025-10-10T11:11:14.732748025Z level=info msg="Imported CiliumNetworkPolicy" module=agent.controlplane.policy-k8s-watcher ciliumNetworkPolicyName=client-egress-l7-http-matchheader-secret k8sApiVersion="" k8sNamespace=cilium-test-1
2025-10-10T19:11:14.742631571+08:00 time=2025-10-10T11:11:14.742503431Z level=info msg="Processing policy updates" module=agent.controlplane.policy count=1
2025-10-10T19:11:14.742713459+08:00 time=2025-10-10T11:11:14.7426211Z level=info msg="Upserted policy to repository" module=agent.controlplane.policy resource=cnp/cilium-test-1/client-egress-l7-http-matchheader-secret policyRevision=194 deletedRules=0 identity=[14347]
2025-10-10T19:11:14.742748667+08:00 time=2025-10-10T11:11:14.742710805Z level=info msg="Policy repository updates complete, triggering endpoint updates" module=agent.controlplane.policy policyRevision=194
2025-10-10T19:12:07.973204464+08:00 time=2025-10-10T11:12:07.97306278Z level=info msg="Deleted CiliumNetworkPolicy" module=agent.controlplane.policy-k8s-watcher ciliumNetworkPolicyName=client-egress-l7-http-matchheader-secret k8sApiVersion="" k8sNamespace=cilium-test-1
2025-10-10T19:12:07.982702111+08:00 time=2025-10-10T11:12:07.982571104Z level=info msg="Processing policy updates" module=agent.controlplane.policy count=1
2025-10-10T19:12:07.982796734+08:00 time=2025-10-10T11:12:07.982638278Z level=info msg="Deleted policy from repository" module=agent.controlplane.policy resource=cnp/cilium-test-1/client-egress-l7-http-matchheader-secret policyRevision=195 deletedRules=1 identity=[14347]
2025-10-10T19:12:07.982805212+08:00 time=2025-10-10T11:12:07.98273973Z level=info msg="Policy repository updates complete, triggering endpoint updates" module=agent.controlplane.policy policyRevision=195
  ℹ  Cilium agent kube-system/cilium-nrksx logs since 2025-10-10 19:11:12.126479091 +0800 CST m=+3222.486341584:
2025-10-10T19:11:14.732743853+08:00 time=2025-10-10T11:11:14.732572553Z level=info msg="Imported CiliumNetworkPolicy" module=agent.controlplane.policy-k8s-watcher ciliumNetworkPolicyName=client-egress-l7-http-matchheader-secret k8sApiVersion="" k8sNamespace=cilium-test-1
2025-10-10T19:11:14.735279909+08:00 time=2025-10-10T11:11:14.735172509Z level=info msg="Processing policy updates" module=agent.controlplane.policy count=1
2025-10-10T19:11:14.735586671+08:00 time=2025-10-10T11:11:14.735351037Z level=info msg="Upserted policy to repository" module=agent.controlplane.policy resource=cnp/cilium-test-1/client-egress-l7-http-matchheader-secret policyRevision=194 deletedRules=0 identity=[14347]
2025-10-10T19:11:14.735598114+08:00 time=2025-10-10T11:11:14.735401489Z level=info msg="Policy repository updates complete, triggering endpoint updates" module=agent.controlplane.policy policyRevision=194
2025-10-10T19:11:56.880562877+08:00 time=2025-10-10T11:11:56.880420813Z level=info msg="FQDN garbage collector work deleted entries" module=agent.controlplane.fqdn.namemanager controller=dns-garbage-collector-job lenEntries=2 entries=one.one.one.one.,k8s.io.
2025-10-10T19:12:07.973354010+08:00 time=2025-10-10T11:12:07.973176923Z level=info msg="Deleted CiliumNetworkPolicy" module=agent.controlplane.policy-k8s-watcher ciliumNetworkPolicyName=client-egress-l7-http-matchheader-secret k8sApiVersion="" k8sNamespace=cilium-test-1
2025-10-10T19:12:07.975261703+08:00 time=2025-10-10T11:12:07.975165565Z level=info msg="Processing policy updates" module=agent.controlplane.policy count=1
2025-10-10T19:12:07.975430045+08:00 time=2025-10-10T11:12:07.975325401Z level=info msg="Deleted policy from repository" module=agent.controlplane.policy resource=cnp/cilium-test-1/client-egress-l7-http-matchheader-secret policyRevision=195 deletedRules=1 identity=[14347]
2025-10-10T19:12:07.975626199+08:00 time=2025-10-10T11:12:07.975404452Z level=info msg="Policy repository updates complete, triggering endpoint updates" module=agent.controlplane.policy policyRevision=195
  ℹ  Cilium agent kube-system/cilium-w8fc7 logs since 2025-10-10 19:11:12.126479091 +0800 CST m=+3222.486341584:
2025-10-10T19:11:14.732661021+08:00 time=2025-10-10T11:11:14.732493763Z level=info msg="Imported CiliumNetworkPolicy" module=agent.controlplane.policy-k8s-watcher ciliumNetworkPolicyName=client-egress-l7-http-matchheader-secret k8sApiVersion="" k8sNamespace=cilium-test-1
2025-10-10T19:11:14.741266301+08:00 time=2025-10-10T11:11:14.741107208Z level=info msg="Processing policy updates" module=agent.controlplane.policy count=1
2025-10-10T19:11:14.741386277+08:00 time=2025-10-10T11:11:14.741235085Z level=info msg="Upserted policy to repository" module=agent.controlplane.policy resource=cnp/cilium-test-1/client-egress-l7-http-matchheader-secret policyRevision=194 deletedRules=0 identity=[14347]
2025-10-10T19:11:14.741393962+08:00 time=2025-10-10T11:11:14.741285255Z level=info msg="Policy repository updates complete, triggering endpoint updates" module=agent.controlplane.policy policyRevision=194
2025-10-10T19:11:14.741866443+08:00 time=2025-10-10T11:11:14.74175318Z level=info msg="Envoy: Upserting new listener" module=agent.controlplane.envoy-proxy listener=cilium-http-egress:19730
<...>
2025-10-10T19:12:07.981527545+08:00 time=2025-10-10T11:12:07.981416597Z level=info msg="Policy repository updates complete, triggering endpoint updates" module=agent.controlplane.policy policyRevision=195
2025-10-10T19:12:08.032558426+08:00 time=2025-10-10T11:12:08.032419122Z level=info msg="Updated link for program" module=agent.datapath.loader link=/sys/fs/bpf/cilium/endpoints/896/links/cil_from_container progName=cil_from_container
2025-10-10T19:12:08.032894878+08:00 time=2025-10-10T11:12:08.032669242Z level=info msg="Updated link for program" module=agent.datapath.loader link=/sys/fs/bpf/cilium/endpoints/896/links/cil_to_container progName=cil_to_container
2025-10-10T19:12:08.033155863+08:00 time=2025-10-10T11:12:08.03302559Z level=info msg="Reloaded endpoint BPF program" ipv6="" ciliumEndpointName=cilium-test-1/client2-66475877c6-bghj6 endpointID=896 ipv4=172.22.48.13 containerID=d22dae0af3 datapathPolicyRevision=194 identity=14347 desiredPolicyRevision=195 containerInterface="" k8sPodName=cilium-test-1/client2-66475877c6-bghj6 subsys=endpoint
2025-10-10T19:12:08.033363591+08:00 time=2025-10-10T11:12:08.033138571Z level=info msg="Envoy: Deleting listener" module=agent.controlplane.envoy-proxy listener=cilium-http-egress:19730
  ❌ Error finalizing 'client-egress-l7-set-header': deleting secret: cls-cj61w10e/cilium-test-1/header-match secret delete failed: Delete "https://43.163.27.230:443/api/v1/namespaces/cilium-test-1/secrets/header-match": http2: client connection lost
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
...............
[=] [cilium-test-1] Test [to-fqdns] [101/123]
............
[=] [cilium-test-1] Test [to-fqdns-with-proxy] [102/123]
.
  ℹ  curl stdout:
  172.22.48.10:51952 -> 1.1.1.1:80 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  [.] Action [to-fqdns-with-proxy/pod-to-world:https-to-one.one.one.one.-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443)]
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-to-fqdns-one.one.one.one' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-only-dns' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  [-] Scenario [to-fqdns-with-proxy/pod-to-world]
  [.] Action [to-fqdns-with-proxy/pod-to-world:http-to-one.one.one.one.-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-http (one.one.one.one.:80)]
  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --retry 3 --retry-all-errors --retry-delay 3 http://one.one.one.one.:80" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 22
.  [.] Action [to-fqdns-with-proxy/pod-to-world:https-to-one.one.one.one.-index-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  [.] Action [to-fqdns-with-proxy/pod-to-world:http-to-one.one.one.one.-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-http (one.one.one.one.:80)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --retry 3 --retry-all-errors --retry-delay 3 http://one.one.one.one.:80" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
  ℹ  curl stdout:
  172.22.48.13:47720 -> 1.0.0.1:80 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  [.] Action [to-fqdns-with-proxy/pod-to-world:https-to-one.one.one.one.-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443)]
.  [.] Action [to-fqdns-with-proxy/pod-to-world:https-to-one.one.one.one.-index-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https-index (one.one.one.one.:443)]
.  [.] Action [to-fqdns-with-proxy/pod-to-world:http-to-one.one.one.one.-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-http (one.one.one.one.:80)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --retry 3 --retry-all-errors --retry-delay 3 http://one.one.one.one.:80" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 22
  ℹ  curl stdout:
  172.22.48.11:38846 -> 1.1.1.1:80 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  [.] Action [to-fqdns-with-proxy/pod-to-world:https-to-one.one.one.one.-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443)]
.  [.] Action [to-fqdns-with-proxy/pod-to-world:https-to-one.one.one.one.-index-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https-index (one.one.one.one.:443)]
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
  172.22.48.10:58876 -> 1.1.1.1:443 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  [.] Action [seq-client-egress-l7-tls-headers/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443)]
  ℹ  📜 Applying secret 'cabundle' to namespace 'cilium-test-1'..
  ℹ  📜 Applying secret 'externaltarget-tls' to namespace 'cilium-test-1'..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-l7-tls' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-only-dns' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  [-] Scenario [seq-client-egress-l7-tls-headers/pod-to-world-with-tls-intercept]
  [.] Action [seq-client-egress-l7-tls-headers/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443)]
  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 22
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
  ℹ  curl stdout:
  172.22.48.13:33944 -> 1.1.1.1:443 = 503
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
  172.22.48.11:53370 -> 1.0.0.1:443 = 503
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
  172.22.48.10:58230 -> 1.0.0.1:443 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  [.] Action [seq-client-egress-l7-extra-tls-headers/pod-to-world-with-extra-tls-intercept:https-to-k8s.io.-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> k8s.io.-https (k8s.io.:443)]
  ℹ  📜 Applying secret 'cabundle' to namespace 'cilium-test-1'..
  ℹ  📜 Applying secret 'externaltarget-tls' to namespace 'cilium-test-1'..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-l7-tls' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-only-dns' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  [-] Scenario [seq-client-egress-l7-extra-tls-headers/pod-to-world-with-extra-tls-intercept]
  ℹ  📜 Appending secret 'externaltarget-tls' to namespace 'cilium-test-1'..
  [.] Action [seq-client-egress-l7-extra-tls-headers/pod-to-world-with-extra-tls-intercept:https-to-one.one.one.one.-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443)]
  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 22
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: k8s.io -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://k8s.io.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 22
  ℹ  curl stdout:
  172.22.48.10:44728 -> 34.107.204.206:443 = 503
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
  172.22.48.13:35614 -> 1.1.1.1:443 = 503
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
  172.22.48.13:51630 -> 34.107.204.206:443 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  [.] Action [seq-client-egress-l7-extra-tls-headers/pod-to-world-with-extra-tls-intercept:https-to-one.one.one.one.-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443)]
.  🟥 Writing data to pod failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): error sending request: Post "https://43.163.27.230:443/api/v1/namespaces/cilium-test-1/pods/client3-795488bf5-68xdx/exec?command=sh&command=-c&command=echo+LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUJkekNDQVJ5Z0F3SUJBZ0lVREdXUFlZQXpVcG1ObmMzMmUvbkE4ZzFsYWFVd0NnWUlLb1pJemowRUF3SXcKR1RFWE1CVUdBMVVFQXhNT1EybHNhWFZ0SUZSbGMzUWdRMEV3SGhjTk1qVXhNREV3TVRBeE5EQXdXaGNOTXpBeApNREE1TVRBeE5EQXdXakFaTVJjd0ZRWURWUVFERXc1RGFXeHBkVzBnVkdWemRDQkRRVEJaTUJNR0J5cUdTTTQ5CkFnRUdDQ3FHU000OUF3RUhBMElBQkU4K0thT0sxUnJCVWFXck9FZnMxVFA2U1NWaGZqb0dBUjZ2M3VZT1lzTXkKNzlxc21hY1psc2NyNDkvcmNHYTRmTVJMcnZaWk5uc3dMelJWb0d3UzEzeWpRakJBTUE0R0ExVWREd0VCL3dRRQpBd0lCQmpBUEJnTlZIUk1CQWY4RUJUQURBUUgvTUIwR0ExVWREZ1FXQkJTL2d2L2hXcWMrL09zQWdyRWxwcTNLCks0MnJpREFLQmdncWhrak9QUVFEQWdOSkFEQkdBaUVBbDJ3ODJrSzduWEd4NlYvT1VlZGFENGNQMm41MjFjTCsKamlaTDU3cmRkanNDSVFEb0N4MmV1b25RaDRQSVpTeWM5VVo5WHpLcHhBNDRyZjVFVUZGUlZPelpmdz09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0KCg%3D%3D+%7C+base64+-d+%3E+%2Ftmp%2Ftest-ca.crt&container=client3&stderr=true&stdout=true": http: server gave HTTP response to HTTPS client:
  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-l7-tls' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-only-dns' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Deleting secret 'cabundle' from namespace 'cilium-test-1'..
  ℹ  📜 Deleting secret 'externaltarget-tls' from namespace 'cilium-test-1'..
[=] [cilium-test-1] Test [seq-client-egress-l7-tls-headers-port-range] [121/123]
.
  ℹ  curl stdout:
  172.22.48.10:54894 -> 1.0.0.1:443 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  [.] Action [seq-client-egress-l7-tls-headers-port-range/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443)]
  ℹ  📜 Applying secret 'cabundle' to namespace 'cilium-test-1'..
  ℹ  📜 Applying secret 'externaltarget-tls' to namespace 'cilium-test-1'..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-l7-tls-port-range' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Applying CiliumNetworkPolicy 'client-egress-only-dns' to namespace 'cilium-test-1' on cluster cls-cj61w10e..
  [-] Scenario [seq-client-egress-l7-tls-headers-port-range/pod-to-world-with-tls-intercept]
  [.] Action [seq-client-egress-l7-tls-headers-port-range/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443)]
  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 22
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
  ℹ  curl stdout:
  172.22.48.13:36328 -> 1.0.0.1:443 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  [.] Action [seq-client-egress-l7-tls-headers-port-range/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 22
  ℹ  curl stdout:
  172.22.48.11:35468 -> 1.1.1.1:443 = 503
  ℹ  curl stderr:
  curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503
curl: (22) The requested URL returned error: 503

  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-l7-tls-port-range' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Deleting CiliumNetworkPolicy 'client-egress-only-dns' in namespace 'cilium-test-1' on cluster cls-cj61w10e..
  ℹ  📜 Deleting secret 'externaltarget-tls' from namespace 'cilium-test-1'..
  ℹ  📜 Deleting secret 'cabundle' from namespace 'cilium-test-1'..
[=] [cilium-test-1] Test [no-unexpected-packet-drops] [122/123]
...
[=] [cilium-test-1] Test [check-log-errors] [123/123]
..........................

📋 Test Report [cilium-test-1]
❌ 16/77 tests failed (39/781 actions), 46 tests skipped, 2 scenarios skipped:
Test [client-egress]:
Test [client-egress-knp]:
Test [client-egress-expression-knp]:
Test [node-to-node-encryption]:
  🟥 node-to-node-encryption/node-to-node-encryption:curl-ipv4: cilium-test-1/host-netns-pmhl7 (172.22.48.43) -> cilium-test-1/echo-other-node-689b8c9477-rvkw4 (172.22.48.12:8080): Failed to stop tcpdump on cilium-test-1/host-netns-pmhl7 (172.22.48.43): command failed (pod=cilium-test-1/host-netns-pmhl7, container=): context deadline exceeded
Test [client-egress-l7]:
  🟥 client-egress-l7/pod-to-world:http-to-one.one.one.one.-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-http (one.one.one.one.:80): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --retry 3 --retry-all-errors --retry-delay 3 http://one.one.one.one.:80" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
Test [client-egress-l7-port-range]:
  🟥 client-egress-l7-port-range/pod-to-world:http-to-one.one.one.one.-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-http (one.one.one.one.:80): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --retry 3 --retry-all-errors --retry-delay 3 http://one.one.one.one.:80" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
Test [client-egress-l7-named-port]:
  🟥 client-egress-l7-named-port/pod-to-world:http-to-one.one.one.one.-ipv4-0: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-http (one.one.one.one.:80): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --retry 3 --retry-all-errors --retry-delay 3 http://one.one.one.one.:80" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
Test [client-egress-tls-sni]:
  🟥 client-egress-tls-sni/pod-to-world:https-to-one.one.one.one.-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 28
  🟥 client-egress-tls-sni/pod-to-world:https-to-one.one.one.one.-index-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https-index (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 28
  🟥 client-egress-tls-sni/pod-to-world:https-to-one.one.one.one.-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 28
  🟥 client-egress-tls-sni/pod-to-world:https-to-one.one.one.one.-index-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https-index (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 28
  🟥 client-egress-tls-sni/pod-to-world:https-to-one.one.one.one.-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 28
  🟥 client-egress-tls-sni/pod-to-world:https-to-one.one.one.one.-index-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https-index (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 28
Test [client-egress-tls-sni-wildcard]:
  🟥 client-egress-tls-sni-wildcard/pod-to-world:https-to-one.one.one.one.-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 28
  🟥 client-egress-tls-sni-wildcard/pod-to-world:https-to-one.one.one.one.-index-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https-index (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 28
  🟥 client-egress-tls-sni-wildcard/pod-to-world:https-to-one.one.one.one.-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 28
  🟥 client-egress-tls-sni-wildcard/pod-to-world:https-to-one.one.one.one.-index-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https-index (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 28
  🟥 client-egress-tls-sni-wildcard/pod-to-world:https-to-one.one.one.one.-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 28
  🟥 client-egress-tls-sni-wildcard/pod-to-world:https-to-one.one.one.one.-index-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https-index (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 28
Test [client-egress-tls-sni-double-wildcard]:
  🟥 client-egress-tls-sni-double-wildcard/pod-to-world:https-to-one.one.one.one.-ipv4-0: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 28
  🟥 client-egress-tls-sni-double-wildcard/pod-to-world:https-to-one.one.one.one.-index-ipv4-0: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https-index (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 28
  🟥 client-egress-tls-sni-double-wildcard/pod-to-world:https-to-one.one.one.one.-ipv4-1: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 28
  🟥 client-egress-tls-sni-double-wildcard/pod-to-world:https-to-one.one.one.one.-index-ipv4-1: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https-index (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 28
  🟥 client-egress-tls-sni-double-wildcard/pod-to-world:https-to-one.one.one.one.-ipv4-2: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 28
  🟥 client-egress-tls-sni-double-wildcard/pod-to-world:https-to-one.one.one.one.-index-ipv4-2: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https-index (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null https://one.one.one.one.:443/index.html" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 28
Test [client-egress-l7-tls-headers-sni]:
  🟥 client-egress-l7-tls-headers-sni/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-0: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
  🟥 client-egress-l7-tls-headers-sni/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-1: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 22
  🟥 client-egress-l7-tls-headers-sni/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-2: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 22
Test [client-egress-l7-set-header]:
Test [to-fqdns-with-proxy]:
  🟥 to-fqdns-with-proxy/pod-to-world:http-to-one.one.one.one.-ipv4-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-http (one.one.one.one.:80): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --retry 3 --retry-all-errors --retry-delay 3 http://one.one.one.one.:80" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 22
  🟥 to-fqdns-with-proxy/pod-to-world:http-to-one.one.one.one.-ipv4-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-http (one.one.one.one.:80): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --retry 3 --retry-all-errors --retry-delay 3 http://one.one.one.one.:80" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
  🟥 to-fqdns-with-proxy/pod-to-world:http-to-one.one.one.one.-ipv4-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-http (one.one.one.one.:80): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --retry 3 --retry-all-errors --retry-delay 3 http://one.one.one.one.:80" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 22
Test [seq-client-egress-l7-tls-headers]:
  🟥 seq-client-egress-l7-tls-headers/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 22
  🟥 seq-client-egress-l7-tls-headers/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
  🟥 seq-client-egress-l7-tls-headers/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 22
Test [seq-client-egress-l7-extra-tls-headers]:
  🟥 seq-client-egress-l7-extra-tls-headers/pod-to-world-with-extra-tls-intercept:https-to-one.one.one.one.-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 22
  🟥 seq-client-egress-l7-extra-tls-headers/pod-to-world-with-extra-tls-intercept:https-to-k8s.io.-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> k8s.io.-https (k8s.io.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: k8s.io -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://k8s.io.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 22
  🟥 seq-client-egress-l7-extra-tls-headers/pod-to-world-with-extra-tls-intercept:https-to-one.one.one.one.-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
  🟥 seq-client-egress-l7-extra-tls-headers/pod-to-world-with-extra-tls-intercept:https-to-k8s.io.-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> k8s.io.-https (k8s.io.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: k8s.io -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://k8s.io.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
  🟥 seq-client-egress-l7-extra-tls-headers/pod-to-world-with-extra-tls-intercept:https-to-one.one.one.one.-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443): Writing data to pod failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): error sending request: Post "https://43.163.27.230:443/api/v1/namespaces/cilium-test-1/pods/client3-795488bf5-68xdx/exec?command=sh&command=-c&command=echo+LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUJkekNDQVJ5Z0F3SUJBZ0lVREdXUFlZQXpVcG1ObmMzMmUvbkE4ZzFsYWFVd0NnWUlLb1pJemowRUF3SXcKR1RFWE1CVUdBMVVFQXhNT1EybHNhWFZ0SUZSbGMzUWdRMEV3SGhjTk1qVXhNREV3TVRBeE5EQXdXaGNOTXpBeApNREE1TVRBeE5EQXdXakFaTVJjd0ZRWURWUVFERXc1RGFXeHBkVzBnVkdWemRDQkRRVEJaTUJNR0J5cUdTTTQ5CkFnRUdDQ3FHU000OUF3RUhBMElBQkU4K0thT0sxUnJCVWFXck9FZnMxVFA2U1NWaGZqb0dBUjZ2M3VZT1lzTXkKNzlxc21hY1psc2NyNDkvcmNHYTRmTVJMcnZaWk5uc3dMelJWb0d3UzEzeWpRakJBTUE0R0ExVWREd0VCL3dRRQpBd0lCQmpBUEJnTlZIUk1CQWY4RUJUQURBUUgvTUIwR0ExVWREZ1FXQkJTL2d2L2hXcWMrL09zQWdyRWxwcTNLCks0MnJpREFLQmdncWhrak9QUVFEQWdOSkFEQkdBaUVBbDJ3ODJrSzduWEd4NlYvT1VlZGFENGNQMm41MjFjTCsKamlaTDU3cmRkanNDSVFEb0N4MmV1b25RaDRQSVpTeWM5VVo5WHpLcHhBNDRyZjVFVUZGUlZPelpmdz09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0KCg%3D%3D+%7C+base64+-d+%3E+%2Ftmp%2Ftest-ca.crt&container=client3&stderr=true&stdout=true": http: server gave HTTP response to HTTPS client:
Test [seq-client-egress-l7-tls-headers-port-range]:
  🟥 seq-client-egress-l7-tls-headers-port-range/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-0: cilium-test-1/client-645b68dcf7-w7kcn (172.22.48.10) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-645b68dcf7-w7kcn, container=client): command terminated with exit code 22
  🟥 seq-client-egress-l7-tls-headers-port-range/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-1: cilium-test-1/client2-66475877c6-bghj6 (172.22.48.13) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client2-66475877c6-bghj6, container=client2): command terminated with exit code 22
  🟥 seq-client-egress-l7-tls-headers-port-range/pod-to-world-with-tls-intercept:https-to-one.one.one.one.-2: cilium-test-1/client3-795488bf5-68xdx (172.22.48.11) -> one.one.one.one.-https (one.one.one.one.:443): command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --cacert /tmp/test-ca.crt -H X-Very-Secret-Token: 42 --retry 5 --retry-delay 0 --retry-all-errors https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client3-795488bf5-68xdx, container=client3): command terminated with exit code 22
[cilium-test-1] 16 tests failed

________________________________________________________
Executed in   80.50 mins    fish           external
   usr time   14.13 secs    1.08 millis   14.13 secs
   sys time    4.87 secs    1.07 millis    4.87 secs
```


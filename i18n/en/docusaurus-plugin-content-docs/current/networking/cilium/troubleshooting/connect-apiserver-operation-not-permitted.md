# Troubleshooting: Connecting APIServer failed with "operation not permitted"

## Symptoms

A TKE cluster with Cilium installed was running normally for many days, then suddenly became paralyzed. All nodes' cilium-agent pods were in `CrashLoopBackoff` state and failed to start successfully.

## Analyzing the Scene

Analyzing the cilium pod status, we found that the config init container kept failing to start, with the following error logs:

```txt
$ kubectl -n kube-system logs cilium-qsj2r -c config -p --tail 10
time=2026-01-03T23:17:16.844750142Z level=info msg="Establishing connection to apiserver" subsys=cilium-dbg module=k8s-client ipAddr=https://10.15.1.8:443
time=2026-01-03T23:17:21.849247774Z level=info msg="Establishing connection to apiserver" subsys=cilium-dbg module=k8s-client ipAddr=https://10.15.1.8:443
time=2026-01-03T23:17:26.849702247Z level=info msg="Establishing connection to apiserver" subsys=cilium-dbg module=k8s-client ipAddr=https://10.15.1.8:443
time=2026-01-03T23:17:26.850125515Z level=error msg="Unable to contact k8s api-server" subsys=cilium-dbg module=k8s-client ipAddr=https://10.15.1.8:443 error="Get \"https://10.15.1.8:443/api/v1/namespaces/kube-system\": dial tcp 10.15.1.8:443: connect: operation not permitted"
time=2026-01-03T23:17:26.850182994Z level=error msg="Start hook failed" subsys=cilium-dbg function="client.(*compositeClientset).onStart (k8s-client)" error="Get \"https://10.15.1.8:443/api/v1/namespaces/kube-system\": dial tcp 10.15.1.8:443: connect: operation not permitted"
time=2026-01-03T23:17:26.850204644Z level=error msg="Failed to start hive" subsys=cilium-dbg error="Get \"https://10.15.1.8:443/api/v1/namespaces/kube-system\": dial tcp 10.15.1.8:443: connect: operation not permitted" duration=1m0.033776717s
time=2026-01-03T23:17:26.850241303Z level=info msg="Stopping hive" subsys=cilium-dbg
time=2026-01-03T23:17:26.850304873Z level=info msg="Stopped hive" subsys=cilium-dbg duration=55.274µs
Error: Build config failed: failed to start: Get "https://10.15.1.8:443/api/v1/namespaces/kube-system": dial tcp 10.15.1.8:443: connect: operation not permitted
```

The logs show that the connection to the apiserver failed with `operation not permitted` error. We tried to manually curl test the connection to the apiserver on the node, and got the same error:

```txt
$ curl -v -k https://10.15.1.8:443
*   Trying 10.15.1.8:443...
* Immediate connect fail for 10.15.1.8: Operation not permitted
* Failed to connect to 10.15.1.8 port 443 after 0 ms: Couldn't connect to server
* Closing connection
curl: (7) Failed to connect to 10.15.1.8 port 443 after 0 ms: Couldn't connect to server
```

## Analyzing Historical Logs

After comprehensively analyzing the cluster event logs and APIServer audit logs, we found that after a cilium update (executing helm upgrade to modify cilium configuration), the cilium pod was recreated and then failed to start successfully, though this was not noticed initially.

Before the cilium pod was recreated, the cilium-agent was also reporting similar error logs:

```txt
time=2026-01-03T23:17:48.232653954Z level=info msg="/healthz returning unhealthy" module=agent.infra.agent-healthz state=Failure error="1.18.5 (v1.18.5-7d4d8932)    Kubernetes service is not ready: Get \"https://10.15.1.8:443/version\": dial tcp 10.15.1.8:443: connect: operation not permitted"
time=2026-01-03T23:17:55.588789531Z level=error msg=k8sError error="failed to list <unspecified>: Get \"https://10.15.1.8:443/api/v1/namespaces/kube-system/configmaps?fieldSelector=metadata.name%3Dcilium-config&resourceVersion=2589006567\": dial tcp 10.15.1.8:443: connect: operation not permitted"
time=2026-01-03T23:17:56.586877801Z level=error msg=k8sError error="failed to list *v1.NetworkPolicy: Get \"https://10.15.1.8:443/apis/networking.k8s.io/v1/networkpolicies?resourceVersion=2589041072\": dial tcp 10.15.1.8:443: connect: operation not permitted"
time=2026-01-03T23:17:58.071814409Z level=error msg=k8sError error="failed to list *v2.CiliumNode: Get \"https://10.15.1.8:443/apis/cilium.io/v2/ciliumnodes?fieldSelector=metadata.name%3D10.15.0.4&resourceVersion=2588865016\": dial tcp 10.15.1.8:443: connect: operation not permitted"
time=2026-01-03T23:17:58.165160666Z level=error msg=k8sError error="failed to list *v2.CiliumIdentity: Get \"https://10.15.1.8:443/apis/cilium.io/v2/ciliumidentities?resourceVersion=2588960557\": dial tcp 10.15.1.8:443: connect: operation not permitted"
time=2026-01-03T23:17:58.252131821Z level=error msg=k8sError error="failed to list <unspecified>: Get \"https://10.15.1.8:443/apis/cilium.io/v2/ciliumlocalredirectpolicies?resourceVersion=2589018442\": dial tcp 10.15.1.8:443: connect: operation not permitted"
time=2026-01-03T23:17:58.485345758Z level=error msg=k8sError error="failed to list <unspecified>: Get \"https://10.15.1.8:443/api/v1/namespaces?resourceVersion=2588921517\": dial tcp 10.15.1.8:443: connect: operation not permitted"
time=2026-01-03T23:17:59.056962574Z level=error msg=k8sError error="failed to list *v2.CiliumClusterwideNetworkPolicy: Get \"https://10.15.1.8:443/apis/cilium.io/v2/ciliumclusterwidenetworkpolicies?resourceVersion=2589056728\": dial tcp 10.15.1.8:443: connect: operation not permitted"
time=2026-01-03T23:18:02.953060556Z level=error msg=k8sError error="failed to list *v2.CiliumNetworkPolicy: Get \"https://10.15.1.8:443/apis/cilium.io/v2/ciliumnetworkpolicies?resourceVersion=2589058068\": dial tcp 10.15.1.8:443: connect: operation not permitted"
time=2026-01-03T23:18:05.295364811Z level=error msg=k8sError error="failed to list *v1.Node: Get \"https://10.15.1.8:443/api/v1/nodes?fieldSelector=metadata.name%3D10.15.0.4&resourceVersion=2589037860\": dial tcp 10.15.1.8:443: connect: operation not permitted"
```

## Initial Root Cause Analysis

From the `operation not permitted` error, we can tell that the packets accessing the apiserver never left the node and were directly dropped by the kernel (normally, if the apiserver is unreachable, you would get errors like `timeout` or `connection refused`).

The apiserver address configured for cilium is the CLB address created after enabling internal network access for the TKE cluster (the CLB automatically created by the LoadBalancer type Service `kubernetes-intranet`):

```bash
$ kubectl -n default get svc kubernetes-intranet
NAME                  TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)         AGE
kubernetes-intranet   LoadBalancer   192.168.60.179   10.15.1.8     443:30965/TCP   11d
```

Since cilium is installed with kubeProxyReplacement enabled, traffic accessing the apiserver is directly intercepted by cilium's eBPF program and forwarded to the backend address - the traffic doesn't actually go through the CLB (this behavior is consistent with native Kubernetes kube-proxy).

Checking the eBPF data written by cilium-agent:

```txt
$ kubectl -n kube-system exec cilium-kddvm -- cilium bpf lb list
SERVICE ADDRESS               BACKEND ADDRESS (REVNAT_ID) (SLOT)
10.15.1.8:443/TCP (0)         0.0.0.0:0 (14) (0) [LoadBalancer]
0.0.0.0:30965/TCP (0)         0.0.0.0:0 (12) (0) [NodePort, non-routable]
192.168.60.179:443/TCP (0)    0.0.0.0:0 (15) (0) [ClusterIP, non-routable]
```

We can see that the backend address for the server addresses related to the `kubernetes-intranet` svc are all empty (NodePort, CLB VIP, ClusterIP).

Checking the data in cilium-agent's process memory, we found they were also empty:

```txt
$ kubectl -n kube-system exec cilium-kddvm -- cilium shell -- db/show frontends
Address                   Type           ServiceName                          PortName         Backends                                RedirectTo   Status   Since   Error
0.0.0.0:30965/TCP         NodePort       default/kubernetes-intranet          https                                                                 Done     4m20s
10.15.1.8:443/TCP         LoadBalancer   default/kubernetes-intranet          https                                                                 Done     4m20s
192.168.60.179:443/TCP    ClusterIP      default/kubernetes-intranet          https                                                                 Done     4m20s

$ kubectl -n kube-system exec cilium-kddvm -- cilium service list
ID   Frontend                  Service Type   Backend
4    0.0.0.0:30965/TCP         NodePort
6    10.15.1.8:443/TCP         LoadBalancer
7    192.168.60.179:443/TCP    ClusterIP
```

The backend addresses recorded in cilium come from the EndpointSlice associated with the k8s Service. Checking the EndpointSlice for this Service, we found addresses exist and the association with the Service is correct:

```txt
$ kubectl get endpointslices.discovery.k8s.io | grep kubernetes-intranet
kubernetes-intranet-qxgk4   IPv4          60002   169.254.128.7   11d

$ kubectl get endpointslices.discovery.k8s.io kubernetes-intranet-qxgk4 -o yaml | grep service-name
    kubernetes.io/service-name: kubernetes-intranet
```

A possibility came to mind:

1. When cilium first connects to the apiserver, since cilium is not yet ready and eBPF data is not initialized, packets accessing the apiserver actually go to the CLB.
2. When the EndpointSlice corresponding to `kubernetes-intranet` is recreated or endpoints are temporarily deleted, cilium temporarily clears the backend data in eBPF.
3. When the endpoint is added back, since cilium has already initialized the eBPF program and data, subsequent packets accessing the apiserver are intercepted and processed by the eBPF program.
4. Since the backend data in eBPF for `kubernetes-intranet` was temporarily cleared, packets accessing this address are considered to have no corresponding backend, resulting in the `operation not permitted` error.

This creates a circular dependency - once the EndpointSlice corresponding to `kubernetes-intranet` changes, the node can no longer access the apiserver through the corresponding CLB address.

This issue can indeed be reproduced by manually deleting and recreating the EndpointSlice corresponding to `kubernetes-intranet`.

However, in reality, the EndpointSlice for this Service has always existed and was never deleted and recreated:

```txt
$ kubectl get endpointslices kubernetes-intranet-qxgk4
NAME                        ADDRESSTYPE   PORTS   ENDPOINTS       AGE
kubernetes-intranet-qxgk4   IPv4          60002   169.254.128.7   11d
```

Furthermore, checking the cluster audit, there were no patch/update operations on this EndpointSlice object, so this couldn't be the cause.

At this point, we hadn't found the root cause yet, but we could derive a workaround: when installing cilium, don't use the CLB address for the apiserver address - instead, directly use the endpoint address of the `kubernetes` svc (an address starting with 169.254, which doesn't change after cluster creation). This address is not intercepted and forwarded by cilium, so it doesn't have this problem.

Without finding the root cause, we couldn't be sure if other scenarios would also have problems, representing a significant hidden risk, so further investigation was needed.

## Finding Reproduction Conditions

For further investigation, we first needed to find the reproduction conditions before continuing with debugging and analysis.

After various suspicions and attempts (details omitted here), **we finally discovered the reproduction condition: adjusting the TKE cluster specification**.

TKE cluster specifications can be adjusted automatically or manually. After attempting to manually adjust the cluster specification, the problem was reproduced, though not all nodes reproduced it every time.

This reproduction condition has an obvious characteristic: the apiserver will be recreated, and all ListWatch operations will be disconnected.

## Adding Debug Code to Cilium

Based on previous investigation, it was obvious that the backend state recorded internally in cilium didn't match the actual EndpointSlice resource - the former was empty while the latter always existed and hadn't changed.

So, we suspected there was a logic problem in how cilium synchronizes Service/EndpointSlice. The key processing function is `runServiceEndpointsReflector` (`pkg/loadbalancer/reflectors/k8s.go`). First, we added two debug log lines to see whether the code path goes to processServiceEvent or processEndpointsEvent during reproduction, or both:

```go
  processBuffer := func(buf buffer) {
    for key, val := range buf.All() {
      if key.isSvc {
        // highlight-next-line
        p.Log.Info("DEBUG: Processing service event", "key", key)
        processServiceEvent(txn, val.kind, val.svc)
      } else {
        // highlight-next-line
        p.Log.Info("DEBUG: Processing endpointslice event", "key", key)
        processEndpointsEvent(txn, key, val.kind, val.allEndpoints)
      }
    }
  }
```

Building the image, retagging and pushing to our own image registry:

```bash
make dev-docker-image-debug
docker tag quay.io/cilium/cilium-dev:latest docker.io/imroc/cilium:dev
docker push docker.io/imroc/cilium:dev
```

Then replacing the cilium image in the cluster:

```bash
kubectl -n kube-system patch ds cilium --patch '{"spec": {"template": {"spec": {"containers": [{"name": "cilium-agent","image": "docker.io/imroc/cilium:dev" }]}}}}'
```

After adjusting the cluster specification to reproduce the problem, we observed that during the adjustment:

1. cilium-agent receives events for the `default/kubernetes-intranet` Service, with no corresponding EndpointSlice events.
2. cilium-agent receives EndpointSlice events for `default/kubernetes`, with no corresponding Service events.

## Analyzing APIServer Audit

In the cluster's **Monitoring & Alerts - Logs - Audit Logs - Global Search**, we used the following CQL to search audit logs related to the `kubernetes-intranet` and `kubernetes` Services and their associated EndpointSlices:

```txt
objectRef.namespace:"default" AND objectRef.name:"kubernetes*" AND (NOT verb:get NOT verb:watch) AND (objectRef.resource:"services" OR objectRef.resource:"endpointslices")
```

From the logs, we discovered that during cluster specification adjustment:

1. The `default/kubernetes-intranet` Service has some patch operations, but no operations on the corresponding EndpointSlice object.
2. The `default/kubernetes` Service has no operations, but the corresponding EndpointSlice has update operations.

Further analysis:

1. The patch operations on the `default/kubernetes-intranet` Service come from TKE's service-controller, because this Service is of LoadBalancer type and is processed by service-controller. When the cluster specification is adjusted, the apiserver is recreated, causing service-controller's existing ListWatch connection to disconnect, then automatically reconnect and re-reconcile. After reconciliation, it issues a patch operation to record the latest reconciliation timestamp in the Service annotation.
2. The update operations on the `default/kubernetes` EndpointSlice come from kube-apiserver. The content of the update has no difference from before the change - both point to the TKE apiserver address 169.254.128.7.

## Further Debugging

Returning to the key issue: why does the backend for the `default/kubernetes-intranet` Service get cleared in cilium-agent's memory when the cluster specification is adjusted, even though there were no changes to this Service's corresponding EndpointSlice?

This can clearly be identified as a state inconsistency between cilium-agent's backend state and the actual EndpointSlice state, most likely a logic problem in cilium itself.

So we needed to add more debug code for further analysis. Following the previous method, we continued adding debug code deeper into `processServiceEvent` and `processEndpointsEvent` (details omitted here).

Finally, we found a key clue: when adjusting the cluster specification, multiple events for the `default/kubernetes` EndpointSlice are received, some of which have empty backends, while the next event has non-empty backends.

Key debug code:

:::tip[Note]

Printing the invocation of `convertEndpoints` and `UpsertAndReleaseBackends` functions respectively.

:::

```go showLineNumbers title="pkg/loadbalancer/reflectors/k8s.go"
func runServiceEndpointsReflector(ctx context.Context, health cell.Health, p reflectorParams, initServices, initEndpoints func(writer.WriteTxn)) error {
  // ...
  processEndpointsEvent := func(txn writer.WriteTxn, key bufferKey, kind resource.EventKind, allEps allEndpoints) {
    switch kind {
    // ...
    case resource.Upsert:
      backends := convertEndpoints(p.Log, p.ExtConfig, name, allEps.Backends())
      // highlight-next-line
      p.Log.Info("DEBUG: convertEndpoints in processEndpointsEvent", "name", name.String(), "backends", slices.Collect(backends))

      // Find orphaned backends. We are using iter.Seq to avoid unnecessary allocations.
      var orphans iter.Seq[loadbalancer.L3n4Addr] = func(yield func(loadbalancer.L3n4Addr) bool) {
        // ...
      }
      // highlight-next-line
      p.Log.Info("DEBUG: UpsertAndReleaseBackends in processEndpointsEvent", "name", name.String(), "backends", slices.Collect(backends), "orphans", slices.Collect(orphans))
      err = p.Writer.UpsertAndReleaseBackends(txn, name, source.Kubernetes, backends, orphans)
    }
  }
  // ...
}
```

From the debug logs, we could roughly see that when convertEndpoints calculates backends as empty, orphans is not empty. UpsertAndReleaseBackends is called to clean up orphan backends (backends not referenced by any service). From the timing of event processing, there was no corresponding update operation in the APIServer audit logs at that time.

## Investigating APIServer Audit Policy

Checking the file corresponding to the `--audit-policy-file` parameter configured for the TKE cluster's APIServer, we found that the current configuration couldn't possibly ignore the audit of the `default/kubernetes` EndpointSlice. Moreover, we could see kube-apiserver's operation records for this EndpointSlice in the logs, though it seemed like some were missing.

## Developing a Test Program to Observe K8s Events

Since we couldn't see the update operation that clears the `default/kubernetes` EndpointSlice's endpoint in the APIServer audit logs, but we suspected it might exist, we developed a test program to verify. This program ListWatches all events for the `default/kubernetes` Service/EndpointSlice and prints detailed logs.

Finally, we discovered: during cluster specification adjustment, there is indeed an update operation that clears the endpoint of the `default/kubernetes` EndpointSlice, with the content:

```json
{
  "metadata": {
    "name": "kubernetes",
    "namespace": "default",
    "uid": "35f8e338-7ac7-4ac0-ad2b-95d58f800d89",
    "resourceVersion": "2706233134",
    "generation": 140,
    "creationTimestamp": "2025-12-23T12:37:52Z",
    "labels": {
      "kubernetes.io/service-name": "kubernetes"
    },
    "managedFields": [
      {
        "manager": "kube-apiserver",
        "operation": "Update",
        "apiVersion": "discovery.k8s.io/v1",
        "time": "2026-01-08T11:11:55Z",
        "fieldsType": "FieldsV1",
        "fieldsV1": {
          "f:addressType": {},
          "f:endpoints": {},
          "f:metadata": {
            "f:labels": {
              ".": {},
              "f:kubernetes.io/service-name": {}
            }
          },
          "f:ports": {}
        }
      }
    ]
  },
  "addressType": "IPv4",
  "endpoints": null,
  "ports": null
}
```

We can see the endpoints field is null, meaning the endpoint list is cleared.

From managedFields, we can see the operation was initiated by kube-apiserver, but the corresponding update operation couldn't be found in the audit logs.

## APIServer Code Analysis

To understand why we receive an update operation that clears the `default/kubernetes` EndpointSlice's endpoint when adjusting the cluster specification, we need to analyze the relevant Kubernetes code.

EndpointSlices are generally automatically created and managed by kube-controller-manager based on Service definitions, but for the special `default/kubernetes` service, endpoint, and endpointslice, their controller runs in kube-apiserver rather than kube-controller-manager. It synchronizes the master IP list to the corresponding endpoint/endpointslice.

The code for this controller running in kube-apiserver is in `pkg/controlplane/controller/kubernetesservice/controller.go`. When kube-apiserver is recreated, the old kube-apiserver instance is stopped, and stopping goes into the Controller's Stop method:

```go title="pkg/controlplane/controller/kubernetesservice/controller.go"
func (c *Controller) Stop() {
  // ...
  go func() {
    //  Remove own IP from the master IP list
    if err := c.EndpointReconciler.RemoveEndpoints(c.CustomKubernetesServiceName, c.PublicIP, endpointPorts); err != nil {
      klog.Errorf("Unable to remove endpoints from kubernetes service: %v", err)
    }
  }()
}
```

In Stop, `c.EndpointReconciler.RemoveEndpoints` is called to remove its own IP from the master IP list.

Let's look at the RemoveEndpoints implementation:

```go title="pkg/controlplane/reconcilers/lease.go"
func (r *leaseEndpointReconciler) RemoveEndpoints(serviceName string, ip net.IP, endpointPorts []corev1.EndpointPort) error {
  // Delete own lease from etcd /masterleases/{ip}
  if err := r.masterLeases.RemoveLease(ip.String()); err != nil {
    return err
  }

  // Sync master IP list from etcd to endpoint/endpointslice
  return r.doReconcile(serviceName, endpointPorts, true)
}

func (r *leaseEndpointReconciler) doReconcile(serviceName string, endpointPorts []corev1.EndpointPort, reconcilePorts bool) error {
  // Get current master IP list from endpoint object
  e, err := r.epAdapter.Get(corev1.NamespaceDefault, serviceName, metav1.GetOptions{})

  // Get master IP list from etcd
  masterIPs, err := r.masterLeases.ListLeases()
  if err != nil {
    return err
  }

  // Compare the differences between the two master IP lists
  formatCorrect, ipCorrect, portsCorrect := checkEndpointSubsetFormatWithLease(e, masterIPs, endpointPorts, reconcilePorts)

  // If IPs differ, update the master IP list in endpoint, using etcd's master IP list as the source of truth
  if !formatCorrect || !ipCorrect {
    e.Subsets[0].Addresses = make([]corev1.EndpointAddress, len(masterIPs))
    for ind, ip := range masterIPs {
      e.Subsets[0].Addresses[ind] = corev1.EndpointAddress{IP: ip}
    }
  }

  if shouldCreate {
    if _, err = r.epAdapter.Create(corev1.NamespaceDefault, e); errors.IsAlreadyExists(err) {
      err = nil
    }
  } else {
    // Update endpoint/endpointslice
    _, err = r.epAdapter.Update(corev1.NamespaceDefault, e)
  }
  return err
}
```

We can see: the logic for removing own IP from the master IP list is to first remove own IP from the master IP list stored in etcd, then trigger reconciliation of the special `default/kubernetes` endpoint/endpointslice, overwriting it with the master IP list from etcd.

Let's continue to look at the source of the passed IP value (`c.PublicIP`). If kube-apiserver is configured with the `--advertise-address` parameter, this address will be used as its own IP:

```go
  fs.IPVar(&s.AdvertiseAddress, "advertise-address", s.AdvertiseAddress, ""+
    "The IP address on which to advertise the apiserver to members of the cluster. This "+
    "address must be reachable by the rest of the cluster. If blank, the --bind-address "+
    "will be used. If --bind-address is unspecified, the host's default interface will "+
    "be used.")
```

Checking the TKE cluster's kube-apiserver startup parameters, this parameter is configured with the IP address of the `default/kubernetes` endpoint:

```yaml
    - kube-apiserver
    - --advertise-address=169.254.128.7
```

TKE's kube-apiserver is deployed with multiple replicas for high availability by default. Its external address is load-balanced by a VIP starting with `169.254`, which is dynamically allocated when the cluster is created and doesn't change after cluster creation.

All kube-apiserver instances think their IP is this address. Once a kube-apiserver instance enters the stopping process, it removes this address from etcd's master IP list and re-reconciles the `default/kubernetes` endpoint/endpointslice, thereby removing this IP from the endpoint/endpointslice resource as well (update operation).

So why can't we find this update operation in the audit logs? It should be because kube-apiserver was already stopping at that time, causing the final operation audit to not be recorded.

## Cilium Code Analysis

We've confirmed that when TKE's kube-apiserver is recreated, it issues a clearing update operation to the `default/kubernetes` EndpointSlice, but the EndpointSlice corresponding to the `default/kubernetes-intranet` Service has no operations, because this Service is not managed by kube-apiserver and won't be cleared due to kube-apiserver recreation.

So why does the clearing operation on `default/kubernetes` cause the backend associated with `default/kubernetes-intranet` to also be cleared in cilium?

This required further analysis of cilium code. Continuing with the previous debugging method, we added more debug logs.

Finally, we found that in the EndpointSlice update operation, if an address is removed, it goes to `backendRelease` to release the corresponding backend:

```go title="pkg/loadbalancer/writer/writer.go"
func backendRelease(be *loadbalancer.Backend, name loadbalancer.ServiceName) (*loadbalancer.Backend, bool) {
  instances := be.Instances
  if be.Instances.Len() == 1 {
    for k := range be.Instances.All() {
      if k.ServiceName == name {
        return nil, true
      }
    }
  }
  // If Service matches, delete the corresponding instance from the backend
  for k := range be.GetInstancesOfService(name) {
    instances = instances.Delete(k)
  }
  beCopy := *be
  beCopy.Instances = instances
  return &beCopy, beCopy.Instances.Len() == 0
}
```

Looking at the `GetInstancesOfService` implementation:

```go title="pkg/loadbalancer/backend.go"
// pkg/loadbalancer/backend.go
func (be *Backend) GetInstancesOfService(name ServiceName) iter.Seq2[BackendInstanceKey, BackendParams] {
  return be.Instances.Prefix(BackendInstanceKey{ServiceName: name, SourcePriority: 0})
}

type BackendInstanceKey struct {
  ServiceName    ServiceName
  SourcePriority uint8
}

func (k BackendInstanceKey) Key() []byte {
  if k.SourcePriority == 0 { // Key point: when SourcePriority is 0, key equals ServiceName
    return k.ServiceName.Key()
  }
  sk := k.ServiceName.Key()
  buf := make([]byte, 0, 2+len(sk))
  buf = append(buf, sk...)
  return append(buf, ' ', k.SourcePriority)
}
```

From the implementation, we can see that BackendInstanceKey's Key is ServiceName + space + SourcePriority, and when SourcePriority is 0, it's just ServiceName.

Here SourcePriority is fixed at 0 (indicating the data source comes from Kubernetes resources), so the key is always ServiceName. The `GetInstancesOfService` above uses `[]byte` prefix matching to find backend instances. When looking for backend instances of `default/kubernetes`, it also finds backend instances of `default/kubernetes-intranet`. And coincidentally, the backend instance address of `default/kubernetes-intranet` is the same as the backend instance address of `default/kubernetes`. When releasing backend addresses for `default/kubernetes`, the backend instances of `default/kubernetes-intranet` are also released. During kube-apiserver recreation, service-controller's ListWatch connection disconnects and reconnects, then re-reconciles, recording the reconciliation timestamp in the `default/kubernetes-intranet` Service annotation. cilium-agent watches this event and re-reconciles this Service, finding that the corresponding backend is now empty, updating the corresponding eBPF Map. This ultimately causes all addresses related to the `default/kubernetes-intranet` Service to be inaccessible (NodePort, ClusterIP, CLB VIP).

## Refining Reproduction Steps

Based on the previous code analysis, we can deduce that: if Service B's name has Service A's name as a prefix, and they have the same endpoint addresses, then when Service A's endpoint removes an address, Service B's address will also be removed.

Based on this conclusion, we can refine a simplified stable reproduction procedure.

First, save the following yaml to file `test.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: test
  namespace: default
spec:
  type: ClusterIP
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80

---
apiVersion: v1
kind: Service
metadata:
  name: test-extended
  namespace: default
spec:
  type: ClusterIP
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80

---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: test
  namespace: default
  labels:
    kubernetes.io/service-name: test
addressType: IPv4
endpoints:
- addresses:
  - 1.1.1.1
ports:
- port: 80
  protocol: TCP

---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: test-extended
  namespace: default
  labels:
    kubernetes.io/service-name: test-extended
addressType: IPv4
endpoints:
- addresses:
  - 1.1.1.1
ports:
- port: 80
  protocol: TCP
```

Then apply it to the cluster and observe the k8s resource status:

```txt
$ kubectl apply -f test.yaml
service/test created
service/test-extended created
endpointslice.discovery.k8s.io/test created
endpointslice.discovery.k8s.io/test-extended created
$ kubectl -n default get svc | grep test
test                  ClusterIP      192.168.71.144   <none>           80/TCP          86s
test-extended         ClusterIP      192.168.92.25    <none>           80/TCP          86s
$ kubectl -n default get endpointslices | grep test
test                        IPv4          80      1.1.1.1         93s
test-extended               IPv4          80      1.1.1.1         93s
```

Observe that cilium's backend addresses for Services starting with test match the EndpointSlice addresses:

```txt
$ kubectl -n kube-system exec ds/cilium -- cilium shell -- db/show frontends | grep test
192.168.71.144:80/TCP     ClusterIP      default/test                                          1.1.1.1:80/TCP                                       Done     2m25s
192.168.92.25:80/TCP      ClusterIP      default/test-extended                                 1.1.1.1:80/TCP                                       Done     2m25s
```

Then patch the `test` EndpointSlice to remove the address, and observe cilium's in-memory Service state:

```txt
$ kubectl -n default patch endpointslices test -p '{"endpoints": []}'
endpointslice.discovery.k8s.io/test patched
$ kubectl -n kube-system exec ds/cilium -- cilium shell -- db/show frontends | grep test
192.168.71.144:80/TCP     ClusterIP      default/test                                                                                               Done     2s
192.168.92.25:80/TCP      ClusterIP      default/test-extended                                 1.1.1.1:80/TCP                                       Done     5m14s
```

We can see that the `test` Service's backend address is now empty, while the `test-extended` Service's backend address is unaffected.

Then patch the `test-extended` Service to trigger cilium-agent to re-reconcile this Service, and observe cilium's in-memory Service state again:

```txt
$ kubectl -n default patch service test-extended -p '{"metadata": {"annotations": {"test": "'$(date +%s)'"}}}'
service/test-extended patched
$ kubectl -n kube-system exec ds/cilium -- cilium shell -- db/show frontends | grep test
192.168.71.144:80/TCP     ClusterIP      default/test                                                                                               Done     5m38s
192.168.92.25:80/TCP      ClusterIP      default/test-extended                                                                                      Done     7s
```

We can see that after re-reconciliation, the `test-extended` Service's backend address is also cleared. Looking at this Service's backend data at the eBPF level, there's also no backend and it's non-routable:

```bash
$ kubectl -n kube-system exec ds/cilium -- cilium bpf lb list | grep 192.168.92.25
192.168.92.25:80/TCP (0)      0.0.0.0:0 (21) (0) [ClusterIP, non-routable]
```

Phenomenon summary: Removing an endpoint from Service A's EndpointSlice can actually cause all requests to Service B to fail.

## How to Fix?

The key is in the `BackendInstanceKey.Key` implementation. When SourcePriority is 0, we should also add a space at the end. This will solve the problem. Using the current issue as an example, `default/kubernetes ` will no longer be a prefix of `default/kubernetes-intranet ` because it has a trailing space.

The issue and fix have been submitted to the community:

- Issue: https://github.com/cilium/cilium/issues/43619
- PR: https://github.com/cilium/cilium/pull/43620

## Afterword

The debugging process was extremely complex. We suspected issues with the kernel, k8s, and TKE, but ultimately identified it as a bug in cilium. The troubleshooting steps summarized in this article assume expertise in the underlying principles and code implementation of k8s and cilium, as well as proficiency in their respective debugging methods and tools - these are the ideal steps. The actual process was many times more complex, with many unrelated debugging details removed.

When facing giant complex projects like k8s and cilium, using AI to assist with analysis and review can significantly improve efficiency. The test program was also written by AI.

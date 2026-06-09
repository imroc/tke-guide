# Troubleshooting: Connecting to APIServer Returns "operation not permitted"

## Symptoms

After running normally for many days, a Cilium-installed TKE cluster suddenly became unresponsive. All cilium-agent pods on every node were in `CrashLoopBackoff` state and could not start successfully.

## Scene Analysis

Analyzing the cilium pod status, the `config` init container kept failing to start, with the following error log:

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

The log shows connection to the apiserver failed with `operation not permitted`. Trying to curl the apiserver from the node manually also returned the same error:

```txt
$ curl -v -k https://10.15.1.8:443
*   Trying 10.15.1.8:443...
* Immediate connect fail for 10.15.1.8: Operation not permitted
* Failed to connect to 10.15.1.8 port 443 after 0 ms: Couldn't connect to server
* Closing connection
curl: (7) Failed to connect to 10.15.1.8 port 443 after 0 ms: Couldn't connect to server
```

## Analyzing Historical Logs

Comprehensively analyzing the cluster event logs and APIServer audit logs, it was found that after a cilium update (helm upgrade modifying cilium configuration), the cilium pods were recreated and then never started successfully — it just wasn't noticed initially.

Before the cilium pods were recreated, cilium-agent was also logging similar errors:

```txt
time=2026-01-03T23:17:48.232653954Z level=info msg="/healthz returning unhealthy" module=agent.infra.agent-healthz state=Failure error="1.18.6 (v1.18.6-7d4d8932)    Kubernetes service is not ready: Get \"https://10.15.1.8:443/version\": dial tcp 10.15.1.8:443: connect: operation not permitted"
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

## Preliminary Root Cause Analysis

The `operation not permitted` error indicates the packet destined for the apiserver never left the node — it was dropped by the kernel (normally, if the apiserver were unreachable, the error would be `timeout` or `connection refused`).

The apiserver address configured for cilium was the CLB address created when the TKE cluster enabled internal network access (a LoadBalancer type Service named `kubernetes-intranet`):

```bash
$ kubectl -n default get svc kubernetes-intranet
NAME                  TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)         AGE
kubernetes-intranet   LoadBalancer   192.168.60.179   10.15.1.8     443:30965/TCP   11d
```

Since Cilium was installed with kubeProxyReplacement enabled, traffic to the apiserver is intercepted by Cilium's eBPF program and forwarded directly to the backend address, bypassing the CLB (this behavior is consistent with native Kubernetes kube-proxy).

Checking the eBPF data written by cilium-agent:

```txt
$ kubectl -n kube-system exec cilium-kddvm -- cilium bpf lb list
SERVICE ADDRESS               BACKEND ADDRESS (REVNAT_ID) (SLOT)
10.15.1.8:443/TCP (0)         0.0.0.0:0 (14) (0) [LoadBalancer]
0.0.0.0:30965/TCP (0)         0.0.0.0:0 (12) (0) [NodePort, non-routable]
192.168.60.179:443/TCP (0)    0.0.0.0:0 (15) (0) [ClusterIP, non-routable]
```

You can see that the server addresses related to the `kubernetes-intranet` svc all have empty backend addresses (NodePort, CLB VIP, ClusterIP).

Checking the in-memory data of the cilium-agent process also showed empty backends:

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

The backend addresses recorded in cilium come from the EndpointSlice associated with the k8s Service. Checking the EndpointSlice for this Service showed that addresses existed and the association with the Service was correct:

```txt
$ kubectl get endpointslices.discovery.k8s.io | grep kubernetes-intranet
kubernetes-intranet-qxgk4   IPv4          60002   169.254.128.7   11d

$ kubectl get endpointslices.discovery.k8s.io kubernetes-intranet-qxgk4 -o yaml | grep service-name
    kubernetes.io/service-name: kubernetes-intranet
```

One possibility came to mind:

1. When cilium first connects to the apiserver, since cilium is not yet ready and eBPF data has not been initialized, the packets to the apiserver actually reach the CLB.
2. When the EndpointSlice for `kubernetes-intranet` is recreated or endpoints are temporarily deleted, cilium temporarily clears the backend data in eBPF.
3. When the endpoint is added back, since cilium has already initialized the eBPF program and data, subsequent packets to the apiserver are intercepted by the eBPF program.
4. Since the eBPF backend data for `kubernetes-intranet` was temporarily cleared, packets to this address are considered to have no corresponding backend, and the error `operation not permitted` is returned.

This creates a circular dependency — any change to the EndpointSlice for `kubernetes-intranet` would make the node unable to reach the apiserver via the corresponding CLB address.

Manually deleting and recreating the EndpointSlice for `kubernetes-intranet` did reproduce the issue.

However, going back to the current problem, the EndpointSlice for this Service had always existed and was never deleted or recreated:

```txt
$ kubectl get endpointslices kubernetes-intranet-qxgk4
NAME                        ADDRESSTYPE   PORTS   ENDPOINTS       AGE
kubernetes-intranet-qxgk4   IPv4          60002   169.254.128.7   11d
```

Checking the cluster audit logs, this EndpointSlice object had no patch/update operations. So, this could not be the cause.

At this point, the root cause had not been found, but a workaround was identified: when installing cilium, do not use the CLB address as the apiserver address. Instead, use the endpoint address of the `kubernetes` svc (the address starting with 169.254, which never changes after cluster creation). This address is not intercepted by cilium and does not have this issue.

Without finding the root cause, it was impossible to determine if other scenarios would also have problems, posing a significant risk. Further investigation was needed.

## Finding the Reproduction Condition

To investigate further, the reproduction condition had to be found first.

After various hypotheses and attempts (skipping ten thousand words here), **the reproduction condition was finally discovered: adjusting the TKE cluster规格 (spec/size).**

The TKE cluster spec can be adjusted automatically or manually. After manually adjusting the cluster spec, the issue was reproduced, though sometimes not on all nodes.

This reproduction condition had a clear characteristic: the apiserver would restart, causing all ListWatch connections to disconnect.

## Adding Debug Code to Cilium

Based on the previous investigation, it was clear that the backend state recorded internally by cilium did not match the actual EndpointSlice resource — the former was empty, while the latter had always existed and never changed.

Therefore, the issue was suspected to be in cilium's Service/EndpointSlice synchronization logic. The key handler function was identified as `runServiceEndpointsReflector` (`pkg/loadbalancer/reflectors/k8s.go`). Two debug log lines were added to see which code path would be taken during reproduction — `processServiceEvent` or `processEndpointsEvent`, or both:

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

Build the image, retag, and push to a private registry:

```bash
make dev-docker-image-debug
docker tag quay.io/cilium/cilium-dev:latest docker.io/imroc/cilium:dev
docker push docker.io/imroc/cilium:dev
```

Then replace the cilium image in the cluster:

```bash
kubectl -n kube-system patch ds cilium --patch '{"spec": {"template": {"spec": {"containers": [{"name": "cilium-agent","image": "docker.io/imroc/cilium:dev" }]}}}}'
```

Then adjust the cluster spec to reproduce the issue. It was observed that during the spec adjustment:

1. cilium-agent received events for the `default/kubernetes-intranet` Service, but no corresponding EndpointSlice events.
2. cilium-agent received events for the `default/kubernetes` EndpointSlice, but no corresponding Service events.

## Analyzing APIServer Audit Logs

Searching the cluster's **Monitoring & Alerts - Logs - Audit Logs - Global Search** with the following CQL for audit logs related to the `kubernetes-intranet` and `kubernetes` Services and their associated EndpointSlices:

```txt
objectRef.namespace:"default" AND objectRef.name:"kubernetes*" AND (NOT verb:get NOT verb:watch) AND (objectRef.resource:"services" OR objectRef.resource:"endpointslices")
```

Based on the logs, during the cluster spec adjustment:

1. The `default/kubernetes-intranet` Service had some patch operations, but its corresponding EndpointSlice object had no operations.
2. The `default/kubernetes` Service had no operations, but its corresponding EndpointSlice had update operations.

Further analysis:

1. The patch operations on `default/kubernetes-intranet` came from TKE's service-controller. Since this Service is of type LoadBalancer, it is handled by service-controller. When the cluster spec is adjusted, the apiserver restarts, causing service-controller's existing ListWatch connections to disconnect, then automatically reconnect and reconcile. After reconciliation, a patch operation is issued to record the latest reconciliation timestamp in the Service annotations.
2. The update operations on the `default/kubernetes` EndpointSlice came from kube-apiserver. The content of the update was identical to before the change, both pointing to the TKE apiserver address 169.254.128.7.

## Further Debugging

Back to the key question: why, during the cluster spec adjustment, did the `default/kubernetes-intranet` Service's corresponding EndpointSlice remain unchanged, yet its backends in cilium-agent memory were cleared?

This clearly indicated that the backend state in cilium-agent was inconsistent with the actual EndpointSlice state, most likely a bug in cilium itself.

So more debug code was needed. Following the same approach, more debug logging was added inside `processServiceEvent` and `processEndpointsEvent` (skipping another ten thousand words here).

Finally, a key clue was discovered: during the cluster spec adjustment, multiple events for the `default/kubernetes` EndpointSlice were received, some with empty backends, and the next event would have backends again.

Key debug code:

:::tip[Note]

Print the calls to `convertEndpoints` and `UpsertAndReleaseBackends` respectively.

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

From the debug logs, when `convertEndpoints` computed empty backends and orphans was not empty, `UpsertAndReleaseBackends` was called to clean up orphan backends (backends not referenced by any service). Looking at the event processing timestamps, there was no corresponding update operation in the APIServer audit logs.

## Investigating APIServer Audit Policy

Checking the file configured by the `--audit-policy-file` parameter of the TKE cluster's kube-apiserver, the current configuration should not ignore the audit of the `default/kubernetes` EndpointSlice. The logs did show kube-apiserver's operations on this EndpointSlice, but some seemed to be missing.

## Developing a Test Program to Observe k8s Events

The APIServer audit logs did not show an update operation that cleared the endpoints of the `default/kubernetes` EndpointSlice. However, suspicion remained, so a test program was developed to verify. This program ListWatch'd all events for the `default/kubernetes` Service/EndpointSlice and printed detailed logs.

Finally, it was found that during the cluster spec adjustment, an update operation that cleared the endpoints of the `default/kubernetes` EndpointSlice was indeed received. The content was:

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

The `endpoints` field was null, meaning the endpoint list was cleared.

From `managedFields`, this was an operation initiated by kube-apiserver, but no corresponding update operation was found in the audit logs.

## Code Analysis of APIServer

To understand why the `default/kubernetes` EndpointSlice received an update clearing its endpoints during the cluster spec adjustment, the relevant Kubernetes code needed to be analyzed.

EndpointSlices are typically created and managed automatically by kube-controller-manager based on Service definitions. However, for the special `default/kubernetes` service, endpoint, and endpointslice, the controller runs inside kube-apiserver rather than kube-controller-manager. It synchronizes the master IP list into the corresponding endpoint/endpointslice.

This controller running in kube-apiserver is located in `pkg/controlplane/controller/kubernetesservice/controller.go`. When kube-apiserver is restarted, the old instance is stopped, triggering the Controller's Stop method:

```go title="pkg/controlplane/controller/kubernetesservice/controller.go"
func (c *Controller) Stop() {
  // ...
  go func() {
    //  Remove its own IP from the master IP list
    if err := c.EndpointReconciler.RemoveEndpoints(c.CustomKubernetesServiceName, c.PublicIP, endpointPorts); err != nil {
      klog.Errorf("Unable to remove endpoints from kubernetes service: %v", err)
    }
  }()
}
```

In `Stop`, `c.EndpointReconciler.RemoveEndpoints` is called to remove its own IP from the master IP list.

Looking at the implementation of `RemoveEndpoints`:

```go title="pkg/controlplane/reconcilers/lease.go"
func (r *leaseEndpointReconciler) RemoveEndpoints(serviceName string, ip net.IP, endpointPorts []corev1.EndpointPort) error {
  // Remove its own lease from etcd /masterleases/{ip}
  if err := r.masterLeases.RemoveLease(ip.String()); err != nil {
    return err
  }

  // Sync the master IP list from etcd to endpoint/endpointslice
  return r.doReconcile(serviceName, endpointPorts, true)
}

func (r *leaseEndpointReconciler) doReconcile(serviceName string, endpointPorts []corev1.EndpointPort, reconcilePorts bool) error {
  // Get the current master IP list from the endpoint object
  e, err := r.epAdapter.Get(corev1.NamespaceDefault, serviceName, metav1.GetOptions{})

  // Get the master IP list from etcd
  masterIPs, err := r.masterLeases.ListLeases()
  if err != nil {
    return err
  }

  // Compare the two master IP lists
  formatCorrect, ipCorrect, portsCorrect := checkEndpointSubsetFormatWithLease(e, masterIPs, endpointPorts, reconcilePorts)

  // If IPs differ, update the endpoint's master IP list using etcd's list as source of truth
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

The logic is clear: to remove its own IP from the master IP list, it first removes its own lease from etcd's master IP list, then triggers reconciliation of the `default/kubernetes` endpoint/endpointslice, overwriting with etcd's master IP list as the source of truth.

Now, looking at the source of its own IP value (`c.PublicIP`): if kube-apiserver is configured with `--advertise-address`, this address is used as its own IP:

```go
  fs.IPVar(&s.AdvertiseAddress, "advertise-address", s.AdvertiseAddress, ""+
    "The IP address on which to advertise the apiserver to members of the cluster. This "+
    "address must be reachable by the rest of the cluster. If blank, the --bind-address "+
    "will be used. If --bind-address is unspecified, the host's default interface will "+
    "be used.")
```

Checking the startup parameters of the TKE cluster's kube-apiserver, this parameter was configured with the IP address of the `default/kubernetes` endpoint:

```yaml
    - kube-apiserver
    - --advertise-address=169.254.128.7
```

TKE's kube-apiserver is typically deployed with multiple replicas for high availability. Its external address is load-balanced by a VIP starting with `169.254`, which is dynamically allocated when the cluster is created and never changes thereafter.

All kube-apiserver instances consider this address as their own IP. When any kube-apiserver instance enters the shutdown process, it removes this address from etcd's master IP list and reconciles the `default/kubernetes` endpoint/endpointslice, which also removes this IP from the endpoint/endpointslice resource (update operation).

So, why couldn't this update operation be found in the audit logs? Probably because the kube-apiserver was already shutting down at that point, and the final operation audit was not recorded.

## Cilium Code Analysis

It was confirmed that when the TKE kube-apiserver restarts, it issues an update operation that clears the endpoints of the `default/kubernetes` EndpointSlice. However, the `default/kubernetes-intranet` Service's corresponding EndpointSlice had no operations, since this Service is not managed by kube-apiserver and is not cleared during apiserver restarts.

So, why did clearing `default/kubernetes` in cilium also clear the backends associated with `default/kubernetes-intranet`?

This required deeper analysis of the cilium code. Following the same debugging approach, more debug logging was added.

Finally, it was discovered that when an EndpointSlice update removes an address, it reaches `backendRelease` to release the corresponding backend:

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
  // If the Service matches, delete the corresponding instance from the backend
  for k := range be.GetInstancesOfService(name) {
    instances = instances.Delete(k)
  }
  beCopy := *be
  beCopy.Instances = instances
  return &beCopy, beCopy.Instances.Len() == 0
}
```

Looking at the implementation of `GetInstancesOfService`:

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
  if k.SourcePriority == 0 { // Key point: when SourcePriority is 0, the key equals ServiceName
    return k.ServiceName.Key()
  }
  sk := k.ServiceName.Key()
  buf := make([]byte, 0, 2+len(sk))
  buf = append(buf, sk...)
  return append(buf, ' ', k.SourcePriority)
}
```

From the implementation, the Key of BackendInstanceKey is `ServiceName + space + SourcePriority`. When SourcePriority is 0, it is just the `ServiceName`.

Here, SourcePriority is always 0 (indicating the data source is from Kubernetes resources), so the key is always just the ServiceName. Since `GetInstancesOfService` uses `[]byte` prefix matching to find backend instances, looking up backend instances for `default/kubernetes` would also find those for `default/kubernetes-intranet`. And since the backend instance address for `default/kubernetes-intranet` happens to be the same as that for `default/kubernetes`, when releasing the backend address for `default/kubernetes`, the backend instance for `default/kubernetes-intranet` was also released. During the kube-apiserver restart, the service-controller's ListWatch connections would disconnect and reconnect, performing reconciliation and recording the reconciliation timestamp in the `default/kubernetes-intranet` Service annotations. cilium-agent watched this event and also reconciled this Service, finding its backends empty, and updated the corresponding eBPF Map. This eventually caused all addresses related to `default/kubernetes-intranet` (NodePort, ClusterIP, CLB VIP) to become unreachable.

## Extracting Reproduction Steps

Based on the code analysis, it can be deduced: if Service B's name is a prefix of Service A's name, and their corresponding endpoints share the same address, then when an address is removed from Service A's endpoint, the same address in Service B will also be removed.

From this conclusion, a simplified and stable reproduction procedure can be derived.

First, save the following yaml to `test.yaml`:

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

Then apply it to the cluster and observe the k8s resource state:

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

Observe the backend addresses of the Services starting with `test` in both cilium and k8s, consistent with the EndpointSlice:

```txt
$ kubectl -n kube-system exec ds/cilium -- cilium shell -- db/show frontends | grep test
192.168.71.144:80/TCP     ClusterIP      default/test                                          1.1.1.1:80/TCP                                       Done     2m25s
192.168.92.25:80/TCP      ClusterIP      default/test-extended                                 1.1.1.1:80/TCP                                       Done     2m25s
```

Then patch the `test` EndpointSlice to remove the address, and observe the Service state in cilium's memory:

```txt
$ kubectl -n default patch endpointslices test -p '{"endpoints": []}'
endpointslice.discovery.k8s.io/test patched
$ kubectl -n kube-system exec ds/cilium -- cilium shell -- db/show frontends | grep test
192.168.71.144:80/TCP     ClusterIP      default/test                                                                                               Done     2s
192.168.92.25:80/TCP      ClusterIP      default/test-extended                                 1.1.1.1:80/TCP                                       Done     5m14s
```

Now the `test` Service's backend address is empty, while the `test-extended` Service's backend address remains unaffected.

Next, patch the `test-extended` Service to trigger cilium-agent to reconcile this Service, then re-observe the Service state in cilium's memory:

```txt
$ kubectl -n default patch service test-extended -p '{"metadata": {"annotations": {"test": "'$(date +%s)'"}}}'
service/test-extended patched
$ kubectl -n kube-system exec ds/cilium -- cilium shell -- db/show frontends | grep test
192.168.71.144:80/TCP     ClusterIP      default/test                                                                                               Done     5m38s
192.168.92.25:80/TCP      ClusterIP      default/test-extended                                                                                      Done     7s
```

After reconciliation, the `test-extended` Service's backend address was also cleared. Checking this Service's backend data at the eBPF level, there were also no backends, showing as non-routable:

```bash
$ kubectl -n kube-system exec ds/cilium -- cilium bpf lb list | grep 192.168.92.25
192.168.92.25:80/TCP (0)      0.0.0.0:0 (21) (0) [ClusterIP, non-routable]
```

Summary of the phenomenon: removing an endpoint from Service A's EndpointSlice could cause all requests to Service B to fail.

## How to Fix?

The key is in the implementation of `BackendInstanceKey.Key`. When SourcePriority is 0, adding a trailing space at the end would fix this. Using the current issue as an example, `default/kubernetes ` would no longer be a prefix of `default/kubernetes-intranet ` because it has a trailing space.

The issue and fix have been submitted to the community:

- Issue: https://github.com/cilium/cilium/issues/43619
- PR: https://github.com/cilium/cilium/pull/43620

The PR has been merged. Upgrading cilium in the next release should resolve the issue.

## Postscript

The root cause analysis was extremely complex. Suspicions included the kernel, k8s, and TKE, but ultimately it was identified as a cilium bug. The troubleshooting steps summarized in this article assume proficiency in k8s and cilium internals, code implementation, and debugging methods and tools. The actual process was many times more complex, with many irrelevant debugging details removed.

For large complex projects like k8s and cilium, using AI-assisted analysis and organization can significantly improve efficiency. The test program was also written by AI.

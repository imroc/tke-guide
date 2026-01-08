# 问题排查：访问 APIServer 报错 operation not permitted

## 问题现象

安装了 cilium 的 TKE 集群在正常运行很多天后，发现陷入瘫痪，所有节点的 cilium-agent 处于 `CrashLoopBackoff` 状态，无法成功启动。

## 分析现场

分析 cilium pod 状态，发现是 config 这个 init 容器一直启动失败，报错日志如下：

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

日志显示连接 apiserver 失败，报错 `operation not permitted`，尝试在节点上手动 curl 测试连接 apiserver，发现也报这个错：

```txt
$ curl -v -k https://10.15.1.8:443
*   Trying 10.15.1.8:443...
* Immediate connect fail for 10.15.1.8: Operation not permitted
* Failed to connect to 10.15.1.8 port 443 after 0 ms: Couldn't connect to server
* Closing connection
curl: (7) Failed to connect to 10.15.1.8 port 443 after 0 ms: Couldn't connect to server
```

## 分析历史日志

综合分析集群的事件日志和 APIServer 审计日志，发现是在一次 cilium 更新（执行 helm upgrade 修改 cilium 配置进行更新）后，cilium pod 被重建，然后就一直无法启动成功，只是一开始没关注到。

在 cilium pod 被重建之前，cilium-agent 也是报类似的错误日志：

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

## 初步原因分析

从 `operation not permitted` 这个错误可知，访问 apiserver 的数据包并未出节点，直接被内核丢弃了（正常情况下，如果是 apiserver 不通，也是 `timeout` 或 `connection refused` 之类的错误）。

给 cilium 配置的 apiserver 地址是 TKE 集群开启内网访问后的 CLB 地址（kubernetes-intranet 这个 LoadBalancer 类型 Service 自动创建出的 CLB）：

```bash
$ kubectl -n default get svc kubernetes-intranet
NAME                  TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)         AGE
kubernetes-intranet   LoadBalancer   192.168.60.179   10.15.1.8     443:30965/TCP   11d
```

由于安装了 cilium 且启用了 kubeProxyReplacement，访问 apiserver 的流量也会直接被 cilium 的 ebpf 程序拦截并直接转发到后端地址，流量并不会经过 CLB（这个行为也与原生 Kubernetes 的 kube-proxy 一致）。

检查 cilium-agent 写入的 ebpf 数据:

```txt
$ kubectl -n kube-system exec cilium-kddvm -- cilium bpf lb list
SERVICE ADDRESS               BACKEND ADDRESS (REVNAT_ID) (SLOT)
10.15.1.8:443/TCP (0)         0.0.0.0:0 (14) (0) [LoadBalancer]
0.0.0.0:30965/TCP (0)         0.0.0.0:0 (12) (0) [NodePort, non-routable]
192.168.60.179:443/TCP (0)    0.0.0.0:0 (15) (0) [ClusterIP, non-routable]
```

可以看到 `kubernetes-intranet` 这个 svc 相关的 server address 对应的 backend address 都为空（NodePort、CLB VIP、ClusterIP）。

再查看 cilium-agent 进程内存中的数据，发现同样也都是空的：

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

cilium 中记录的 backend 地址来源是 k8s Service 关联的 EndpointSlice，查看改 Service 对应的 EndpointSlice 是存在地址的，且确认与 Service 的关联关系也是正确的：

```txt
$ kubectl get endpointslices.discovery.k8s.io | grep kubernetes-intranet
kubernetes-intranet-qxgk4   IPv4          60002   169.254.128.7   11d

$ kubectl get endpointslices.discovery.k8s.io kubernetes-intranet-qxgk4 -o yaml | grep service-name
    kubernetes.io/service-name: kubernetes-intranet
```

想到一种可能性：

1. cilium 第一次连接 apiserver 时，由于 cilium 还未就绪，ebpf 数据还未初始化，访问 apiserver 的数据包会真正到 CLB。
2. 当 `kubernetes-intranet` 对应的 EndpointSlice 重建或临时删除 endpoint 时，cilium 会临时清空 ebpf 中的 backend 数据。
3. 当 endpoint 重新加回来时，由于 cilium 已经初始化过 ebpf 程序和数据，后续访问 apiserver 的数据包会被 ebpf 程序拦截处理。
4. 由于 `kubernetes-intranet` 对应的 ebpf 的 backend 数据被临时清空，访问这个地址的数据包被认为没有对应的 backend，就报错 `operation not permitted`。

这样形成了循环依赖，只要 `kubernetes-intranet` 对应的 EndpointSlice 一变更就导致节点再也无法通过对应的 CLB 地址访问 apiserver。

通过手动删除重建 `kubernetes-intranet` 对应的 EndpointSlice，确实也能复现改问题。

但实际上，这个 Service 对应的 EndpointSlice 一直是存在的，没有被删除重建：

```txt
$ kubectl get endpointslices kubernetes-intranet-qxgk4
NAME                        ADDRESSTYPE   PORTS   ENDPOINTS       AGE
kubernetes-intranet-qxgk4   IPv4          60002   169.254.128.7   11d
```

并且查看集群审计，这个 EndpointSlice 对象也没有任何 patch/update 操作，所以，不可能是这个原因导致的。

查到这里，还没找到根因，但可以得出规避方案：安装 cilium 时配置的 apiserver 地址不使用 CLB 地址，直接使用 `kubernetes` 这个 svc 的 endpoint 地址（169.254 开头的地址，集群创建后就不会再变），该地址不会被 cilium 拦截转发，不存在这个问题。

没有查到根因，无法确定其它场景是否也会有问题，存在重大隐患，所以还需进一步排查。

## 寻找复现条件

要进一步排查，得先找到复现条件，然后才好继续调试分析。

经过各种怀疑和尝试（此处省略一万字），**最后终于发现了复现条件：调整 TKE 集群规格**。

TKE 集群规格可自动或手动调整，尝试手动调整集群规格后，问题复现了，但有时候不是所有节点都复现。

这个复现条件有个明显的特征：apiserver 会重建，所有 ListWatch 操作都会断连。

## 给 cilium 增加调试代码

根据之前的排查，明显可以看出是 cilium 内部记录的 backend 状态与实际的 EndpointSlice 资源不匹配，前者是空的，后者是一直存在且没有变动的。

所以，猜测是 cilium 同步 Service/EndpointSlice 时的逻辑问题，定位到关键处理函数是 `runServiceEndpointsReflector`(`pkg/loadbalancer/reflectors/k8s.go`)，先加两行调试日志，看复现时代码路径会走 processServiceEvent 还是 processEndpointsEvent，或者都会走：

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

编译镜像，重新 tag 并推送到自己的镜像仓库：

```bash
make dev-docker-image-debug
docker tag quay.io/cilium/cilium-dev:latest docker.io/imroc/cilium:dev
docker push docker.io/imroc/cilium:dev
```

然后替换集群中的 cilium 镜像：

```bash
kubectl -n kube-system patch ds cilium --patch '{"spec": {"template": {"spec": {"containers": [{"name": "cilium-agent","image": "docker.io/imroc/cilium:dev" }]}}}}'
```

然后调整集群规格来复现问题，可以观察到在调整集群规格时：

1. cilium-agent 会收到 `default/kubernetes-intranet` 这个 Service 的事件，没有对应的 EndpointSlice 事件。
2. cilium-agent 会收到 `default/kubernetes` 这个 EndpointSlice 事件，没有对应的 Service 事件。

## 分析 APIServer 审计

在集群的 **监控告警-日志-审计日志-全局搜索** 中使用下面的 CQL `kubernetes-intranet` 和 `kubernetes` 这两个 Service 及其关联的 EndpointSlice 相关审计日志：

```txt
objectRef.namespace:"default" AND objectRef.name:"kubernetes*" AND (NOT verb:get NOT verb:watch) AND (objectRef.resource:"services" OR objectRef.resource:"endpointslices")
```

根据日志清理可以发现，在调整集群规格时：

1. `default/kubernetes-intranet` 这个 Service 会有一些 patch 操作，对应的 EndpointSlice 对象没有任何操作。
2. `default/kubernetes` 这个 Service 没有任何操作，对应的 EndpointSlice 有 update 操作。

进一步分析：

1. `default/kubernetes-intranet` 这个 Service 的 patch 操作来自 TKE 的 service-controller，因为这个 Service 是 LoadBalancer 类型的，会被 service-controller 处理，当调整集群规格时，apiserver 重建，导致 service-controller 存量 ListWatch 连接断开，然后自动重连并重新对账，对账完成后发起 patch 操作，将最新的对账时间戳记录到 Service 注解中。
2. `default/kubernetes` 这个 EndpointSlice 的 update 操作来自 kube-apiserver，update 的内容与变更之前没有任何区别，都是指向的 TKE 的 apiserver 地址 169.254.128.7。

## 进一步调试

回到现在问题的关键：为什么调整集群规格时，`default/kubernetes-intranet` 这个 Service 对应的 EndpointSlice 并没有任何变动，cilium-agent 内存中对应的 backend 却清空了？

这个可以明确是 cilium-agent 中的 backend 状态与实际的 EndpointSlice 状态不一致，大概率是 cilium 自身的逻辑问题。

所以还需进一步加更多的调试代码来分析，按照前面的方法，继续深入 `processServiceEvent` 和 `processEndpointsEvent` 加调试代码（此处再省略一万字）。

最后发现一个关键疑点：调整集群规格时，会收到多个 `default/kubernetes` 这个 EndpointSlice 的事件，其中会有 backends 为空的情况，下一次事件中 backends 又不为空了。

关键调试代码：

:::tip[说明]

分别打印 `convertEndpoints` 和 `UpsertAndReleaseBackends` 函数的调用情况。

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

从调试日志中大致可以看出，当 convertEndpoints 计算出 backends 为空时，orphans 不为空，调用 UpsertAndReleaseBackends 来清理孤儿 backend（没有被任何 service 引用的 backend），从处理事件的时间点看，此时 APIServer 审计日志中并没有对应的 update 操作。

## 排查 APIServer 审计策略

查看 TKE 集群的 APIServer 配置的 `--audit-policy-file` 参数对应的文件内容，发现当前配置不可能会忽略 `default/kubernetes` 这个 EndpointSlice 的审计，而且从日志中也能看到 kube-apiserver 对这个 EndpointSlice 的操作记录，只是感觉像是有缺失。

## 开发测试程序观察 k8s 事件

从 APIServer 审计日志中并不能看到 `default/kubernetes` 这个 EndpointSlice 的 endpoint 置空的 update 操作，但怀疑可能存在，所以又开发了一个测试程序来验证，该程序会 ListWatch `default/kubernetes` 这个 Service/EndpointSlice 的所有事件，并打印详细日志。

最后发现：在调整集群规格时，确实会收到 `default/kubernetes` 这个 EndpointSlice 的 endpoint 置空的 update 操作，内容是：

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

可以看到 endpoints 字段为 null，也就是会将 endpoint 列表置空。

从 managedFields 中可以看到是 kube-apiserver 发起的操作，但在审计日志中却找不到对应的 update 操作。

## APIServer 代码梳理

为了搞清楚调整集群规格为什么时会收到 `default/kubernetes` 这个 EndpointSlice 的 endpoint 置空的 update 操作，我们需要梳理下 Kubernetes 相关代码。

EndpointSlice 一般是 kube-controller-mananger 根据 Service 的定义自动创建和管理的，但 `default/kubernetes` 这个特殊的 service、endpoint、endpointslice，其 controller 运行在 kube-apiserver 中而非 kube-controller-manager，它会将 master 的 ip 列表同步到相应的 endpoint/endpointslice 中。

这个在 kube-apiserver 中运行的 controller 代码在 `pkg/controlplane/controller/kubernetesservice/controller.go`，在 kube-apiserver 重建时会停止旧的 kube-apiserver 实例，停止时会走到 Controller 的 Stop 方法中:

```go title="pkg/controlplane/controller/kubernetesservice/controller.go"
func (c *Controller) Stop() {
  // ...
  go func() {
    //  将自己的 ip 从 master ip 列表中移除
    if err := c.EndpointReconciler.RemoveEndpoints(c.CustomKubernetesServiceName, c.PublicIP, endpointPorts); err != nil {
      klog.Errorf("Unable to remove endpoints from kubernetes service: %v", err)
    }
  }()
}
```

在 Stop 中，会调用 `c.EndpointReconciler.RemoveEndpoints` 将自己的 ip 从 master ip 列表中移除。

再看下 RemoveEndpoints 的实现：

```go title="pkg/controlplane/reconcilers/lease.go"
func (r *leaseEndpointReconciler) RemoveEndpoints(serviceName string, ip net.IP, endpointPorts []corev1.EndpointPort) error {
  // 从 etcd /masterleases/{ip} 删除自己的 lease
  if err := r.masterLeases.RemoveLease(ip.String()); err != nil {
    return err
  }

  // 将 etcd 中的 master ip 列表同步到 endpoint/endpointslice 中
  return r.doReconcile(serviceName, endpointPorts, true)
}

func (r *leaseEndpointReconciler) doReconcile(serviceName string, endpointPorts []corev1.EndpointPort, reconcilePorts bool) error {
  // 从 endpoint 对象中获取当前 master ip 列表
  e, err := r.epAdapter.Get(corev1.NamespaceDefault, serviceName, metav1.GetOptions{})

  // 从 etcd 中获取 master ip 列表
  masterIPs, err := r.masterLeases.ListLeases()
  if err != nil {
    return err
  }

  // 对比两个 master ip 列表的差异
  formatCorrect, ipCorrect, portsCorrect := checkEndpointSubsetFormatWithLease(e, masterIPs, endpointPorts, reconcilePorts)

  // ip 存在差异，更新 endpoint 中的 master ip 列表，以 etcd 的 master ip 列表为准
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
    // 更新 endpoint/endpointslice
    _, err = r.epAdapter.Update(corev1.NamespaceDefault, e)
  }
  return err
}
```

可以看出：将自己 ip 从 master ip 列表移除的逻辑是先从 etcd 中存储的 master ip 列表将自己 ip 移除，然后触发 `default/kubernetes` 这个特殊的 endpoint/endpointslice 对账，以 etcd 中的 master ip 列表为准进行覆盖。

再继续看传入的自己的 ip 的值的来源（`c.PublicIP`），如果 kube-apiserver 配置了 `--advertise-address` 参数，会优先使用此地址作为自己的 ip：

```go
  fs.IPVar(&s.AdvertiseAddress, "advertise-address", s.AdvertiseAddress, ""+
    "The IP address on which to advertise the apiserver to members of the cluster. This "+
    "address must be reachable by the rest of the cluster. If blank, the --bind-address "+
    "will be used. If --bind-address is unspecified, the host's default interface will "+
    "be used.")
```

查看 TKE 集群的 kube-apiserver 启动参数，配置了该参数，且值为 `default/kubernetes` 这个 endpoint 的 ip 地址：

```yaml
    - kube-apiserver
    - --advertise-address=169.254.128.7
```

TKE 的 kube-apiserver 默认是多副本高可用部署，其对外地址由一个 `169.254` 开头的 VIP 进行负载均衡，该地址是集群创建时动态分配的，集群创建完成后就不会改变。

所有的 kube-apiserver 都认为自己的 ip 是这个地址，一旦有 kube-apiserver 实例进入停止流程，会将该地址从 etcd 的 master ip 列表中移除并重新对账 `default/kubernetes` 这个 endpoint/endpointslice，进而将该 ip 从 endpoint/endpointslice 资源中也移除掉（update 操作）。

那为什么审计日志中查不到这个 update 操作？应该是因为 kube-apiserver 此时已经在停止了，导致最后的操作审计没有被记录到。

## cilium 代码梳理

前面已经确认了在 TKE 的 kube-apiserver 重建时，会对 `default/kubernetes` 这个 EndpointSlice 发起置空的 update 操作，但 `default/kubernetes-intranet` 这个 Service 对应的 EndpointSlice 没有任何操作，因为这个 Service 不被 kube-apiserver 管理，不会因 kube-apiserver 重建而置空。

那为什么 `default/kubernetes` 的置空操作在 cilium 这里会导致 `default/kubernetes-intranet` 关联的 backend 也被置空？

这个需要继续深入 cilium 代码进行分析了，继续按照之前的调试方法增加更多的调试日志。

最后发现，在 EndpointSlice 的 update 操作中，如果有地址被移除，会走到 `backendRelease` 来释放相应的 backend：

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
  // 如果 Service 匹配，从 backend 中删除对应的实例
  for k := range be.GetInstancesOfService(name) {
    instances = instances.Delete(k)
  }
  beCopy := *be
  beCopy.Instances = instances
  return &beCopy, beCopy.Instances.Len() == 0
}
```

查看 `GetInstancesOfService` 的实现:

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
  if k.SourcePriority == 0 { // 关键，当 SourcePriority 为 0 时，key 等于 ServiceName
    return k.ServiceName.Key()
  }
  sk := k.ServiceName.Key()
  buf := make([]byte, 0, 2+len(sk))
  buf = append(buf, sk...)
  return append(buf, ' ', k.SourcePriority)
}
```

从实现上可以看到，BackendInstanceKey 的 Key 是 ServiceName + 空格 + SourcePriority，当 SourcePriority 为 0 时，为 ServiceName。

这里 SourcePriority 固定为 0（表示数据源来自 Kubernetes 资源），所以 key 始终为 ServiceName，而前面 `GetInstancesOfService` 是通过 `[]byte` 的前缀匹配来查到后端实例，查找 `default/kubernetes` 的后端实例时，也会找到 `default/kubernetes-intranet` 的后端实例，而刚好 `default/kubernetes-intranet` 的后端实例的地址跟 `default/kubernetes` 的后端实例地址相同，在释放 `default/kubernetes` 的后端地址时，也就会将 `default/kubernetes-intranet` 的后端实例也释放掉了，在 kube-apiserver 重建期间，service-controller 的 ListWatch 连接会断线重连并重新对账，将对账时间戳记录到 `default/kubernetes-intranet` 的 Service 注解，cilium-agent watch 到了这个事件，也对这个 Service 重新对账，发现此时对应的 backend 为空，更新相应的 eBPF Map，最终导致 `default/kubernetes-intranet` 这个 Service 相关的地址均无法访问（NodePort、ClusterIP、CLB VIP)。

## 提炼复现步骤

根据前面的代码分析可以反推出：如果 Service B 的名称前缀是 Service A，且对应的 endpoint 有相同地址，那么当 Service A 的 endpoint 移除一个地址时，Service B 中的地址也会被移除。

根据这个结论可以提炼出一个简化的稳定复现步骤。

首先保存以下 yaml 到文件 `test.yaml`:

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

然后将其 apply 到集群并观察 k8s 资源状态：

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

观察 cilium 与 k8s 中 test 开头的 Service 的后端地址，与 EndpointSlice 地址保持一致：

```txt
$ kubectl -n kube-system exec ds/cilium -- cilium shell -- db/show frontends | grep test
192.168.71.144:80/TCP     ClusterIP      default/test                                          1.1.1.1:80/TCP                                       Done     2m25s
192.168.92.25:80/TCP      ClusterIP      default/test-extended                                 1.1.1.1:80/TCP                                       Done     2m25s
```

然后再 patch 一下 `test` 这个 EndpointSlice，将地址移除，并观察 cilium 内存中的 Service 状态：

```txt
$ kubectl -n default patch endpointslices test -p '{"endpoints": []}'
endpointslice.discovery.k8s.io/test patched
$ kubectl -n kube-system exec ds/cilium -- cilium shell -- db/show frontends | grep test
192.168.71.144:80/TCP     ClusterIP      default/test                                                                                               Done     2s
192.168.92.25:80/TCP      ClusterIP      default/test-extended                                 1.1.1.1:80/TCP                                       Done     5m14s
```

可以看到此时 `test` 这个 Service 后端地址已经为空，而 `test-extended` 这个 Service 的后端地址不影响。

再 patch 一下 `test-extended` 这个 Service，触发 cilium-agent 对这个 Service 重新对账，然后再重新观察 cilium 内存中的 Service 状态：

```txt
$ kubectl -n default patch service test-extended -p '{"metadata": {"annotations": {"test": "'$(date +%s)'"}}}'
service/test-extended patched
$ kubectl --namespace=kube-system exec ds/cilium -- cilium shell -- db/show frontends | grep test
192.168.71.144:80/TCP     ClusterIP      default/test                                                                                               Done     5m38s
192.168.92.25:80/TCP      ClusterIP      default/test-extended                                                                                      Done     7s
```

可以看到重新对账后，`test-extended` 这个 Service 的后端地址也被清空了，再看这个 Service 在 ebpf 层面的后端数据，也是没有后端，无法路由(non-routeable)：

```bash
$ kubectl --namespace=kube-system exec ds/cilium -- cilium bpf lb list | grep 192.168.92.25
192.168.92.25:80/TCP (0)      0.0.0.0:0 (21) (0) [ClusterIP, non-routable]
```

现象总结：从 Service A 的 EndpointSlice 中移除一个 endpoint 后竟然可能导致访问 Service B 的请求全部失败。

## 如何解决？

关键点在于 `BackendInstanceKey.Key` 的实现，当在 SourcePriority 为 0 时，我们在末尾也加一个空格，这样就可以解决，以当前的问题为例，`default/kubernetes ` 将不再是 `default/kubernetes-intranet ` 的前缀，因为它末尾有个空格。

当前已将问题和修复方案提交到社区：

- issue: https://github.com/cilium/cilium/issues/43619
- PR: https://github.com/cilium/cilium/pull/43620

## 后记

问题定位过程极其复杂，怀疑过内核、k8s 和 TKE 的问题，最终定位是 cilium 的 bug，本文所总结的排查步骤是假设在精通 k8s、cilium 的底层原理、代码实现和熟练各自排障方法和工具的情况下的理想步骤，而实际过程复杂很多倍，去除了很多不相关的排查细节。

面对 k8s 和 cilium 这种巨型复杂项目，利用 AI 辅助分析和梳理可以提升不少效率，其中测试程序也是由 AI 编写的。

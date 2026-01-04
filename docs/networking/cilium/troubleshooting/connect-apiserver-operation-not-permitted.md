# 问题排查：访问 APIServer 报错 operation not permitted

## 问题现象

安装了 cilium 的 TKE 集群在正常运行很多天后，突然陷入瘫痪，所有节点的 cilium-agent 处于 NotReady 状态。

## 分析现场

查看 cilium-agent 容器日志有报错：

```txt
$ kubectl -n kube-system logs cilium-kddvm --tail 10
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

尝试删除重建 cilium pod 看是否恢复，发现重建后 config 这个 init 容器一直启动失败，报错：

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

这些日志均表示连接 apiserver 失败，报错 `operation not permitted`，尝试在节点上手动 curl 测试连接 apiserver，发现也报错 `Operation not permitted`：

```txt
$ curl -v -k https://10.15.1.8:443
*   Trying 10.15.1.8:443...
* Immediate connect fail for 10.15.1.8: Operation not permitted
* Failed to connect to 10.15.1.8 port 443 after 0 ms: Couldn't connect to server
* Closing connection
curl: (7) Failed to connect to 10.15.1.8 port 443 after 0 ms: Couldn't connect to server
```

## 初步原因分析

从 `operation not permitted` 这个错误可知，访问 apiserver 的数据包并未出节点，直接被内核丢弃了（正常情况下，如果是 apiserver 不通，也是 `timeout` 或 `connection refused` 之类的错误）。

apiserver 地址 TKE 集群开启内网访问后的 CLB 地址（LoadBalancer 类型 Service 自动创建出的 CLB）：

```bash
$ kubectl -n default get svc kubernetes-intranet
NAME                  TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)         AGE
kubernetes-intranet   LoadBalancer   192.168.60.179   10.15.1.8     443:30965/TCP   11d
```

由于安装了 cilium 且启用了 kubeProxyReplacement，访问 apiserver 的流量也会直接被 cilium 的 ebpf 程序拦截并负载均衡，并不会将数据包真正发到 CLB。

查看 cilium-agent 进程内存数据和 ebpf 数据，发现 `kubernetes-intranet` 这个 svc 的 backend 都为空（NodePort、CLB VIP、ClusterIP 均为空）：

```txt
$ kubectl -n kube-system exec cilium-kddvm -- cilium service list
ID   Frontend                  Service Type   Backend
4    0.0.0.0:30965/TCP         NodePort
6    10.15.1.8:443/TCP         LoadBalancer
7    192.168.60.179:443/TCP    ClusterIP

$ kubectl -n kube-system exec cilium-kddvm -- cilium shell -- db/show frontends
Address                   Type           ServiceName                          PortName         Backends                                RedirectTo   Status   Since   Error
0.0.0.0:30965/TCP         NodePort       default/kubernetes-intranet          https                                                                 Done     4m20s
10.15.1.8:443/TCP         LoadBalancer   default/kubernetes-intranet          https                                                                 Done     4m20s
192.168.60.179:443/TCP    ClusterIP      default/kubernetes-intranet          https                                                                 Done     4m20s

$ kubectl -n kube-system exec cilium-kddvm -- cilium bpf lb list
SERVICE ADDRESS               BACKEND ADDRESS (REVNAT_ID) (SLOT)
10.15.1.8:443/TCP (0)         0.0.0.0:0 (14) (0) [LoadBalancer]
0.0.0.0:30965/TCP (0)         0.0.0.0:0 (12) (0) [NodePort, non-routable]
192.168.60.179:443/TCP (0)    0.0.0.0:0 (15) (0) [ClusterIP, non-routable]
```

想到一种可能性：

1. cilium 第一次连接 apiserver 时，由于 cilium 还未就绪，ebpf 数据还未初始化，访问 apiserver 的数据包会真正到 CLB。
2. 当 `kubernetes-intranet` 对应的 EndpointSlice 重建或临时删除 endpoint 时，cilium 会临时清空 ebpf 中的 backend 数据。
3. 当 endpoint 重新加回来时，由于 cilium 已经初始化过 ebpf 程序和数据，后续访问 apiserver 的数据包会被 ebpf 程序拦截处理。
4. 由于 `kubernetes-intranet` 对应的 ebpf 的 backend 数据被临时清空，访问这个地址的数据包被认为没有对应的 backend，就报错 `operation not permitted`。

这样形成了循环依赖，只要 `kubernetes-intranet` 对应的 EndpointSlice 一变更就导致节点再也无法通过对应的 CLB 地址访问 apiserver。

通过手动删除重建 `kubernetes-intranet` 对应的 EndpointSlice，确实也能复现改问题。

但实际上，这个 svc 对应的 EndpointSlice 一直是存在的，没有被删除重建：

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

经过各种尝试，**终于发现了复现条件：调整 TKE 集群规格**。

TKE 集群规格可自动或手动调整，尝试手动调整集群规格后，问题复现了，但有时候不是所有节点都复现。

这个复现条件的特征是 apiserver 会重建，所有 ListWatch 操作都会断连。

## 给 cilium 增加调试代码

根据之前的排查，明显可以看出是 cilium 内部的状态 (cilium service list 看到的 backend) 与实际的 EndpointSlice 不匹配，前者是空的，后者是一直存在且没有变动的。

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

然后调整集群规格来复现问题，查看 cilium-agent 的日志：

```txt
$ kubectl -n kube-system logs cilium-dn47b --tail 15
time=2026-01-04T04:37:14.723083417Z level=info msg="DEBUG: Processing service event" module=agent.controlplane.loadbalancer-reflectors.k8s-reflector key="{key:{Name:kubernetes-intranet Namespace:default} isSvc:true}"
time=2026-01-04T04:37:16.722637542Z level=info msg="DEBUG: Processing service event" module=agent.controlplane.loadbalancer-reflectors.k8s-reflector key="{key:{Name:kubernetes-intranet Namespace:default} isSvc:true}"
time=2026-01-04T04:37:28.223095883Z level=info msg="DEBUG: Processing service event" module=agent.controlplane.loadbalancer-reflectors.k8s-reflector key="{key:{Name:kubernetes-intranet Namespace:default} isSvc:true}"
time=2026-01-04T04:37:28.72302971Z level=info msg="DEBUG: Processing service event" module=agent.controlplane.loadbalancer-reflectors.k8s-reflector key="{key:{Name:kubernetes-intranet Namespace:default} isSvc:true}"
time=2026-01-04T04:38:13.222620275Z level=info msg="DEBUG: Processing service event" module=agent.controlplane.loadbalancer-reflectors.k8s-reflector key="{key:{Name:kubernetes-intranet Namespace:default} isSvc:true}"
time=2026-01-04T04:38:14.222853386Z level=info msg="DEBUG: Processing service event" module=agent.controlplane.loadbalancer-reflectors.k8s-reflector key="{key:{Name:kubernetes-intranet Namespace:default} isSvc:true}"
time=2026-01-04T04:38:18.722798226Z level=info msg="DEBUG: Processing service event" module=agent.controlplane.loadbalancer-reflectors.k8s-reflector key="{key:{Name:kubernetes-intranet Namespace:default} isSvc:true}"
time=2026-01-04T04:38:23.723207324Z level=info msg="DEBUG: Processing service event" module=agent.controlplane.loadbalancer-reflectors.k8s-reflector key="{key:{Name:kubernetes-intranet Namespace:default} isSvc:true}"
time=2026-01-04T04:38:24.222522501Z level=info msg="DEBUG: Processing service event" module=agent.controlplane.loadbalancer-reflectors.k8s-reflector key="{key:{Name:kubernetes-intranet Namespace:default} isSvc:true}"
time=2026-01-04T04:38:43.22250763Z level=info msg="DEBUG: Processing service event" module=agent.controlplane.loadbalancer-reflectors.k8s-reflector key="{key:{Name:kubernetes-intranet Namespace:default} isSvc:true}"
time=2026-01-04T04:39:27.558444466Z level=error msg=k8sError error="Get \"https://10.15.1.8:443/api/v1/namespaces?allowWatchBookmarks=true&resourceVersion=2595060490&timeout=9m6s&timeoutSeconds=546&watch=true\": dial tcp 10.15.1.8:443: connect: operation not permitted"
time=2026-01-04T04:39:27.558512846Z level=error msg=k8sError error="Get \"https://10.15.1.8:443/apis/cilium.io/v2/ciliumnodes?allowWatchBookmarks=true&resourceVersion=2595021218&timeout=7m44s&timeoutSeconds=464&watch=true\": dial tcp 10.15.1.8:443: connect: operation not permitted"
time=2026-01-04T04:39:27.558573601Z level=error msg=k8sError error="Get \"https://10.15.1.8:443/apis/discovery.k8s.io/v1/endpointslices?allowWatchBookmarks=true&labelSelector=endpointslice.kubernetes.io%2Fmanaged-by%21%3Dendpointslice-mesh-controller.cilium.io%2C%21service.kubernetes.io%2Fheadless&resourceVersion=2595174540&timeout=7m2s&timeoutSeconds=422&watch=true\": dial tcp 10.15.1.8:443: connect: operation not permitted"
time=2026-01-04T04:39:27.558611351Z level=error msg=k8sError error="Get \"https://10.15.1.8:443/apis/cilium.io/v2/ciliumnetworkpolicies?allowWatchBookmarks=true&resourceVersion=2595069082&timeout=8m49s&timeoutSeconds=529&watch=true\": dial tcp 10.15.1.8:443: connect: operation not permitted"
time=2026-01-04T04:39:27.559328906Z level=error msg=k8sError error="Get \"https://10.15.1.8:443/api/v1/namespaces/kube-system/configmaps?allowWatchBookmarks=true&fieldSelector=metadata.name%3Dcilium-config&resourceVersion=2595172652&timeout=5m20s&timeoutSeconds=320&watch=true\": dial tcp 10.15.1.8:443: connect: operation not permitted"
```

可以看出：当调整 TKE 集群规格后，cilium-agent 会处理 `kubernetes-intranet` 这个 Service 事件，没有对应的 EndpointSlice 事件。

## 分析 APIServer 审计

在集群的 **监控告警-日志-审计日志-全局搜索** 中使用下面的 CQL 查询 `kubernetes-intranet` 这个 Service 及其关联的 EndpointSlice 相关审计日志。

```txt
objectRef.namespace:"default" AND ((objectRef.name:"kubernetes-intranet" AND objectRef.resource:"services") OR (objectRef.name:"kubernetes-intranet-qxgk4" AND objectRef.resource:"endpointslices")) NOT verb:get
```

从集群审计日志看，调整集群规格时，`kubernetes-intranet` 这个 Service 会有一些 patch 操作，对应的 EndpointSlice 对象没有任何操作：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2026%2F01%2F04%2F20260104155041.png)

这个 patch 操作来自 TKE 的 service-controller，因为这个 Service 是 LoadBalancer 类型的，会被 service-controller 处理，当调整集群规格时，apiserver 重建，导致 service-controller 存量 ListWatch 连接断开，然后自动重连并重新对账，对账完成后发起 patch 操作记录最新的对账时间戳到 Service 注解。

结合这里的审计分析与前面的调试日志可以得出：在调整集群规格时，apiserver 重建，触发 service-controller 多次自动重新对账，每次对账时会将对账的时间戳 patch 到 Service 注解，然后每次 patch 操作又触发 cilium-agent 对该 Service 的对账。

## 进一步调试

从前面的调试日志可以看出，调整集群规格时，会多次走到 processServiceEvent 这个函数对 `kubernetes-intranet` 这个 Service 进行对账，移除之前的调试代码，重新为 processServiceEvent 增加一行调试代码，看调整集群规格时会走哪个 switch 代码分支：

```go
  processServiceEvent := func(txn writer.WriteTxn, kind resource.EventKind, obj *slim_corev1.Service) {
    // 增加调试日志，看调整集群规格时会走哪个 switch 代码分支
    p.Log.Info("DEBUG: processServiceEvent", "kind", kind, "obj", obj)
    switch kind {
    case resource.Sync:
      // ...
    case resource.Upsert:
      // ...
    case resource.Delete:
      // ...
  }
```

重新更新镜像并加入新节点，然后再复现问题，观察日志：

```txt
$ kubectl -n kube-system logs cilium-lz9m7 --tail 10
time=2026-01-04T08:24:43.75566508Z level=info msg="DEBUG: processServiceEvent" module=agent.controlplane.loadbalancer-reflectors.k8s-reflector kind=upsert obj="&Service{ObjectMeta:{kubernetes-intranet  default f92bb6a6-55a7-4bc4-bf58-85a138d10a9f 2599249315 0 <nil> map[service.cloud.tencent.com/loadbalance-type:INTERNAL] map[service.cloud.tencent.com/client-token:ed7a31f0-24cd-4aea-ab10-e00d63994dd8 service.cloud.tencent.com/direct-access:true service.cloud.tencent.com/loadbalancer-source-endpoints:{\"name\":\"kubernetes-intranet-loadbalancer\"} service.cloud.tencent.com/sync-begin-time:2026-01-04T16:24:42+08:00 service.cloud.tencent.com/sync-end-time:2026-01-04T16:24:43+08:00 service.kubernetes.io/loadbalance-id:lb-ly81db73 service.kubernetes.io/qcloud-loadbalancer-internal-subnetid:subnet-loelppdt] []},Spec:ServiceSpec{Ports:[]ServicePort{ServicePort{Name:https,Protocol:TCP,Port:443,TargetPort:{0 60002 },NodePort:30965,AppProtocol:nil,},},Selector:map[string]string{},ClusterIP:192.168.60.179,Type:LoadBalancer,ExternalIPs:[],SessionAffinity:None,LoadBalancerIP:,LoadBalancerSourceRanges:[],ExternalTrafficPolicy:Cluster,HealthCheckNodePort:0,SessionAffinityConfig:nil,IPFamilyPolicy:*SingleStack,ClusterIPs:[192.168.60.179],IPFamilies:[IPv4],LoadBalancerClass:nil,InternalTrafficPolicy:*Cluster,TrafficDistribution:nil,},Status:ServiceStatus{LoadBalancer:LoadBalancerStatus{Ingress:[]LoadBalancerIngress{LoadBalancerIngress{IP:10.15.1.8,Hostname:,IPMode:*VIP,Ports:[]PortStatus{},},},},Conditions:[]Condition{{Ready True 0 2025-12-23 12:57:03 +0000 UTC Success },},},}"
time=2026-01-04T08:25:29.255390814Z level=info msg="DEBUG: processServiceEvent" module=agent.controlplane.loadbalancer-reflectors.k8s-reflector kind=upsert obj="&Service{ObjectMeta:{kubernetes-intranet  default f92bb6a6-55a7-4bc4-bf58-85a138d10a9f 2599262993 0 <nil> map[service.cloud.tencent.com/loadbalance-type:INTERNAL] map[service.cloud.tencent.com/client-token:ed7a31f0-24cd-4aea-ab10-e00d63994dd8 service.cloud.tencent.com/direct-access:true service.cloud.tencent.com/loadbalancer-source-endpoints:{\"name\":\"kubernetes-intranet-loadbalancer\"} service.cloud.tencent.com/sync-begin-time:2026-01-04T16:25:28+08:00 service.cloud.tencent.com/sync-end-time:2026-01-04T16:25:29+08:00 service.kubernetes.io/loadbalance-id:lb-ly81db73 service.kubernetes.io/qcloud-loadbalancer-internal-subnetid:subnet-loelppdt] []},Spec:ServiceSpec{Ports:[]ServicePort{ServicePort{Name:https,Protocol:TCP,Port:443,TargetPort:{0 60002 },NodePort:30965,AppProtocol:nil,},},Selector:map[string]string{},ClusterIP:192.168.60.179,Type:LoadBalancer,ExternalIPs:[],SessionAffinity:None,LoadBalancerIP:,LoadBalancerSourceRanges:[],ExternalTrafficPolicy:Cluster,HealthCheckNodePort:0,SessionAffinityConfig:nil,IPFamilyPolicy:*SingleStack,ClusterIPs:[192.168.60.179],IPFamilies:[IPv4],LoadBalancerClass:nil,InternalTrafficPolicy:*Cluster,TrafficDistribution:nil,},Status:ServiceStatus{LoadBalancer:LoadBalancerStatus{Ingress:[]LoadBalancerIngress{LoadBalancerIngress{IP:10.15.1.8,Hostname:,IPMode:*VIP,Ports:[]PortStatus{},},},},Conditions:[]Condition{{Ready True 0 2025-12-23 12:57:03 +0000 UTC Success },},},}"
time=2026-01-04T08:25:29.755911336Z level=info msg="DEBUG: processServiceEvent" module=agent.controlplane.loadbalancer-reflectors.k8s-reflector kind=upsert obj="&Service{ObjectMeta:{kubernetes-intranet  default f92bb6a6-55a7-4bc4-bf58-85a138d10a9f 2599263160 0 <nil> map[service.cloud.tencent.com/loadbalance-type:INTERNAL] map[service.cloud.tencent.com/client-token:ed7a31f0-24cd-4aea-ab10-e00d63994dd8 service.cloud.tencent.com/direct-access:true service.cloud.tencent.com/loadbalancer-source-endpoints:{\"name\":\"kubernetes-intranet-loadbalancer\"} service.cloud.tencent.com/sync-begin-time:2026-01-04T16:25:29+08:00 service.cloud.tencent.com/sync-end-time:2026-01-04T16:25:29+08:00 service.kubernetes.io/loadbalance-id:lb-ly81db73 service.kubernetes.io/qcloud-loadbalancer-internal-subnetid:subnet-loelppdt] []},Spec:ServiceSpec{Ports:[]ServicePort{ServicePort{Name:https,Protocol:TCP,Port:443,TargetPort:{0 60002 },NodePort:30965,AppProtocol:nil,},},Selector:map[string]string{},ClusterIP:192.168.60.179,Type:LoadBalancer,ExternalIPs:[],SessionAffinity:None,LoadBalancerIP:,LoadBalancerSourceRanges:[],ExternalTrafficPolicy:Cluster,HealthCheckNodePort:0,SessionAffinityConfig:nil,IPFamilyPolicy:*SingleStack,ClusterIPs:[192.168.60.179],IPFamilies:[IPv4],LoadBalancerClass:nil,InternalTrafficPolicy:*Cluster,TrafficDistribution:nil,},Status:ServiceStatus{LoadBalancer:LoadBalancerStatus{Ingress:[]LoadBalancerIngress{LoadBalancerIngress{IP:10.15.1.8,Hostname:,IPMode:*VIP,Ports:[]PortStatus{},},},},Conditions:[]Condition{{Ready True 0 2025-12-23 12:57:03 +0000 UTC Success },},},}"
time=2026-01-04T08:25:32.755364217Z level=info msg="DEBUG: processServiceEvent" module=agent.controlplane.loadbalancer-reflectors.k8s-reflector kind=upsert obj="&Service{ObjectMeta:{kubernetes  default ff45cd82-d8ad-479c-bb86-76fe10f64ed0 2599264056 0 <nil> map[component:apiserver provider:kubernetes service.cloud.tencent.com/loadbalance-type:OPEN] map[service.cloud.tencent.com/client-token:cf84b188-b982-4186-9230-25adf2493404 service.cloud.tencent.com/sync-begin-time:2026-01-04T16:25:32+08:00 service.cloud.tencent.com/sync-end-time:2026-01-04T16:25:32+08:00 service.kubernetes.io/loadbalance-id:lb-qjyknmqt] []},Spec:ServiceSpec{Ports:[]ServicePort{ServicePort{Name:https,Protocol:TCP,Port:443,TargetPort:{0 60002 },NodePort:30724,AppProtocol:nil,},},Selector:map[string]string{},ClusterIP:192.168.0.1,Type:LoadBalancer,ExternalIPs:[],SessionAffinity:None,LoadBalancerIP:,LoadBalancerSourceRanges:[],ExternalTrafficPolicy:Cluster,HealthCheckNodePort:0,SessionAffinityConfig:nil,IPFamilyPolicy:*SingleStack,ClusterIPs:[192.168.0.1],IPFamilies:[IPv4],LoadBalancerClass:nil,InternalTrafficPolicy:*Cluster,TrafficDistribution:nil,},Status:ServiceStatus{LoadBalancer:LoadBalancerStatus{Ingress:[]LoadBalancerIngress{LoadBalancerIngress{IP:139.155.65.129,Hostname:,IPMode:*VIP,Ports:[]PortStatus{},},},},Conditions:[]Condition{{Ready True 0 2025-12-23 12:38:25 +0000 UTC Success },},},}"
time=2026-01-04T08:25:33.755375798Z level=info msg="DEBUG: processServiceEvent" module=agent.controlplane.loadbalancer-reflectors.k8s-reflector kind=upsert obj="&Service{ObjectMeta:{kubernetes  default ff45cd82-d8ad-479c-bb86-76fe10f64ed0 2599264415 0 <nil> map[component:apiserver provider:kubernetes service.cloud.tencent.com/loadbalance-type:OPEN] map[service.cloud.tencent.com/client-token:cf84b188-b982-4186-9230-25adf2493404 service.cloud.tencent.com/sync-begin-time:2026-01-04T16:25:33+08:00 service.cloud.tencent.com/sync-end-time:2026-01-04T16:25:33+08:00 service.kubernetes.io/loadbalance-id:lb-qjyknmqt] []},Spec:ServiceSpec{Ports:[]ServicePort{ServicePort{Name:https,Protocol:TCP,Port:443,TargetPort:{0 60002 },NodePort:30724,AppProtocol:nil,},},Selector:map[string]string{},ClusterIP:192.168.0.1,Type:LoadBalancer,ExternalIPs:[],SessionAffinity:None,LoadBalancerIP:,LoadBalancerSourceRanges:[],ExternalTrafficPolicy:Cluster,HealthCheckNodePort:0,SessionAffinityConfig:nil,IPFamilyPolicy:*SingleStack,ClusterIPs:[192.168.0.1],IPFamilies:[IPv4],LoadBalancerClass:nil,InternalTrafficPolicy:*Cluster,TrafficDistribution:nil,},Status:ServiceStatus{LoadBalancer:LoadBalancerStatus{Ingress:[]LoadBalancerIngress{LoadBalancerIngress{IP:139.155.65.129,Hostname:,IPMode:*VIP,Ports:[]PortStatus{},},},},Conditions:[]Condition{{Ready True 0 2025-12-23 12:38:25 +0000 UTC Success },},},}"
time=2026-01-04T08:26:03.756013721Z level=info msg="DEBUG: processServiceEvent" module=agent.controlplane.loadbalancer-reflectors.k8s-reflector kind=upsert obj="&Service{ObjectMeta:{kubernetes-intranet  default f92bb6a6-55a7-4bc4-bf58-85a138d10a9f 2599271125 0 <nil> map[service.cloud.tencent.com/loadbalance-type:INTERNAL] map[service.cloud.tencent.com/client-token:ed7a31f0-24cd-4aea-ab10-e00d63994dd8 service.cloud.tencent.com/direct-access:true service.cloud.tencent.com/loadbalancer-source-endpoints:{\"name\":\"kubernetes-intranet-loadbalancer\"} service.cloud.tencent.com/sync-begin-time:2026-01-04T16:25:55+08:00 service.cloud.tencent.com/sync-end-time:2026-01-04T16:25:56+08:00 service.kubernetes.io/loadbalance-id:lb-ly81db73 service.kubernetes.io/qcloud-loadbalancer-internal-subnetid:subnet-loelppdt] []},Spec:ServiceSpec{Ports:[]ServicePort{ServicePort{Name:https,Protocol:TCP,Port:443,TargetPort:{0 60002 },NodePort:30965,AppProtocol:nil,},},Selector:map[string]string{},ClusterIP:192.168.60.179,Type:LoadBalancer,ExternalIPs:[],SessionAffinity:None,LoadBalancerIP:,LoadBalancerSourceRanges:[],ExternalTrafficPolicy:Cluster,HealthCheckNodePort:0,SessionAffinityConfig:nil,IPFamilyPolicy:*SingleStack,ClusterIPs:[192.168.60.179],IPFamilies:[IPv4],LoadBalancerClass:nil,InternalTrafficPolicy:*Cluster,TrafficDistribution:nil,},Status:ServiceStatus{LoadBalancer:LoadBalancerStatus{Ingress:[]LoadBalancerIngress{LoadBalancerIngress{IP:10.15.1.8,Hostname:,IPMode:*VIP,Ports:[]PortStatus{},},},},Conditions:[]Condition{{Ready True 0 2025-12-23 12:57:03 +0000 UTC Success },},},}"
time=2026-01-04T08:26:04.255530658Z level=info msg="DEBUG: processServiceEvent" module=agent.controlplane.loadbalancer-reflectors.k8s-reflector kind=upsert obj="&Service{ObjectMeta:{kubernetes-intranet  default f92bb6a6-55a7-4bc4-bf58-85a138d10a9f 2599273498 0 <nil> map[service.cloud.tencent.com/loadbalance-type:INTERNAL] map[service.cloud.tencent.com/client-token:ed7a31f0-24cd-4aea-ab10-e00d63994dd8 service.cloud.tencent.com/direct-access:true service.cloud.tencent.com/loadbalancer-source-endpoints:{\"name\":\"kubernetes-intranet-loadbalancer\"} service.cloud.tencent.com/sync-begin-time:2026-01-04T16:26:03+08:00 service.cloud.tencent.com/sync-end-time:2026-01-04T16:26:03+08:00 service.kubernetes.io/loadbalance-id:lb-ly81db73 service.kubernetes.io/qcloud-loadbalancer-internal-subnetid:subnet-loelppdt] []},Spec:ServiceSpec{Ports:[]ServicePort{ServicePort{Name:https,Protocol:TCP,Port:443,TargetPort:{0 60002 },NodePort:30965,AppProtocol:nil,},},Selector:map[string]string{},ClusterIP:192.168.60.179,Type:LoadBalancer,ExternalIPs:[],SessionAffinity:None,LoadBalancerIP:,LoadBalancerSourceRanges:[],ExternalTrafficPolicy:Cluster,HealthCheckNodePort:0,SessionAffinityConfig:nil,IPFamilyPolicy:*SingleStack,ClusterIPs:[192.168.60.179],IPFamilies:[IPv4],LoadBalancerClass:nil,InternalTrafficPolicy:*Cluster,TrafficDistribution:nil,},Status:ServiceStatus{LoadBalancer:LoadBalancerStatus{Ingress:[]LoadBalancerIngress{LoadBalancerIngress{IP:10.15.1.8,Hostname:,IPMode:*VIP,Ports:[]PortStatus{},},},},Conditions:[]Condition{{Ready True 0 2025-12-23 12:57:03 +0000 UTC Success },},},}"
time=2026-01-04T08:26:40.399231084Z level=error msg=k8sError error="Get \"https://10.15.1.8:443/apis/cilium.io/v2/ciliumlocalredirectpolicies?allowWatchBookmarks=true&resourceVersion=2599180028&timeout=7m39s&timeoutSeconds=459&watch=true\": dial tcp 10.15.1.8:443: connect: operation not permitted"
time=2026-01-04T08:26:40.400102528Z level=error msg=k8sError error="Get \"https://10.15.1.8:443/apis/networking.k8s.io/v1/networkpolicies?allowWatchBookmarks=true&resourceVersion=2599093620&timeout=9m49s&timeoutSeconds=589&watch=true\": dial tcp 10.15.1.8:443: connect: operation not permitted"
time=2026-01-04T08:26:40.400148264Z level=error msg=k8sError error="Get \"https://10.15.1.8:443/apis/cilium.io/v2/ciliumclusterwidenetworkpolicies?allowWatchBookmarks=true&resourceVersion=2599093645&timeout=5m25s&timeoutSeconds=325&watch=true\": dial tcp 10.15.1.8:443: connect: operation not permitted"
```

可以看到会每次处理的 Service 事件都是 upsert 类型。

再次移除之前的调试代码，处理 upsert 类型事件的地方打印关键调试调试信息：

```go
  processServiceEvent := func(txn writer.WriteTxn, kind resource.EventKind, obj *slim_corev1.Service) {
    switch kind {
    case resource.Sync:
       // ...
    case resource.Upsert:
      svc, fes := convertService(p.Config, p.ExtConfig, p.Log, p.LocalNodeStore, obj, source.Kubernetes)
      p.Log.Info("DEBUG: convertService", "name", obj.Name, "svc", svc, "fes", fes)
      // ...
      err := p.Writer.UpsertServiceAndFrontends(txn, svc, fes...)
      // ...
    case resource.Delete:
      // ...
  }
```

替换镜像并观察日志：

```txt
$ kubectl -n kube-system logs cilium-wkjqq --tail 15
time=2026-01-04T08:57:52.235681319Z level=info msg="DEBUG: convertService" module=agent.controlplane.loadbalancer-reflectors.k8s-reflector name=kubernetes-intranet svc="&{Name:default/kubernetes-intranet Source:k8s Labels:k8s:service.cloud.tencent.com/loadbalance-type=INTERNAL Annotations:map[service.cloud.tencent.com/client-token:ed7a31f0-24cd-4aea-ab10-e00d63994dd8 service.cloud.tencent.com/direct-access:true service.cloud.tencent.com/loadbalancer-source-endpoints:{\"name\":\"kubernetes-intranet-loadbalancer\"} service.cloud.tencent.com/sync-begin-time:2026-01-04T16:57:51+08:00 service.cloud.tencent.com/sync-end-time:2026-01-04T16:57:51+08:00 service.kubernetes.io/loadbalance-id:lb-ly81db73 service.kubernetes.io/qcloud-loadbalancer-internal-subnetid:subnet-loelppdt] Selector:map[] NatPolicy: ExtTrafficPolicy:Cluster IntTrafficPolicy:Cluster ForwardingMode: SessionAffinity:false SessionAffinityTimeout:0s LoadBalancerClass:<nil> ProxyRedirect: HealthCheckNodePort:0 LoopbackHostPort:false SourceRanges:[] PortNames:map[https:443] TrafficDistribution:}" fes="[{Address:192.168.60.179:443/TCP Type:ClusterIP ServiceName:default/kubernetes-intranet PortName:https ServicePort:443} {Address:0.0.0.0:30965/TCP Type:NodePort ServiceName:default/kubernetes-intranet PortName:https ServicePort:443} {Address:10.15.1.8:443/TCP Type:LoadBalancer ServiceName:default/kubernetes-intranet PortName:https ServicePort:443}]"
time=2026-01-04T08:57:59.735491667Z level=info msg="DEBUG: convertService" module=agent.controlplane.loadbalancer-reflectors.k8s-reflector name=kubernetes-intranet svc="&{Name:default/kubernetes-intranet Source:k8s Labels:k8s:service.cloud.tencent.com/loadbalance-type=INTERNAL Annotations:map[service.cloud.tencent.com/client-token:ed7a31f0-24cd-4aea-ab10-e00d63994dd8 service.cloud.tencent.com/direct-access:true service.cloud.tencent.com/loadbalancer-source-endpoints:{\"name\":\"kubernetes-intranet-loadbalancer\"} service.cloud.tencent.com/sync-begin-time:2026-01-04T16:57:58+08:00 service.cloud.tencent.com/sync-end-time:2026-01-04T16:57:59+08:00 service.kubernetes.io/loadbalance-id:lb-ly81db73 service.kubernetes.io/qcloud-loadbalancer-internal-subnetid:subnet-loelppdt] Selector:map[] NatPolicy: ExtTrafficPolicy:Cluster IntTrafficPolicy:Cluster ForwardingMode: SessionAffinity:false SessionAffinityTimeout:0s LoadBalancerClass:<nil> ProxyRedirect: HealthCheckNodePort:0 LoopbackHostPort:false SourceRanges:[] PortNames:map[https:443] TrafficDistribution:}" fes="[{Address:192.168.60.179:443/TCP Type:ClusterIP ServiceName:default/kubernetes-intranet PortName:https ServicePort:443} {Address:0.0.0.0:30965/TCP Type:NodePort ServiceName:default/kubernetes-intranet PortName:https ServicePort:443} {Address:10.15.1.8:443/TCP Type:LoadBalancer ServiceName:default/kubernetes-intranet PortName:https ServicePort:443}]"
time=2026-01-04T08:58:06.235523544Z level=info msg="DEBUG: convertService" module=agent.controlplane.loadbalancer-reflectors.k8s-reflector name=kubernetes-intranet svc="&{Name:default/kubernetes-intranet Source:k8s Labels:k8s:service.cloud.tencent.com/loadbalance-type=INTERNAL Annotations:map[service.cloud.tencent.com/client-token:ed7a31f0-24cd-4aea-ab10-e00d63994dd8 service.cloud.tencent.com/direct-access:true service.cloud.tencent.com/loadbalancer-source-endpoints:{\"name\":\"kubernetes-intranet-loadbalancer\"} service.cloud.tencent.com/sync-begin-time:2026-01-04T16:58:05+08:00 service.cloud.tencent.com/sync-end-time:2026-01-04T16:58:06+08:00 service.kubernetes.io/loadbalance-id:lb-ly81db73 service.kubernetes.io/qcloud-loadbalancer-internal-subnetid:subnet-loelppdt] Selector:map[] NatPolicy: ExtTrafficPolicy:Cluster IntTrafficPolicy:Cluster ForwardingMode: SessionAffinity:false SessionAffinityTimeout:0s LoadBalancerClass:<nil> ProxyRedirect: HealthCheckNodePort:0 LoopbackHostPort:false SourceRanges:[] PortNames:map[https:443] TrafficDistribution:}" fes="[{Address:192.168.60.179:443/TCP Type:ClusterIP ServiceName:default/kubernetes-intranet PortName:https ServicePort:443} {Address:0.0.0.0:30965/TCP Type:NodePort ServiceName:default/kubernetes-intranet PortName:https ServicePort:443} {Address:10.15.1.8:443/TCP Type:LoadBalancer ServiceName:default/kubernetes-intranet PortName:https ServicePort:443}]"
time=2026-01-04T08:58:26.899392909Z level=info msg="Starting GC of connection tracking" module=agent.datapath.maps.ct-nat-map-gc first=false
time=2026-01-04T08:58:26.906111111Z level=info msg="Conntrack garbage collector interval recalculated" module=agent.datapath.maps.ct-nat-map-gc expectedPrevInterval=5m0s actualPrevInterval=5m0.002279235s newInterval=7m30s deleteRatio=0.0078887939453125 adjustedDeleteRatio=0.0078887939453125
time=2026-01-04T08:58:52.236003318Z level=info msg="DEBUG: convertService" module=agent.controlplane.loadbalancer-reflectors.k8s-reflector name=kubernetes-intranet svc="&{Name:default/kubernetes-intranet Source:k8s Labels:k8s:service.cloud.tencent.com/loadbalance-type=INTERNAL Annotations:map[service.cloud.tencent.com/client-token:ed7a31f0-24cd-4aea-ab10-e00d63994dd8 service.cloud.tencent.com/direct-access:true service.cloud.tencent.com/loadbalancer-source-endpoints:{\"name\":\"kubernetes-intranet-loadbalancer\"} service.cloud.tencent.com/sync-begin-time:2026-01-04T16:58:50+08:00 service.cloud.tencent.com/sync-end-time:2026-01-04T16:58:51+08:00 service.kubernetes.io/loadbalance-id:lb-ly81db73 service.kubernetes.io/qcloud-loadbalancer-internal-subnetid:subnet-loelppdt] Selector:map[] NatPolicy: ExtTrafficPolicy:Cluster IntTrafficPolicy:Cluster ForwardingMode: SessionAffinity:false SessionAffinityTimeout:0s LoadBalancerClass:<nil> ProxyRedirect: HealthCheckNodePort:0 LoopbackHostPort:false SourceRanges:[] PortNames:map[https:443] TrafficDistribution:}" fes="[{Address:192.168.60.179:443/TCP Type:ClusterIP ServiceName:default/kubernetes-intranet PortName:https ServicePort:443} {Address:0.0.0.0:30965/TCP Type:NodePort ServiceName:default/kubernetes-intranet PortName:https ServicePort:443} {Address:10.15.1.8:443/TCP Type:LoadBalancer ServiceName:default/kubernetes-intranet PortName:https ServicePort:443}]"
time=2026-01-04T08:58:52.735569221Z level=info msg="DEBUG: convertService" module=agent.controlplane.loadbalancer-reflectors.k8s-reflector name=kubernetes-intranet svc="&{Name:default/kubernetes-intranet Source:k8s Labels:k8s:service.cloud.tencent.com/loadbalance-type=INTERNAL Annotations:map[service.cloud.tencent.com/client-token:ed7a31f0-24cd-4aea-ab10-e00d63994dd8 service.cloud.tencent.com/direct-access:true service.cloud.tencent.com/loadbalancer-source-endpoints:{\"name\":\"kubernetes-intranet-loadbalancer\"} service.cloud.tencent.com/sync-begin-time:2026-01-04T16:58:51+08:00 service.cloud.tencent.com/sync-end-time:2026-01-04T16:58:52+08:00 service.kubernetes.io/loadbalance-id:lb-ly81db73 service.kubernetes.io/qcloud-loadbalancer-internal-subnetid:subnet-loelppdt] Selector:map[] NatPolicy: ExtTrafficPolicy:Cluster IntTrafficPolicy:Cluster ForwardingMode: SessionAffinity:false SessionAffinityTimeout:0s LoadBalancerClass:<nil> ProxyRedirect: HealthCheckNodePort:0 LoopbackHostPort:false SourceRanges:[] PortNames:map[https:443] TrafficDistribution:}" fes="[{Address:192.168.60.179:443/TCP Type:ClusterIP ServiceName:default/kubernetes-intranet PortName:https ServicePort:443} {Address:0.0.0.0:30965/TCP Type:NodePort ServiceName:default/kubernetes-intranet PortName:https ServicePort:443} {Address:10.15.1.8:443/TCP Type:LoadBalancer ServiceName:default/kubernetes-intranet PortName:https ServicePort:443}]"
time=2026-01-04T08:59:24.736138273Z level=info msg="DEBUG: convertService" module=agent.controlplane.loadbalancer-reflectors.k8s-reflector name=kubernetes-intranet svc="&{Name:default/kubernetes-intranet Source:k8s Labels:k8s:service.cloud.tencent.com/loadbalance-type=INTERNAL Annotations:map[service.cloud.tencent.com/client-token:ed7a31f0-24cd-4aea-ab10-e00d63994dd8 service.cloud.tencent.com/direct-access:true service.cloud.tencent.com/loadbalancer-source-endpoints:{\"name\":\"kubernetes-intranet-loadbalancer\"} service.cloud.tencent.com/sync-begin-time:2026-01-04T16:59:18+08:00 service.cloud.tencent.com/sync-end-time:2026-01-04T16:59:19+08:00 service.kubernetes.io/loadbalance-id:lb-ly81db73 service.kubernetes.io/qcloud-loadbalancer-internal-subnetid:subnet-loelppdt] Selector:map[] NatPolicy: ExtTrafficPolicy:Cluster IntTrafficPolicy:Cluster ForwardingMode: SessionAffinity:false SessionAffinityTimeout:0s LoadBalancerClass:<nil> ProxyRedirect: HealthCheckNodePort:0 LoopbackHostPort:false SourceRanges:[] PortNames:map[https:443] TrafficDistribution:}" fes="[{Address:192.168.60.179:443/TCP Type:ClusterIP ServiceName:default/kubernetes-intranet PortName:https ServicePort:443} {Address:0.0.0.0:30965/TCP Type:NodePort ServiceName:default/kubernetes-intranet PortName:https ServicePort:443} {Address:10.15.1.8:443/TCP Type:LoadBalancer ServiceName:default/kubernetes-intranet PortName:https ServicePort:443}]"
time=2026-01-04T08:59:25.735454276Z level=info msg="DEBUG: convertService" module=agent.controlplane.loadbalancer-reflectors.k8s-reflector name=kubernetes-intranet svc="&{Name:default/kubernetes-intranet Source:k8s Labels:k8s:service.cloud.tencent.com/loadbalance-type=INTERNAL Annotations:map[service.cloud.tencent.com/client-token:ed7a31f0-24cd-4aea-ab10-e00d63994dd8 service.cloud.tencent.com/direct-access:true service.cloud.tencent.com/loadbalancer-source-endpoints:{\"name\":\"kubernetes-intranet-loadbalancer\"} service.cloud.tencent.com/sync-begin-time:2026-01-04T16:59:25+08:00 service.cloud.tencent.com/sync-end-time:2026-01-04T16:59:25+08:00 service.kubernetes.io/loadbalance-id:lb-ly81db73 service.kubernetes.io/qcloud-loadbalancer-internal-subnetid:subnet-loelppdt] Selector:map[] NatPolicy: ExtTrafficPolicy:Cluster IntTrafficPolicy:Cluster ForwardingMode: SessionAffinity:false SessionAffinityTimeout:0s LoadBalancerClass:<nil> ProxyRedirect: HealthCheckNodePort:0 LoopbackHostPort:false SourceRanges:[] PortNames:map[https:443] TrafficDistribution:}" fes="[{Address:192.168.60.179:443/TCP Type:ClusterIP ServiceName:default/kubernetes-intranet PortName:https ServicePort:443} {Address:0.0.0.0:30965/TCP Type:NodePort ServiceName:default/kubernetes-intranet PortName:https ServicePort:443} {Address:10.15.1.8:443/TCP Type:LoadBalancer ServiceName:default/kubernetes-intranet PortName:https ServicePort:443}]"
time=2026-01-04T08:59:27.235625567Z level=info msg="DEBUG: convertService" module=agent.controlplane.loadbalancer-reflectors.k8s-reflector name=kubernetes-intranet svc="&{Name:default/kubernetes-intranet Source:k8s Labels:k8s:service.cloud.tencent.com/loadbalance-type=INTERNAL Annotations:map[service.cloud.tencent.com/client-token:ed7a31f0-24cd-4aea-ab10-e00d63994dd8 service.cloud.tencent.com/direct-access:true service.cloud.tencent.com/loadbalancer-source-endpoints:{\"name\":\"kubernetes-intranet-loadbalancer\"} service.cloud.tencent.com/sync-begin-time:2026-01-04T16:59:26+08:00 service.cloud.tencent.com/sync-end-time:2026-01-04T16:59:26+08:00 service.kubernetes.io/loadbalance-id:lb-ly81db73 service.kubernetes.io/qcloud-loadbalancer-internal-subnetid:subnet-loelppdt] Selector:map[] NatPolicy: ExtTrafficPolicy:Cluster IntTrafficPolicy:Cluster ForwardingMode: SessionAffinity:false SessionAffinityTimeout:0s LoadBalancerClass:<nil> ProxyRedirect: HealthCheckNodePort:0 LoopbackHostPort:false SourceRanges:[] PortNames:map[https:443] TrafficDistribution:}" fes="[{Address:192.168.60.179:443/TCP Type:ClusterIP ServiceName:default/kubernetes-intranet PortName:https ServicePort:443} {Address:0.0.0.0:30965/TCP Type:NodePort ServiceName:default/kubernetes-intranet PortName:https ServicePort:443} {Address:10.15.1.8:443/TCP Type:LoadBalancer ServiceName:default/kubernetes-intranet PortName:https ServicePort:443}]"
time=2026-01-04T09:00:04.632218089Z level=error msg=k8sError error="Get \"https://10.15.1.8:443/apis/networking.k8s.io/v1/networkpolicies?allowWatchBookmarks=true&resourceVersion=2599664664&timeout=7m4s&timeoutSeconds=424&watch=true\": dial tcp 10.15.1.8:443: connect: operation not permitted"
time=2026-01-04T09:00:04.632378389Z level=error msg=k8sError error="Get \"https://10.15.1.8:443/api/v1/namespaces?allowWatchBookmarks=true&resourceVersion=2599842706&timeout=6m40s&timeoutSeconds=400&watch=true\": dial tcp 10.15.1.8:443: connect: operation not permitted"
time=2026-01-04T09:00:04.632423794Z level=error msg=k8sError error="Get \"https://10.15.1.8:443/apis/cilium.io/v2/ciliumnodes?allowWatchBookmarks=true&fieldSelector=metadata.name%3D10.15.0.70&resourceVersion=2599779437&timeout=7m46s&timeoutSeconds=466&watch=true\": dial tcp 10.15.1.8:443: connect: operation not permitted"
time=2026-01-04T09:00:04.632513584Z level=error msg=k8sError error="Get \"https://10.15.1.8:443/api/v1/namespaces/kube-system/configmaps?allowWatchBookmarks=true&fieldSelector=metadata.name%3Dcilium-config&resourceVersion=2599840639&timeout=5m26s&timeoutSeconds=326&watch=true\": dial tcp 10.15.1.8:443: connect: operation not permitted"
time=2026-01-04T09:00:04.632700565Z level=error msg=k8sError error="Get \"https://10.15.1.8:443/apis/cilium.io/v2/ciliumcidrgroups?allowWatchBookmarks=true&resourceVersion=2599767279&timeout=7m20s&timeoutSeconds=440&watch=true\": dial tcp 10.15.1.8:443: connect: operation not permitted"
```

可以看到每次 convertService 得到的 svc 和 fes 变量均无异常。

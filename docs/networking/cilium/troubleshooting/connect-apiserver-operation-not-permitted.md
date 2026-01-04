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

查看 cilium 的 ebpf 数据，发现 `kubernetes-intranet` 这个 svc 的 backend 为空（NodePort、CLB VIP、ClusterIP 均为空）：

```txt
$ kubectl -n kube-system exec cilium-kddvm -- cilium service list
ID   Frontend                  Service Type   Backend
1    192.168.95.86:19090/TCP   ClusterIP      1 => 169.254.128.10:19090/TCP (active)
2    192.168.87.140:443/TCP    ClusterIP      1 => 169.254.128.10:443/TCP (active)
3    192.168.110.83:8080/TCP   ClusterIP      1 => 10.15.0.4:61678/TCP (active)
4    0.0.0.0:30965/TCP         NodePort
6    10.15.1.8:443/TCP         LoadBalancer
7    192.168.60.179:443/TCP    ClusterIP
8    192.168.47.130:443/TCP    ClusterIP      1 => 169.254.128.10:17443/TCP (active)
9    192.168.22.35:443/TCP     ClusterIP      1 => 10.15.0.4:4244/TCP (active)
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

## 深入 cilium 源码分析

根据之前的排查，明显可以看出是 cilium 内部的状态 (cilium service list 看到的 backend) 与实际的 EndpointSlice 不匹配，前者是空的，后者是一直存在且没有变动的。

所以，猜测是 cilium 同步 Service/EndpointSlice 时的逻辑问题。

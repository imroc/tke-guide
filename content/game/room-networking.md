# 房间类游戏网络接入

## 网络模型

对于需要开房间的游戏，我们通常需要为每个房间分配一个独立的公网地址(`IP:Port`)，玩家匹配成功后会被分配到同一个房间，开局前游戏客户端通过公网连上该房间：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F08%2F22%2F20240822161108.png)

下面介绍在 TKE 中，为每个房间分配独立公网地址的方法。

## EIP 方案

TKE 支持 [Pod 绑 EIP](../networking/pod-eip.md)，Pod 绑定 EIP 后，每个 Pod 都会分配一个独立的公网地址，房间的公网地址就是 Pod EIP + 房间进程监听的端口号。

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F08%2F22%2F20240822172226.png)

## CLB 映射方案

安装开源的 [tke-extend-network-controller](https://github.com/imroc/tke-extend-network-controller) 插件，可实现用 CLB 四层监听器来为每个 Pod 映射公网地址，每个 Pod 占用 CLB 一个端口，Pod 中房间的公网地址就是 Pod 所被绑定的 CLB 实例的公网 IP 或域名及其监听器对应的端口号。

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F08%2F22%2F20240822165733.png)

## 方案对比与选型

| 方案     | 费用                                                                                                             | Pod 绑定数量                                             | 大规模使用                                                     |
| -------- | ---------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- | -------------------------------------------------------------- |
| EIP      | IP 资源费用(闲置时才收取) + 网络费用，参考 [EIP 计费概述](https://cloud.tencent.com/document/product/1199/41692) | 一个 EIP 只能绑定一个 Pod                                | 不适合，EIP 资源有限，不仅是数量的限制，还有每日申请的数量限制 |
| CLB 映射 | 实例费用 + 网络费用，参考 [CLB 计费概述](https://cloud.tencent.com/document/product/214/42934)                   | 单个 CLB 的监听器数量上限默认为 50，可根据需求提工单调大 | 适合，一个 CLB 实例可为大量 Pod 映射公网地址，实例数量可控     |

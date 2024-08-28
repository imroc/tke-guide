# 房间类游戏网络接入

## 网络模型

对于需要开房间的游戏，我们通常需要为每个房间分配一个独立的公网地址(`IP:Port`)，玩家匹配成功后会被分配到同一个房间，开局前游戏客户端通过该公网地址连上房间：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F08%2F22%2F20240822161108.png)

下面介绍在 TKE 中，为每个房间分配独立公网地址的方法。

## EIP 方案

TKE 支持为 Pod 绑 EIP ，每个 Pod 都会被分配一个独立的公网 IP，房间的公网地址就是 Pod EIP + 房间进程监听的端口号。

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F08%2F22%2F20240822172226.png)

配置方法参考 [Pod 绑 EIP](../networking/pod-eip.md)。

## CLB 映射方案

安装开源的 [tke-extend-network-controller](https://github.com/imroc/tke-extend-network-controller) 插件，可实现用 CLB 四层监听器来为每个 Pod 映射公网地址，每个 Pod 占用 CLB 一个端口，Pod 中房间的公网地址就是 Pod 所被绑定的 CLB 实例的公网 IP 或域名及其监听器对应的端口号。

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F08%2F22%2F20240822165733.png)

配置方法参考 [使用 CLB 为 Pod 分配公网地址映射](https://github.com/imroc/tke-extend-network-controller/blob/main/docs/clb-mapping.md)。

## 方案对比与选型

| 方案     | 费用                                                                                                             | 大规模使用                                                                                                                                                                                                  |
| -------- | ---------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| EIP      | IP 资源费用(闲置时才收取) + 网络费用，参考 [EIP 计费概述](https://cloud.tencent.com/document/product/1199/41692) | 不适合，一个 EIP 只能绑定一个 Pod，EIP 资源有限，有申请的数量限制和每日申请的次数限制（参考 [EIP配额限制](https://cloud.tencent.com/document/product/1199/41648#eip-.E9.85.8D.E9.A2.9D.E9.99.90.E5.88.B6)） |
| CLB 映射 | 实例费用 + 网络费用，参考 [CLB 计费概述](https://cloud.tencent.com/document/product/214/42934)                   | 适合，一个 CLB 实例可为大量 Pod 映射公网地址，实例数量可控                                                                                                                                                  |

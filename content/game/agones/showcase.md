# 案例分享：使用 Agones 在 TKE 上部署游戏专用服务器

## 背景

有一款 PVP（房间类）游戏基于虚幻引擎 UE5.4 开发，玩家在线匹配到一个房间后，会进入房间进行对战，同一局的玩家都会连上同一个游戏专用服务器（DS, Dedicated Server）。为降低成本和提升灵活性，决定基于开源的 Agones 在 TKE 上部署游戏专用服务器，可根据空闲房间数量和比例自动扩缩容。

## 使用虚幻引擎插件接入 Agones

在游戏项目导入 Agones 插件并启用后，在合适位置初始化 Agones SDK 和调用相关 hook 函数，即可接入 Agones。

Agones 官方提供了 UE5 的插件和使用方法，参考 [Unreal Engine Game Server Client Plugin](https://agones.dev/site/docs/guides/client-sdks/unreal/)。

## TKE 集群与节点类型选型

TKE 集群主要有标准集群和 Serverless 集群之分，Serverless 集群的能力现已融入标准集群，未来将不再有 Serverless 集群，所以直接创建 TKE 标准集群即可。

部署游戏专用服务器使用超级节点，超级节点并非实体节点，仅代表一个子网，其中每个 Pod 都是独占的轻量虚拟机，Pod 扩容时没有耗时长的扩容节点过程，调度 Pod 后立即创建和启动一台轻量虚拟机并拉起容器，Pod 停止立即停止计费，即能保证扩容速度，又能按需使用，降低成本。

## 使用 tke-extend-network-controller 网络插件

游戏房间的公网地址如何暴露？Agones 只提供了 HostPort 这一种方式，如果用 TKE 超级节点，HostPort 无法使用（因为超级节点是虚拟的节点，HostPort 没有意义）。

而 TKE 提供了 tke-extend-network-controller 网络插件，可以通过 CLB 端口来为游戏专用服务器暴露公网地址，可参考 [使用 CLB 为 Pod 分配公网地址映射](https://cloud.tencent.com/document/product/457/111623) 进行安装和配置。

## 遇到的问题

游戏的业务场景是：在玩家匹配成功后，分配一个游戏房间（即 Agones 的 GameServer），但还需等待房间加载完将要连上来的玩家信息后，才通知玩家连接进入房间进行对战。

## 核心流程

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F11%2F06%2F20241106172705.png)

## 弹性伸缩

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F11%2F06%2F20241106172751.png)

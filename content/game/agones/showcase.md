# 案例分享：使用 Agones 在 TKE 上部署游戏专用服务器

## 术语

- DS：Dedicated Server，游戏专用服务器。在线对战的房间类游戏，同一局的玩家都会连上同一个 DS。本文中的方案采用单 Pod 单房间模式，可以认为一个 DS 就是一个游戏房间。

## 用户诉求

有一款 PVP（房间类）的游戏基于虚幻引擎 UE5.4 开发，玩家在线匹配到一个房间后，连上同一个 DS 开始进行对战。

具体流程如下。

1. 首先玩家准备游戏，游戏客户端请求大厅服进行游戏匹配：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F11%2F15%2F20241115154851.png)

2. 大厅服对玩家进行匹配，匹配成功后，大厅服会根据玩家所选地图、游戏模式和最终匹配人数等条件筛选出符合条件的 DS，将选中的 DS 标记为已分配并下发玩家信息，让 DS 加载：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F11%2F15%2F20241115155743.png)

3. 等 DS 加载完玩家信息后，大厅服通知游戏客户端开始游戏并提供 DS 公网地址：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F11%2F15%2F20241115160312.png)

4. 客户端拿到 DS 地址后就可以连上 DS，玩家开始对战：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F11%2F15%2F20241115160505.png)

核心诉求：
1. 玩家同时在线数量可能暴涨或暴跌，需支持 DS 的动态扩缩容，且扩容速度要快，避免玩家等待过久。
2. 每个 DS 都需要独立的公网地址，且 DS 数量可能较大，需要支持大规模动态分配公网地址的能力。
3. 被分配的 DS 不能被再次被分配，缩容时也不允许已分配的 DS 被销毁，避免玩家中断。

## 初步选型

围绕 DS 有类似 GameLift 这样专门对 DS 进行部署与弹性伸缩云服务，但价格相对较高，灵活性较低，为降低成本和提升灵活性，业务团队决定基于云厂商的托管 Kubernetes 和云原生游戏开源项目来部署 DS，并配置根据空闲房间数量和比例的自动扩缩容。 

## 托管 Kubernetes 选型

TKE 是腾讯云上托管 Kubernetes 集群的服务，支持超级节点这种 Serverless 形态，每个 Pod 独占轻量虚拟机，既能避免 DS 间相互干扰（强隔离），也能实现快速扩容 Pod（Pod 独占轻量虚机，无需扩容节点）。

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F11%2F07%2F20241107103814.png)

Pod 销毁立即自动停止计费，即能保证隔离性和扩容速度，又能按需使用，降低成本，所以托管 Kubernetes 服务选择了 TKE。

## 工作负载选型

集群选择了 TKE，接下来就是要确定用什么工作负载类型来部署 DS 了。

Kubernetes 自带了 Deployment 和 StatefulSet 两种工作负载类型，但对游戏 DS 来说，都太简陋了。它们都无法做到标识 Pod 中的房间是否空闲，缩容的时候，非空闲的 Pod 可能会被删除，影响正在对战的玩家。

[OpenKruiseGame](https://openkruise.io/zh/kruisegame/introduction/) 和 [Agones](https://agones.dev/site/) 都提供了专门针对游戏场景的 Kubernetes 自定义工作负载类型，都能实现 DS 的动态伸缩，且能避免缩容时销毁非空闲的 DS。

根据自身业务情况，决定采用使用 [Agones](https://agones.dev/site/) 来部署 DS。

## 分配游戏房间(DS)的方法

Agones 是单 Pod 单房间的模型，社区也有讨论对单 Pod 多房间的支持，参考 [issue #1197](https://github.com/googleforgames/agones/issues/1197)，但这会让游戏服的管理很复杂也很难实现，最终只给了个 [High Density GameServers](https://agones.dev/site/docs/integration-patterns/high-density-gameservers/) 的妥协方案，流程复杂且需要游戏服自己做很大开发工作来适配。

所以还是选择了用单 Pod 单房间的模型进行管理，Agones 提供了 [GameServerAllocation](https://agones.dev/site/docs/reference/gameserverallocation/) API 来分配 GameServer，一个 GameServer 代表一个房间，也代表一个 DS，还支持根据特征（如 label）分配合适的 GameServer，如不同地图、不同 Pod 规格的 GameServer 打上指定的 label，匹配时根据游戏人数和游戏属性（如选择的地图和游戏模式）来匹配到适合的 GameServer。

## 使用虚幻引擎插件接入 Agones

在游戏项目导入 Agones 插件并启用后，在合适位置初始化 Agones SDK 和调用相关 hook 函数，即可接入 Agones。

Agones 官方提供了 UE5 的插件及其使用方法，参考 [Unreal Engine Game Server Client Plugin](https://agones.dev/site/docs/guides/client-sdks/unreal/)。

## 使用流水线自动构建容器镜像

使用虚幻引擎开发的游戏，需使用虚幻官方提供的工具进行构建，平时自测一般用虚幻编辑器构建在本地测试，发版时则使用 [Coding](https://coding.net/) 流水线来自动构建并编译容器镜像，推送至 [TCR 镜像仓库](https://cloud.tencent.com/product/tcr)。

流水线的大致思路是：
1.  UE 官方提供了 [通过命令行构建项目](https://dev.epicgames.com/documentation/zh-cn/unreal-engine/linux-development-quickstart-for-unreal-engine#5b%E9%80%9A%E8%BF%87%E5%91%BD%E4%BB%A4%E8%A1%8C%E6%9E%84%E5%BB%BA%E9%A1%B9%E7%9B%AE) 的方法，可根据自身需求在流水线中编写适合的构建命令。
2.  假设上一步构建出压缩包名为 `LinuxServer.zip`，流水线中将其解压到 `LinuxServer` 文件夹，并使用如下的 `Dockerfile` 构建容器镜像（注意替换 `ENTRYPOINT` 中的脚本名称）。
    ```dockerfile
    FROM ubuntu:22.04
    RUN mkdir /app
    COPY ./LinuxServer /app
    RUN useradd -m ue5
    RUN chown -R ue5:ue5 /app
    USER ue5

    EXPOSE 7777/tcp
    EXPOSE 7777/udp

    ENTRYPOINT [ "/app/LyraServer.sh" ]
    ```
3. 最后流水线自动将容器镜像推送到镜像仓库。一般游戏的镜像都较大，就使用腾讯云 [TCR 镜像仓库](https://cloud.tencent.com/product/tcr)，确保镜像拉取的速度和稳定性。

## 使用 Agones Fleet 部署

Agones 提供了 Fleet 来编排 DS，也就是一种 Kubernetes 中扩展的自定义工作负载类型，类似 Kubernetes 的 StatefulSet，只是专为游戏场景设计。

Fleet 指定 DS 的副本数，每个副本对应一个 GameServer 对象，该对象中可以记录游戏服务器的状态，如是否已被分配、对外的公网地址、玩家数量等。

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F11%2F07%2F20241107120107.png)

Fleet 配置方法参考官方文档 [Quickstart: Create a Game Server Fleet](https://agones.dev/site/docs/getting-started/create-fleet/)。

由于游戏中每场对局的人数、地图、游戏模式等业务属性可能不同，所以需要将 Fleet 拆分成多个，不同 Fleet 使用不同 Pod 规格、使用不同启动参数加载不同地图等业务数据，并打上能标识规格、地图等属性的 label，用于后续分配房间（DS）时根据 label 过滤合适的 GameServer。

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F11%2F07%2F20241107150329.png)

## 使用 TKE 网络插件为游戏房间映射公网地址

每个游戏房间（DS）都需要独立的公网地址，而 Agones 只提供了 HostPort 这一种方式，如果用 TKE 超级节点，HostPort 无法使用（因为超级节点是虚拟的节点，HostPort 没有意义）。

TKE 提供了 `tke-extend-network-controller` 网络插件，可以通过 CLB 端口来为 DS 暴露公网地址，可参考 [使用 CLB 为 Pod 分配公网地址映射](https://cloud.tencent.com/document/product/457/111623) 进行安装和配置。

如何关联 Agones 的 GameServer 与映射的 CLB IP:Port？可以将 IP:Port 信息写到 GameServer 的 label 中。

下面介绍实现步骤：

1. 首先定义 `DedicatedCLBService` 时指定 `addressPodAnnotation`，即将 CLB 的 IP:Port 信息注入到 Pod 指定注解中：

```yaml
apiVersion: networking.cloud.tencent.com/v1alpha1
kind: DedicatedCLBService
metadata:
  namespace: demo
  name: gameserver
spec:
  maxPod: 50
  selector:
    app: gameserver
  ports:
  - protocol: UDP
    targetPort: 9000
    addressPodAnnotation: networking.cloud.tencent.com/external-address # 将外部地址自动注入到指定的 pod annotation 中
  existedLbIds:
    - lb-xxx
```

2. 然后定义游戏服工作负载的 pod template 时（`Fleet` 是 `.spec.template.spec.template` 字段），利用 downward API 将注解信息挂载到容器中：

```yaml
    spec:
      containers:
        - ...
          volumeMounts:
            - name: podinfo
              mountPath: /etc/podinfo
      volumes:
        - name: podinfo
          downwardAPI:
            items:
              - path: "address"
                fieldRef:
                  fieldPath: metadata.annotations['networking.cloud.tencent.com/external-address']
```

3. 游戏服启动时轮询此文件，发现内容不为空时即表示 CLB 已绑定好 Pod，内容即为当前房间的公网地址。可通过调用 Agones SDK 的 [SetLabel](https://pkg.go.dev/agones.dev/agones/sdks/go#SDK.SetLabel)  函数将信息写入到 GameServer 对象中以实现 GameServer 与 CLB 公网地址映射的关联。

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F11%2F06%2F20241106191629.png)

## 架构设计

在游戏业务场景中，游戏房间（DS）不仅有是否分配的状态，还有一些其他业务扩展的状态，比如玩家信息是否加载完成的状态（在玩家匹配成功后，分配一个游戏房间，即 Agones 的 GameServer，但还需等待房间加载完将要连上来的玩家信息后，才通知玩家连接进入房间进行对战）。

考虑到后续还有很多其它游戏要用，就打算不直接在大厅服里写这些房间管理的逻辑，所以引入 room-manager 作为房间管理的中间件，该中间件使用 Go 语言开发，利用 k8s 的 client-go 对集群中的 GameServer 进行 list-watch （其他语言的 k8s SDK 不支持自定义资源的 list-watch），为大厅服暴露两个接口：
1. 查询 GameServer 信息(从 client-go list-watch 的缓存拿，用于大厅服查询分配的房间是否加载完玩家信息，等加载完就通知玩家连上该房间进行战斗)。
2. 分配 GameServer (本质上会调用 Agones 提供的 GameServerAllocation API，只是会根据业务需求加一些过滤条件，比如根据匹配的人数、选择的地图和游戏模式等条件匹配满足条件的  GameServer，通过 label 标识和过滤)。

整体流程如下:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F11%2F06%2F20241106172705.png)

## 弹性伸缩

Agones 支持通过 `FleetAutoScaler` 声明游戏服的弹性伸缩策略，可以指定 Fleet 预留的 buffer 大小（冗余的空闲房间），可以是数量，也可以是百分比（空闲房间比例）：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F11%2F11%2F20241111162148.png)

考虑到 Fleet 众多和游戏规模等因素，希望尽可能控制成本，尽可能精准控制 GameServer 数量，决定设定预留 buffer 大小为指定数量的 GameServer，使用脚本定时修改 buffer 大小，以实现在每日高峰期到来之前提前预留的 GameServer 数量，减少玩家的等待时间；高峰期结束后减小 buffer 数量，降低成本。

## 参考资料

- Agones 官网： https://agones.dev/site/ 
- Agones 的 UE 插件： https://agones.dev/site/docs/guides/client-sdks/unreal/
- 使用 CLB 为 Pod 分配公网地址映射: https://cloud.tencent.com/document/product/457/111623
- tke-extend-network-controller 开源项目: https://github.com/tkestack/tke-extend-network-controller
- TCR 镜像仓库: https://cloud.tencent.com/product/tcr
- Coding: https://coding.net/
- OpenMatch: https://github.com/googleforgames/open-match
- kruise-game-open-match-director: https://github.com/CloudNativeGame/kruise-game-open-match-director

# 案例分享：使用 Agones 在 TKE 上部署游戏专用服务器

## 项目背景

有一款 PVP（房间类）的游戏基于虚幻引擎 UE5.4 开发，玩家在线匹配到一个房间后，会一起进入该房间进行对战，同一局的玩家都会连上同一个游戏专用服务器（DS, Dedicated Server）。为降低成本和提升灵活性，决定基于开源的 Agones 在 TKE 上部署游戏专用服务器，可根据空闲房间数量和比例自动扩缩容。

## TKE 集群与节点类型选型

TKE 集群主要有标准集群和 Serverless 集群之分，Serverless 集群的能力现已融入标准集群，未来将不再有 Serverless 集群，所以直接创建 TKE 标准集群即可。

部署游戏专用服务器使用超级节点，超级节点并非实体节点，仅代表一个子网，其中每个 Pod 都独占的轻量虚拟机，Pod 扩容时没有耗时长的扩容节点过程，调度 Pod 后立即创建和启动一台轻量虚拟机并拉起容器，Pod 销毁立即自动停止计费，即能保证扩容速度，又能按需使用，降低成本。

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F11%2F07%2F20241107103814.png)

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

Agones 提供了 Fleet 来编排游戏专用服务器，也就是一种 Kubernetes 中扩展的自定义工作负载类型，类似 Kubernetes 的 StatefulSet，只是专为游戏场景设计。

Fleet 指定游戏专用服务器的副本数，每个副本对应一个 GameServer 对象，该对象中可以记录游戏服务器的状态，如是否已被分配、对外的公网地址、玩家数量等。

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F11%2F07%2F20241107120107.png)

Fleet 配置方法参考官方文档 [Quickstart: Create a Game Server Fleet](https://agones.dev/site/docs/getting-started/create-fleet/)。

## 分配游戏房间的方法

Agones 是单 Pod 单房间的模型，社区也有讨论对单 Pod 多房间的支持，参考 [issue #1197](https://github.com/googleforgames/agones/issues/1197)，但这会让游戏服的管理很复杂也很难实现，最终只给了个 [High Density GameServers](https://agones.dev/site/docs/integration-patterns/high-density-gameservers/) 的妥协方案，流程复杂且需要游戏服自己做很大开发工作来适配。

所以还是选择了用单 Pod 单房间的模型进行管理，Agones 提供了 [GameServerAllocation](https://agones.dev/site/docs/reference/gameserverallocation/) API 来分配 GameServer，一个 GameServer 代表一个房间，调用 GameServerAllocation 分配 GameServer 后，被分配的 GameServer 状态会被标记为 Allocated，该状态的 GameServer 对应的 Pod 可以避免缩容时被删除，下次分配房间时也不会分配该状态的 GameServer。

## 使用 tke-extend-network-controller 网络插件为房间映射公网地址

每个游戏房间都需要独立的公网地址，而 Agones 只提供了 HostPort 这一种方式，如果用 TKE 超级节点，HostPort 无法使用（因为超级节点是虚拟的节点，HostPort 没有意义）。

TKE 提供了 tke-extend-network-controller 网络插件，可以通过 CLB 端口来为游戏专用服务器暴露公网地址，可参考 [使用 CLB 为 Pod 分配公网地址映射](https://cloud.tencent.com/document/product/457/111623) 进行安装和配置。

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

3. 游戏服启动时轮询此文件，发现内容不为空时即表示 CLB 已绑定好 Pod，内容即为当前房间的公网地址。可通过调用 Agones SDK 的 `SetLabel` 或 `SetAnnotation` 函数将信息写入到 GameServer 对象中以实现 GameServer 与 CLB 公网地址映射的关联。

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F11%2F06%2F20241106191629.png)

## 架构设计

在游戏业务场景中，游戏房间不仅有是否分配的状态，还有一些其他业务扩展的状态，比如玩家信息是否加载完成的状态（在玩家匹配成功后，分配一个游戏房间，即 Agones 的 GameServer，但还需等待房间加载完将要连上来的玩家信息后，才通知玩家连接进入房间进行对战）。

考虑到后续还有很多其它游戏要用，不能直接在大厅服里写这些房间管理的逻辑，所以引入 room-manager 作为房间管理的中间件，该中间件使用 Go 语言开发，利用 k8s 的 client-go 对集群中的 GameServer 进行 list-watch （其他语言 SDK 不支持自定义资源的 list-watch），为大厅服暴露两个接口：
1. 查询 GameServer 信息(从 client-go list-watch 的缓存拿)。
2. 分配 GameServer (Agones 提供的 GameServerAllocation API)。

整体流程:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F11%2F06%2F20241106172705.png)

## 弹性伸缩

Agones 支持通过 `FleetAutoScaler` 声明游戏服的弹性伸缩策略，可以指定 Fleet 预留的 buffer 大小（冗余的空闲房间），可以是数量，也可以是百分比（空闲房间比例）：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F11%2F06%2F20241106172751.png)

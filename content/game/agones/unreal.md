# 将虚幻引擎开发的游戏接入 Agones 并部署到 TKE

## 安装 Visual Studio

1. 进入 [Visual Studio 下载页面](https://visualstudio.microsoft.com/zh-hans/downloads/)，下载 Visual Studio 并安装，如需免费，可使用社区版。
2. 安装时确保以下 C++ 相关选项勾选上。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F15%2F20241015102406.png)
3. 虚幻引擎对最新编译器版本可能有兼容性问题，建议勾选下虚幻引擎支持的最新 MVSC 版本，现在虚幻引擎源码中找到当前首选的编译器版本，文件路径 `Engine/Config/Windows/Windows_SDK.json`。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F15%2F20241015165228.png)
4. 在 Visual Studio Installer 中点到【单个组件】，搜索并勾选下首选编译器版本相关组件（记得取消勾选下最新版本）。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F16%2F20241016102245.png)
5. 同样也在 `Windows_SDK.json` 文件中可找到建议的 .NET 版本。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F16%2F20241016102810.png)
6. 在【单个组件】中搜索并勾选下 .NET 相关组件（记得取消勾选下最新版本）。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F16%2F20241016102718.png)

## 通过源码安装虚幻引擎

虚幻引擎支持通过 `Epic Games Launcher` 来安装虚幻引擎，也可以通过源码安装。一般虚幻引擎的游戏都结合 Visual Studio 和 C++ 来开发，虚幻引擎需要通过源码方式来安装。

以下是安装步骤：

1. 确保已注册 Epic Games 账号与 GitHub 账号。
2. 登录[Epic Games 官网](https://www.unrealengine.com/)，进入[应用与账户](https://www.unrealengine.com/account/connections?lang=zh-CN)，连接 GitHub 账号。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F15%2F20241015103049.png)
3. 登录 [Github](https://github.com/) 官网，等待接收 Epic Games 加入组织的邀请。
4. 接受邀请后进入 [Unreal Engine 代码仓库](https://github.com/EpicGames/UnrealEngine)，在 [release 页面](https://github.com/EpicGames/UnrealEngine/releases) 下载最新版本的源码压缩包。
5. 解压后打开命令行，进入源码目录。
6. 执行 `Setup.bat`，会下载安装一些依赖，预计需要较长时间。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F15%2F20241015102521.png)
7. 执行 `GenerateProjectFiles.bat`，生成 Visual Studio 项目文件。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F15%2F20241015104317.png)
9. 双击 `UE5.sln` 文件以将项目通过 Visual Studio 加载。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F15%2F20241015104403.png)
10. 解决方案配置设为 `Development Editor` (开发编辑器)。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F15%2F20241015104726.png)
11. 解决方案平台设为 `Win64`：
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F15%2F20241015104840.png)
12. 在右侧解决方案资源管理器中，右键 `UE5`，点击【生成】。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F15%2F20241015105001.png)
13. 然后经过漫长的构建等待，具体时长也跟机器性能有关（我这里使用的16c64g的windows云服务器，耗时1小时42分），注意需要 0 失败，如果有发现失败的，要看下失败原因。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F16%2F20241016140321.png)
14. 右键 `UE5`，点击【设为启动项目】。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F15%2F20241015144043.png)
15. 点击启动调试。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F15%2F20241015144326.png)
16. 如果一切正常，会看到虚幻编辑器启动界面。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F16%2F20241016141131.png)

## 下载 Lyra 项目

1. 进入 [Epic Games 官网](https://store.epicgames.com/zh-CN/) 。
2. 点击右上角的【下载】，下载 `EpicInstaller` 来安装 `Epic Games Launcher`。
3. 打开 `Epic Games Launcher` 后登录 Epic Games 账号。
4. 依次点击【虚幻引擎】-【示例】。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F15%2F20241015100706.png)
5. 点击 【Lyra Starter Game】-【创建工程】。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F15%2F20241015100848.png) 
6. 选择好位置，点击【创建】。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F15%2F20241015101010.png)
7. 等待下载完成。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F15%2F20241015101039.png)

## 配置 Lyra 项目

1. 将 Lyra 项目文件夹里放到 UE 源码目录下，Visual Studio 会自动识别并提示是否重新加载，点【是】。
2. 右键 Lyra，点击【生成】。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F16%2F20241016144429.png)
3. 等待生成成功。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F16%2F20241016144631.png)
4. 在 Lyra 项目的文件夹下双击 UE 文件(`.uproject`) 的图标，在虚幻引擎中打开 Lyra。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F16%2F20241016144851.png)
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F16%2F20241016143823.png)
5. 打开成功后，会看到如下界面。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F16%2F20241016144742.png)
6. 点击【编辑】-【项目设置】。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F16%2F20241016145106.png)
7. 默认地图设置为 `L_Expanse` ，这样启动游戏客户端时会直接进入地图，而不是主菜单，方便测试。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F16%2F20241016145330.png)
8. 回到主界面，依次点击【内容侧滑菜单】-【Plugins】，搜索并双击 `B_ShooterBotSpawner` 打开蓝图窗口。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F16%2F20241016145917.png)
9. `Num bots to Create` 设为 0，然后点【编译】。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F16%2F20241016150409.png)
10. 关闭蓝图窗口。

## 编译服务端

1. 在 Visual Studio 中，解决方案配置切到 `Development Server`。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F16%2F20241016163724.png)
2. 右键 Lyra，点击【生成】。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F16%2F20241016163807.png)
3. 经过漫长的等待后，在 Lyra 的 `Binaries\Win64` 目录下会生成 `LyraServer` 二进制。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F16%2F20241016163628.png)

## 编译客户端

1. 在 Visual Studio 中，解决方案配置切到 `Development Client`。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F16%2F20241016163724.png)
2. 右键 Lyra，点击【生成】。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F16%2F20241016163807.png)
3. 经过漫长的等待后，在 Lyra 的 `Binaries\Win64` 目录下会生成 `LyraClient` 二进制。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F16%2F20241016171047.png)

## 烘培服务端

1. 按照截图勾选 `开发` 和 `Server`。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F16%2F20241016171540.png)
2. 按照如下截图点击【烘培内容】。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F16%2F20241016171752.png)
3. 右下角将显示一个对话框，表明内容正在烘焙。点击此对话框中的 显示输出日志（Show Output Log） ，监控烘焙过程，等待完成。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F16%2F20241016172115.png)
4. 在 Lyra 的 `Saved\Cooked` 目录下可以看到烘培出的内容。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F16%2F20241016172226.png)
5. 在命令提示符中找到你的项目目录，并执行 `./Binaries/Win64/<PROJECT_NAME>Server.exe -log` ，测试服务器是否成功运行。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F16%2F20241016172601.png)

## 烘培客户端

1. 按照截图勾选 `开发` 和 `Client`。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F16%2F20241016172706.png)
2. 按照如下截图点击【烘培内容】。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F16%2F20241016172806.png)

## TODO

* 下载安装交叉编译工具：https://dev.epicgames.com/documentation/zh-cn/unreal-engine/linux-development-requirements-for-unreal-engine

## FAQ

### 安装额外组件

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F15%2F20241015104550.png)

## 参考资料

* [虚幻引擎: 设置专用服务器](https://dev.epicgames.com/documentation/zh-cn/unreal-engine/setting-up-dedicated-servers-in-unreal-engine)

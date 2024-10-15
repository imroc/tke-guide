# 将虚幻引擎开发的游戏接入 Agones 并部署到 TKE

## 安装 Visual Studio

1. 进入 [Visual Studio 下载页面](https://visualstudio.microsoft.com/zh-hans/downloads/)，下载 Visual Studio 并安装，如需免费，可使用社区版。
2. 安装时确保以下 C++ 相关选项勾选上。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F15%2F20241015102406.png)
3. 虚幻引擎对最新编译器版本可能有兼容性问题，建议勾选下虚幻引擎支持的最新 MVSC 版本，现在虚幻引擎源码中找到当前首选的编译器版本，文件路径 `Engine/Config/Windows/Windows_SDK.json`。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F15%2F20241015165228.png)
4. 在 Visual Studio Installer 中点到【单个组件】，搜索并勾选下首选编译器版本相关组件（记得取消勾选下最新版本）。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F15%2F20241015155311.png)

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
13. 然后经过漫长的构建等待，具体时长也跟机器性能有关（我这里使用的8c32g的windows云服务器，耗时3小时47分）。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F15%2F20241015143829.png)
14. 右键 `UE5`，点击【设为启动项目】。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F15%2F20241015144043.png)
15. 点击启动调试。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F15%2F20241015144326.png)

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

## TODO

## FAQ

### 安装额外组件

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F10%2F15%2F20241015104550.png)

## 参考资料

* [虚幻引擎: 设置专用服务器](https://dev.epicgames.com/documentation/zh-cn/unreal-engine/setting-up-dedicated-servers-in-unreal-engine)

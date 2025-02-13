# 在 TKE 上部署 AI 大模型

## 概述

本文介绍如何在 TKE 上部署 AI 大模型，以 `DeepSeek-R1` 为例，使用 `Ollama` 或 `vLLM` 运行大模型并暴露 API，然后使用 `OpenWebUI` 提供交互界面。

`Ollama` 提供是 Ollama API，部署架构：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F06%2F20250206171758.png)

`vLLM` 提供的是兼容 OpenAI 的 API，部署架构：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F06%2F20250206144336.png)

## Ollama、vLLM 与 OpenWebUI 介绍

* [Ollama](https://ollama.com/) 是一个运行大模型的工具，可以看成是大模型领域的 Docker，可以下载所需的大模型并暴露 Ollama API，极大的简化了大模型的部署。
* [vLLM](https://docs.vllm.ai) 与 Ollama 类似，也是一个运行大模型的工具，但它针对推理做了很多优化，提高了模型的运行效率和性能，使得在资源有限的情况下也能高效运行大语言模型，另外，它提供兼容 OpenAI 的 API。
* [OpenWebUI](https://openwebui.com/) 是一个大模型的 Web UI 交互工具，支持通过 Ollama 与 OpenAI 两种 API 与大模型交互。

## 技术选型

### 选择 Ollama 还是 vLLM？

- Ollama 的特点：个人用户或本地开发环境使用 Ollama 很方便，对各种 GPU 硬件和大模型的兼容性很好，不需要复杂的配置就能跑起来，但性能上不如 vLLM。
- vLLM 的特点：推理性能更好，也更节约资源，适合部署到服务器供多人使用，还支持多机多卡分布式部署，上限更高，但能适配的 GPU 硬件比 Ollama 少，且需要根据不同 GPU 和大模型来调整 vllm 的启动参数才能跑起来或者获得更好的性能表现。

- **选型建议**：如果有一定的技术能力且愿意折腾，能用 vLLM 成功跑起来更推荐用 vLLM 将大模型部署到 Kubernetes 中，否则就用 Ollama ，两种方式在本文中都有相应的部署示例。

### AI 大模型数据如何存储？

AI 大模型通常占用体积较大，直接打包到容器镜像不太现实，如果启动时通过 `initContainers` 自动下载又会导致启动时间过长，因此建议使用共享存储来挂载 AI 大模型（先下发一个 Job 将模型下载到共享存储，然后再将共享存储挂载到运行大模型的 Pod 中）。

在腾讯云上可使用 CFS 来作为共享存储，CFS 的性能和可用性都非常不错，适合 AI 大模型的存储。本文将使用 CFS 来存储 AI 大模型。

### GPU 机型如何选？

不同的机型使用的 GPU 型号不一样，机型与 GPU 型号的对照表参考 [GPU 计算型实例](https://cloud.tencent.com/document/product/560/19700) 和 [GPU 渲染型实例](https://cloud.tencent.com/document/product/560/63854)，Ollama 相比 vLLM，支持的 GPU 型号更广泛，兼容性更好，建议根据事先调研自己所使用的工具和大模型，选择合适的 GPU 型号，再根据前面的对照表确定要使用的 GPU 机型，另外也注意下选择的机型在哪些地域在售，以及是否售罄，可通过 [购买云服务器](https://buy.cloud.tencent.com/cvm) 页面进行查询（**实例族**选择**GPU机型**）。

## 操作步骤

### 步骤1: 准备集群

登录 [容器服务控制台](https://console.cloud.tencent.com/tke2)，创建一个集群，集群类型选择**TKE 标准集群**。详情请参见 [创建集群](https://cloud.tencent.com/document/product/457/103981)。

### 步骤2: 准备 CFS 存储

#### 安装 CFS 插件

1. 在集群列表中，单击**集群 ID**，进入集群详情页。
2. 选择左侧菜单栏中的**组件管理**，在组件页面单击**新建**。
3. 在新建组件管理页面中勾选 **CFS（腾讯云文件存储）**。

:::tip[说明]

* 支持选择 **CFS（腾讯云文件存储）** 或 **CFS Turbo（腾讯云高性能并行文件系统）**，本文以 **CFS（腾讯云文件存储）为例**。
* CFS-Turbo 的性能更强，读写速度更快，但成本也更高。如果希望大模型运行和下载速度更快，可以考虑使用 CFS-Turbo。

:::

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F05%2F20250205104156.png)

4. 单击完成即可创建组件。


#### 新建 StorageClass

:::tip[说明]

该步骤选择项较多，因此本文示例通过容器服务控制台来创建 PVC。若您希望通过 YAML 来创建，可以先用控制台创建一个测试 PVC，然后复制生成的 YAML 文件

:::

1. 在集群列表中，单击**集群 ID**，进入集群详情页。
2. 选择左侧菜单栏中的**存储**，在 StorageClass 页面单击**新建**。
3. 在新建存储页面，根据实际需求，创建 CFS 类型的 StorageClass。如下图所示：
  ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F06%2F20250206160151.png)
  * 名称：请输入 StorageClass 名称，本文以 “cfs-ai” 为例。
  * Provisioner：选择 “文件存储 CFS”。
  * 存储类型：建议选择“性能存储”，其读写速度比“标准存储”更快。


:::tip[说明]

如果是新建 CFS-Turbo `StorageClass`，则需要在文件存储控制台先新建好 CFS-Turbo 文件系统，然后创建 `StorageClass` 时引用对应的 CFS-Turbo 实例。

:::

#### 创建 PVC

创建一个 CFS 类型的 PVC，用于存储 AI 大模型：

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ai-model
  labels:
    app: ai-model
spec:
  storageClassName: cfs-ai
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 100Gi
```

:::info[注意]

1. 注意替换 `storageClassName`。
2. 对于 CFS 来说，`storage` 大小无所谓，可随意指定，按实际占用空间付费的。

:::

再创建一个 PVC 给 OpenWebUI 用，可使用同一个 `storageClassName`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: webui
  labels:
    app: webui
spec:
  accessModes:
  - ReadWriteMany
  storageClassName: cfs-ai
  resources:
    requests:
      storage: 100Gi
```

### 步骤3: 新建 GPU 节点池

1. 在集群管理页面，选择**集群 ID**，进入集群的基本信息页面。
2. 选择左侧菜单栏中的**节点管理**，在节点池页面单击**新建**。
3. 选择节点类型。配置详情请参见 [创建节点池](https://cloud.tencent.com/document/product/457/43735)。
  * 如果使用**原生节点**或**普通节点**，**操作系统**选新一点的；**系统盘**和**数据盘**默认 50GB，建议调大点（如200GB），避免因 AI 相关镜像大导致节点磁盘空间压力大；**机型配置**在**GPU 机型**中选择一个符合需求且没有售罄的机型，如有 GPU 驱动选项，也选最新的版本。
    ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F06%2F20250206172803.png)
  * 如果使用**超级节点**，是虚拟的节点，每个 Pod 都是独占的轻量虚拟机，所以无需选择机型，只需在部署的时候通过 Pod 注解来指定 GPU 卡的型号（后面示例中会有）。
4. 单击**创建节点池**。

:::tip[说明]

GPU 插件无需显式安装，如果使用**普通节点**或**原生节点**，配置了 GPU 机型，会自动安装 GPU 插件；如果使用**超级节点**，则无需安装 GPU 插件。

:::

### 步骤4: 使用 Job 下载 AI 大模型

下发一个 Job，将需要用的 AI 大模型下载到 CFS 共享存储中，以下分别是 vLLM 和 Ollama 的 Job 示例：

:::tip[注意]

1. 使用之前 Ollama 或 vLLM 的镜像执行一个脚本去下载我们需要的 AI 大模型，本例中下载的是 DeepSeek-R1 的模型，修改 `LLM_MODEL` 以替换大语言模型。
2. 如果使用 Ollama，可以在 [Ollama 模型库](https://ollama.com/search) 查询和搜索需要的模型；如果使用 vLLM，可以在 [Hugging Face 模型库](https://huggingface.co/models) 和 [ModelScope 模型库](https://www.modelscope.cn/models) 查询和搜索需要的模型（国内环境可以用 ModelScope 的模型库，避免因网络问题下载失败，通过 `USE_MODELSCOPE` 环境环境变量控制是否从 ModelScope 下载）。

:::

<Tabs>
  <TabItem value="vLLM" label="vLLM Job">
    <FileBlock file="ai/vllm-download-model-job.yaml" showLineNumbers title="vllm-download-model-job.yaml" />
  </TabItem>
  <TabItem value="Ollama" label="Ollama Job">
    <FileBlock file="ai/ollama-download-model-job.yaml" showLineNumbers title="ollama-download-model-job.yaml" />
  </TabItem>
</Tabs>

### 步骤5: 部署 Ollama 或 vLLM

<Tabs>
  <TabItem value="deploy-vllm" label="部署 vLLM">
    通过 Deployment 部署 vLLM:
    <Tabs>
      <TabItem value="vllm" label="原生节点或普通节点">
        <FileBlock file="ai/vllm.yaml" showLineNumbers />
      </TabItem>
      <TabItem value="vllm-eks" label="超级节点">
        <FileBlock file="ai/vllm-eks.yaml" showLineNumbers />
      </TabItem>
    </Tabs>
    1. `--served-model-name` 参数指定大模型名称，与前面下载 Job 中指定的名称要一致，注意替换。
    2. 模型数据引用前面下载 Job 使用的 PVC，挂载到 `/data` 目录下。
    3. vLLM 监听 8000 端口暴露 API，定义 Service 方便后续被 OpenWebUI 调用。
  </TabItem>
  <TabItem value="deploy-ollama" label="部署 Ollama">
    通过 Deployment 部署 Ollama:
    <Tabs>
      <TabItem value="ollama" label="原生节点或普通节点">
        <FileBlock file="ai/ollama.yaml" showLineNumbers />
      </TabItem>
      <TabItem value="ollama-eks" label="超级节点">
        <FileBlock file="ai/ollama-eks.yaml" showLineNumbers />
      </TabItem>
    </Tabs>
    1. Ollama 的模型数据存储在 `/root/.ollama` 目录下，挂载已经下载好 AI 大模型的 CFS 类型 PVC 到该路径。
    2. Ollama 监听 11434 端口暴露 API，定义 Service 方便后续被 OpenWebUI 调用。
    3. Ollama 默认监听的是回环地址(127.0.0.1)，指定 `OLLAMA_HOST` 环境变量，强制对外暴露 11434 端口。
  </TabItem>
</Tabs>
4. 运行大模型需要使用 GPU，因此在 requests/limits 中指定了 `nvidia.com/gpu` 资源，以便让 Pod 调度到 GPU 机型并分配 GPU 卡使用。
5. 如果希望大模型跑在超级节点，需通过 Pod 注解 `eks.tke.cloud.tencent.com/gpu-type` 指定 GPU 类型，可选 `V100`、`T4`、`A10*PNV4`、`A10*GNV4`，具体可参考 [这里](https://cloud.tencent.com/document/product/457/39808#gpu-.E8.A7.84.E6.A0.BC)。

### 步骤6: 配置 GPU 弹性伸缩

如果需要对 GPU 资源进行弹性伸缩，可以按照下面的方法进行配置。

GPU 的 Pod 会有一些监控指标，参考 [GPU 监控指标](https://cloud.tencent.com/document/product/457/38929#gpu)，可以根据这些监控指标配置 HPA 实现 GPU Pod 的弹性伸缩，比如按照 GPU 利用率：

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: vllm
spec:
  minReplicas: 1
  maxReplicas: 2
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: vllm
  metrics: # 更多 GPU 指标参考 https://cloud.tencent.com/document/product/457/38929#gpu
  - pods:
      metric:
        name: k8s_pod_rate_gpu_used_request # GPU利用率 (占 Request)
      target:
        averageValue: "80"
        type: AverageValue
    type: Pods
  behavior:
    scaleDown:
      policies:
      - periodSeconds: 15
        type: Percent
        value: 100
      selectPolicy: Max
      stabilizationWindowSeconds: 300
    scaleUp:
      policies:
      - periodSeconds: 15
        type: Percent
        value: 100
      - periodSeconds: 15
        type: Pods
        value: 4
      selectPolicy: Max
      stabilizationWindowSeconds: 0
```

:::info[注意]

需要注意的是，GPU 资源通常比较紧张，缩容后不一定还能再买回来，如不希望缩容，可以给 HPA 配置下禁止缩容：

```yaml
behavior:
  scaleDown:
    selectPolicy: Disabled
```

:::

如果使用原生节点或普通节点，还需对节点池启动弹性伸缩，否则 GPU Pod 扩容后没相应的 GPU 节点会导致 Pod 一直处于 Pending 状态。

节点池启用弹性伸缩的方法是**编辑**节点池，然后勾选**弹性伸缩**，配置一下**节点数量范围**，最后点击**确认**：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F07%2F20250207192313.png)

### 步骤7: 部署 OpenWebUI

使用 Deployment 部署 OpenWebUI，并定义 Service 方便后续对外暴露访问。后端 API 可以由 vLLM 或 Ollama 提供，以下提供这两种情况的 OpenWebUI 部署示例：

<Tabs>
  <TabItem value="webui-vllm" label="vLLM 后端">
    <FileBlock file="ai/webui-vllm.yaml" showLineNumbers />
  </TabItem>
  <TabItem value="webui-ollama" label="Ollama 后端">
    <FileBlock file="ai/webui-ollama.yaml" showLineNumbers />
  </TabItem>
</Tabs>

> OpenWebUI 的数据存储在 `/app/backend/data` 目录（如账号密码、聊天历史等数据），我们挂载 PVC 到这个路径。

### 步骤8: 暴露 OpenWebUI 并与模型对话

如果只是本地测试，可以使用 `kubectl port-forward` 暴露服务：

```bash
kubectl port-forward service/webui 8080:8080
```
在浏览器中访问 `http://127.0.0.1:8080` 即可。

你还可以通过 Ingress 或 Gateway API 来暴露，示例：

<Tabs>
  <TabItem value="webui-httproute" label="Gateway API">
    :::info[注意]

    使用 Gateway API 需要集群中装有 Gateway API 的实现，如 TKE 应用市场中的 EnvoyGateway，具体 Gateway API 用法参考 [官方文档](https://gateway-api.sigs.k8s.io/guides/)

    :::
    <FileBlock file="ai/webui-httproute.yaml" showLineNumbers />
    :::tip[说明]

    1. `parentRefs` 引用定义好的 `Gateway`（通常一个 Gateway 对应一个 CLB）。
    2. `hostnames` 替换为你自己的域名，确保域名能正常解析到 Gateway 对应的 CLB 地址。
    3. `backendRefs` 指定 OpenWebUI 的 Service。

    :::
  </TabItem>
  <TabItem value="webui-ingress" label="Ingress">
    <FileBlock file="ai/webui-ingress.yaml" showLineNumbers />
    :::tip[说明]

    1. `host` 替换为你自己的域名，确保域名能正常解析到 Ingress 对应的 CLB 地址。
    2. `backend.service` 指定 OpenWebUI 的 Service。

    :::
  </TabItem>
</Tabs>


最后在浏览器访问相应的地址即可进入 OpenWebUI 页面。

首次进入 OpenWebUI 会提示创建管理员账号密码，创建完毕后即可登录，然后默认会使用前面下载好的大模型进行对话。

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F05%2F20250205191427.png)

## 常见问题

### CUDA、GPU 驱动、PyTorch、大模型兼容性问题

通常 `Ollama` 和 `vLLM` 官方的 `latest` 容器镜像中的 CUDA 版本能兼容很大部分 GPU 卡和驱动，但要将大模型顺利跑起来，跟 CUDA、GPU卡及其驱动、PyTorch（vLLM）以及大模型本身都可能有关系，很难枚举所有情况，特别是 vLLM，并不是所有大模型都支持，且依赖 PyTorch，而不同 PyTorch 版本能兼容的 CUDA 版本也不一样，不同 CUDA 版本能兼容的 GPU 驱动版本也不一样。

vLLM 启动或运行过程中可能报错，如：

<Tabs>
  <TabItem value="error-1" label="报错1">
    <FileBlock file="ai/vllm-unknown-error.txt" showLineNumbers />
  </TabItem>
  <TabItem value="error-2" label="报错2">
    <FileBlock file="ai/vllm-mqllmengine-dead.txt" showLineNumbers />
  </TabItem>
  <TabItem value="error-3" label="报错3">
    <FileBlock file="ai/vllm-driver-too-old-error.txt" showLineNumbers />
  </TabItem>
  <TabItem value="error-4" label="报错4">
    <FileBlock file="ai/vllm-cuda-no-kernel-image-error.txt" showLineNumbers />
  </TabItem>
</Tabs>

遇到这些情况建议是先调研和确认下各种版本信息，看能否兼容。不行则尝试换 GPU 卡或换 CUDA 版本(GPU 驱动是自动装的，一般无法改变)，下面有如何指定最佳 CUDA 版本的方法。

### 如何指定最佳的 CUDA 版本？

如果希望精确控制 CUDA 版本以达到最佳效果或规避一些兼容性问题，可按照下面的方法来指定最佳的 CUDA 版本。

#### 步骤1: 确认 GPU 驱动和所需 CUDA 版本

确认 GPU 驱动版本：
1. 如果是普通节点或原生节点，在创建节点池选机型，勾选 `后台自动安装GPU驱动` 的时候就会提示 GPU 驱动版本，如果没有也可以登录节点执行 `nvidia-smni` 查看。
2. 如果调度到超级节点，可进入 Pod 执行 `nvidia-smi` 命令查看 GPU 驱动版本。

确认 CUDA 版本：在 NVIDIA 官网的 [CUDA Toolkit and Corresponding Driver Versions](https://docs.nvidia.com/cuda/cuda-toolkit-release-notes/index.html#id6) 中，查找适合前面确认到的 GPU 驱动版本的 CUDA 版本，用于后面打包镜像时选择对应版本的基础镜像。

#### 步骤2: 编译 Ollama 或 vLLM 镜像

##### Ollama 镜像

如果使用 Ollama 运行大模型，按照下面的方法编译指定 CUDA 版本的 Ollama 镜像。

准备 `Dockerfile`:

```dockerfile
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04

RUN apt update -y && apt install -y curl

RUN curl -fsSL https://ollama.com/install.sh | sh
```

> 基础镜像使用 `nvidia/cuda`，具体使用哪个 tag 可根据前面确认的 cuda 版本来定。[这里](https://hub.docker.com/r/nvidia/cuda/tags) 是所有 tag 的列表。

编译并上传镜像：

```bash
docker build -t ccr.ccs.tencentyun.com/imroc/ollama:cuda11.8-ubuntu22.04 .
docker push ccr.ccs.tencentyun.com/imroc/ollama:cuda11.8-ubuntu22.04
```

> 注意修改成自己的镜像名称。


##### vLLM 镜像

如果使用 vLLM 运行大模型，按照下面的方法编译指定 CUDA 版本的 vLLM 镜像。

1. 克隆 vLLM 仓库：

```bash
git clone --depth=1 https://github.com/vllm-project/vllm.git
```

2. 指定 CUDA 版本并编译上传：

```bash
cd vllm
docker build --build-arg CUDA_VERSION=11.8.0 -t ccr.ccs.tencentyun.com/imroc/vllm-openai:cuda-11.8.0 .
docker push ccr.ccs.tencentyun.com/imroc/vllm-openai:cuda-11.8.0
```

> 通过 `CUDA_VERSION` 参数指定 CUDA 版本；注意替换成自己的镜像名称。

:::info[注意]

该方法只使用 CUDA 版本的微调，不要跨大版本，比如官方 Dockerfile 中使用的 `CUDA_VERSION` 是 12.x，那么指定的 `CUDA_VERSION` 就不要低于 12，因为 vLLM、PyTorch、CUDA 这几个的版本需要在兼容范围内，否则会有兼容性问题。如要编译更低版本的 CUDA，建议参考官方文档的方法（通过 pip 命令安装低版本编译好的 vLLM 二进制），然后编写相应的 Dockerfile 来编译镜像。

:::

#### 步骤3: 替换镜像

最后在部署 `Ollama` 或 `vLLM` 的 `Deplioyment` 中，将镜像替换成自己指定了 CUDA 版本编译上传的镜像名称，即可完成指定最佳的 CUDA 版本。

### 模型为何下载失败？

通常是没有开公网，下面是开通公网的方法。

如果使用普通节点或原生节点，可以在创建节点池的时候指定公网带宽：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F07%2F20250207105632.png)

如果使用超级节点，Pod 默认没有公网，可以使用 NAT 网关来访问外网，详情请参考 [通过 NAT 网关访问外网](https://cloud.tencent.com/document/product/457/48710)，当然这个也适用于普通节点和原生节点。

### 如何实现多卡并行？

Ollama 和 vLLM 默认将模型部署到单张 GPU 卡上，如果是多人使用，并发请求，或者模型太大，可以配置下 Ollama 和 vLLM，将模型部署到多张 GPU 卡上并行计算来提升推理速度和吞吐量。

首先在定义 Ollama 或 vLLM 的 Deployment 时，需声明 GPU 的数量大于 1，示例：

```yaml
resources:
  requests:
    nvidia.com/gpu: "2"
  limits:
    nvidia.com/gpu: "2"
```

对于 Ollama， 指定环境变量 `OLLAMA_SCHED_SPREAD` 为 `1` 表示将模型部署到所有 GPU 卡上，示例：

```yaml
env:
- name: OLLAMA_SCHED_SPREAD # 多卡部署
  value: "1"
```

对于 vLLM， 则需显示指定 `--tensor-parallel-size` 参数，表示将模型部署到多少张 GPU 卡上，示例：

```yaml showLineNumbers
command:
- bash
- -c
- |
  set -ex
  exec vllm serve /data/DeepSeek-R1-Distill-Qwen-7B \
    --served-model-name DeepSeek-R1-Distill-Qwen-7B \
    --host 0.0.0.0 --port 8000 \
    --trust-remote-code \
    --enable-chunked-prefill \
    --max_num_batched_tokens 1024 \
    --max_model_len 1024 \
    # highlight-add-line
    --tensor-parallel-size 2 # 指定 N 张卡并行，与 requests 中指定的 GPU 数量一致
```

### 如何实现多机分布式部署？

前面说的多卡部署仅限单台机器内的多卡，如果单个模型实在太大，而单台机器的 GPU 推理太慢，可以考虑用多机多卡分布式部署。

如何做到多机部署？如果只是简单增加副本数，各个节点的 GPU 并不能协同处理同一个任务，只能提升并发量，不能提升单个任务的推理速度。下面给出实现多机多卡分布式部署的思路，具体方案可参考相关链接，结合本文给出的示例 YAML 并进行相关修改。

- vLLM 官方支持通过 Ray 实现多机分布式部署，参考 [Running vLLM on multiple nodes](https://docs.vllm.ai/en/latest/serving/distributed_serving.html#running-vllm-on-multiple-nodes) 和 [Deploy Distributed Inference Service with vLLM and LWS on GPUs](https://github.com/kubernetes-sigs/lws/tree/main/docs/examples/vllm/GPU)。
- Ollama 官方不支持多机分布式部署，但 [llama.cpp](https://github.com/ggerganov/llama.cpp) 给出了一些支持，参考 issue [Llama.cpp now supports distributed inference across multiple machines. ](https://github.com/ollama/ollama/issues/4643)（门槛较高）。

对于 vLLM 来说，在 Kubernetes 环境中推荐使用 [lws](https://github.com/kubernetes-sigs/lws) 来实现多机分布式部署，下面给出部署实例。

首先，按照 [lws 官方文档](https://github.com/kubernetes-sigs/lws/blob/main/docs/setup/install.md) 安装 lws 到集群，需要注意的是，默认使用镜像是 `registry.k8s.io/lws/lws`，这个在国内环境下载不了，需修改 Deployment 的镜像地址为 `docker.io/k8smirror/lws`，该镜像为 lws 在 DockerHub 上的 mirror 镜像，长期自动同步，可放心使用（TKE 环境可直接拉取 DockerHub 的镜像）。

然后，下载 [ray_init.sh](https://raw.githubusercontent.com/kubernetes-sigs/lws/refs/heads/main/docs/examples/vllm/build/ray_init.sh) 脚本，制作 vLLM+Ray 的镜像：

```dockerfile
FROM docker.io/vllm/vllm-openai:latest
COPY ray_init.sh /vllm-workspace/ray_init.sh
RUN chmod +x /vllm-workspace/ray_init.sh
```

编译镜像并推送到镜像仓库：

```bash
docker build -t ccr.ccs.tencentyun.com/imroc/vllm-lws:latest .
docker push ccr.ccs.tencentyun.com/imroc/vllm-lws:latest
```

然后编写 `LeaderWorkerSet` 的 YAML 文件并将其部署到集群中：

:::info[说明]

这里假设每台 GPU 节点至少有 2 张 GPU 算卡，每个 Pod 使用 2 张卡，leader + worker 一共 2 个 Pod。

:::

```yaml
apiVersion: leaderworkerset.x-k8s.io/v1
kind: LeaderWorkerSet
metadata:
  name: vllm
spec:
  replicas: 1
  leaderWorkerTemplate:
    size: 2
    restartPolicy: RecreateGroupOnPodRestart
    leaderTemplate:
      metadata:
        labels:
          role: leader
      spec:
        containers:
        - name: vllm-leader
          image: ccr.ccs.tencentyun.com/imroc/vllm-lws:latest
          env:
          - name: RAY_CLUSTER_SIZE
            valueFrom:
              fieldRef:
                fieldPath: metadata.annotations['leaderworkerset.sigs.k8s.io/size']
          command:
          - sh
          - -c
          - |
            /vllm-workspace/ray_init.sh leader --ray_cluster_size=$RAY_CLUSTER_SIZE
            python3 -m vllm.entrypoints.openai.api_server \
              --port 8000 \
              --model /data/DeepSeek-R1-Distill-Qwen-32B \
              --served-model-name DeepSeek-R1-Distill-Qwen-32B \
              --tensor-parallel-size 2 \
              --pipeline-parallel-size 2 \
              --enforce-eager
          resources:
            limits:
              nvidia.com/gpu: "2"
          ports:
          - containerPort: 8000
          readinessProbe:
            tcpSocket:
              port: 8000
            initialDelaySeconds: 15
            periodSeconds: 10
          volumeMounts:
          - mountPath: /dev/shm
            name: dshm
          - mountPath: /data
            name: data
        volumes:
        - name: dshm
          emptyDir:
            medium: Memory
            sizeLimit: 15Gi
        - name: data
          persistentVolumeClaim:
            claimName: ai-model
    workerTemplate:
      spec:
        containers:
        - name: vllm-worker
          image: ccr.ccs.tencentyun.com/imroc/vllm-lws:latest
          command:
          - sh
          - -c
          - "/vllm-workspace/ray_init.sh worker --ray_address=$(LWS_LEADER_ADDRESS)"
          resources:
            limits:
              nvidia.com/gpu: "2"
          volumeMounts:
          - mountPath: /dev/shm
            name: dshm
          - mountPath: /data
            name: data
        volumes:
        - name: dshm
          emptyDir:
            medium: Memory
            sizeLimit: 15Gi
        - name: data
          persistentVolumeClaim:
            claimName: ai-model
---

apiVersion: v1
kind: Service
metadata:
  name: vllm-api
spec:
  ports:
  - name: http
    port: 8000
    protocol: TCP
    targetPort: 8000
  selector:
    leaderworkerset.sigs.k8s.io/name: vllm
    role: leader
  type: ClusterIP
```

:::info[注意]

- `nvidia.com/gpu` 和 `--tensor-parallel-size` 指定每台节点有多少张 GPU 卡。
- `--pipeline-parallel-size` 指定有多少台节点。
- `--model` 指定模型文件在容器内的路径。
- `--served-model-name` 指定模型名称。

:::

Pod 成功跑起来后进入 leader Pod：

```bash
kubectl exec -it vllm-0 -- bash
```

测试 API：

```bash
curl -v http://127.0.0.1:8000/v1/completions -H "Content-Type: application/json" -d '{
      "model": "DeepSeek-R1-Distill-Qwen-32B",
      "prompt": "你是谁?",
      "max_tokens": 100,
      "temperature": 0
    }'
```

如果部署了 OpenWebUI，确保 `OPENAI_API_BASE_URL` 指向上面示例 YAML 中 Service 的地址，如 `http://vllm-api:8000/v1`。

### 多 GPU 集群部署如何负载均衡？

vLLM 分布式多机部署要求每台节点 GPU 数量一致，且要事先规划好节点数量，如果要扩容，只有再建新 GPU 集群，如何让不同的 GPU 集群进行负载均衡呢？

可以用同一个 Service 选中多个不同 GPU 集群的所有 Pod 来实现。

比如用 lws 部署 vllm，让所有 `LeaderWorkerSet` 在同一命名空间，且所有 `LeaderWorkerSet` 的 `leaderTemplate` 下要声明一个相同的 label，比如用 `role: leader`：

```yaml showLineNumbers
apiVersion: leaderworkerset.x-k8s.io/v1
kind: LeaderWorkerSet
metadata:
  name: vllm
spec:
  replicas: 1
  leaderWorkerTemplate:
    size: 2
    leaderTemplate:
      # highlight-add-start
      metadata:
        labels:
          role: leader
      # highlight-add-end
      spec:
```

然后确保 vllm 的 Service 的 selector 选中该 label：

```yaml showLineNumbers
apiVersion: v1
kind: Service
metadata:
  name: vllm-api
spec:
  ports:
  - name: http
    port: 8080
    protocol: TCP
    targetPort: 8080
  # highlight-add-start
  selector:
    role: leader
  # highlight-add-end
  type: ClusterIP
```

配置好后，该 Service 就选中了所有 GPU 集群的 leader Pod，API 请求就可以在多个 GPU 集群之间负载均衡了。

### 如何使用超过 2T 的系统盘？

如果出于成本和性能的权衡考虑，或者测试阶段先不引入 CFS，降低复杂度，希望直接用本地系统盘存储大模型，而大模型占用又空间太大，希望能用超过 2T 的系统盘，则需要操作系统支持才可以，名称中带 `UEFI` 字样的系统镜像才支持超过 2T 的系统盘，默认不可用，如有需要可联系官方开通使用。

## 踩坑分享

### vLLM 报错 ValueError: invalid literal for int() with base 10: 'tcp://xxx.xx.xx.xx:8000'

vLLM 启动时报这个错：

```txt
ERROR 02-06 18:29:55 engine.py:389] ValueError: invalid literal for int() with base 10: 'tcp://172.16.168.90:8000'
Traceback (most recent call last):
  File "/usr/lib/python3.12/multiprocessing/process.py", line 314, in _bootstrap
    self.run()
  File "/usr/lib/python3.12/multiprocessing/process.py", line 108, in run
    self._target(*self._args, **self._kwargs)
  File "/usr/local/lib/python3.12/dist-packages/vllm/engine/multiprocessing/engine.py", line 391, in run_mp_engine
    raise e
  File "/usr/local/lib/python3.12/dist-packages/vllm/engine/multiprocessing/engine.py", line 380, in run_mp_engine
    engine = MQLLMEngine.from_engine_args(engine_args=engine_args,
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/dist-packages/vllm/engine/multiprocessing/engine.py", line 123, in from_engine_args
    return cls(ipc_path=ipc_path,
           ^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/dist-packages/vllm/engine/multiprocessing/engine.py", line 75, in __init__
    self.engine = LLMEngine(*args, **kwargs)
                  ^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/dist-packages/vllm/engine/llm_engine.py", line 273, in __init__
    self.model_executor = executor_class(vllm_config=vllm_config, )
                          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/dist-packages/vllm/executor/executor_base.py", line 51, in __init__
    self._init_executor()
  File "/usr/local/lib/python3.12/dist-packages/vllm/executor/uniproc_executor.py", line 29, in _init_executor
    get_ip(), get_open_port())
              ^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/dist-packages/vllm/utils.py", line 506, in get_open_port
    port = envs.VLLM_PORT
           ^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/dist-packages/vllm/envs.py", line 583, in __getattr__
    return environment_variables[name]()
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/dist-packages/vllm/envs.py", line 188, in <lambda>
    lambda: int(os.getenv('VLLM_PORT', '0'))
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
```

- **原因**：是用 DeepSeek 来帮忙分析得到灵感后发现的：关键点是 `VLLM_PORT` 这个环境变量，vLLM 会解析这个环境变量，它期望是个数字但实际得到的不是所以才报错，但我没定义这个环境变量，这个环境变量是 K8S 根据 Service 自动生成注入到 Pod 中的。
- **解决办法**：不要给 vLLM 的 Service 名称定义成 `vllm`，换成其它名字。

### vLLM 报错 ValueError: Bfloat16 is only supported on GPUs with compute capability of at least 8.0.

vLLM 启动时报这个错：

```txt
ValueError: Bfloat16 is only supported on GPUs with compute capability of at least 8.0. Your Tesla V100-SXM2-32GB GPU has compute capability 7.0. You can use float16 instead by explicitly setting the`dtype` flag in CLI, for example: --dtype=half.
Traceback (most recent call last):
  File "/usr/local/bin/vllm", line 8, in <module>
    sys.exit(main())
             ^^^^^^
  File "/usr/local/lib/python3.12/dist-packages/vllm/scripts.py", line 204, in main
    args.dispatch_function(args)
  File "/usr/local/lib/python3.12/dist-packages/vllm/scripts.py", line 44, in serve
    uvloop.run(run_server(args))
  File "/usr/local/lib/python3.12/dist-packages/uvloop/__init__.py", line 109, in run
    return __asyncio.run(
           ^^^^^^^^^^^^^^
  File "/usr/lib/python3.12/asyncio/runners.py", line 195, in run
    return runner.run(main)
           ^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.12/asyncio/runners.py", line 118, in run
    return self._loop.run_until_complete(task)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "uvloop/loop.pyx", line 1518, in uvloop.loop.Loop.run_until_complete
  File "/usr/local/lib/python3.12/dist-packages/uvloop/__init__.py", line 61, in wrapper
    return await main
           ^^^^^^^^^^
  File "/usr/local/lib/python3.12/dist-packages/vllm/entrypoints/openai/api_server.py", line 875, in run_server
    async with build_async_engine_client(args) as engine_client:
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.12/contextlib.py", line 210, in __aenter__
    return await anext(self.gen)
           ^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/dist-packages/vllm/entrypoints/openai/api_server.py", line 136, in build_async_engine_client
    async with build_async_engine_client_from_engine_args(
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.12/contextlib.py", line 210, in __aenter__
    return await anext(self.gen)
           ^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/dist-packages/vllm/entrypoints/openai/api_server.py", line 230, in build_async_engine_client_from_engine_args
    raise RuntimeError(
RuntimeError: Engine process failed to start. See stack trace for the root cause.
```

- **原因**：如报错所提示，GPU 卡不支持指定的 `--dtype` 类型（`bfloat16`)，并指定 `--dtype=half` 的建议。
- **解决办法**: 修改 vLLM 的 Deployment 中的启动参数，将 `--dtype` 的值指定为 `half`。

### vLLM 启动报 KeyboardInterrupt: terminated 然后退出

退出前日志：

```txt
Loading safetensors checkpoint shards:   0% Completed | 0/2 [00:00<?, ?it/s]
Traceback (most recent call last):
  File "/usr/local/bin/vllm", line 8, in <module>
    sys.exit(main())
             ^^^^^^
  File "/usr/local/lib/python3.12/dist-packages/vllm/scripts.py", line 204, in main
    args.dispatch_function(args)
  File "/usr/local/lib/python3.12/dist-packages/vllm/scripts.py", line 44, in serve
    uvloop.run(run_server(args))
  File "/usr/local/lib/python3.12/dist-packages/uvloop/__init__.py", line 109, in run
    return __asyncio.run(
           ^^^^^^^^^^^^^^
  File "/usr/lib/python3.12/asyncio/runners.py", line 195, in run
    return runner.run(main)
           ^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.12/asyncio/runners.py", line 118, in run
    return self._loop.run_until_complete(task)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "uvloop/loop.pyx", line 1512, in uvloop.loop.Loop.run_until_complete
  File "uvloop/loop.pyx", line 1505, in uvloop.loop.Loop.run_until_complete
  File "uvloop/loop.pyx", line 1379, in uvloop.loop.Loop.run_forever
  File "uvloop/loop.pyx", line 557, in uvloop.loop.Loop._run
  File "uvloop/handles/poll.pyx", line 216, in uvloop.loop.__on_uvpoll_event
  File "uvloop/cbhandles.pyx", line 83, in uvloop.loop.Handle._run
  File "uvloop/cbhandles.pyx", line 66, in uvloop.loop.Handle._run
  File "uvloop/loop.pyx", line 399, in uvloop.loop.Loop._read_from_self
  File "uvloop/loop.pyx", line 404, in uvloop.loop.Loop._invoke_signals
  File "uvloop/loop.pyx", line 379, in uvloop.loop.Loop._ceval_process_signals
  File "/usr/local/lib/python3.12/dist-packages/vllm/entrypoints/openai/api_server.py", line 871, in signal_handler
    raise KeyboardInterrupt("terminated")
KeyboardInterrupt: terminated
```

- **原因**: vLLM 启动慢，存活检查失败到阈值，主进程收到 SIGTERM 信号后退出。
- **解决办法**: 延长 `livenessProbe` 的 `initialDelaySeconds`，避免因 vLLM 启动慢被终止，或者去掉 `livenessProbe`。


### vLLM 报错: max seq len is larger than the maximum number of tokens

报错日志：

```txt
ValueError: The model's max seq len (131072) is larger than the maximum number of tokens that can be stored in KV cache (93760). Try increasing `gpu_memory_utilization` or decreasing `max_model_len` when initializing the engine.
[rank0]:[W207 01:57:35.912382100 ProcessGroupNCCL.cpp:1250] Warning: WARNING: process group has NOT been destroyed before we destruct ProcessGroupNCCL. On normal program exit, the application should call destroy_process_group to ensure that any pending NCCL operations have finished in this process. In rare cases this process can exit before this point and block the progress of another member of the process group. This constraint has always been present,  but this warning has only been added since PyTorch 2.4 (function operator())
Traceback (most recent call last):
  File "/usr/local/bin/vllm", line 8, in <module>
    sys.exit(main())
             ^^^^^^
  File "/usr/local/lib/python3.12/dist-packages/vllm/scripts.py", line 204, in main
    args.dispatch_function(args)
  File "/usr/local/lib/python3.12/dist-packages/vllm/scripts.py", line 44, in serve
    uvloop.run(run_server(args))
  File "/usr/local/lib/python3.12/dist-packages/uvloop/__init__.py", line 109, in run
    return __asyncio.run(
           ^^^^^^^^^^^^^^
  File "/usr/lib/python3.12/asyncio/runners.py", line 195, in run
    return runner.run(main)
           ^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.12/asyncio/runners.py", line 118, in run
    return self._loop.run_until_complete(task)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "uvloop/loop.pyx", line 1518, in uvloop.loop.Loop.run_until_complete
  File "/usr/local/lib/python3.12/dist-packages/uvloop/__init__.py", line 61, in wrapper
    return await main
           ^^^^^^^^^^
  File "/usr/local/lib/python3.12/dist-packages/vllm/entrypoints/openai/api_server.py", line 875, in run_server
    async with build_async_engine_client(args) as engine_client:
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.12/contextlib.py", line 210, in __aenter__
    return await anext(self.gen)
           ^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/dist-packages/vllm/entrypoints/openai/api_server.py", line 136, in build_async_engine_client
    async with build_async_engine_client_from_engine_args(
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.12/contextlib.py", line 210, in __aenter__
    return await anext(self.gen)
           ^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/dist-packages/vllm/entrypoints/openai/api_server.py", line 230, in build_async_engine_client_from_engine_args
    raise RuntimeError(
RuntimeError: Engine process failed to start. See stack trace for the root cause.
```

**解决办法**: vllm 启动参数指定下 `--max-model-len`，如 `--max-model-len 1024`。

### vLLM 或 SGLang 报错: CUDA out of memory

vLLM 报错日志：

```txt
ERROR 02-07 03:25:19 engine.py:389] CUDA out of memory. Tried to allocate 150.00 MiB. GPU 0 has a total capacity of 14.58 GiB of which 95.56 MiB is free. Process 81610 has 14.48 GiB memory in use. Of the allocated memory 14.30 GiB is allocated by PyTorch, and 34.90 MiB is reserved by PyTorch but unallocated. If reserved but unallocated memory is large try setting PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True to avoid fragmentation.  See documentation for Memory Management  (https://pytorch.org/docs/stable/notes/cuda.html#environment-variables)
ERROR 02-07 03:25:19 engine.py:389] Traceback (most recent call last):
Process SpawnProcess-1:
ERROR 02-07 03:25:19 engine.py:389]   File "/usr/local/lib/python3.12/dist-packages/vllm/engine/multiprocessing/engine.py", line 380, in run_mp_engine
ERROR 02-07 03:25:19 engine.py:389]     engine = MQLLMEngine.from_engine_args(engine_args=engine_args,
ERROR 02-07 03:25:19 engine.py:389]              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
ERROR 02-07 03:25:19 engine.py:389]   File "/usr/local/lib/python3.12/dist-packages/vllm/engine/multiprocessing/engine.py", line 123, in from_engine_args
ERROR 02-07 03:25:19 engine.py:389]     return cls(ipc_path=ipc_path,
ERROR 02-07 03:25:19 engine.py:389]            ^^^^^^^^^^^^^^^^^^^^^^
ERROR 02-07 03:25:19 engine.py:389]   File "/usr/local/lib/python3.12/dist-packages/vllm/engine/multiprocessing/engine.py", line 75, in __init__
ERROR 02-07 03:25:19 engine.py:389]     self.engine = LLMEngine(*args, **kwargs)
ERROR 02-07 03:25:19 engine.py:389]                   ^^^^^^^^^^^^^^^^^^^^^^^^^^
ERROR 02-07 03:25:19 engine.py:389]   File "/usr/local/lib/python3.12/dist-packages/vllm/engine/llm_engine.py", line 276, in __init__
ERROR 02-07 03:25:19 engine.py:389]     self._initialize_kv_caches()
ERROR 02-07 03:25:19 engine.py:389]   File "/usr/local/lib/python3.12/dist-packages/vllm/engine/llm_engine.py", line 416, in _initialize_kv_caches
ERROR 02-07 03:25:19 engine.py:389]     self.model_executor.determine_num_available_blocks())
ERROR 02-07 03:25:19 engine.py:389]     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
ERROR 02-07 03:25:19 engine.py:389]   File "/usr/local/lib/python3.12/dist-packages/vllm/executor/executor_base.py", line 101, in determine_num_available_blocks
ERROR 02-07 03:25:19 engine.py:389]     results = self.collective_rpc("determine_num_available_blocks")
ERROR 02-07 03:25:19 engine.py:389]               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
ERROR 02-07 03:25:19 engine.py:389]   File "/usr/local/lib/python3.12/dist-packages/vllm/executor/uniproc_executor.py", line 51, in collective_rpc
ERROR 02-07 03:25:19 engine.py:389]     answer = run_method(self.driver_worker, method, args, kwargs)
ERROR 02-07 03:25:19 engine.py:389]              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
ERROR 02-07 03:25:19 engine.py:389]   File "/usr/local/lib/python3.12/dist-packages/vllm/utils.py", line 2220, in run_method
ERROR 02-07 03:25:19 engine.py:389]     return func(*args, **kwargs)
ERROR 02-07 03:25:19 engine.py:389]            ^^^^^^^^^^^^^^^^^^^^^
ERROR 02-07 03:25:19 engine.py:389]   File "/usr/local/lib/python3.12/dist-packages/torch/utils/_contextlib.py", line 116, in decorate_context
ERROR 02-07 03:25:19 engine.py:389]     return func(*args, **kwargs)
ERROR 02-07 03:25:19 engine.py:389]            ^^^^^^^^^^^^^^^^^^^^^
ERROR 02-07 03:25:19 engine.py:389]   File "/usr/local/lib/python3.12/dist-packages/vllm/worker/worker.py", line 229, in determine_num_available_blocks
ERROR 02-07 03:25:19 engine.py:389]     self.model_runner.profile_run()
ERROR 02-07 03:25:19 engine.py:389]   File "/usr/local/lib/python3.12/dist-packages/torch/utils/_contextlib.py", line 116, in decorate_context
ERROR 02-07 03:25:19 engine.py:389]     return func(*args, **kwargs)
ERROR 02-07 03:25:19 engine.py:389]            ^^^^^^^^^^^^^^^^^^^^^
ERROR 02-07 03:25:19 engine.py:389]   File "/usr/local/lib/python3.12/dist-packages/vllm/worker/model_runner.py", line 1235, in profile_run
ERROR 02-07 03:25:19 engine.py:389]     self._dummy_run(max_num_batched_tokens, max_num_seqs)
ERROR 02-07 03:25:19 engine.py:389]   File "/usr/local/lib/python3.12/dist-packages/vllm/worker/model_runner.py", line 1346, in _dummy_run
ERROR 02-07 03:25:19 engine.py:389]     self.execute_model(model_input, kv_caches, intermediate_tensors)
ERROR 02-07 03:25:19 engine.py:389]   File "/usr/local/lib/python3.12/dist-packages/torch/utils/_contextlib.py", line 116, in decorate_context
ERROR 02-07 03:25:19 engine.py:389]     return func(*args, **kwargs)
ERROR 02-07 03:25:19 engine.py:389]            ^^^^^^^^^^^^^^^^^^^^^
ERROR 02-07 03:25:19 engine.py:389]   File "/usr/local/lib/python3.12/dist-packages/vllm/worker/model_runner.py", line 1775, in execute_model
ERROR 02-07 03:25:19 engine.py:389]     output: SamplerOutput = self.model.sample(
ERROR 02-07 03:25:19 engine.py:389]                             ^^^^^^^^^^^^^^^^^^
ERROR 02-07 03:25:19 engine.py:389]   File "/usr/local/lib/python3.12/dist-packages/vllm/model_executor/models/qwen2.py", line 505, in sample
ERROR 02-07 03:25:19 engine.py:389]     next_tokens = self.sampler(logits, sampling_metadata)
ERROR 02-07 03:25:19 engine.py:389]                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
ERROR 02-07 03:25:19 engine.py:389]   File "/usr/local/lib/python3.12/dist-packages/torch/nn/modules/module.py", line 1736, in _wrapped_call_impl
ERROR 02-07 03:25:19 engine.py:389]     return self._call_impl(*args, **kwargs)
ERROR 02-07 03:25:19 engine.py:389]            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
ERROR 02-07 03:25:19 engine.py:389]   File "/usr/local/lib/python3.12/dist-packages/torch/nn/modules/module.py", line 1747, in _call_impl
ERROR 02-07 03:25:19 engine.py:389]     return forward_call(*args, **kwargs)
ERROR 02-07 03:25:19 engine.py:389]            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
ERROR 02-07 03:25:19 engine.py:389]   File "/usr/local/lib/python3.12/dist-packages/vllm/model_executor/layers/sampler.py", line 271, in forward
```

SGLang 报错日志：

```txt
torch.OutOfMemoryError: CUDA out of memory. Tried to allocate 540.00 MiB. GPU 0 has a total capacity of 14.76 GiB of which 298.75 MiB is free. Process 63729 has 14.46 GiB memory in use. Of the allocated memory 14.35 GiB is allocated by PyTorch, and 1.52 MiB is reserved by PyTorch but unallocated. If reserved but unallocated memory is large try setting PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True to avoid fragmentation.  See documentation for Memory Management  (https://pytorch.org/docs/stable/notes/cuda.html#environment-variables)
```

- **原因**: GPU 卡显存不够。
- **解决方案**: 换显存更大的 GPU 卡，或使用多机部署组成 GPU 集群。

### SGLang 报错：SGLang only supports sm75 and above.

报错日志：

```txt
[2025-02-12 02:56:48 TP0] Compute capability below sm80. Use float16 due to lack of bfloat16 support.
[2025-02-12 02:56:48 TP0] Scheduler hit an exception: Traceback (most recent call last):
  File "/sgl-workspace/sglang/python/sglang/srt/managers/scheduler.py", line 1787, in run_scheduler_process
    scheduler = Scheduler(server_args, port_args, gpu_id, tp_rank, dp_rank)
  File "/sgl-workspace/sglang/python/sglang/srt/managers/scheduler.py", line 240, in __init__
    self.tp_worker = TpWorkerClass(
  File "/sgl-workspace/sglang/python/sglang/srt/managers/tp_worker_overlap_thread.py", line 63, in __init__
    self.worker = TpModelWorker(server_args, gpu_id, tp_rank, dp_rank, nccl_port)
  File "/sgl-workspace/sglang/python/sglang/srt/managers/tp_worker.py", line 68, in __init__
    self.model_runner = ModelRunner(
  File "/sgl-workspace/sglang/python/sglang/srt/model_executor/model_runner.py", line 186, in __init__
    self.load_model()
  File "/sgl-workspace/sglang/python/sglang/srt/model_executor/model_runner.py", line 293, in load_model
    raise RuntimeError("SGLang only supports sm75 and above.")
RuntimeError: SGLang only supports sm75 and above.
```

- 原因：GPU 显卡计算能力不够，提示至少计算能力要 SM7.5
- 解决方案：换成计算能力大于等于 SM7.5 的 GPU，如 T4、A100

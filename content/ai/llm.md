# 在 TKE 上部署 AI 大模型

## 概述

本文介绍如何在 TKE 上部署 AI 大模型，以 `DeepSeek-R1` 为例，使用 `Ollama`、`vLLM` 或 `SGLang` 运行大模型并暴露 API，然后使用 `OpenWebUI` 提供交互界面。

`Ollama` 提供是 Ollama API，部署架构：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F06%2F20250206171758.png)

`vLLM` 和 `SGLang` 都提供了兼容 OpenAI 的 API，部署架构：


![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F13%2F20250213145518.png)

## Ollama、vLLM、SGLang 与 OpenWebUI 介绍

* [Ollama](https://ollama.com/) 是一个运行大模型的工具，可以看成是大模型领域的 Docker，可以下载所需的大模型并暴露 Ollama API，极大的简化了大模型的部署。
* [vLLM](https://docs.vllm.ai) 与 Ollama 类似，也是一个运行大模型的工具，但它针对推理做了很多优化，提高了模型的运行效率和性能，使得在资源有限的情况下也能高效运行大语言模型，另外，它提供兼容 OpenAI 的 API。
* [SGLang](https://docs.sglang.ai/) 与 vLLM 类似，性能更强，且针对 DeepSeek 做了深度优化，也是 DeepSeek 官方推荐的工具。
* [OpenWebUI](https://openwebui.com/) 是一个大模型的 Web UI 交互工具，支持通过 Ollama 与 OpenAI 两种 API 与大模型交互。

## 技术选型

### Ollama、vLLM 还是 SGLang？

- Ollama 的特点：个人用户或本地开发环境使用 Ollama 很方便，对各种 GPU 硬件和大模型的兼容性很好，不需要复杂的配置就能跑起来，但性能上不如 vLLM。
- vLLM 的特点：推理性能更好，也更节约资源，适合部署到服务器供多人使用，还支持多机多卡分布式部署，上限更高，但能适配的 GPU 硬件比 Ollama 少，且需要根据不同 GPU 和大模型来调整 vllm 的启动参数才能跑起来或者获得更好的性能表现。
- SGLang 的特点：是性能卓越的新兴之秀，针对特定模型优化（如 DeepSeek），吞吐量更高。

- **选型建议**：如果有一定的技术能力且愿意折腾，能用 vLLM 或 SGLang 成功跑起来更推荐用 vLLM 和 SGLang 将大模型部署到 Kubernetes 中，否则就用 Ollama ，两种方式在本文中都有相应的部署示例。

### AI 大模型数据如何存储？

AI 大模型通常占用体积较大，直接打包到容器镜像不太现实，如果启动时通过 `initContainers` 自动下载又会导致启动时间过长，因此建议使用共享存储来挂载 AI 大模型（先下发一个 Job 将模型下载到共享存储，然后再将共享存储挂载到运行大模型的 Pod 中），这样后面 Pod 启动时就无需下载模型了（虽然最终加载模型时同样也会经过CFS的网络下载，但只要 CFS 使用规格比较高，如 Turbo 类型，速度就会很快）。

在腾讯云上可使用 CFS 来作为共享存储，CFS 的性能和可用性都非常不错，适合 AI 大模型的存储。本文将使用 CFS 来存储 AI 大模型。

### GPU 机型如何选？

不同的机型使用的 GPU 型号不一样，机型与 GPU 型号的对照表参考 [GPU 计算型实例](https://cloud.tencent.com/document/product/560/19700) ，Ollama 相比 vLLM，支持的 GPU 型号更广泛，兼容性更好，建议根据事先调研自己所使用的工具和大模型，选择合适的 GPU 型号，再根据前面的对照表确定要使用的 GPU 机型，另外也注意下选择的机型在哪些地域在售，以及是否售罄，可通过 [购买云服务器](https://buy.cloud.tencent.com/cvm) 页面进行查询（**实例族**选择**GPU机型**）。

## 镜像说明

本文中的示例使用的镜像都是官方提供的镜像 tag 为 latest，建议根据自身情况改成指定版本的 tag，可点击下面的连接查看镜像的 tag 列表：

- sglang: [lmsysorg/sglang](https://hub.docker.com/r/lmsysorg/sglang/tags)
- ollama: [ollama/ollama](https://hub.docker.com/r/ollama/ollama/tags)
- vllm: [vllm/vllm-openai](https://hub.docker.com/r/vllm/vllm-openai/tags)

官方镜像均在 DockerHub，且体积较大，在 TKE 环境 默认有免费的 DockerHub 镜像加速，国内地域也可以拉取 DockerHub 的镜像，但速度一般，镜像较大时等待的时间较长，建议将镜像同步至 [容器镜像服务 TCR](https://cloud.tencent.com/product/tcr)，再替换 YAML 中镜像地址，这样可极大加快镜像拉取速度。

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
  <TabItem value="SGLang" label="SGLang Job">
    <FileBlock file="ai/sglang-download-model-job.yaml" showLineNumbers title="sglang-download-model-job.yaml" />
  </TabItem>
  <TabItem value="Ollama" label="Ollama Job">
    <FileBlock file="ai/ollama-download-model-job.yaml" showLineNumbers title="ollama-download-model-job.yaml" />
  </TabItem>
</Tabs>

### 步骤5: 部署 Ollama、vLLM 或 SGLang

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
  <TabItem value="deploy-sglang" label="部署 SGLang">
    通过 Deployment 部署 SGLang:
    <FileBlock file="ai/sglang.yaml" showLineNumbers />
    1. `LLM_MODEL` 环境变量指定大模型名称，与前面下载 Job 中指定的名称要一致，注意替换。
    2. 模型数据引用前面下载 Job 使用的 PVC，挂载到 `/data` 目录下。
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

:::info[注意]

- 运行大模型需要使用 GPU，因此在 requests/limits 中指定了 `nvidia.com/gpu` 资源，以便让 Pod 调度到 GPU 机型并分配 GPU 卡使用。
- 如果希望大模型跑在超级节点，需通过 Pod 注解 `eks.tke.cloud.tencent.com/gpu-type` 指定 GPU 类型，可选 `V100`、`T4`、`A10*PNV4`、`A10*GNV4`，具体可参考 [这里](https://cloud.tencent.com/document/product/457/39808#gpu-.E8.A7.84.E6.A0.BC)。
:::

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

使用 Deployment 部署 OpenWebUI，并定义 Service 方便后续对外暴露访问。后端 API 可以由 vLLM、SGLang 或 Ollama 提供，以下提供这三种情况的 OpenWebUI 部署示例：

<Tabs>
  <TabItem value="webui-vllm" label="vLLM 后端">
    <FileBlock file="ai/webui-vllm.yaml" showLineNumbers />
  </TabItem>
  <TabItem value="webui-sglang" label="SGLang 后端">
    <FileBlock file="ai/webui-sglang.yaml" showLineNumbers />
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

参考 [部署大模型常见问题](faq.md)

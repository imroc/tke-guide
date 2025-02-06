# 在 TKE 上部署 AI 大模型

## 概述

本文介绍如何在 TKE 上部署 AI 大模型，以 `DeepSeek-R1` 为例，使用 `Ollama` 或 `vLLM` 运行大模型并暴露 API，然后使用 `OpenWebUI` 提供交互界面。

## Ollama、vLLM 与 OpenWebUI 介绍

* [Ollama](https://ollama.com/) 是一个运行大模型的工具，可以看成是大模型领域的 Docker，可以下载所需的大模型并暴露 Ollama API，极大的简化了大模型的部署。
* [vLLM](https://docs.vllm.ai) 与 Ollama 类似，也是一个运行大模型的工具，但它针对推理做了很多优化，提高了模型的运行效率和性能，使得在资源有限的情况下也能高效运行大语言模型，另外，它提供兼容 OpenAI 的 API。
* [OpenWebUI](https://openwebui.com/) 是一个大模型的 Web UI 交互工具，支持通过 Ollama 与 OpenAI 两种 API 与大模型交互。

## 部署思路

使用 `Ollama` 或 `vLLM` 运行 AI 大模型，再通过 `OpenWebUI` 暴露一个聊天交互的界面，`OpenWebUI` 会调用 `Ollama` 或 `vLLM` 提供的 API 来与大模型交互。

`Ollama` 提供是 Ollama API，部署架构：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F06%2F20250206144144.png)

`vLLM` 提供的是兼容 OpenAI 的 API，部署架构：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F06%2F20250206144336.png)

## 选择 Ollama 还是 vLLM？

个人用户或本地开发环境使用 Ollama 很方便，而 vLLM 的性能更好，也更节约资源，适合部署到服务器供多人使用，将大模型部署到 Kubernetes 中也更推荐用 vLLM，不过 Ollama 很流行，所以本文两种方式的部署都会有示例。

## AI 大模型数据如何存储？

AI 大模型通常占用体积较大，直接打包到容器镜像不太现实，如果启动时通过 `initContainers` 自动下载又会导致启动时间过长，因此建议使用共享存储来挂载 AI 大模型（先下发一个 Job 将模型下载到共享存储，然后再将共享存储挂载到运行大模型的 Pod 中）。

在腾讯云上可使用 CFS 来作为共享存储，CFS 的性能和可用性都非常不错，适合 AI 大模型的存储。本文将使用 CFS 来存储 AI 大模型。

## 新建 GPU 节点池并安装 GPU 插件

在 TKE 控制台的【节点管理】-【节点池】中点击【新建】：
1. 如果使用【原生节点】或【普通节点】，机型在【GPU 机型】中选择一个没售罄的机型，此时也记一下选中机型下方提示的 GPU 驱动版本。
2. 如果使用【超级节点】，无需选择机型（在部署的时候通过 Pod 注解指定 GPU 类型）。

## 安装 GPU 插件

如果使用普通节点或原生节点，需安装 GPU 插件，在【组件管理】中的【GPU】找到 `nvidia-gpu` 并安装：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F06%2F20250206152134.png)

如果使用超级节点则无需安装。

## 准备 CFS 存储

在【组件管理】中的【存储】找到 `CFS-Turbo` 或 `CFS` 插件并安装：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F05%2F20250205104156.png)

> `CFS-Turbo` 的性能更强，读写速度更快，也更贵，如果希望大模型运行速度更快，可以考虑使用 `CFS-Turbo`。

下面是新建 CFS `StorageClass` 的示例：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F06%2F20250206160151.png)

1. 选项较多，所以该示例通过 TKE 控制台来创建 PVC。如希望通过 YAML 来创建，可先用控制台创建一个测试 PVC，再复制出生成的 YAML。
2. `Provisioner` 选 `文件存储CFS`。
3. `存储类型` 建议选 `性能存储`，读写速度比 `标准存储` 更快。

如果是新建 CFS-Turbo `StorageClass`，则需要在文件存储控制台先新建好 CFS-Turbo 文件系统，然后创建 `StorageClass` 时引用对应的 CFS-Turbo 实例。

## 创建 PVC

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

1. 注意替换 `storageClassName`。
2. 对于 CFS 来说，`storage` 大小无所谓，可随意指定，按实际占用空间付费的。

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

## 使用 Job 下载 AI 大模型

下发一个 Job，将需要用的 AI 大模型下载到 CFS 共享存储中，以下分别是 vLLM 和 Ollama 的 Job 示例：

<Tabs>
  <TabItem value="vLLM" label="vLLM Job">
    <FileBlock file="ai/vllm-download-model-job.yaml" showLineNumbers title="vllm-download-model-job.yaml" />
  </TabItem>
  <TabItem value="Ollama" label="Ollama Job">
    <FileBlock file="ai/ollama-download-model-job.yaml" showLineNumbers title="ollama-download-model-job.yaml" />
  </TabItem>
</Tabs>


1. 使用之前 Ollama 或 vLLM 的镜像执行一个脚本去下载我们需要的 AI 大模型，本例中下载的是 DeepSeek-R1 的模型，修改 `LLM_MODEL` 以替换大语言模型。
2. 如果使用 Ollama，可以在 [Ollama 模型库](https://ollama.com/search) 查询和搜索需要的模型；如果使用 vLLM，可以在 [Hugging Face 模型库](https://huggingface.co/models) 和 [ModelScope 模型库](https://www.modelscope.cn/models) 查询和搜索需要的模型（国内环境可以用 ModelScope 的模型库，避免因网络问题下载失败，通过 `USE_MODELSCOPE` 环境环境变量控制是否从 ModelScope 下载）。

## 部署 Ollama 或 vLLM

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
5. 如果希望大模型跑在超级节点，需通过 Pod 注解 `eks.tke.cloud.tencent.com/gpu-type` 指定 GPU 类型，可选 `V100`、`T4`、`A10*PNV4`、`A10*GNV4`，参考 [这里](https://cloud.tencent.com/document/product/457/39808#gpu-.E8.A7.84.E6.A0.BC)。

## 部署 OpenWebUI

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

## 暴露 OpenWebUI 并与模型对话

如果只是本地测试，可以使用 `kubectl port-forward` 暴露服务：

```bash
kubectl port-forward service/webui 8080:8080
```
在浏览器中访问 `http://127.0.0.1:8080` 即可。

你还可以通过 Ingress 或 Gateway API 来暴露，我这里通过 Gateway API 来暴露（需安装 Gateway API 的实现，如 TKE 应用市场中的 EnvoyGateway，具体 Gateway API 用法参考 [官方文档](https://gateway-api.sigs.k8s.io/guides/)）：

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ai
spec:
  parentRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    namespace: envoy-gateway-system
    name: imroc
    sectionName: https
  hostnames:
  - "ai.imroc.cc"
  rules:
  - backendRefs:
    - group: ""
      kind: Service
      name: webui
      port: 8080
```

1. `parentRefs` 引用定义好的 `Gateway`（通常一个 Gateway 对应一个 CLB）。
2. `hostnames` 替换为你自己的域名，确保域名能正常解析到 Gateway 对应的 CLB 地址。
3. `backendRefs` 指定 OpenWebUI 的 Service。

最后在浏览器访问 `hostnames` 中的地址即可。

首次进入 OpenWebUI 会提示创建管理员账号密码，创建完毕后即可登录，然后默认会使用前面下载好的大模型进行对话。

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F05%2F20250205191427.png)

## 常见问题：如何指定最佳的 CUDA 版本？

通常 `Ollama` 和 `vLLM` 官方的 `latest` 容器镜像中的 CUDA 版本能兼容大部分 GPU 驱动，如果希望精确控制 CUDA 版本以达到最佳效果或规避一些兼容性问题，可按照下面的方法来指定最佳的 CUDA 版本。

### 确认 GPU 驱动和所需 CUDA 版本

确认 GPU 驱动版本：
1. 如果是普通节点或原生节点，在创建节点池选机型的时候就会提示 GPU 驱动版本。
2. 如果调度到超级节点，可进入 Pod 执行 `nvidia-smi` 命令查看 GPU 驱动版本。

确认 CUDA 版本：在 NVIDIA 官网的 [CUDA Toolkit Release Notes](https://docs.nvidia.com/cuda/cuda-toolkit-release-notes/index.html) 中，查找适合前面确认到的 GPU 驱动版本的 CUDA 版本，用于后面打包镜像时选择对应版本的基础镜像。

### 编译 Ollama 镜像

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
docker build -t imroc/ollama:cuda11.8-ubuntu22.04 .
docker push imroc/ollama:cuda11.8-ubuntu22.04
```

> 注意修改成自己的镜像名称。

### 编译 vLLM 镜像

如果使用 Ollama 运行大模型，按照下面的方法编译指定 CUDA 版本的 Ollama 镜像。

1. 克隆 vLLM 仓库：

```bash
git clone --depth=1 https://github.com/vllm-project/vllm.git
```

2. 指定 CUDA 版本并编译上传：

```bash
cd vllm
docker build --build-arg CUDA_VERSION=11.8.0 -t imroc/vllm-openai:cuda-11.8.0 .
docker push imroc/vllm-openai:cuda-11.8.0
```

> 通过 `CUDA_VERSION` 参数指定 CUDA 版本；注意替换成自己的镜像名称。

### 替换镜像

最后在部署 `Ollama` 或 `vLLM` 的 `Deplioyment` 中，将镜像替换成自己指定了 CUDA 版本编译上传的镜像名称，即可完成指定最佳的 CUDA 版本。

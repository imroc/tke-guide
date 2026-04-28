# 在 TKE 上部署 DeepSeek-V4 (SGLang)

## 概述

DeepSeek-V4 是 DeepSeek 于 2026 年 4 月 24 日发布的新一代开源大语言模型，采用 MoE（混合专家）架构，MIT 协议开源，支持 **100 万 token** 超长上下文。V4 分为两个版本：

| 版本                  | 总参数 | 激活参数 | 模型文件大小 (FP8) | 定位                   |
| --------------------- | ------ | -------- | ------------------ | ---------------------- |
| **DeepSeek-V4-Flash** | 284B   | 13B      | ~158GB             | 轻量高效，适合单机部署 |
| **DeepSeek-V4-Pro**   | 1.6T   | 49B      | ~862GB             | 旗舰性能，需多机部署   |

V4 采用了多项架构创新：混合注意力机制（CSA + HCA）使得在 1M token 上下文中推理 FLOPs 仅需 V3 的 27%，KV 缓存仅需 10%；流形约束超连接（mHC）增强信号传播稳定性。

本文将基于 [SGLang](https://docs.sglang.ai/) 在 TKE 集群上部署 DeepSeek-V4，SGLang 是 DeepSeek 官方推荐的部署工具，针对 DeepSeek 进行了深度优化。

:::info[镜像说明]

SGLang 为 DeepSeek-V4 提供了按 GPU 架构区分的专用镜像：

| 硬件平台                       | Docker 镜像                                   |
| ------------------------------ | --------------------------------------------- |
| NVIDIA H20/H200 (Hopper)       | `lmsysorg/sglang:deepseek-v4-hopper`          |
| NVIDIA B200 (Blackwell)        | `lmsysorg/sglang:deepseek-v4-blackwell`       |
| NVIDIA GB300 (Grace Blackwell) | `lmsysorg/sglang:deepseek-v4-grace-blackwell` |

官方镜像托管在 DockerHub，且体积较大，在 TKE 环境中，默认提供免费的 DockerHub 镜像加速服务。为提高镜像拉取速度，建议将镜像同步至 [容器镜像服务 TCR](https://cloud.tencent.com/product/tcr)，并在 YAML 文件中替换相应的镜像地址。

:::

## 机型与部署方案

### 腾讯云 GPU 机型选择

DeepSeek-V4 需要支持 FP8 的大显存 GPU，腾讯云上合适的机型有：

| 规格                 | GPU 型号 | GPU 卡数 | 单卡显存 | 总显存 | RDMA          | CPU 核心数 | 内存(GB) |
| -------------------- | -------- | -------- | -------- | ------ | ------------- | ---------- | -------- |
| PNV6.16XLARGE640     | H20      | 4        | 96GB     | 384GB  | 不支持        | 64         | 640      |
| PNV6.32XLARGE1280    | H20      | 8        | 96GB     | 768GB  | 不支持        | 128        | 1280     |
| PNV6.96XLARGE2304    | H20      | 8        | 96GB     | 768GB  | 不支持        | 384        | 2304     |
| HCCPNV6.96XLARGE2304 | H20      | 8        | 96GB     | 768GB  | 支持(3.2Tbps) | 384        | 2304     |

:::info[注意]

这些规格的实例都正在邀测中，且资源紧张，需联系您的销售经理开通使用并协调好资源。

:::

### 部署方案选择

| 部署方案          | 模型版本         | 所需机型             | 节点数 | 总显存 | 说明                   |
| ----------------- | ---------------- | -------------------- | ------ | ------ | ---------------------- |
| **V4-Flash 单机** | V4-Flash (158GB) | PNV6.32XLARGE1280    | 1 台   | 768GB  | 推荐，成本最低，效果好 |
| **V4-Flash 4卡**  | V4-Flash (158GB) | PNV6.16XLARGE640     | 1 台   | 384GB  | 最低配置，4卡可运行    |
| **V4-Pro 双机**   | V4-Pro (862GB)   | HCCPNV6.96XLARGE2304 | 2 台   | 1536GB | 旗舰性能，需 RDMA      |

**选型建议**：

- **V4-Flash 单机部署**：推荐选 `PNV6.32XLARGE1280`（8 卡 H20，总显存 768GB），模型文件 158GB 仅占 1/5 显存，剩余大量显存可用于 KV 缓存，支持较高并发。如果资源紧张或想节省成本，也可用 `PNV6.16XLARGE640`（4 卡 H20，总显存 384GB）运行。
- **V4-Pro 双机部署**：建议选 `HCCPNV6.96XLARGE2304`，因为支持 RDMA（3.2Tbps），可显著提升多机通信效率。

## 操作步骤

### 购买 GPU 服务器

测试 POC 阶段，可先在 [云服务器购买页面](https://buy.cloud.tencent.com/cvm) 进行购买，按量计费。

:::note[备注]

对于 **PNV6** 系列规格，**架构**选择**异构计算**才能看到；对于 **HCCPNV6** 规格，**架构**选择**高性能计算集群**才能看到，且要先提前创建高性能计算集群，详情请参见 [创建高性能计算集群](https://cloud.tencent.com/document/product/1646/93026#3680502d-53cb-440e-8cf1-3eebbb7db3c5)。

:::

正式购买阶段，需通过 [高性能计算平台-工作空间](https://console.cloud.tencent.com/thpc/workspace/index) 购买，包年包月计费，请联系腾讯云架构师进行开通使用。

### 创建 TKE 集群

登录 [容器服务控制台](https://console.cloud.tencent.com/tke2)，创建一个集群：

:::tip[说明]

更多详情请参见 [创建集群](https://cloud.tencent.com/document/product/457/103981)。

:::

- **地域**：选择购买的 GPU 服务器所在地域
- **集群类型**：选择**TKE 标准集群**。
- **Kubernetes版本**：要大于等于1.28（多机部署依赖的 LWS 组件的要求），建议选最新版。
- **VPC**：选择购买的 GPU 资源所在的 VPC。

### 添加 GPU 节点

通过添加已有节点的方式将购买到的 GPU 服务器加入 TKE 集群。

系统镜像选 `TencentOS Server 3.1 (TK4) UEFI | img-39ywauzd`，驱动和 CUDA 选最新版本。

### 准备存储与模型文件

V4-Flash 模型文件约 158GB，V4-Pro 约 862GB，建议使用性能最强的存储。本文提供本地存储和 CFS-Turbo 共享存储两种方案。

:::tip[说明]

CFS-Turbo 的创建和配置方法参见 [在 TKE 上部署满血版 DeepSeek-R1 (SGLang)](./sglang-deepseek-r1) 中的相关步骤。

:::

#### 使用 Job 下载模型文件

DeepSeek-V4 针对不同 GPU 提供了不同精度的模型权重：

- **H20/H200**：使用 FP8 版本的模型（`sgl-project/DeepSeek-V4-Flash-FP8`）
- **B200/GB300**：使用 FP4+FP8 混合精度版本（`deepseek-ai/DeepSeek-V4-Flash`）

**下载 V4-Flash FP8 模型（H20 适用）**：

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: download-deepseek-v4-flash
  labels:
    app: download-model
spec:
  template:
    metadata:
      name: download-model
      labels:
        app: download-model
    spec:
      containers:
      - name: download
        image: lmsysorg/sglang:deepseek-v4-hopper
        command:
        - huggingface-cli
        - download
        - --local-dir=/data/model/DeepSeek-V4-Flash-FP8
        - sgl-project/DeepSeek-V4-Flash-FP8
        volumeMounts:
        - name: data
          mountPath: /data/model
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: ai-model
      restartPolicy: OnFailure
```

**下载 V4-Pro FP8 模型（双机部署用）**：

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: download-deepseek-v4-pro
  labels:
    app: download-model
spec:
  template:
    metadata:
      name: download-model
      labels:
        app: download-model
    spec:
      containers:
      - name: download
        image: lmsysorg/sglang:deepseek-v4-hopper
        command:
        - huggingface-cli
        - download
        - --local-dir=/data/model/DeepSeek-V4-Pro-FP8
        - deepseek-ai/DeepSeek-V4-Pro
        volumeMounts:
        - name: data
          mountPath: /data/model
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: ai-model
      restartPolicy: OnFailure
```

:::info[说明]

- 国内环境下载 HuggingFace 模型可能较慢，可使用 ModelScope 镜像或配置 HuggingFace 镜像站。
- V4-Flash FP8 模型约 158GB，V4-Pro 模型约 862GB，确保存储空间充足。
- 如果使用本地存储，可将 PVC 替换为 hostPath 挂载。

:::

### 安装 LWS 组件

:::info[注意]

如果只使用单机部署的方案（V4-Flash），无需安装 LWS 组件，可跳过此步骤。

:::

SGLang 多机部署（V4-Pro 双机集群）需借助 [LWS](https://github.com/kubernetes-sigs/lws) 组件，安装方法参见 [在 TKE 上部署满血版 DeepSeek-R1 (SGLang)](./sglang-deepseek-r1) 中的 LWS 安装步骤。

### 部署 DeepSeek-V4

#### V4-Flash 单机部署

使用 `Deployment` 部署单机 DeepSeek-V4-Flash：

<Tabs>
  <TabItem value="share" label="挂载 CFS 共享存储">
    <FileBlock file="ai/sglang-deployment-deepseek-v4-flash.yaml" showLineNumbers />
  </TabItem>
  <TabItem value="local" label="挂载本地存储">
    <FileBlock file="ai/sglang-deployment-deepseek-v4-flash-hostpath.yaml" showLineNumbers />
  </TabItem>
</Tabs>

:::info[说明]

- `nvidia.com/gpu` 和 `TOTAL_GPU` 为单机 GPU 卡数，8 卡 H20 填 8，4 卡 H20 填 4。
- `MODEL_DIRECTORY` 为模型文件的子目录路径，H20 使用 FP8 版本 `DeepSeek-V4-Flash-FP8`。
- `MODEL_NAME` 为模型名称，API 调用将使用此名称。
- `--mem-fraction-static 0.85` 控制静态显存分配比例，可根据实际显存占用调整。
- `--max-running-requests 64` 控制最大并发请求数，可根据负载调整。
- `--chunked-prefill-size 4096` 分块预填充大小，有助于降低首 token 延迟。
- 涉及 OpenAI API 地址配置的地方（如 OpenWebUI），指向 Service 地址（如 `http://deepseek-v4-flash-api:30000/v1`）。

:::

#### V4-Pro 双机集群部署

使用 `LeaderWorkerSet` 部署 DeepSeek-V4-Pro 双机集群（2 台 8 卡 H20 节点，1 个 leader 和 1 个 worker）：

<Tabs>
  <TabItem value="share" label="挂载 CFS 共享存储">
    <FileBlock file="ai/sglang-lws-deepseek-v4-pro.yaml" showLineNumbers />
  </TabItem>
  <TabItem value="local" label="挂载本地存储">
    <FileBlock file="ai/sglang-lws-deepseek-v4-pro-hostpath.yaml" showLineNumbers />
  </TabItem>
</Tabs>

:::info[说明]

- `nvidia.com/gpu` 为单机 GPU 卡数（8 卡），leader 和 worker 保持一致。
- `leaderWorkerTemplate.size` 为 GPU 集群的节点数，2 表示两个节点（1 个 leader + 1 个 worker）。
- `replicas` 为 GPU 集群数量，如需扩容准备好节点资源后调整此值。
- `TOTAL_GPU` 为 GPU 集群总卡数（节点数 \* 单机卡数），这里是 16 卡。
- 使用 HCCPNV6 支持 RDMA 的机型时，需使用 HostNetwork 才能让 RDMA 生效。
- leader 和 worker 的环境变量需一致。
- 涉及 OpenAI API 地址配置的地方（如 OpenWebUI），指向 Service 地址（如 `http://deepseek-v4-pro-api:30000/v1`）。

:::

### 验证 API

Pod 成功跑起来后用 kubectl exec 进入 Pod（双机部署进入 leader Pod），使用 curl 测试 API：

```bash
curl http://127.0.0.1:30000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "DeepSeek-V4-Flash",
    "messages": [{"role": "user", "content": "你是谁？简单介绍一下自己。"}],
    "max_tokens": 200,
    "temperature": 1.0
  }'
```

## DeepSeek-V4 推理模式

V4 支持三种推理模式，通过系统提示词控制：

| 模式           | 说明                           | 适用场景                   |
| -------------- | ------------------------------ | -------------------------- |
| **Non-think**  | 快速直觉式响应，不进行深度推理 | 简单对话、快速问答         |
| **Think High** | 有意识的逻辑分析               | 复杂推理、代码生成         |
| **Think Max**  | 最大推理能力                   | 数学证明、竞赛题、深度分析 |

:::tip[说明]

使用 Think Max 模式时，建议上下文窗口至少 384K tokens，以获得最佳推理效果。

:::

## 常见问题

### V4 与 R1 的部署有什么区别？

1. **镜像不同**：V4 需要使用专用镜像（如 `lmsysorg/sglang:deepseek-v4-hopper`），而非通用的 `lmsysorg/sglang:latest`。
2. **精度格式**：V4 使用 FP4+FP8 混合精度（B200）或 FP8（H20/H200），R1 使用 FP8。
3. **显存需求**：V4-Flash (158GB) 比 R1 (约 720GB) 小很多，单机部署更容易；V4-Pro (862GB) 比 R1 稍大。
4. **模型来源**：H20 需使用 `sgl-project/DeepSeek-V4-Flash-FP8` 的 FP8 版本，而非默认的 FP4 版本。

### 如何对外暴露 API？

方法与 DeepSeek-R1 部署相同，支持 LoadBalancer Service、Ingress、Gateway API 等方式，参见 [在 TKE 上部署满血版 DeepSeek-R1 (SGLang)](./sglang-deepseek-r1) 中的相关说明。

### 如何使用 OpenWebUI 与模型对话？

SGLang 提供了兼容 OpenAI 的 API，配置 OpenWebUI 时将 API 地址指向 DeepSeek-V4 的 Service 地址即可：

```yaml
env:
- name: OPENAI_API_BASE_URL
  value: http://deepseek-v4-flash-api:30000/v1 # 或 deepseek-v4-pro-api
- name: ENABLE_OLLAMA_API
  value: "False"
```

### H20 能否运行 V4-Pro？

单机 8 卡 H20（总显存 768GB）无法运行 V4-Pro（模型文件 862GB），需要双机 16 卡 H20（总显存 1536GB）。双机部署建议使用 HCCPNV6 机型（支持 RDMA），并通过 LWS 组件进行编排。

### SGLang 的 V4 专用镜像与通用镜像有什么区别？

V4 专用镜像针对不同 GPU 架构做了优化，包含了 FP4 量化支持（Blackwell）和 FP8 优化（Hopper）等特定功能。使用通用的 `latest` 镜像可能无法正确加载 V4 模型或无法获得最佳性能。

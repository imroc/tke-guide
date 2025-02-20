# 在 TKE 上部署满血版 DeepSeek-R1 (SGLang)

## 概述

[SGLang](https://docs.sglang.ai/) 与 [vLLM](https://docs.vllm.ai) 类似， 用于运行 AI 大模型，是性能卓越的新兴之秀，与 DeepSeek 官方合作并专门针对 DeepSeek 进行了深度优化，也是 DeepSeek 官方推荐的部署工具。

本文将基于 SGLang 在 TKE 集群上部署满血版 DeepSeek-R1 模型，提供最佳实践的部署示例。

## 机型与部署方案

由于满血版的 DeepSeek-R1 参数量较大，需要用较大显存且支持 FP8 量化的大规格 GPU 实例，目前合适的机型规格有 [HCCPNV6.96XLARGE2304](https://cloud.tencent.com/document/product/1646/81562#HCCPNV6)（[高性能计算集群](https://cloud.tencent.com/product/hcc)）和 [PNV6.32XLARGE1280 / PNV6.96XLARGE2304](https://cloud.tencent.com/document/product/560/19700#PNV6)（[GPU 云服务器](https://cloud.tencent.com/product/gpu)），推荐的部署方案是用两台该机型的节点组建 GPU 集群来运行满血 DeepSeek-R1，如果对并发和性能要求不高，也可以单台部署。

下面是这几种规格的核心参数：

| 规格                 | RDMA          | CPU核心数 | 内存(GB) | GPU 卡数 |
| -------------------- | ------------- | --------- | -------- | -------- |
| PNV6.32XLARGE1280    | 不支持        | 128       | 1280     | 8        |
| PNV6.96XLARGE2304    | 不支持        | 384       | 2304     | 8        |
| HCCPNV6.96XLARGE2304 | 支持(3.2Tbps) | 384       | 2304     | 8        |

:::info[注意]

这几种规格的机型实例都正在邀测中，且资源紧张，需联系您的销售经理开通使用并协调好资源。

:::

**选型建议**：两台组建 GPU 集群来运行满血 DeepSeek-R1 建议选 `HCCPNV6.96XLARGE2304`，因为支持 RDMA，可显著提升 DeepSeek 运行性能；单台部署优先考虑 `PNV6.32XLARGE1280` 和 `PNV6.96XLARGE2304` 以节约成本。

## 镜像说明

本文中的示例使用的镜像是 SGLang 官方提供的镜像（[lmsysorg/sglang](https://hub.docker.com/r/lmsysorg/sglang/tags)），tag 为 latest，建议指定 tag 到固定版本。

官方镜像托管在 DockerHub，且体积较大，在 TKE 环境中，默认提供免费的 DockerHub 镜像加速服务。中国大陆用户也可以直接从 DockerHub 拉取镜像，但速度可能较慢，尤其是对于较大的镜像，等待时间会更长。为提高镜像拉取速度，建议将镜像同步至 [容器镜像服务 TCR](https://cloud.tencent.com/product/tcr)，并在 YAML 文件中替换相应的镜像地址，这样可以显著加快镜像的拉取速度。

## 操作步骤

### 购买 GPU 服务器

测试 POC 阶段，可先在 [云服务器购买页面](https://buy.cloud.tencent.com/cvm) 进行购买，支持按量计费。

:::info[注意]

对于 **PNV6.32XLARGE1280** 和 **PNV6.96XLARGE2304** 的这两种规格，需在**架构**为**异构计算**中找；对于 **HCCPNV6.96XLARGE2304** 的规格，需在**架构**为**高性能计算集群**中找，且要先提前创建高性能计算集群，详情请参见 [创建高性能计算集群](https://cloud.tencent.com/document/product/1646/93026#3680502d-53cb-440e-8cf1-3eebbb7db3c5)。

:::

正式购买阶段，需通过 [高性能计算平台-工作空间](https://console.cloud.tencent.com/thpc/workspace/index) 购买，工作空间规格与机型规格的对应关系，以及各自的正式购买入口如下所示：

| 规格              | 机型                 | 购买入口                                   |
| ----------------- | -------------------- | ------------------------------------------ |
| 96AS.32XLARGE1280 | PNV6.32XLARGE1280    | 高性能计算平台-工作空间-新建，选择标准空间 |
| 96AS.32XLARGE1280 | PNV6.96XLARGE2304    | 高性能计算平台-工作空间-新建，选择标准空间 |
| 96A.96XLARGE2304  | HCCPNV6.96XLARGE2304 | 高性能计算平台-工作空间-新建，选择互联空间 |

### 创建 TKE 集群

登录 [容器服务控制台](https://console.cloud.tencent.com/tke2)，创建一个集群：

:::tip[说明]

更多详情请参见 [创建集群](https://cloud.tencent.com/document/product/457/103981)。

:::

- **地域**：选择购买的 GPU 服务器所在地域
- **集群类型**：选择**TKE 标准集群**。
- **Kubernetes版本**：要大于等于1.28（多机部署依赖的 LWS 组件的要求），建议选最新版。

### 添加 GPU 节点

通过添加已有节点的方式将购买到的 GPU 服务器加入 TKE 集群。

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F19%2F20250219175511.png)

系统镜像选 `TencentOS Server 3.1 (TK4) UEFI | img-39ywauzd`，驱动和 CUDA 选最新版本。

### 准备存储与模型文件

满血版 DeepSeek-R1 体积较大，为加快模型下载和加载速度，建议使用性能最强的存储，本文给出 NVME SSD 本地存储和 CFS-Trubo 共享存储两种方案的示例。

#### CFS-Turbo 共享存储

共享存储使用 CFS-Turbo 性能更好，Turbo 系列性能与规格详情参考 [腾讯云文件存储官方文档](https://cloud.tencent.com/document/product/582/38112#turbo-.E7.B3.BB.E5.88.97)，使用下面的步骤准备 CFS-Turbo 存储和下载大模型文件。

##### 安装 CFS 插件

1. 在集群列表中，单击**集群 ID**，进入集群详情页。
2. 选择左侧菜单栏中的**组件管理**，在组件页面单击**新建**。
3. 在新建组件管理页面中勾选 **CFSTurbo（腾讯云高性能并行文件系统）**。

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F14%2F20250214162518.png)

4. 单击完成即可创建组件。

##### 创建 CFS-Turbo 实例

1. 登录 [CFS 控制台](https://console.cloud.tencent.com/cfs/fs)，单击**创建**来新建一个 CFS-Turbo 实例。
2. **文件系统类型**选择 Turbo 系列的：
  ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F14%2F20250214162925.png)
3. **地域**选择 TKE 集群所在地域。
4. **可用区** 选择 GPU 节点池所在可用区（降低时延）。
5. **网络类型**如果选**云联网网络**，需确保 TKE 集群所在 VPC 已加入该云联网中；如果选**VPC 网络**，则需选择 TKE 集群所在 VPC，子网选与 GPU 节点池在同一个可用区的子网。
6. 单击**立即创建**。

##### 新建 StorageClass

新建一个后续使用 CFS 存储大模型的 PVC，可通过控制台或 YAML 创建。

<Tabs>
<TabItem value="console" label="通过控制台创建">

1. 在集群列表中，单击**集群 ID**，进入集群详情页。
2. 选择左侧菜单栏中的**存储**，在 StorageClass 页面单击**新建**。
3. 在新建存储页面，根据实际需求，创建 CFS-Turbo 类型的 StorageClass。如下图所示：
  ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F14%2F20250214164723.png)
  - 名称：请输入 StorageClass 名称，本文以 “cfs-turbo” 为例。
  - Provisioner：选择 “文件存储CFS turbo”。
  - CFS turbo：选择前面**创建 CFS-Turbo 实例**步骤中创建出来的 CFS-Turbo 的实例。

</TabItem>
<TabItem value="yaml" label="通过 YAML 创建">

:::info[注意]

- `fsid` 替换为前面步骤新建的 CFS-Turbo 实例的挂载点 ID（在实例的挂载点信息页面可查看，注意不是 `cfs-xxx` 的 ID）。
- `host` 替换为前面步骤新建的 CFS-Turbo 实例的IPv4地址（同样也在挂载点信息页面可查看）。

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F14%2F20250214195827.png)

:::

```yaml showLineNumbers
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: cfs-turbo
provisioner: com.tencent.cloud.csi.cfsturbo
reclaimPolicy: Delete
volumeBindingMode: Immediate
# highlight-start
parameters:
  fsid: 564b8ef1
  host: 11.0.0.7
# highlight-end
```
</TabItem>
</Tabs>


##### 创建 PVC

创建一个使用 CFS-Turbo 的 PVC，用于存储 AI 大模型，可通过控制台或 YAML 创建。

<Tabs>
<TabItem value="console" label="通过控制台创建">

1. 在集群列表中，单击**集群 ID**，进入集群详情页。
2. 选择左侧菜单栏中的**存储**，在 PersistentVolumeClaim 页面单击**新建**。
3. 在新建存储页面，创建存储大模型的 PVC。如下图所示：
  ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F17%2F20250217101923.png)
  - 名称：请输入 PVC 名称，本文以 “ai-model” 为例。
  - 命名空间：SGLang 将要被部署的命名空间。
  - Provisioner：选择 “文件存储CFS turbo”。
  - 是否指定StorageClass：选择 “指定”。
  - StorageClass：选择前面新建的  StorageClass 的名称。
  - 是否指定PersistentVolue：选择 “不指定”。

</TabItem>
<TabItem value="yaml" label="通过 YAML 创建">

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ai-model
  labels:
    app: ai-model
spec:
  storageClassName: cfs-turbo
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 700Gi
```

:::info[注意]

注意替换 `storageClassName` 为**新建 StorageClass** 步骤中配置的名称。

:::

</TabItem>
</Tabs>

##### 使用 Job 下载大模型文件

创建一个 Job 用于下载大模型文件到 CFS：

:::info[注意]

满血版的 DeepSeek-R1 是 671B 的大模型，一共 642G，下载耗时可能较长，实测在上海下载 ModelScope 上的模型文件，100Mbps 的云服务器带宽，耗时 16 个多小时：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F17%2F20250217100442.png)

:::

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: download-model
  labels:
    app: download-model
spec:
  template:
    metadata:
      name: sglang
      labels:
        app: download-model
    spec:
      containers:
      - name: sglang
        image: lmsysorg/sglang:latest
        command:
        - modelscope
        - download
        - --local_dir=/data/model/DeepSeek-R1
        - --model=deepseek-ai/DeepSeek-R1
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

- CFS-Turbo 的 PVC 挂载到 `/data` 目录，存储下载的模型文件。
- `--local_dir` 指定模型文件下载目录。
- `--model` 指定 [ModelScope 模型库](https://www.modelscope.cn/models) 中的模型名称，满血版的 DeepSeek-R1 模型名称为 `deepseek-ai/DeepSeek-R1`。

:::

#### 本地存储

如果使用本地存储大模型，可以创建一个下载模型文件的 DaemonSet，相当于给每个节点都下发一个下载 Job：

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: download-model
  labels:
    app: download-model
spec:
  selector:
    matchLabels:
      app: download-model
  template:
    metadata:
      labels:
        app: download-model
    spec:
      restartPolicy: OnFailure # 默认 Always，改成 OnFailure 避免重复下载
      nodeSelector:
        nvidia-device-enable: "true" # 只让 GPU 节点下载
      containers:
      - name: sglang
        image: lmsysorg/sglang:latest
        command:
        - modelscope
        - download
        - --local_dir=/data/model/DeepSeek-R1
        - --model=deepseek-ai/DeepSeek-R1
        volumeMounts:
        - name: model
          mountPath: /data/model
      volumes:
      - name: model
        hostPath:
          path: /data/model
          type: DirectoryOrCreate
```

### 安装 LWS 组件

:::info[注意]

如果只使用单机部署的方案，无需安装 LWS 组件，可跳过此步骤。

:::

SGLang 多机部署（GPU 集群）需借助 [LWS](https://github.com/kubernetes-sigs/lws) 组件，在 TKE 应用市场中找到 lws：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F14%2F20250214151529.png)

安装到集群中：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F14%2F20250214153816.png)

- 应用名：建议填 `lws`。
- 命名空间：建议使用 `lws-system`（新建命名空间）。

:::info[说明]

如需希望使用 kubectl 或 helm 等方式部署 LWS，可请参考 LWS 官方文档（[kubectl 方式安装](https://github.com/kubernetes-sigs/lws/blob/main/docs/setup/install.md) 和 [helm 方式安装](https://github.com/kubernetes-sigs/lws/blob/main/charts/lws/README.md)）。
需要注意的是，官方默认使用镜像是 `registry.k8s.io/lws/lws`，这个在国内环境下载不了，可替换镜像地址为 `docker.io/k8smirror/lws`，该镜像为 lws 在 DockerHub 上的 mirror 镜像，长期自动同步，可放心使用（TKE 环境可直接拉取 DockerHub 的镜像），也可以同步到自己的 TCR 或 CCR 镜像仓库，提高镜像下载速度。

:::

### 部署 DeepSeek-R1

使用本文指定的机型，每台有 8 张 GPU 算卡，单机部署也能成功运行，如果并发和吞吐要求较高，建议使用双机集群部署。

双机（多机）集群部署使用 [LWS](https://github.com/kubernetes-sigs/lws) 中的 `LeaderWorkerSet` 来部署，单机部署则直接使用 `Deployment` 部署。

下面提供单机和双机两种部署方式的示例。

#### 双机集群部署

使用 `LeaderWorkerSet` 部署满血版的 DeepSeek-R1 双机集群(2 台 8 卡的 GPU 节点，1 个 leader 和 1 个 worker)：

<Tabs>
  <TabItem value="share" label="挂载 CFS 共享存储">
    <FileBlock file="ai/sglang-lws-deepseek-r1.yaml" showLineNumbers />
  </TabItem>
  <TabItem value="local" label="挂载本地存储">
    <FileBlock file="ai/sglang-lws-deepseek-r1-hostpath.yaml" showLineNumbers />
  </TabItem>
</Tabs>


:::info[说明]

- `nvidia.com/gpu` 为单机 GPU 卡数，这里是 8 卡（leader 和 worker 保持一致）。
- `leaderWorkerTemplate.size` 为单个 GPU 集群的节点数，2 表示两个节点组成的 GPU 集群（1 个 leader 和 1 个 worker）。
- `replicas` 为 GPU 集群数量，这里是 1 个 GPU 集群，如需扩容，准备好节点资源后，调整这里的数量即可。
- `TOTAL_GPU` 为单个 GPU 集群的 GPU 总卡数（节点数量*单机 GPU 卡数），这里是 16 卡。
- `MODEL_DIRECTORY` 为模型文件的子目录路径。
- `MODEL_NAME` 为模型名称，API 调用将使用此模型名称进行交互。
- leader 和 worker 的环境变量需一致，如需调整记得将 leader 和 worker 的 template 都做相同的修改。
- 如果使用支持 RDMA 的机型，需使用 HostNetwork 才能让 RDMA 生效。
- Service 中 `leaderworkerset.sigs.k8s.io/name` 指定的是 lws 的名称。
- 涉及 OpenAI API 地址配置的地方（如 OpenWebUI），指向这个 Service 的地址（如 `http://deepseek-r1-api:30000/v1`）。

:::

部署好后如果像扩容，可以通过调高 `replicas` 来增加 GPU 集群数量（前提是准备好新的 GPU 节点资源）。

#### 单机部署

使用 `Deployment` 部署单机满血版的 DeepSeek-R1：

<Tabs>
  <TabItem value="share" label="挂载 CFS 共享存储">
    <FileBlock file="ai/sglang-deployment-deepseek-r1.yaml" showLineNumbers />
  </TabItem>
  <TabItem value="local" label="挂载本地存储">
    <FileBlock file="ai/sglang-deployment-deepseek-r1-hostpath.yaml" showLineNumbers />
  </TabItem>
</Tabs>

:::info[说明]

- `nvidia.com/gpu` 和 `TOTAL_GPU` 都是单机 GPU 卡数，这里是 8 卡。
- `replicas` 为 DeepSeek-R1 副本数，1 个副本占用 1 台 GPU 节点。
- `MODEL_DIRECTORY` 为模型文件的子目录路径。
- `MODEL_NAME` 为模型名称，API 调用将使用此模型名称进行交互。
- 由于是单机部署，无需 RDMA，也无需使用 HostNetwork。
- 单机部署配置了 `--mem-fraction-static`和 `--max-running-request` 参数，用于避免显存不足导致 SGLang 启动失败。
- 涉及 OpenAI API 地址配置的地方（如 OpenWebUI），指向这里创建的 Service 的地址（如 `http://deepseek-r1-api:30000/v1`）。

:::

部署好后如果像扩容，可以通过调高 `replicas` 来增加 DeepSeek-R1 副本数（前提是准备好新的 GPU 节点资源）。

### 验证 API

Pod 成功跑起来后用 kubectl exec 进入 leader Pod，使用 curl 测试 API：

```bash
curl -v http://127.0.0.1:30000/v1/completions -H 'X-API-Key: 93e8b39f55fc4097956054c80a8ed7cf'  -H "Content-Type: application/json" -d '{
      "model": "DeepSeek-R1",
      "prompt": "你是谁?",
      "max_tokens": 100,
      "temperature": 0
    }'
```

## 常见问题

### 如何对外暴露 API ？

通常对外暴露 API 一般会配置 API 密钥，配置方法是修改本文示例中的 YAML，将密钥配置到 `API_KEY` 环境变量中。

如果希望将 API 对外暴露，最简单的是直接修改 DeepSeek 的 Service 类型为 LoadBalancer，TKE 会自动为其创建公网 CLB 将 API 暴露到公网：

<Tabs>
  <TabItem value="dubble" label="双机集群部署版">
    <FileBlock file="ai/deepseek-r1-api-lb-leader-svc.yaml" showLineNumbers />
  </TabItem>
  <TabItem value="single" label="单机部署版">
    <FileBlock file="ai/deepseek-r1-api-lb-svc.yaml" showLineNumbers />
  </TabItem>
</Tabs>

如果需要更灵活的方式暴露，比如配置证书通过 HTTPS 协议暴露，或者与其他服务共用网关入口，可以通过 Ingress 或 Gateway API 来暴露，示例：

<Tabs>
<TabItem value="api-httproute" label="Gateway API">

:::info[注意]

使用 Gateway API 需要集群中装有 Gateway API 的实现，如 TKE 应用市场中的 EnvoyGateway，具体 Gateway API 用法参考 [官方文档](https://gateway-api.sigs.k8s.io/guides/)。

:::

<FileBlock file="ai/deepseek-r1-httproute.yaml" showLineNumbers />

:::tip[说明]

1. `parentRefs` 引用定义好的 `Gateway`（通常一个 Gateway 对应一个 CLB）。
2. `hostnames` 替换为你自己的域名，确保域名能正常解析到 Gateway 对应的 CLB 地址。
3. `backendRefs` 指定 DeepSeek 的 Service。

:::

</TabItem>

<TabItem value="webui-ingress" label="Ingress">

<FileBlock file="ai/deepseek-r1-ingress.yaml" showLineNumbers />

:::tip[说明]

1. `host` 替换为你自己的域名，确保域名能正常解析到 Ingress 对应的 CLB 地址。
2. `backend.service` 指定 DeepSeek 的 Service。

:::

</TabItem>
</Tabs>

最后在需要使用 API 的应用中配置 API 地址、API 密钥、模型名称等，比如 [Chatbox](https://chatboxai.app/) 的配置：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F20%2F20250220165250.png)

:::info[说明]

- **模型提供方**: 由于 SGLang 兼容 OpenAI 的 API，所以选择 **OPENAI API**。
- **API 密钥**：填写 DeepSeek-R1 部署时指定的 API KEY（`API_KEY` 环境变量）。
- **API 域名**：用 DeepSeek-R1 最终被暴露出来的外部地址。
- **模型**：填写 DeepSeek-R1 部署时指定的模型名称（`MODEL_NAME` 环境变量）。

:::

### 如何使用 OpenWebUI 与模型对话？

SGLang 提供了兼容 OpenAI 的 API，部署 OpenWebUI 时，如不需要 Ollama API 可禁用掉，再配置下 OpenAI 的 API 地址，指向 DeepSeek-R1 的地址即可。

如果[使用 helm 部署 OpenWebUI](https://github.com/open-webui/helm-charts)，`values.yaml` 配置示例：

```yaml
ollama:
  enabled: false
openaiBaseApiUrl: "http://deepseek-r1:30000/api/v1"
```

如果通过 YAML 部署 OpenWebUI，需配置下 Pod 环境变量，示例：

```yaml
env:
- name: OPENAI_API_BASE_URL
  value: http://deepseek-r1:30000/api/v1 # vllm 的地址
- name: ENABLE_OLLAMA_API # 禁用 Ollama API，只保留 OpenAI API
  value: "False"
```

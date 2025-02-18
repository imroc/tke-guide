# 在 TKE 使用 SGLang 部署 DeepSeek-R1

:::warning[警告]

实践还在进行中，本文尚未完成！

:::

## 概述

[SGLang](https://docs.sglang.ai/) 与 [vLLM](https://docs.vllm.ai) 类似， 用于运行 AI 大模型，是性能卓越的新兴之秀，与 DeepSeek 官方合作并专门针对 DeepSeek 进行了深度优化，也是 DeepSeek 官方推荐的部署工具。

本文将基于 SGLang 在 TKE 集群上部署 DeepSeek-R1 模型，提供最佳实践的部署示例。

## DeepSeek-R1 模型列表

SGLang 支持 [HuggingFace](https://huggingface.co/models) 和 [ModelScope](https://www.modelscope.cn/models) 上的大模型，由于腾讯云的 GPU 机型基本只在国内售卖，而 HuggingFace 上的模型在国内下载会有网络问题，所以本文以 ModelScope 上的 DeepSeek-R1 模型为例。

DeepSeek-R1 除了原版的 671B （满血版）模型外，还有一系列蒸馏版，满血版对硬件要求高，蒸馏版是缩小版 DeepSeek-R1，对硬件要求低。

| 参数量 | 模型名称                      |
| ------ | ----------------------------- |
| 1.5B   | DeepSeek-R1-Distill-Qwen-1.5B |
| 7B     | DeepSeek-R1-Distill-Qwen-7B   |
| 8B     | DeepSeek-R1-Distill-Llama-8B  |
| 14B    | DeepSeek-R1-Distill-Qwen-14B  |
| 32B    | DeepSeek-R1-Distill-Qwen-32B  |
| 70B    | DeepSeek-R1-Distill-Llama-70B |
| 671B   | DeepSeek-R1 (满血版)          |

## 选择 GPU 型号

SGLang 用 GPU 运行 DeepSeek 大模型，要求 GPU 的计算能力大于等于 7.5，推荐 8.0 以上，如果不满足可能出现类似以下的报错：

```yaml
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

在腾讯云上售卖的 GPU 服务器分两类：[GPU 云服务器](https://cloud.tencent.com/product/gpu) 和 [高性能计算集群 HCC](https://cloud.tencent.com/product/hcc)。
- GPU 云服务器售卖的机型、地域以及对应的 GPU 型号和显存大小及参考 [GPU 云服务器实例规格](https://cloud.tencent.com/document/product/560/19700)。
- HCC 售卖的机型以及对应的 GPU 型号和显存大小参考 [HCC 实例规格](https://cloud.tencent.com/document/product/1646/81562)，售卖地域参考 [HCC 实例售卖地域](https://cloud.tencent.com/document/product/1646/81565)。

GPU 型号与计算能力的关系参考 NVIDIA 官方文档 [Your GPU Compute Capability](https://developer.nvidia.com/cuda-gpus) 中 **CUDA-Enabled Datacenter Products** 的表格。

根据以上信息，总结一下腾讯云售卖的 GPU 型号计算能力与显存：

| GPU 型号           | 计算能力 | 显存      | 售卖渠道 |
| ------------------ | -------- | --------- | -------- |
| NVIDIA P4          | 6.1      | 8GB       | CVM      |
| NVIDIA P40         | 6.1      | 24GB      | CVM      |
| NVIDIA V100        | 7.0      | 32GB      | CVM/HCC  |
| NVIDIA P40         | 6.1      | 24GB      | CVM      |
| NVIDIA T4          | 7.5      | 16GB      | CVM      |
| NVIDIA A10         | 8.6      | 24GB      | CVM      |
| NVIDIA A100        | 8.0      | 40GB      | CVM/HCC  |
| NVIDIA A800        | 8.0      | 40GB/80GB | HCC      |
| NVIDIA H800        | 9.0      | 80GB      | HCC      |
| NVIDIA GPU（邀测） | 9.0      | 未知      | HCC      |

## 选择 TKE 集群地域

由于 GPU 机型只在部分地域售卖，所以我们需要选择这些有售卖的地域来创建 TKE 集群，具体售卖地域参考 [GPU 云服务器实例规格](https://cloud.tencent.com/document/product/560/19700) 和 [HCC 实例售卖地域](https://cloud.tencent.com/document/product/1646/81565) 中的表格。

**结论**：选择广州、上海、南京、北京这些国内地域创建 TKE 集群。

## 操作步骤

### 准备集群

登录 [容器服务控制台](https://console.cloud.tencent.com/tke2)，创建一个集群：

:::tip[说明]

更多详情请参见 [创建集群](https://cloud.tencent.com/document/product/457/103981)。

:::

- **集群类型**：选择**TKE 标准集群**。
- **Kubernetes版本**：要大于等于1.28（多机部署依赖的 LWS 组件的要求），建议选最新版。

### 新建 GPU 节点池

1. 在集群管理页面，选择**集群 ID**，进入集群的基本信息页面。
2. 选择左侧菜单栏中的**节点管理**，在节点池页面单击**新建**。
3. 节点类型选择**原生节点**或**普通节点**。配置详情请参见 [创建节点池](https://cloud.tencent.com/document/product/457/43735)。
  - 如果使用**原生节点**或**普通节点**，**操作系统**选新一点的；**系统盘**和**数据盘**默认 50GB，建议调大点（如200GB），避免因 SGLang 镜像大导致节点磁盘空间不够而无法正常拉起；**机型配置**在**GPU 机型**中选择一个符合需求且没有售罄的机型，如有 GPU 驱动选项，也选最新的版本。
  - 如果使用**超级节点**，是虚拟的节点，每个 Pod 都是独占的轻量虚拟机，所以无需选择机型，只需在部署的时候通过 Pod 注解来指定 GPU 卡的型号（后面示例中会有），但超级节点暂不支持 A100，只有用 A10。
  - **子网**选同一个可用区的，避免 GPU 集群跨机房传输数据导致性能损耗，并且需要所在可用区有 A10 或 A100 卡的机型可购买。
4. 单击**创建节点池**。

### 准备 CFS 存储

满血版 DeepSeek-R1 体积较大，为加快模型下载和加载速度，建议使用 CFS-Turbo 共享存储，Turbo 系列性能与规格详情参考 [腾讯云文件存储官方文档](https://cloud.tencent.com/document/product/582/38112#turbo-.E7.B3.BB.E5.88.97)。

#### 安装 CFS 插件

1. 在集群列表中，单击**集群 ID**，进入集群详情页。
2. 选择左侧菜单栏中的**组件管理**，在组件页面单击**新建**。
3. 在新建组件管理页面中勾选 **CFSTurbo（腾讯云高性能并行文件系统）**。

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F14%2F20250214162518.png)

4. 单击完成即可创建组件。

#### 创建 CFS-Turbo 实例

1. 登录 [CFS 控制台](https://console.cloud.tencent.com/cfs/fs)，单击**创建**来新建一个 CFS-Turbo 实例。
2. **文件系统类型**选择 Turbo 系列的：
  ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F14%2F20250214162925.png)
3. **地域**选择 TKE 集群所在地域。
4. **可用区** 选择 GPU 节点池所在可用区（降低时延）。
5. **网络类型**如果选**云联网网络**，需确保 TKE 集群所在 VPC 已加入该云联网中；如果选**VPC 网络**，则需选择 TKE 集群所在 VPC，子网选与 GPU 节点池在同一个可用区的子网。
6. 单击**立即创建**。

#### 新建 StorageClass

新建一个后续使用 CFS 存储大模型的 PVC，可通过控制台或 YAML 创建。

##### 通过控制台创建

1. 在集群列表中，单击**集群 ID**，进入集群详情页。
2. 选择左侧菜单栏中的**存储**，在 StorageClass 页面单击**新建**。
3. 在新建存储页面，根据实际需求，创建 CFS-Turbo 类型的 StorageClass。如下图所示：
  ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F14%2F20250214164723.png)
  - 名称：请输入 StorageClass 名称，本文以 “cfs-turbo” 为例。
  - Provisioner：选择 “文件存储CFS turbo”。
  - CFS turbo：选择前面**创建 CFS-Turbo 实例**步骤中创建出来的 CFS-Turbo 的实例。

##### 通过 YAML 创建

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
#### 创建 PVC

创建一个使用 CFS-Turbo 的 PVC，用于存储 AI 大模型，可通过控制台或 YAML 创建。

##### 通过控制台创建

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

##### 通过 YAML 创建

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

### 安装 LWS 组件

SGLang 多机部署（GPU 集群）需借助 [LWS](https://github.com/kubernetes-sigs/lws) 组件，在 TKE 应用市场中找到 lws：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F14%2F20250214151529.png)

安装到集群中：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F14%2F20250214153816.png)

- 应用名：建议填 `lws`。
- 命名空间：建议使用 `lws-system`（新建命名空间）。

:::info[说明]

如需希望使用 kubectl 或 helm 等方式部署 LWS，可请参考 LWS 官方文档（[kubectl 方式安装](https://github.com/lwsws/lws-helm/blob/main/docs/install.md) 和 [helm 方式安装]）。
需要注意的是，官方默认使用镜像是 `registry.k8s.io/lws/lws`，这个在国内环境下载不了，可替换镜像地址为 `docker.io/k8smirror/lws`，该镜像为 lws 在 DockerHub 上的 mirror 镜像，长期自动同步，可放心使用（TKE 环境可直接拉取 DockerHub 的镜像），也可以同步到自己的 TCR 或 CCR 镜像仓库，提高镜像下载速度。

:::

### 下载 AI 大模型

下发一个 Job 用于下载 AI 大模型：

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
      name: download-model
      labels:
        app: download-model
    spec:
      containers:
      - name: sglang
        image: lmsysorg/sglang:latest
        command:
        - modelscope
        - download
        - --local_dir=/data/DeepSeek-R1
        - --model=deepseek-ai/DeepSeek-R1
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: ai-model
      restartPolicy: OnFailure
```

:::info[说明]

- 由于 A10 和 A00 只在国内地域售卖，所以集群一定在国内地域，而国内地域下载 HuggingFace 上的模型会有网络问题，而 ModelScope 不会有问题，所以我们下载 ModelScope 上的模型。
- CFS-Turbo 的 PVC 挂载到 `/data` 目录，存储下载的模型文件。
- `--local_dir` 指定模型文件下载目录。
- `--model` 指定 [ModelScope 模型库](https://www.modelscope.cn/models) 中的模型名称，满血版的 DeepSeek-R1 模型名称为 `deepseek-ai/DeepSeek-R1`。

:::

### 部署 DeepSeek-R1

使用 `LeaderWorkerSet` 多机部署满血版的 DeepSeek-R1：

:::info[说明]

- `nvidia.com/gpu` 为单机 GPU 卡数。
- `--tp` 为单个 GPU 集群的 GPU 总卡数（节点数量*单机 GPU 卡数）。
- `size` 为单个 GPU 集群的节点数。
- `replicas` 为 GPU 集群数量。

:::

```yaml showLineNumbers
apiVersion: leaderworkerset.x-k8s.io/v1
kind: LeaderWorkerSet
metadata:
  name: deepseek-r1
spec:
  replicas: 1
  leaderWorkerTemplate:
    size: 4
    restartPolicy: RecreateGroupOnPodRestart
    leaderTemplate:
      metadata:
        labels:
          role: leader
      spec:
        terminationGracePeriodSeconds: 1
        containers:
        - name: leader
          image: lmsysorg/sglang:latest
          command:
          - bash
          - -c
          - |
            set -x
            exec python3 -m sglang.launch_server \
              --model-path /data/DeepSeek-R1 \
              --nnodes $LWS_GROUP_SIZE \
              --tp 4 \
              --node-rank 0 \
              --dist-init-addr $(LWS_LEADER_ADDRESS):5000 \
              --trust-remote-code \
              --host 0.0.0.0 \
              --port 30000
          resources:
            limits:
              nvidia.com/gpu: "4"
          ports:
          - containerPort: 30000
          volumeMounts:
          - mountPath: /dev/shm
            name: dshm
          - mountPath: /data
            name: data
        volumes:
        - name: dshm
          emptyDir:
            medium: Memory
            sizeLimit: 40Gi
        - name: data
          persistentVolumeClaim:
            claimName: ai-model-turbo
    workerTemplate:
      spec:
        terminationGracePeriodSeconds: 1
        containers:
        - name: worker
          image: lmsysorg/sglang:latest
          env:
          - name: ORDINAL_NUMBER
            valueFrom:
              fieldRef:
                fieldPath: metadata.labels['apps.kubernetes.io/pod-index']
          command:
          - bash
          - -c
          - |
            set -x
            exec python3 -m sglang.launch_server \
              --model-path /data/DeepSeek-R1 \
              --nnodes $LWS_GROUP_SIZE \
              --tp 4 \
              --node-rank $ORDINAL_NUMBER \
              --dist-init-addr $(LWS_LEADER_ADDRESS):5000 \
              --trust-remote-code
          resources:
            limits:
              nvidia.com/gpu: "4"
          volumeMounts:
          - mountPath: /dev/shm
            name: dshm
          - mountPath: /data
            name: data
        volumes:
        - name: dshm
          emptyDir:
            medium: Memory
            sizeLimit: 40Gi
        - name: data
          persistentVolumeClaim:
            claimName: ai-model
```

再创建一个 Service 用于 SGLang 提供的兼容 OpenAI 的 API：

:::info[注意]

- `leaderworkerset.sigs.k8s.io/name` 指定 lws 的名称。
- 所有 GPU 集群的 leader Pod 的 index 固定为 0，可以通过 `apps.kubernetes.io/pod-index: "0"` 这个 label 来选中。
- 涉及 API 地址配置的地方（如 OpenWebUI），指向这个 Service 的地址（如 `http://deepseek-r1-api:30000/v1`）。

:::

```yaml
apiVersion: v1
kind: Service
metadata:
  name: deepseek-r1-api
spec:
  type: ClusterIP
  selector:
    leaderworkerset.sigs.k8s.io/name: deepseek-r1
    apps.kubernetes.io/pod-index: "0"
  ports:
  - name: api
    port: 30000
    targetPort: 30000
```

## 常见问题

### 报错: undefined symbol: cuTensorMapEncodeTiled

SGLang 启动报错：

```txt
INFO 02-17 02:35:21 __init__.py:190] Automatically detected platform cuda.
Traceback (most recent call last):
  File "/usr/lib/python3.10/runpy.py", line 196, in _run_module_as_main
    return _run_code(code, main_globals, None,
  File "/usr/lib/python3.10/runpy.py", line 86, in _run_code
    exec(code, run_globals)
  File "/sgl-workspace/sglang/python/sglang/launch_server.py", line 6, in <module>
    from sglang.srt.entrypoints.http_server import launch_server
  File "/sgl-workspace/sglang/python/sglang/srt/entrypoints/http_server.py", line 41, in <module>
    from sglang.srt.entrypoints.engine import _launch_subprocesses
  File "/sgl-workspace/sglang/python/sglang/srt/entrypoints/engine.py", line 36, in <module>
    from sglang.srt.managers.data_parallel_controller import (
  File "/sgl-workspace/sglang/python/sglang/srt/managers/data_parallel_controller.py", line 27, in <module>
    from sglang.srt.managers.io_struct import (
  File "/sgl-workspace/sglang/python/sglang/srt/managers/io_struct.py", line 24, in <module>
    from sglang.srt.managers.schedule_batch import BaseFinishReason
  File "/sgl-workspace/sglang/python/sglang/srt/managers/schedule_batch.py", line 42, in <module>
    from sglang.srt.configs.model_config import ModelConfig
  File "/sgl-workspace/sglang/python/sglang/srt/configs/model_config.py", line 24, in <module>
    from sglang.srt.layers.quantization import QUANTIZATION_METHODS
  File "/sgl-workspace/sglang/python/sglang/srt/layers/quantization/__init__.py", line 5, in <module>
    from vllm.model_executor.layers.quantization.aqlm import AQLMConfig
  File "/usr/local/lib/python3.10/dist-packages/vllm/__init__.py", line 7, in <module>
    from vllm.engine.arg_utils import AsyncEngineArgs, EngineArgs
  File "/usr/local/lib/python3.10/dist-packages/vllm/engine/arg_utils.py", line 20, in <module>
    from vllm.executor.executor_base import ExecutorBase
  File "/usr/local/lib/python3.10/dist-packages/vllm/executor/executor_base.py", line 15, in <module>
    from vllm.platforms import current_platform
  File "/usr/local/lib/python3.10/dist-packages/vllm/platforms/__init__.py", line 222, in __getattr__
    _current_platform = resolve_obj_by_qualname(
  File "/usr/local/lib/python3.10/dist-packages/vllm/utils.py", line 1906, in resolve_obj_by_qualname
    module = importlib.import_module(module_name)
  File "/usr/lib/python3.10/importlib/__init__.py", line 126, in import_module
    return _bootstrap._gcd_import(name[level:], package, level)
  File "/usr/local/lib/python3.10/dist-packages/vllm/platforms/cuda.py", line 15, in <module>
    import vllm._C  # noqa
ImportError: /usr/local/lib/python3.10/dist-packages/vllm/_C.abi3.so: undefined symbol: cuTensorMapEncodeTiled
```

- **原因**：创建节点池选机型时，如果驱动版本选的过低，导致容器的 CUDA 版本与节点安装的驱动版本不兼容。
- **解决方案**： 选机型时，驱动版本选最新的。
  ![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F17%2F20250217104343.png)

### 报错: 'str' object cannot be interpreted as an integer

SGLang 启动报错：

```txt
[2025-02-17 03:15:47 TP0] Scheduler hit an exception: Traceback (most recent call last):
  File "/sgl-workspace/sglang/python/sglang/srt/managers/scheduler.py", line 1816, in run_scheduler_process
    scheduler = Scheduler(server_args, port_args, gpu_id, tp_rank, dp_rank)
  File "/sgl-workspace/sglang/python/sglang/srt/managers/scheduler.py", line 240, in __init__
    self.tp_worker = TpWorkerClass(
  File "/sgl-workspace/sglang/python/sglang/srt/managers/tp_worker_overlap_thread.py", line 63, in __init__
    self.worker = TpModelWorker(server_args, gpu_id, tp_rank, dp_rank, nccl_port)
  File "/sgl-workspace/sglang/python/sglang/srt/managers/tp_worker.py", line 68, in __init__
    self.model_runner = ModelRunner(
  File "/sgl-workspace/sglang/python/sglang/srt/model_executor/model_runner.py", line 186, in __init__
    min_per_gpu_memory = self.init_torch_distributed()
  File "/sgl-workspace/sglang/python/sglang/srt/model_executor/model_runner.py", line 261, in init_torch_distributed
    initialize_model_parallel(tensor_model_parallel_size=self.tp_size)
  File "/sgl-workspace/sglang/python/sglang/srt/distributed/parallel_state.py", line 1055, in initialize_model_parallel
    _TP = init_model_parallel_group(
  File "/sgl-workspace/sglang/python/sglang/srt/distributed/parallel_state.py", line 890, in init_model_parallel_group
    return GroupCoordinator(
  File "/sgl-workspace/sglang/python/sglang/srt/distributed/parallel_state.py", line 268, in __init__
    self.mq_broadcaster = MessageQueue.create_from_process_group(
  File "/sgl-workspace/sglang/python/sglang/srt/distributed/device_communicators/shm_broadcast.py", line 484, in create_from_process_group
    buffer_io = MessageQueue(
  File "/sgl-workspace/sglang/python/sglang/srt/distributed/device_communicators/shm_broadcast.py", line 207, in __init__
    local_subscribe_port = get_open_port()
  File "/sgl-workspace/sglang/python/sglang/srt/utils.py", line 1392, in get_open_port
    s.bind(("", port))
TypeError: 'str' object cannot be interpreted as an integer
```

- **原因**：创建了名为 `sglang` 的 Service，容器启动时会被自动注入 `SGLANG_PORT` 的环境变量，而该变量的值格式类似 `tcp://x.x.x.x:30000`，SGLang 启动时读取了该环境变量，用于监听端口，而值并非数字格式就报错了。
- **解决方案**：Service 名称改成其它名字，`sglang-api`。

### 报错: Not enough memory. Please try to increase --mem-fraction-static.

SGLang 加载完模型后报错：

```ctx
[2025-02-17 10:13:46 TP4] Scheduler hit an exception: Traceback (most recent call last):
  File "/sgl-workspace/sglang/python/sglang/srt/managers/scheduler.py", line 1816, in run_scheduler_process
    scheduler = Scheduler(server_args, port_args, gpu_id, tp_rank, dp_rank)
  File "/sgl-workspace/sglang/python/sglang/srt/managers/scheduler.py", line 240, in __init__
    self.tp_worker = TpWorkerClass(
  File "/sgl-workspace/sglang/python/sglang/srt/managers/tp_worker_overlap_thread.py", line 63, in __init__
    self.worker = TpModelWorker(server_args, gpu_id, tp_rank, dp_rank, nccl_port)
  File "/sgl-workspace/sglang/python/sglang/srt/managers/tp_worker.py", line 68, in __init__
    self.model_runner = ModelRunner(
  File "/sgl-workspace/sglang/python/sglang/srt/model_executor/model_runner.py", line 215, in __init__
    self.init_memory_pool(
  File "/sgl-workspace/sglang/python/sglang/srt/model_executor/model_runner.py", line 628, in init_memory_pool
    raise RuntimeError(
RuntimeError: Not enough memory. Please try to increase --mem-fraction-static.
```

- **原因**：显存不够。
- **解决方案**：换其它 GPU 型号的机型或者用更多的节点数组建集群。

### 报错: Error 802: system not yet initialized

```txt
[2025-02-18 03:43:01 TP3] Scheduler hit an exception: Traceback (most recent call last):
  File "/sgl-workspace/sglang/python/sglang/srt/managers/scheduler.py", line 1816, in run_scheduler_process
    scheduler = Scheduler(server_args, port_args, gpu_id, tp_rank, dp_rank)
  File "/sgl-workspace/sglang/python/sglang/srt/managers/scheduler.py", line 240, in __init__
    self.tp_worker = TpWorkerClass(
  File "/sgl-workspace/sglang/python/sglang/srt/managers/tp_worker_overlap_thread.py", line 63, in __init__
    self.worker = TpModelWorker(server_args, gpu_id, tp_rank, dp_rank, nccl_port)
  File "/sgl-workspace/sglang/python/sglang/srt/managers/tp_worker.py", line 68, in __init__
    self.model_runner = ModelRunner(
  File "/sgl-workspace/sglang/python/sglang/srt/model_executor/model_runner.py", line 187, in __init__
    min_per_gpu_memory = self.init_torch_distributed()
  File "/sgl-workspace/sglang/python/sglang/srt/model_executor/model_runner.py", line 232, in init_torch_distributed
    torch.get_device_module(self.device).set_device(self.gpu_id)
  File "/usr/local/lib/python3.10/dist-packages/torch/cuda/__init__.py", line 478, in set_device
    torch._C._cuda_setDevice(device)
  File "/usr/local/lib/python3.10/dist-packages/torch/cuda/__init__.py", line 319, in _lazy_init
    torch._C._cuda_init()
RuntimeError: Unexpected error from cudaGetDeviceCount(). Did you run some cuda functions before calling NumCudaDevices() that might have already set an error? Error 802: system not yet initialized
```

- **原因**: 疑似 CUDA 版本不匹配，用的 latest 标签，容器内 CUDA 版本是 12.5，而节点安装的 CUDA 版本是 12.2。
- **解决方案**: 原生节点添加 A800 机型安装的 CUDA 版本最高是 12.2，而直接通过 HCC 控制台安装可以支持到 12.4，改成使用 HCC 创建云服务器，然后通过添加已有节点方式加入 TKE 集群；再改 sglang 的镜像 tag，指定 CUDA 版本与节点匹配的 tag，如 `v0.4.3.post2-cu124`。

### kubectl 报错: status unknown for quota: tke-default-quota, resources: count/leaderworkersets.leaderworkerset.x-k8s.io

通过 kubectl apply 创建 `LeaderWorkerSet` 时报错：

```bash
$ kubectl apply --recursive -f deepseek-r1-a800.yaml
Error from server (Forbidden): error when creating "deepseek-r1-a800.yaml": leaderworkersets.leaderworkerset.x-k8s.io "deepseek-r1" is forbidden: status unknown for quota: tke-default-quota, resources: count/leaderworkersets.leaderworkerset.x-k8s.io


- **原因**：刚安装好 lws 组件不久，ResourceQuota 状态还没同步好。
- **解决方案**：等待一会儿再重试。
```
## 参考资料

- ModelScope 上的 DeepSeek-R1 模型列表: https://www.modelscope.cn/collections/DeepSeek-R1-c8e86ac66ed943


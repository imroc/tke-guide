# 在 TKE 上部署满血版 DeepSeek-R1 (SGLang)

:::warning[警告]

实践还在进行中，本文尚未完成！

:::

## 概述

[SGLang](https://docs.sglang.ai/) 与 [vLLM](https://docs.vllm.ai) 类似， 用于运行 AI 大模型，是性能卓越的新兴之秀，与 DeepSeek 官方合作并专门针对 DeepSeek 进行了深度优化，也是 DeepSeek 官方推荐的部署工具。

本文将基于 SGLang 在 TKE 集群上部署 DeepSeek-R1 模型，提供最佳实践的部署示例。

## 机型与部署方案

由于满血版的 DeepSeek-R1 参数量较大，需要用较大显存且支持 FP8 量化的大规格 GPU 实例，目前合适的机型有 [HCCPNV6](https://cloud.tencent.com/document/product/1646/81562#HCCPNV6)（[高性能计算集群](https://cloud.tencent.com/product/hcc)）和 [PNV6.32XLARGE1280 / PNV6.96XLARGE2304](https://cloud.tencent.com/document/product/560/19700#PNV6)（[GPU 云服务器](https://cloud.tencent.com/product/gpu)），推荐的部署方案是用两台该机型的节点组建 GPU 集群来运行满血 DeepSeek-R1（并发小的话一台也可以）。

:::info[注意]

该机型的实例正在邀测中，需联系您的销售经理开通使用并协调资源。

:::

## 镜像说明

本文中的示例使用的镜像是 SGLang 官方提供的镜像（[lmsysorg/sglang](https://hub.docker.com/r/lmsysorg/sglang/tags)），tag 为 latest，建议指定 tag 到固定版本。

官方镜像托管在 DockerHub，且体积较大，在 TKE 环境中，默认提供免费的 DockerHub 镜像加速服务。中国大陆用户也可以直接从 DockerHub 拉取镜像，但速度可能较慢，尤其是对于较大的镜像，等待时间会更长。为提高镜像拉取速度，建议将镜像同步至 [容器镜像服务 TCR](https://cloud.tencent.com/product/tcr)，并在 YAML 文件中替换相应的镜像地址，这样可以显著加快镜像的拉取速度。

## 操作步骤

### 购买 GPU 服务器

测试 POC 阶段，可先在 [云服务器购买页面](https://buy.cloud.tencent.com/cvm) 进行购买，支持按量计费。

:::info[注意]

对于 **PNV6.32XLARGE1280** 和 **PNV6.96XLARGE2304** 的机型，在**架构**为**异构计算**中找；对于 **HCCPNV6** 的机型，在**架构**为**高性能计算集群**中找，且需提前创建高性能计算集群，详情请参见 [创建高性能计算集群](https://cloud.tencent.com/document/product/1646/93026#3680502d-53cb-440e-8cf1-3eebbb7db3c5)。

:::

正式购买阶段，需通过 [高性能计算平台-工作空间](https://console.cloud.tencent.com/thpc/workspace/index) 购买，不支持按量计费，其规格与机型对照表如下：

| 规格              | 机型              | 是否支持 RDMA |
| ----------------- | ----------------- | ------------- |
| 96AS.32XLARGE1280 | PNV6.32XLARGE1280 | 不支持        |
| 96AS.32XLARGE1280 | PNV6.96XLARGE2304 | 不支持        |
| 96A               | HCCPNV6           | 支持          |

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

如需希望使用 kubectl 或 helm 等方式部署 LWS，可请参考 LWS 官方文档（[kubectl 方式安装](https://github.com/kubernetes-sigs/lws/blob/main/docs/setup/install.md) 和 [helm 方式安装](https://github.com/kubernetes-sigs/lws/blob/main/charts/lws/README.md)）。
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
        annotations:
          eks.tke.cloud.tencent.com/root-cbs-size: '100' # 如果调度到超级节点，默认系统盘只有 20Gi，sglang 镜像解压后会撑爆磁盘，用这个注解自定义一下系统盘容量（超过20Gi的部分会收费）。
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

使用 `LeaderWorkerSet` 部署满血版的 DeepSeek-R1 (2 台 8 卡的 GPU 节点)：

:::info[说明]

- `nvidia.com/gpu` 为单机 GPU 卡数，这里是 8 卡（leader 和 worker 保持一致）。
- `leaderWorkerTemplate.size` 为单个 GPU 集群的节点数，2 表示两个节点组成的 GPU 集群（1 个 leader 和 1 个 worker）。
- `replicas` 为 GPU 集群数量，这里是 1 个 GPU 集群，如需扩容，准备好节点资源后，调整这里的数量即可。
- `TOTAL_GPU` 为单个 GPU 集群的 GPU 总卡数（节点数量*单机 GPU 卡数），这里是 16 卡。
- `MODEL_DIRECTORY` 为模型文件的子目录路径。
- `MODEL_NAME` 为模型名称，API 调用将使用此模型名称进行交互。
- leader 和 worker 的环境变量需一致，如需调整记得将 leader 和 worker 的 template 都做相同的修改。
- 如果使用支持 RDMA 的机型，需使用 HostNetwork 才能让 RDMA 生效。

:::

```yaml showLineNumbers
apiVersion: leaderworkerset.x-k8s.io/v1
kind: LeaderWorkerSet
metadata:
  name: deepseek-r1
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
        hostNetwork: true # 如果使用 HCCPNV6 机型，支持 RDMA，需要使用 HostNetwork 才能让 RDMA 生效。
        hostPID: true
        dnsPolicy: ClusterFirstWithHostNet # 如果使用 HostNetwork，默认使用节点上 /etc/resolv.conf 中的 dns server，会导致 LWS_LEADER_ADDRESS 指定的域名解析失败，所以 dnsPolicy 指定为 ClusterFirstWithHostNet 以便使用 coredns 解析。
        containers:
        - name: leader
          image: lmsysorg/sglang:latest
          env:
          - name: TOTAL_GPU
            value: "16"
          - name: MODEL_DIRECTORY
            value: "DeepSeek-R1"
          - name: MODEL_NAME
            value: "DeepSeek-R1"
          command:
          - bash
          - -c
          - |
            set -x
            MODEL_DIRECTORY="${MODEL_DIRECTORY:-MODEL_NAME}"
            exec python3 -m sglang.launch_server \
              --model-path /data/$MODEL_DIRECTORY \
              --served-model-name $MODEL_NAME \
              --nnodes $LWS_GROUP_SIZE \
              --tp $TOTAL_GPU \
              --node-rank 0 \
              --dist-init-addr $(LWS_LEADER_ADDRESS):5000 \
              --log-requests \
              --enable-metric \
              --allow-auto-truncate \
              --watchdog-timeout 3600 \
              --disable-custom-all-reduce \
              --trust-remote-code \
              --host 0.0.0.0 \
              --port 30000
          resources:
            limits:
              nvidia.com/gpu: "8" # 每台节点 8 张 GPU 卡，每个 Pod 独占 1 台节点。
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
        - name: data
          persistentVolumeClaim:
            claimName: ai-model
    workerTemplate:
      spec:
        hostNetwork: true # worker 与 master 保持一致
        hostPID: true
        dnsPolicy: ClusterFirstWithHostNet # worker 与 master 保持一致
        containers:
        - name: worker
          image: lmsysorg/sglang:latest
          env:
          - name: ORDINAL_NUMBER
            valueFrom:
              fieldRef:
                fieldPath: metadata.labels['apps.kubernetes.io/pod-index']
          - name: TOTAL_GPU
            value: "16"
          - name: MODEL_DIRECTORY
            value: "DeepSeek-R1"
          - name: MODEL_NAME
            value: "DeepSeek-R1"
          command:
          - bash
          - -c
          - |
            set -x
            MODEL_DIRECTORY="${MODEL_DIRECTORY:-MODEL_NAME}"
            exec python3 -m sglang.launch_server \
              --model-path /data/$MODEL_DIRECTORY \
              --served-model-name $MODEL_NAME \
              --nnodes $LWS_GROUP_SIZE \
              --tp $TOTAL_GPU \
              --node-rank $ORDINAL_NUMBER \
              --dist-init-addr $(LWS_LEADER_ADDRESS):5000 \
              --log-requests \
              --enable-metric \
              --allow-auto-truncate \
              --watchdog-timeout 3600 \
              --disable-custom-all-reduce \
              --trust-remote-code
          resources:
            limits:
              nvidia.com/gpu: "8" # 每台节点 8 张 GPU 卡，每个 Pod 独占 1 台节点。
          volumeMounts:
          - mountPath: /dev/shm
            name: dshm
          - mountPath: /data
            name: data
        volumes:
        - name: dshm
          emptyDir:
            medium: Memory
        - name: data
          persistentVolumeClaim:
            claimName: ai-model
```

再创建一个 Service 用于 SGLang 提供的兼容 OpenAI 的 API：

:::info[注意]

- `leaderworkerset.sigs.k8s.io/name` 指定 lws 的名称。
- 所有 GPU 集群的 leader Pod 的 index 固定为 0，可以通过 `apps.kubernetes.io/pod-index: "0"` 这个 label 来选中，如果修改 `replicas` 扩容出新的 GPU 集群，新集群 leader 会被自动被该 Service 选中并负载均衡。
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

### kubectl 报错: status unknown for quota: tke-default-quota, resources: count/leaderworkersets.leaderworkerset.x-k8s.io

通过 kubectl apply 创建 `LeaderWorkerSet` 时报错：

```bash
$ kubectl apply --recursive -f deepseek-r1-a800.yaml
Error from server (Forbidden): error when creating "deepseek-r1-a800.yaml": leaderworkersets.leaderworkerset.x-k8s.io "deepseek-r1" is forbidden: status unknown for quota: tke-default-quota, resources: count/leaderworkersets.leaderworkerset.x-k8s.io
```

- **原因**：刚安装好 lws 组件不久，ResourceQuota 状态还没同步好。
- **解决方案**：等待一会儿再重试。
 

## 参考资料

- ModelScope 上的 DeepSeek-R1 模型列表: https://www.modelscope.cn/collections/DeepSeek-R1-c8e86ac66ed943
- 部署大模型常见问题: https://imroc.cc/tke/ai/faq

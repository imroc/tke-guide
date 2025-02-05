# 在 TKE 上部署 AI 大模型

## 概述

本文介绍如何在 TKE 上部署 AI 大模型，以 DeepSeek-R1 为例。

## 部署思路

使用 ollama 运行 AI 大模型，再通过 OpenWebUI 暴露一个聊天交互的界面，OpenWebUI 会调用 ollama 提供的 API 来与大模型交互。

## 为什么使用 ollama ?

ollama 可以看成 AI 领域的 docker，大模型可以看成 docker 镜像，所有大模型被标准化成相同格式，统一通过 ollama 来运行并提供 API，极大的简化了 AI 大模型部署的复杂度。

## AI 大模型如何存储？

AI 大模型通常占用体积较大，直接打包到容器镜像不太现实，如果启动时通过 `initContainers` 自动下载又会导致启动时间过长，因此建议使用共享存储来挂载 AI 大模型。

在腾讯云上可使用 CFS 来作为共享存储，CFS 的性能和可用性都非常不错，适合 AI 大模型的存储。本文将使用 CFS 来存储 AI 大模型。

## 准备 CFS 存储

在【组建管理】中的【存储】找到 `CFS-Turbo` 或 `CFS` 插件并安装：

<!--![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F05%2F20250205170858.png)-->
![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F05%2F20250205104156.png)

> `CFS-Turbo` 的性能更强，读写速度更快，也更贵，如果希望大模型运行速度更快，可以考虑使用 `CFS-Turbo`。

新建 `StorageClass`：

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F05%2F20250205105304.png)

1. 选项较多，所以该示例通过 TKE 控制台来创建 PVC。如希望通过 YAML 来创建，可先用控制台创建一个测试 PVC，再复制出生成的 YAML。
2. `Provisioner` 选 `文件存储CFS`。
3. `存储类型` 建议选 `性能存储`，读写速度比 `标准存储` 更快。

## 新建 GPU 节点池

在 TKE 控制台的【节点管理】-【节点池】中点击【新建】，如果【原生节点】或【普通节点】，机型在【GPU 机型】中选择一个没售罄的机型；如果选【超级节点】则无需选择机型（在部署的时候通过注解指定 GPU 类型）。

## 确认 GPU 驱动和所需 CUDA 版本

可随便买一台对应节点池机型的云服务器，上去执行 `nvidia-smi` 命令，查看 GPU 驱动版本。

在 nvidia 官网的 [CUDA Toolkit Release Notes](https://docs.nvidia.com/cuda/cuda-toolkit-release-notes/index.html) 中，查找适合对应 GPU 驱动版本的 CUDA 版本。

## 编译 ollama 镜像

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
  storageClassName: deepseek
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
  storageClassName: deepseek
  resources:
    requests:
      storage: 100Gi
```

## 使用 Job 下载 AI 大模型

下发一个 Job，将需要用的 AI 大模型下载到 CFS 共享存储中：

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: pull-model
  labels:
    app: pull-model
spec:
  template:
    metadata:
      name: pull-model
      labels:
        app: pull-model
    spec:
      containers:
      - name: pull-model
        image: imroc/ollama:cuda11.8-ubuntu22.04
        command:
        - bash
        - -c
        - |
          set -ex
          ollama serve &
          sleep 5
          ollama pull deepseek-r1:7b
        volumeMounts:
        - name: data
          mountPath: /root/.ollama
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: ai-model
      restartPolicy: OnFailure
```

1. 使用之前我们编译好的 ollama 镜像，执行一个脚本取下载 AI 大模型，本例中下载的是 deepseek-r1:7b，完整列表 [点击这里跳转](https://ollama.com/search)。
2. ollama 的模型数据存储在 `/root/.ollama` 目录下，挂载 CFS 类型的 PVC 到该路径。

## 部署 ollama

通过 Deployment 部署 ollama:

<Tabs>
  <TabItem value="ollama" label="原生节点或普通节点">
    <FileBlock file="ai/ollama.yaml" showLineNumbers />
  </TabItem>

  <TabItem value="ollama-eks" label="超级节点">
    <FileBlock file="ai/ollama-eks.yaml" showLineNumbers />
  </TabItem>
</Tabs>

1. ollama 的模型数据存储在 `/root/.ollama` 目录下，挂载已经下载好 AI 大模型的 CFS 类型 PVC 到该路径。
2. ollama 监听 11434 端口暴露 API，定义 Service 方便后续被 OpenWebUI 调用。
3. ollama 默认监听的是回环地址(127.0.0.1)，指定 `OLLAMA_HOST` 环境变量，强制对外暴露 11434 端口。
4. 运行大模型需要使用 GPU，因此在 requests/limits 中指定了 `nvidia.com/gpu` 资源，以便让 Pod 调度到 GPU 机型并分配 GPU 卡使用。
5. 如果希望大模型跑在超级节点，需通过 Pod 注解 `eks.tke.cloud.tencent.com/gpu-type` 指定 GPU 类型。

## 部署 OpenWebUI

使用 Deployment 部署 OpenWebUI，并定义 Service 方便后续对外暴露访问:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webui
spec:
  replicas: 1
  selector:
    matchLabels:
      app: webui
  template:
    metadata:
      labels:
        app: webui
    spec:
      containers:
      - name: webui
        image: imroc/open-webui:main # docker hub 中的 mirror 镜像，长期自动同步，可放心使用
        env:
        - name: OLLAMA_BASE_URL
          value: http://ollama:11434 # ollama 的地址
        - name: HF_HUB_OFFLINE
          value: "1"
        - name: ENABLE_OPENAI_API
          value: "false"
        tty: true
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: "500m"
            memory: "500Mi"
          limits:
            cpu: "1000m"
            memory: "1Gi"
        volumeMounts:
        - name: webui-volume
          mountPath: /app/backend/data
      volumes:
      - name: webui-volume
        persistentVolumeClaim:
          claimName: webui

---
apiVersion: v1
kind: Service
metadata:
  name: webui
  labels:
    app: webui
spec:
  type: ClusterIP
  ports:
  - port: 8080
    protocol: TCP
    targetPort: 8080
  selector:
    app: webui
```

1. `OLLAMA_BASE_URL` 是 ollama 的地址，填 ollama 的 service 访问地址。
2. `ENABLE_OPENAI_API` 填 `false`，因为我们使用的是 ollama，不需要使用 openai api，禁用它避免启动时因国内连不上 openapi 地址而无法加载模型（现象是登录 OpenWebUI 返回空白页）。
3. OpenWebUI 的数据存储在 `/app/backend/data` 目录（如账号密码、聊天历史等数据），我们挂载 PVC 到这个路径。

## 暴露 OpenWebUI 并访问

如果只是本地测试，可以使用 `kubectl port-forward` 暴露服务：

```bash
kubectl port-forward service/webui 8080:8080
```
在浏览器中访问 `http://127.0.0.1:8080` 即可。

你还可以通过 Ingress 或 Gateway API 来暴露，我这里通过 Gateway API 来暴露：

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

1. `parentRefs` 指定定义好的 `Gateway`（通常一个 Gateway 对应一个 CLB）。
2. `hostnames` 替换为你自己的域名，确保域名能正常解析到 Gateway 对应的 CLB 地址。
3. `backendRefs` 指定 OpenWebUI 的 Service。

最后在浏览器访问 `hostnames` 中的地址即可。

首次进入 OpenWebUI 会提示创建管理员账号密码，创建完毕后即可登录，然后默认会使用前面下载好的大模型进行对话。

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2025%2F02%2F05%2F20250205191427.png)

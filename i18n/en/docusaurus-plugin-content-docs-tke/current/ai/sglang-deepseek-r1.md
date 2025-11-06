# SGLang with DeepSeek R1 Deployment Guide

## Introduction

This guide explains how to deploy SGLang with DeepSeek R1 model on TKE for efficient language model serving.

## Prerequisites

### Environment Requirements
- Kubernetes cluster with GPU support
- NVIDIA GPU drivers installed
- Sufficient GPU memory for model loading

### Software Dependencies
- SGLang framework
- DeepSeek R1 model weights
- Python 3.8+ environment

## Deployment Steps

### 1. Model Preparation

Download DeepSeek R1 model weights:
```bash
# Download model weights
wget https://example.com/deepseek-r1-weights.tar.gz
tar -xzf deepseek-r1-weights.tar.gz
```

### 2. SGLang Configuration

Create SGLang configuration file:
```python
# sglang_config.py
import sglang as sgl

# Configure SGLang runtime
sgl.init(
    model_path="/path/to/deepseek-r1",
    gpu_memory_utilization=0.8,
    max_num_seqs=64,
    tensor_parallel_size=1
)
```

### 3. Kubernetes Deployment

Create deployment manifest:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sglang-deepseek-r1
spec:
  replicas: 2
  selector:
    matchLabels:
      app: sglang-deepseek
  template:
    metadata:
      labels:
        app: sglang-deepseek
    spec:
      containers:
      - name: sglang-server
        image: sglang-deepseek-r1:latest
        ports:
        - containerPort: 8000
        resources:
          limits:
            nvidia.com/gpu: 1
            memory: 16Gi
            cpu: 4
          requests:
            nvidia.com/gpu: 1
            memory: 16Gi
            cpu: 4
        volumeMounts:
        - name: model-weights
          mountPath: /models
      volumes:
      - name: model-weights
        persistentVolumeClaim:
          claimName: deepseek-model-pvc
```

## Service Configuration

### Load Balancer Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: sglang-service
spec:
  selector:
    app: sglang-deepseek
  ports:
  - port: 80
    targetPort: 8000
  type: LoadBalancer
```

### API Endpoints
- `/generate`: Text generation endpoint
- `/chat`: Chat completion endpoint
- `/health`: Health check endpoint

## Performance Optimization

### GPU Memory Optimization
- Use model quantization
- Implement memory-efficient attention
- Configure appropriate batch sizes

### Inference Optimization
- Enable KV cache optimization
- Use continuous batching
- Implement speculative decoding

## Monitoring and Logging

### Key Metrics
- Request latency
- Token generation speed
- GPU utilization
- Memory usage patterns

### Logging Configuration
```python
import logging

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
```

## Troubleshooting

### Common Issues
- GPU memory allocation failures
- Model loading errors
- Network connectivity issues

### Debug Commands
```bash
# Check GPU status
nvidia-smi

# Check container logs
kubectl logs <pod-name>

# Verify service connectivity
curl http://sglang-service/health
```
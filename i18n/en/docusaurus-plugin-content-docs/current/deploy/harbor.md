# Harbor Deployment Guide

## Overview

This guide provides instructions for deploying Harbor, an open-source container registry, on TKE. Harbor provides enterprise-level features including vulnerability scanning, image signing, and replication.

## Prerequisites

### Cluster Requirements
- Kubernetes cluster version 1.16+
- Persistent storage for registry data
- Load balancer for external access
- DNS configuration for Harbor domain

### Resource Requirements

**Minimum Requirements**:
- 4 CPU cores
- 8GB RAM
- 100GB storage

**Recommended for Production**:
- 8+ CPU cores
- 16GB+ RAM
- 500GB+ storage

## Deployment Methods

### Method 1: Helm Chart Installation

#### Add Harbor Helm Repository

```bash
helm repo add harbor https://helm.goharbor.io
helm repo update
```

#### Basic Installation

```bash
helm install harbor harbor/harbor \
  --namespace harbor \
  --create-namespace \
  --set expose.type=ingress \
  --set expose.tls.secretName=harbor-tls \
  --set externalURL=https://harbor.example.com \
  --set harborAdminPassword=Harbor12345
```

#### Advanced Configuration

```bash
helm upgrade --install harbor harbor/harbor \
  --namespace harbor \
  --set persistence.persistentVolumeClaim.registry.size=200Gi \
  --set persistence.persistentVolumeClaim.chartmuseum.size=20Gi \
  --set persistence.persistentVolumeClaim.jobservice.size=1Gi \
  --set persistence.persistentVolumeClaim.database.size=10Gi \
  --set persistence.persistentVolumeClaim.redis.size=5Gi \
  --set notary.enabled=true \
  --set trivy.enabled=true
```

### Method 2: Custom Kubernetes Manifests

#### Namespace Setup

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: harbor
  labels:
    name: harbor
```

#### Persistent Volume Claims

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: harbor-registry-pvc
  namespace: harbor
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 200Gi
  storageClassName: cbs-ssd
```

## Configuration

### Harbor Configuration

#### harbor.yml Configuration

```yaml
# Harbor configuration
hostname: harbor.example.com

# HTTP/HTTPS configuration
http:
  port: 80
https:
  port: 443
  certificate: /etc/harbor/ssl/tls.crt
  private_key: /etc/harbor/ssl/tls.key

# Database configuration
database:
  password: harbor_db_password
  max_idle_conns: 50
  max_open_conns: 100

# Registry configuration
registry:
  storage:
    filesystem:
      rootdirectory: /storage
```

### Ingress Configuration

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: harbor-ingress
  namespace: harbor
  annotations:
    kubernetes.io/ingress.class: "nginx"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
  - hosts:
    - harbor.example.com
    secretName: harbor-tls
  rules:
  - host: harbor.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: harbor-core
            port:
              number: 80
```

## Storage Configuration

### PostgreSQL Database

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: harbor-database
  namespace: harbor
spec:
  serviceName: harbor-database
  replicas: 1
  selector:
    matchLabels:
      app: harbor-database
  template:
    metadata:
      labels:
        app: harbor-database
    spec:
      containers:
      - name: postgresql
        image: postgres:13
        env:
        - name: POSTGRES_DB
          value: registry
        - name: POSTGRES_USER
          value: harbor
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: harbor-database-secret
              key: password
        volumeMounts:
        - name: database-data
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: database-data
        persistentVolumeClaim:
          claimName: harbor-database-pvc
```

### Redis Cache

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: harbor-redis
  namespace: harbor
spec:
  replicas: 1
  selector:
    matchLabels:
      app: harbor-redis
  template:
    metadata:
      labels:
        app: harbor-redis
    spec:
      containers:
      - name: redis
        image: redis:6.2
        command: ["redis-server", "--appendonly", "yes"]
        volumeMounts:
        - name: redis-data
          mountPath: /data
      volumes:
      - name: redis-data
        persistentVolumeClaim:
          claimName: harbor-redis-pvc
```

## Security Features

### Vulnerability Scanning

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: harbor-trivy
  namespace: harbor
spec:
  replicas: 1
  selector:
    matchLabels:
      app: harbor-trivy
  template:
    metadata:
      labels:
        app: harbor-trivy
    spec:
      containers:
      - name: trivy
        image: aquasec/trivy:latest
        env:
        - name: TRIVY_CACHE_DIR
          value: /home/scanner/.cache/trivy
        volumeMounts:
        - name: trivy-cache
          mountPath: /home/scanner/.cache/trivy
      volumes:
      - name: trivy-cache
        persistentVolumeClaim:
          claimName: harbor-trivy-pvc
```

### Image Signing (Notary)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: harbor-notary-server
  namespace: harbor
spec:
  replicas: 1
  selector:
    matchLabels:
      app: harbor-notary-server
  template:
    metadata:
      labels:
        app: harbor-notary-server
    spec:
      containers:
      - name: notary-server
        image: notary-server:latest
        env:
        - name: NOTARY_SERVER_DB_URL
          value: "postgres://notaryserver:password@harbor-database:5432/notaryserver"
```

## Integration with TKE

### Docker Configuration

Configure Docker to use Harbor registry:
```bash
# Update Docker daemon configuration
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<EOF
{
  "insecure-registries": ["harbor.example.com"]
}
EOF
sudo systemctl restart docker
```

### Kubernetes Image Pull Secret

Create secret for accessing private repositories:
```bash
kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=harbor.example.com \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  --namespace=default
```

## Backup and Recovery

### Backup Configuration

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: harbor-backup
  namespace: harbor
spec:
  schedule: "0 2 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: goharbor/harbor-core:latest
            command:
            - /bin/bash
            - -c
            - |
              # Backup Harbor data
              harbor-backup create
              # Upload to cloud storage
            volumeMounts:
            - name: backup-data
              mountPath: /backup
          restartPolicy: OnFailure
          volumes:
          - name: backup-data
            persistentVolumeClaim:
              claimName: harbor-backup-pvc
```

## Monitoring and Logging

### Prometheus Monitoring

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: harbor-monitor
  namespace: harbor
spec:
  selector:
    matchLabels:
      app: harbor
  endpoints:
  - port: http-metrics
    interval: 30s
```

### Log Aggregation

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: harbor-logging
  namespace: harbor
data:
  fluent.conf: |
    <source>
      @type tail
      path /var/log/harbor/*.log
      pos_file /var/log/fluentd/harbor.log.pos
      tag harbor.*
      format none
    </source>
```

## Security Considerations

### Network Policies

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: harbor-network-policy
  namespace: harbor
spec:
  podSelector:
    matchLabels:
      app: harbor
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: harbor
    ports:
    - protocol: TCP
      port: 80
    - protocol: TCP
      port: 443
    - protocol: TCP
      port: 5432
```

### SSL/TLS Configuration

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: harbor-tls
  namespace: harbor
type: kubernetes.io/tls
data:
  tls.crt: <base64-encoded-certificate>
  tls.key: <base64-encoded-private-key>
```

## Troubleshooting

### Common Issues

#### Pod Startup Issues
- Check resource limits and requests
- Verify persistent volume claims
- Inspect container logs

#### Database Connection Issues
- Verify PostgreSQL service availability
- Check database credentials
- Monitor database resource usage

#### SSL/TLS Issues
- Verify certificate validity
- Check ingress controller configuration
- Test SSL handshake

### Debug Commands

```bash
# Check Harbor pod status
kubectl get pods -n harbor

# Check service endpoints
kubectl get endpoints -n harbor

# Check ingress configuration
kubectl describe ingress harbor-ingress -n harbor

# Check logs
kubectl logs -n harbor -l app=harbor-core
```
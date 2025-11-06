# GitLab Deployment Guide

## Overview

This guide provides instructions for deploying GitLab on TKE, including configuration options, storage setup, and integration with TKE features.

## Prerequisites

### Cluster Requirements
- Kubernetes cluster with sufficient resources
- Persistent storage for GitLab data
- Load balancer for external access
- DNS configuration for GitLab domain

### Resource Requirements

**Minimum Requirements**:
- 4 CPU cores
- 8GB RAM
- 50GB storage

**Recommended for Production**:
- 8+ CPU cores
- 16GB+ RAM
- 100GB+ storage

## Deployment Methods

### Method 1: Helm Chart Installation

#### Add GitLab Helm Repository

```bash
helm repo add gitlab https://charts.gitlab.io/
helm repo update
```

#### Basic Installation

```bash
helm install gitlab gitlab/gitlab \
  --namespace gitlab \
  --create-namespace \
  --set global.hosts.domain=example.com \
  --set global.hosts.externalIP=192.168.1.100 \
  --set certmanager-issuer.email=admin@example.com
```

#### Advanced Configuration

```bash
helm upgrade --install gitlab gitlab/gitlab \
  --namespace gitlab \
  --set global.edition=ce \
  --set global.hosts.https=false \
  --set global.ingress.configureCertmanager=false \
  --set gitlab-runner.runners.privileged=false \
  --set postgresql.persistence.size=100Gi \
  --set redis.persistence.size=10Gi \
  --set gitlab.gitaly.persistence.size=200Gi
```

### Method 2: Custom Kubernetes Manifests

#### Namespace Setup

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: gitlab
  labels:
    name: gitlab
```

#### Persistent Volume Claims

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: gitlab-data
  namespace: gitlab
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
  storageClassName: cbs-ssd
```

## Configuration

### GitLab Configuration

#### gitlab.rb Configuration

```ruby
external_url 'https://gitlab.example.com'

# Database configuration
gitlab_rails['db_adapter'] = 'postgresql'
gitlab_rails['db_encoding'] = 'unicode'

# Redis configuration
redis['bind'] = '127.0.0.1'
redis['port'] = 6379

# SMTP configuration
gitlab_rails['smtp_enable'] = true
gitlab_rails['smtp_address'] = "smtp.example.com"
gitlab_rails['smtp_port'] = 587
```

### Ingress Configuration

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: gitlab-ingress
  namespace: gitlab
  annotations:
    kubernetes.io/ingress.class: "nginx"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
  - hosts:
    - gitlab.example.com
    secretName: gitlab-tls
  rules:
  - host: gitlab.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: gitlab-webservice
            port:
              number: 80
```

## Storage Configuration

### PostgreSQL Database

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgresql
  namespace: gitlab
spec:
  serviceName: postgresql
  replicas: 1
  selector:
    matchLabels:
      app: postgresql
  template:
    metadata:
      labels:
        app: postgresql
    spec:
      containers:
      - name: postgresql
        image: postgres:13
        env:
        - name: POSTGRES_DB
          value: gitlab
        - name: POSTGRES_USER
          value: gitlab
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgresql-secret
              key: password
        volumeMounts:
        - name: postgresql-data
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: postgresql-data
        persistentVolumeClaim:
          claimName: postgresql-pvc
```

### Redis Cache

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: gitlab
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
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
          claimName: redis-pvc
```

## GitLab Runner Integration

### Runner Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitlab-runner
  namespace: gitlab
spec:
  replicas: 2
  selector:
    matchLabels:
      app: gitlab-runner
  template:
    metadata:
      labels:
        app: gitlab-runner
    spec:
      containers:
      - name: gitlab-runner
        image: gitlab/gitlab-runner:latest
        env:
        - name: CI_SERVER_URL
          value: "https://gitlab.example.com"
        - name: RUNNER_REGISTRATION_TOKEN
          valueFrom:
            secretKeyRef:
              name: gitlab-runner-secret
              key: registration-token
        volumeMounts:
        - name: runner-config
          mountPath: /etc/gitlab-runner
      volumes:
      - name: runner-config
        configMap:
          name: gitlab-runner-config
```

## Backup and Recovery

### Backup Configuration

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: gitlab-backup
  namespace: gitlab
spec:
  schedule: "0 2 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: gitlab/gitlab-ce:latest
            command:
            - /bin/bash
            - -c
            - |
              gitlab-backup create
              # Upload to cloud storage
              # aws s3 cp backup.tar s3://gitlab-backups/
            volumeMounts:
            - name: backup-data
              mountPath: /var/opt/gitlab/backups
          restartPolicy: OnFailure
          volumes:
          - name: backup-data
            persistentVolumeClaim:
              claimName: backup-pvc
```

## Monitoring and Logging

### Prometheus Monitoring

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: gitlab-monitor
  namespace: gitlab
spec:
  selector:
    matchLabels:
      app: gitlab
  endpoints:
  - port: web
    interval: 30s
```

### Log Aggregation

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: gitlab-logging
  namespace: gitlab
data:
  fluent.conf: |
    <source>
      @type tail
      path /var/log/gitlab/*.log
      pos_file /var/log/fluentd/gitlab.log.pos
      tag gitlab.*
      format none
    </source>
```

## Security Considerations

### Network Policies

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: gitlab-network-policy
  namespace: gitlab
spec:
  podSelector:
    matchLabels:
      app: gitlab
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: gitlab
    ports:
    - protocol: TCP
      port: 80
    - protocol: TCP
      port: 443
```

### Secret Management

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-secrets
  namespace: gitlab
type: Opaque
data:
  postgres-password: <base64-encoded-password>
  redis-password: <base64-encoded-password>
  smtp-password: <base64-encoded-password>
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
# Check GitLab pod status
kubectl get pods -n gitlab

# Check service endpoints
kubectl get endpoints -n gitlab

# Check ingress configuration
kubectl describe ingress gitlab-ingress -n gitlab

# Check logs
kubectl logs -n gitlab -l app=gitlab
```
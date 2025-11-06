# Cert-Manager Deployment Guide

## Overview

This guide provides instructions for deploying and configuring cert-manager on TKE to automate TLS certificate management for applications.

## Prerequisites

### Cluster Requirements
- Kubernetes cluster version 1.16+
- Cluster-admin permissions
- Access to certificate issuer (Let's Encrypt, internal CA, etc.)

### Network Requirements
- Internet access for Let's Encrypt validation
- DNS configuration for domain validation
- Proper firewall rules for HTTP-01/HTTP-01 challenges

## Installation

### Method 1: Helm Installation

```bash
# Add jetstack helm repository
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install cert-manager
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.13.0 \
  --set installCRDs=true
```

### Method 2: kubectl Installation

```bash
# Install Custom Resource Definitions (CRDs)
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.13.0/cert-manager.crds.yaml

# Create namespace
kubectl create namespace cert-manager

# Install cert-manager
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.13.0/cert-manager.yaml
```

## Configuration

### Cluster Issuer Configuration

#### Let's Encrypt Production

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-private-key
    solvers:
    - http01:
        ingress:
          class: nginx
```

#### Let's Encrypt Staging

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-staging-private-key
    solvers:
    - http01:
        ingress:
          class: nginx
```

### Issuer Configuration (Namespace-scoped)

```yaml
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: letsencrypt-issuer
  namespace: my-app
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-private-key
    solvers:
    - http01:
        ingress:
          class: nginx
```

## Certificate Management

### Basic Certificate

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: example-com-tls
  namespace: default
spec:
  secretName: example-com-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  commonName: example.com
  dnsNames:
  - example.com
  - www.example.com
```

### Wildcard Certificate

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-example-com-tls
  namespace: default
spec:
  secretName: wildcard-example-com-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  commonName: "*.example.com"
  dnsNames:
  - "*.example.com"
```

## Integration with Ingress

### Automatic TLS with Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app-ingress
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
  - hosts:
    - example.com
    secretName: example-com-tls
  rules:
  - host: example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app
            port:
              number: 80
```

### Manual Certificate Reference

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app-ingress
spec:
  tls:
  - hosts:
    - example.com
    secretName: example-com-tls
  rules:
  - host: example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app
            port:
              number: 80
```

## Challenge Solvers

### HTTP-01 Challenge

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-http01
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-private-key
    solvers:
    - http01:
        ingress:
          class: nginx
```

### DNS-01 Challenge

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-dns01
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-private-key
    solvers:
    - dns01:
        cloudflare:
          email: admin@example.com
          apiKeySecretRef:
            name: cloudflare-api-key
            key: api-key
```

## Monitoring and Troubleshooting

### Check Certificate Status

```bash
# List certificates
kubectl get certificates --all-namespaces

# Describe certificate details
kubectl describe certificate example-com-tls

# Check certificate orders
kubectl get orders --all-namespaces

# Check challenges
kubectl get challenges --all-namespaces
```

### Common Issues

#### Certificate Not Issuing
- Check issuer status: `kubectl describe clusterissuer letsencrypt-prod`
- Verify DNS configuration
- Check challenge solver configuration

#### Certificate Renewal Issues
- Check certificate expiration
- Verify issuer configuration
- Monitor renewal events

### Logs and Debugging

```bash
# Check cert-manager pod logs
kubectl logs -n cert-manager -l app=cert-manager

# Check webhook logs
kubectl logs -n cert-manager -l app=webhook

# Check cainjector logs
kubectl logs -n cert-manager -l app=cainjector
```

## Best Practices

### Security

- Use separate issuers for production and staging
- Secure private keys with proper RBAC
- Implement certificate rotation policies

### Performance

- Monitor certificate renewal cycles
- Use appropriate challenge types based on environment
- Implement backup and recovery procedures

### Maintenance

- Regularly update cert-manager to latest version
- Monitor certificate expiration dates
- Test certificate renewal procedures

## Advanced Configurations

### Certificate Duration and Renewal

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: long-duration-cert
spec:
  secretName: long-duration-tls
  duration: 2160h # 90 days
  renewBefore: 360h # 15 days before expiration
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  commonName: example.com
  dnsNames:
  - example.com
```

### Private CA Integration

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: private-ca
spec:
  ca:
    secretName: private-ca-secret
```
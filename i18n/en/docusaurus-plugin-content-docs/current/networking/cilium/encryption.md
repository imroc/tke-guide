# Enable Communication Encryption

## Overview

This article describes how to use Cilium to encrypt traffic.

## What encryption methods are available?

Cilium supports the following encryption methods:

- ipsec (default)
- wireguard (requires the wireguard kernel module to be installed in the kernel)
- ztunnel (available when co-existing with Istio ambient mode)

If Pods use VPC-CNI networking, ipsec encryption cannot be used. Wireguard encryption is recommended instead.

## Enable WireGuard Encryption

The prerequisite for using wireguard encryption is that the wireguard kernel module is installed in the kernel (known to be available in TencentOS 4).

To enable wireguard encryption:

```bash
helm upgrade cilium cilium/cilium --version 1.19.4 \
  --namespace kube-system \
  --reuse-values \
  --set encryption.enabled=true \
  --set encryption.type=wireguard
```

## References

- [Cilium Transparent Encryption](https://docs.cilium.io/en/stable/security/network/encryption/)

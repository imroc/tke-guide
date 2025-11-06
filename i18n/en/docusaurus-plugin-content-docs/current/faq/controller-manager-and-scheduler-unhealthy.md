---
sidebar_position: 2
---

# Controller-manager and Scheduler Status Showing Unhealthy

## Background

Some locations show TKE cluster's controller-manager and scheduler components as Unhealthy, such as when using `kubectl get cs` to view:

```bash
$ kubectl get cs
NAME                 STATUS      MESSAGE                                                                                       ERROR
scheduler            Unhealthy   Get "http://127.0.0.1:10251/healthz": dial tcp 127.0.0.1:10251: connect: connection refused
controller-manager   Unhealthy   Get "http://127.0.0.1:10252/healthz": dial tcp 127.0.0.1:10252: connect: connection refused
etcd-0               Healthy     {"health":"true"}
```

Or when viewing with Rancher:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2023%2F09%2F25%2F20230925161905.png)

## Cause

This is because TKE managed clusters have master components deployed separately - apiserver, controller-manager, and scheduler are not on the same machine. The status of controller-manager and scheduler is probed by apiserver, and the probing code is hardcoded to connect directly to localhost:

```go
func (s componentStatusStorage) serversToValidate() map[string]*componentstatus.Server {
    serversToValidate := map[string]*componentstatus.Server{
        "controller-manager": {Addr: "127.0.0.1", Port: ports.InsecureKubeControllerManagerPort, Path: "/healthz"},
        "scheduler":          {Addr: "127.0.0.1", Port: ports.InsecureSchedulerPort, Path: "/healthz"},
    }
```

This is just a display issue and doesn't affect functionality.

## Related Links

* Probe code connecting directly to localhost: https://github.com/kubernetes/kubernetes/blob/v1.14.3/pkg/registry/core/rest/storage_core.go#L256
* Kubernetes issue: https://github.com/kubernetes/kubernetes/issues/19570
* Rancher issue: https://github.com/rancher/rancher/issues/11496
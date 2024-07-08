# 在 TKE 上安装 OpenKruiseGame

## 安装方法

在 TKE 上安装 OpenKruiseGame 并无特殊之处，可直接参考 [OpenKruiseGame 官方安装文档](https://openkruise.io/zh/kruisegame/installation) 进行安装。


## 踩坑分享

本人使用默认配置安装 OpenKruiseGame 的时候（v0.8.0），`kruise-game-controller-manager` 的 Pod 起不来：

```log
I0708 03:28:11.315405       1 request.go:601] Waited for 1.176544858s due to client-side throttling, not priority and fairness, request: GET:https://172.16.128.1:443/apis/operators.coreos.com/v1alpha2?timeout=32s
I0708 03:28:21.315900       1 request.go:601] Waited for 11.176584459s due to client-side throttling, not priority and fairness, request: GET:https://172.16.128.1:443/apis/install.istio.io/v1alpha1?timeout=32s
```

是因为 OpenKruiseGame 的 helm chart 包中，默认的本地 APIServer 限速太低 (`values.yaml`):

```yaml
kruiseGame:
  apiServerQps: 5
  apiServerQpsBurst: 10
```

可以改高点：

```yaml
kruiseGame:
  apiServerQps: 50
  apiServerQpsBurst: 100
```

## 参考资料

* [OpenKruiseGame 官方安装文档](https://openkruise.io/zh/kruisegame/installation)

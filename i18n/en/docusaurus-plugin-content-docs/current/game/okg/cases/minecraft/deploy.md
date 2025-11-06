# Quick Deployment

## Installing OpenKruiseGame

Installing OpenKruiseGame on TKE has no special requirements. You can directly refer to the [OpenKruiseGame Official Installation Documentation](https://openkruise.io/kruisegame/installation) for installation.

When I installed OpenKruiseGame with default configuration (v0.8.0), the `kruise-game-controller-manager` Pod failed to start:

```log
I0708 03:28:11.315405       1 request.go:601] Waited for 1.176544858s due to client-side throttling, not priority and fairness, request: GET:https://172.16.128.1:443/apis/operators.coreos.com/v1alpha2?timeout=32s
I0708 03:28:21.315900       1 request.go:601] Waited for 11.176584459s due to client-side throttling, not priority and fairness, request: GET:https://172.16.128.1:443/apis/install.istio.io/v1alpha1?timeout=32s
```

This is because the default local APIServer rate limiting in OpenKruiseGame's helm chart package is too low (`values.yaml`):

```yaml
kruiseGame:
  apiServerQps: 5
  apiServerQpsBurst: 10
```

You can increase it:

```yaml
kruiseGame:
  apiServerQps: 50
  apiServerQpsBurst: 100
```

## minecraft-server Container Image

[docker-minecraft-server](https://github.com/itzg/docker-minecraft-server) is an open-source project for the server-side container image of the Minecraft game, which can be deployed on Kubernetes. This image is hosted on DockerHub and can be pulled directly in TKE environments. This image will be used for deployment below.

## Deploying Minecraft with GameServerSet

```yaml
apiVersion: game.kruise.io/v1alpha1
kind: GameServerSet
metadata:
  name: minecraft
spec:
  replicas: 3
  updateStrategy:
    rollingUpdate:
      podUpdatePolicy: InPlaceIfPossible
  gameServerTemplate:
    spec:
      volumes:
        - name: script
          configMap:
            name: minecraft-script
            defaultMode: 0755
      containers:
        - image: itzg/minecraft-server:latest
          name: minecraft
          env:
            - name: EULA
              value: "TRUE"
            - name: ONLINE_MODE
              value: "FALSE"
```

* `EULA` needs to be explicitly set to `TRUE`, indicating agreement with Microsoft's terms.
* If not purchasing the official Minecraft version to connect to the game server, `ONLINE_MODE` needs to be set to `FALSE` to skip Microsoft's player authentication.

## References

* [KruiseGame User Manual: Deploying Game Servers](https://openkruise.io/kruisegame/user-manuals/deploy-gameservers)

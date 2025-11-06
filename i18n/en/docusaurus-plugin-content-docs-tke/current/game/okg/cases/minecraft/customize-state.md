# Customizing Game Server State

## Overview

Games are stateful services. OpenKruiseGame allows defining game server states, and developers can set corresponding handling actions based on different game server states. For example, when scaling down, only scale down idle game server Pods (no players in that room).

## Detection Script

The container image of [docker-minecraft-server](https://github.com/itzg/docker-minecraft-server) provides the `mc-health` script. Executing it can detect the status of minecraft-server, including statistics on the number of online players:

```bash
$ mc-health
localhost:25565 : version=1.21 online=1 max=20 motd='A Minecraft Server'
```

We can write another script as a wrapper to detect whether the game server is idle. When `online=0` is detected, return an exit code of 0, indicating the game server is idle:

```bash title="idle.sh"
#!/bin/bash

result=$(mc-health | grep "online=0")

if [ "$result" != "" ]; then
  exit 0
fi

exit 1
```

Eventually, this script needs to be placed in a `ConfigMap`. If you deploy using `kustomize`, you can use `configMapGenerator` in `kustomization.yaml` to reference this script file and generate the corresponding `ConfigMap`:

```yaml title="kustomization.yaml"
configMapGenerator:
  - name: minecraft-script
    options:
      disableNameSuffixHash: true
    files:
      - idle.sh
```

## Customizing Service Quality in GameServerSet

Focus on the highlighted sections:

```yaml showLineNumbers
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
    volumeClaimTemplates:
      - metadata:
          name: minecraft
        spec:
          accessModes: ["ReadWriteOnce"]
          storageClassName: minecraft
          resources:
            requests:
              storage: 20Gi
    spec:
      # highlight-start
      volumes: # Reference ConfigMap for idle.sh script file
        - name: script
          configMap:
            name: minecraft-script
            defaultMode: 0755
      # highlight-end
      containers:
        - image: itzg/minecraft-server:latest
          name: minecraft
          volumeMounts:
            # highlight-start
            - name: script # Mount idle.sh script file
              mountPath: /idle.sh
              subPath: idle.sh
            # highlight-end
            - name: minecraft
              mountPath: /data
          env:
            - name: EULA
              value: "TRUE"
            - name: ONLINE_MODE
              value: "FALSE"
  # highlight-start
  serviceQualities:
    - name: idle
      containerName: minecraft
      permanent: false
      exec:
        command: ["bash", "/idle.sh"] # Use idle.sh detection to determine opsState
      serviceQualityAction:
        - state: true
          opsState: WaitToBeDeleted # When idle.sh returns 0, set opsState to WaitToBeDeleted. During rolling updates, delete Pod only when this state is detected, achieving "upgrade game server when idle"
        - state: false
          opsState: None
  # highlight-end
```

## Testing and Observing opsState

After connecting to the game server with the client, execute the following command to view the `opsState` of each game server:

```bash
$ kubectl get gameserver
NAME          STATE   OPSSTATE          DP    UP    AGE
minecraft-0   Ready   WaitToBeDeleted   0     0     68m
minecraft-1   Ready   None              0     0     69m
minecraft-2   Ready   WaitToBeDeleted   0     0     70m
```

> Among them, `None` indicates that players are playing on that server, and `WaitToBeDeleted` indicates that the server has no players and can be scaled down.

## References

* [KruiseGame User Manual: Custom Service Quality](https://openkruise.io/kruisegame/user-manuals/service-qualities)

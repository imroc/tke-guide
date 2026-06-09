# Enhanced Observability with Cilium

## One-Click Enable Hubble

If Hubble Relay and Hubble UI were not enabled during Cilium installation, use the one-click script to quickly enable them:

```bash
bash -c "$(curl -sfL https://raw.githubusercontent.com/imroc/tke-guide/main/static/scripts/cilium.sh)" -- enable-hubble
```

The script runs `helm upgrade --reuse-values --set hubble.relay.enabled=true --set hubble.ui.enabled=true` and restarts cilium-agent / operator. The following sections provide manual commands for enabling each component, for reference as needed.

## Enable Hubble Relay

Hubble consists of Hubble Server and Hubble Relay. Hubble Server is built into the cilium-agent on each node and is enabled by default. Hubble Relay is a separately deployed component that aggregates data from all Hubble Servers across the cluster, providing a unified API entry point.

Use the following command to enable Hubble Relay:

```bash
helm upgrade cilium cilium/cilium --version 1.19.4 \
   --namespace kube-system \
   --reuse-values \
   --set hubble.relay.image.repository=quay.tencentcloudcr.com/cilium/hubble-relay \
   --set hubble.relay.enabled=true
```

Verify Hubble is enabled and running correctly with `cilium status`:

```bash showLineNumbers
$ cilium status
    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    OK
               # highlight-next-line
 \__/¯¯\__/    Hubble Relay:       OK
    \__/       ClusterMesh:        disabled

DaemonSet              cilium                   Desired: 3, Ready: 3/3, Available: 3/3
DaemonSet              cilium-envoy             Desired: 3, Ready: 3/3, Available: 3/3
Deployment             cilium-operator          Desired: 2, Ready: 2/2, Available: 2/2
                       # highlight-next-line
Deployment             hubble-relay             Desired: 1, Ready: 1/1, Available: 1/1
Containers:            cilium                   Running: 3
                       cilium-envoy             Running: 3
                       cilium-operator          Running: 2
                       clustermesh-apiserver
                       # highlight-next-line
                       hubble-relay             Running: 1
Cluster Pods:          4/4 managed by Cilium
Helm chart version:    1.19.4
Image versions         cilium             quay.tencentcloudcr.com/cilium/cilium:v1.19.4@sha256:5649db451c88d928ea585514746d50d91e6210801b300c897283ea319d68de15: 3
                       cilium-envoy       quay.tencentcloudcr.com/cilium/cilium-envoy:v1.34.10-1761014632-c360e8557eb41011dfb5210f8fb53fed6c0b3222@sha256:ca76eb4e9812d114c7f43215a742c00b8bf41200992af0d21b5561d46156fd15: 3
                       cilium-operator    quay.tencentcloudcr.com/cilium/operator-generic:v1.19.4@sha256:b5a0138e1a38e4437c5215257ff4e35373619501f4877dbaf92c89ecfad81797: 2
                       hubble-relay       quay.tencentcloudcr.com/cilium/hubble-relay:v1.19.4@sha256:e53e00c47fe4ffb9c086bad0c1c77f23cb968be4385881160683d9e15aa34dc3: 1
```

## Install Hubble Client

The Hubble client is used to interact with the Hubble Relay API. Refer to [Install the Hubble Client](https://docs.cilium.io/en/stable/observability/hubble/setup/#install-the-hubble-client) to install the `hubble` binary (Hubble client) on your local machine.

After installation, verify that the Hubble client can access the Hubble API:

```bash
$ hubble status -P
Healthcheck (via 127.0.0.1:4245): Ok
Current/Max Flows: 12,285/12,285 (100.00%)
Flows/s: 26.42
Connected Nodes: 3/3
```

## Enable Hubble UI

Hubble UI provides a visual view of the cluster's service topology.

Use the following command to enable Hubble UI:

```bash
helm upgrade cilium cilium/cilium --version 1.19.4 \
   --namespace kube-system \
   --reuse-values \
   --set hubble.relay.enabled=true \
   --set hubble.ui.enabled=true \
   --set hubble.ui.backend.image.repository=quay.tencentcloudcr.com/cilium/hubble-ui-backend \
   --set hubble.ui.frontend.image.repository=quay.tencentcloudcr.com/cilium/hubble-ui
```

Confirm the Hubble UI Pod is running:

```bash
$ kubectl --namespace=kube-system get pod -l app.kubernetes.io/name=hubble-ui
NAME                         READY   STATUS    RESTARTS   AGE
hubble-ui-5dd5877df5-8c69k   2/2     Running   0          5m41s

```

Then run `cilium hubble ui` to automatically open the browser and view the cluster's service topology.

```bash
$ cilium hubble ui
ℹ  Opening "http://localhost:12000" in your browser...
```

For more details, see [Network Observability with Hubble / Service Map & Hubble UI](https://docs.cilium.io/en/stable/observability/hubble/hubble-ui/).

## Auditing Network Flow Logs

If you need to audit network packets (e.g., for troubleshooting or security auditing), see [Cilium + CLS for Network Flow Log Audit](flow-logs.md).

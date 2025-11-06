# Migrating from TCM to Self-built Istio

## Overview

Tencent Cloud Mesh (TCM) is istio managed service based on TKE, will be discontinued in the future. This article introduces how to migrate from TCM to self-built istio.

## Migration Approach

Istio architecture consists of control plane and data plane. Control plane is istiod, data plane is gateways (istio-ingressgateway/istio-egressgateway) or sidecars. Data plane essentially uses Envoy as proxy program, control plane distributes computed traffic rules to data plane via `xDS`:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F06%2F18%2F20240618150336.png)

TCM mainly manages isitod. Migration key point is replacing TCM's isitod with self-built istiod. But due to root certificate issues, they cannot coexist, preventing in-place smooth migration. Only option is creating new environment for self-built istio, gradually migrating services to new istio environment, cutting traffic gradually. Before full migration completion, both environments need coexistence:

![](https://image-host-1251893006.cos.ap-chengdu.myqcloud.com/2024%2F06%2F18%2F20240618170536.png)

## Istio Installation Principles

We install and upgrade mesh via `istioctl` command. Each cluster uses declarative YAML `IstioOperator` to maintain istio installation configuration, mainly including control plane and ingressgateway component installation and configuration.

> Using multiple `IstioOperator` YAMLs for same cluster for maintenance may cause unrelated components or configurations being deleted or overwritten during updates.

## Downloading Istio Release Version

Refer to [istio official documentation](https://istio.io/latest/docs/setup/getting-started/#download) to download istio release version. If avoiding compatibility issues during migration, download istio release version same as TCM:

```bash
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.18.5 sh -
```

Then install `istioctl` to `PATH`:

```bash
cp istio-1.18.5/bin/istioctl /usr/local/bin/istioctl
```

## Installing Istiod

Select one TKE cluster as primary cluster to install istiod. Prepare deployment configuration `master-cluster.yaml`:
```yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  components:
    ingressGateways:
    - enabled: false
      name: istio-ingressgateway
  values:
    pilot:
      env:
        EXTERNAL_ISTIOD: true
    global:
      meshID: mesh1
      multiCluster:
        clusterName: cls-dxgdg1rl
      network: main
```

* `meshID` fill according to preference.
* `clusterName` can fill current TKE cluster's cluster ID.

Ensure kubeconfig context switches to cluster installing istiod (primary cluster), execute installation:

```bash
istioctl install -f master-cluster.yaml
```

After installation, check if istiod Pod runs normally:

```bash
$ kubectl get pod -n istio-system
NAME                      READY   STATUS    RESTARTS   AGE
istiod-6b785b7b89-zblbw   1/1     Running   0          6m31s
```

## Exposing Istiod Control Plane

If more TKE clusters need joining this mesh, need to expose primary cluster's istiod via east-west gateway. Exposure method: create east-west gateway in primary cluster, add `ingressGateways` configuration under `IstioOperator`'s `components`:

```yaml showLineNumbers title="master-cluster.yaml"
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  name: eastwest
spec:
  # highlight-start
  components:
    ingressGateways:
      - name: istio-eastwestgateway
        label:
          istio: eastwestgateway
          app: istio-eastwestgateway
          topology.istio.io/network: main
        enabled: true
        k8s:
          env:
            - name: ISTIO_META_REQUESTED_NETWORK_VIEW
              value: main
          serviceAnnotations:
            service.kubernetes.io/tke-existed-lbid: "lb-lujb6a5a" # Specify manually created internal CLB
            # service.kubernetes.io/qcloud-loadbalancer-internal-subnetid: "subnet-oz2k2du5" # Auto-create CLB, need subnet ID
          service:
            ports:
              - name: status-port
                port: 15021
                targetPort: 15021
              - name: tls
                port: 15443
                targetPort: 15443
              - name: tls-istiod
                port: 15012
                targetPort: 15012
              - name: tls-webhook
                port: 15017
                targetPort: 15017
  # highlight-end
  values:
    pilot:
      env:
        EXTERNAL_ISTIOD: true
    global:
      meshID: mesh-mn8gnn1g
      multiCluster:
        clusterName: cls-dxgdg1rl
      network: main
```

East-west gateway exposes traffic via `LoadBalancer`-type Service. In TKE environment, defaults to public CLB creation. Our east-west gateway needs internal CLB exposure. On TKE, add annotations to Service for internal CLB specification:
* Add annotations to east-west gateway's Service via `serviceAnnotations`.
* Two methods for specifying internal CLB: directly specify existing internal CLB's ID, or specify subnet ID for auto-created CLB, refer to example writing.

After preparing east-west gateway configuration, update primary cluster's istio installation configuration:

```bash
istioctl upgrade -f master-cluster.yaml
```

After installation, get external IP address (`EXTERNAL-IP`):

```bash
$ kubectl get svc istio-eastwestgateway -n istio-system
NAME                    TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)                                                           AGE
istio-eastwestgateway   LoadBalancer   192.168.6.166   10.0.250.58   15021:31386/TCP,15443:31315/TCP,15012:30468/TCP,15017:30728/TCP   55s
```

Finally, configure forwarding rules for exposing istiod control plane:

```bash
kubectl apply -n istio-system -f ./samples/multicluster/expose-istiod.yaml
```

## Managing Other TKE Clusters

First switch kubeconfig context to TKE cluster being managed, then prepare `member-cluster-1.yaml`:

```yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  profile: remote
  values:
    global:
      meshID: mesh1
      multiCluster:
        clusterName: cls-ne1cw84b
      network: main
      remotePilotAddress: 10.0.250.58
```

* `remotePilotAddress` fill internal CLB IP address obtained earlier for `istio-eastwestgateway`.
* `clusterName` can write current managed cluster's ID.

Apply this configuration to TKE cluster being managed:

```bash
istioctl install -f member-cluster-1.yaml
```

> This operation sets current cluster as member cluster, deploying MutatingAdmissionWebhook (Sidecar auto-injection) and istiod Service (pointing to primary cluster's east-west gateway internal CLB) to cluster.

Then switch context back to primary cluster, execute final configuration:

```bash
istioctl create-remote-secret --name=cls-ne1cw84b | kubectl apply -f -
```

> `name` is current managed TKE cluster's ID.

## Deploying Istio-ingressgateway

We maintain one `IstioOperator` YAML file per cluster. To install Ingress Gateway in which cluster, add `ingressGateways` configuration to that cluster's corresponding `IstioOperator` file. For example, deploy in member cluster, modify `member-cluster-1.yaml`:

```yaml showLineNumbers title="member-cluster-1.yaml"
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  # highlight-start
  components:
    ingressGateways:
      - name: istio-ingressgateway
        enabled: true
      - name: istio-ingressgateway-staging
        namespace: staging # If namespace doesn't exist, need to create beforehand
        enabled: true
      - name: istio-ingressgateway-intranet
        enabled: true
        k8s:
          serviceAnnotations:
            service.kubernetes.io/qcloud-loadbalancer-internal-subnetid: "subnet-19exjv5n"
  # highlight-end
  profile: remote
  values:
    global:
      meshID: mesh1
      multiCluster:
        clusterName: cls-ne1cw84b
      network: main
      remotePilotAddress: 10.0.250.110
```

Use istioctl to upgrade:

```bash
istioctl upgrade -f member-cluster-1.yaml
```

After successful deployment, check corresponding CLB and Pod status:

```bash
$ kubectl get svc -A | grep ingressgateway
istio-system   istio-ingressgateway            LoadBalancer   192.168.6.172   111.231.152.197                  15021:32500/TCP,80:30148/TCP,443:31128/TCP   2m25s
istio-system   istio-ingressgateway-intranet   LoadBalancer   192.168.6.217   10.0.0.12                        15021:30839/TCP,80:30482/TCP,443:30576/TCP   2m25s
staging        istio-ingressgateway-staging    LoadBalancer   192.168.6.110   111.231.156.200                  15021:31773/TCP,80:31942/TCP,443:32631/TCP   2m8s

$ kubectl get pod -A | grep ingressgateway
istio-system   istio-ingressgateway-58889f648b-87gpq           1/1     Running             0          4m58s
istio-system   istio-ingressgateway-intranet-dc46f7b46-zx4rs   1/1     Running             0          4m58s
staging        istio-ingressgateway-staging-5fbf567984-fnvgf   1/1     Running             0          4m58s
```

## Enabling Sidecar Auto-injection

We can label namespaces needing sidecar auto-injection in managed clusters with `istio-injection=enabled`:

```bash
kubectl label namespace your-namespace istio-injection=enabled --overwrite
```

> This differs from TCM, refer to [TCM FAQ: No Sidecar Auto-injection](https://cloud.tencent.com/document/product/1261/63059).

## Migrating Istio Configuration

Use following script to export TCM-related istio configurations to YAML (`kubedump.sh`):

```bash title="kubedump.sh"
#!/usr/bin/env bash

set -ex

DATA_DIR="data"
mkdir -p ${DATA_DIR}

NAMESPACES=$(kubectl get -o json namespaces | jq '.items[].metadata.name' | sed "s/\"//g")
RESOURCES="virtualservices gateways envoyfilters destinationrules sidecars peerauthentications authorizationpolicies requestauthentications telemetries proxyconfigs serviceentries"

for ns in ${NAMESPACES}; do
	for resource in ${RESOURCES}; do
		rsrcs=$(kubectl -n ${ns} get -o json ${resource} | jq '.items[].metadata.name' | sed "s/\"//g")
		for r in ${rsrcs}; do
			dir="${DATA_DIR}/${ns}/${resource}"
			mkdir -p "${dir}"
			kubectl -n ${ns} get -o yaml ${resource} ${r} | kubectl neat >"${dir}/${r}.yaml"
		done
	done
done
```

> Script depends on jq, sed commands, also depends on [kubectl-neat plugin](https://github.com/itaysk/kubectl-neat).

Ensure context switches to any cluster associated with TCM, execute script to export TCM's istio configurations:

```bash
bash kubedump.sh
```

After script completion, TCM's istio configurations exported to `data` directory.

Check exported YAML files, adjust according to needs if necessary, then apply YAML to self-built istio's primary cluster to complete istio configuration migration.

## Migrating Services

After istio configuration migration, try gradually migrating services from TCM-associated production clusters to self-built istio-associated TKE clusters, cutting traffic gradually to self-built istio environment for observation. After all TCM services migrated to self-built istio environment, decommission TCM environment, finally delete TCM mesh to complete migration.
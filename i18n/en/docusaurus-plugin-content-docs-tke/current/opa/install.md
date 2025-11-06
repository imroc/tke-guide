# Installing OPA Gatekeeper

## Managed Gatekeeper

TKE currently defaults to including managed OPA Gatekeeper, no need for self-installation.

Since gatekeeper is managed, the component itself is invisible in cluster, but related CRD resources can be seen:

```bash
kubectl get crd | grep gatekeeper.sh
```

Visual management available in cluster page's `Policy Management` page.

## Self-built Gatekeeper

If complete control and policy customization desired, can consider opening whitelist via support ticket to avoid pre-installed gatekeeper, then create new cluster to self-install community version gatekeeper.

Since OPA Gatekeeper uses images on DockerHub, can directly use official YAML for one-click installation to TKE (TKE clusters have DockerHub image acceleration).

Refer to [Official Installation Documentation: Deploying a Release using Prebuilt Image](https://open-policy-agent.github.io/gatekeeper/website/docs/install/#deploying-a-release-using-prebuilt-image)
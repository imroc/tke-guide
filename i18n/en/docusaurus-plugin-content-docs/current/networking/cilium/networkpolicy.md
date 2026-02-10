# NetworkPolicy Guide

## NetworkPolicy vs CiliumNetworkPolicy

Kubernetes native NetworkPolicy and Cilium's CiliumNetworkPolicy are both used to define network access control policies between Pods, but CiliumNetworkPolicy is more powerful and flexible in functionality. Although Cilium is also compatible with NetworkPolicy, it's recommended to use the more powerful CiliumNetworkPolicy since Cilium is installed.

### Core Feature Comparison

| Feature                   | NetworkPolicy              | CiliumNetworkPolicy                     |
| ------------------------- | -------------------------- | --------------------------------------- |
| **Scope**                 | Namespace level            | Namespace level                         |
| **Basic Traffic Control** | ✅ Supports ingress/egress | ✅ Supports ingress/egress              |
| **Pod Selector**          | ✅ Label-based selection   | ✅ Supports more complex expressions    |
| **L3/L4 Rules**           | ✅ IP/port control         | ✅ IP/port control                      |
| **L7 Protocol Awareness** | ❌ Not supported           | ✅ Supports HTTP/gRPC/Kafka etc.        |
| **FQDN Support**          | ❌ Not supported           | ✅ Supports domain name matching        |
| **Explicit Deny Rules**   | ❌ Only implicit deny      | ✅ Supports `egressDeny`/`ingressDeny`  |
| **Entity Selector**       | ❌ Not supported           | ✅ Supports `toEntities`/`fromEntities` |
| **DNS Awareness**         | ❌ Not supported           | ✅ Supports DNS rules                   |
| **Service Selector**      | ❌ Not supported           | ✅ Supports `toServices`                |

### Key Differences Explanation

**1. L7 Protocol Awareness**

- NetworkPolicy can only control up to L3/L4 layers (IP addresses and ports).
- CiliumNetworkPolicy can reach deep into L7 layer, controlling HTTP methods, paths, headers, gRPC methods, etc.

**2. FQDN Domain Name Support**

- NetworkPolicy can only use IPs or CIDRs, unable to directly control domain name access.
- CiliumNetworkPolicy supports `toFQDNs`, allowing direct use of domain names and wildcard patterns.

**3. Explicit Deny Rules**

- NetworkPolicy uses a whitelist model, implicitly denying unmatched traffic but unable to explicitly deny specific traffic.
- CiliumNetworkPolicy supports `egressDeny`/`ingressDeny`, allowing explicit denial of specific targets while permitting most traffic.

**4. Entity Selector**

- NetworkPolicy needs to indirectly specify targets through CIDRs or selectors.
- CiliumNetworkPolicy provides `toEntities`/`fromEntities`, allowing direct selection of predefined entities like `kube-apiserver`, `host`, `remote-node`, `world`.

**5. Selector Flexibility**

- NetworkPolicy uses standard `podSelector` and `namespaceSelector`.
- CiliumNetworkPolicy's `endpointSelector` supports more complex expressions.

### Compatibility

- Cilium is fully compatible with Kubernetes native NetworkPolicy.
- Both policy types can be mixed in the same cluster.

## CiliumClusterwideNetworkPolicy

CiliumNetworkPolicy and CiliumClusterwideNetworkPolicy differ primarily in scope and management approach, while their policy syntax is identical.

### Core Differences

| Feature                       | CiliumNetworkPolicy             | CiliumClusterwideNetworkPolicy                  |
| ----------------------------- | ------------------------------- | ----------------------------------------------- |
| **Scope**                     | Namespace level                 | Cluster level                                   |
| **Resource Type**             | Namespaced resource             | Cluster resource (no namespace)                 |
| **Management Permissions**    | Namespace admin                 | Cluster admin                                   |
| **Selector Default Scope**    | Same namespace Pods             | All cluster Pods                                |
| **Cross-Namespace Selection** | Requires explicit specification | Naturally supported                             |
| **Policy Priority**           | Normal priority                 | Higher priority                                 |
| **Node Firewall**             | ❌ Not supported                | ✅ Supported (via nodeSelector targeting nodes) |
| **Use Cases**                 | Application-level policies      | Cluster baseline policies                       |

### Key Differences Explanation

**1. Scope and Resource Location**

- CiliumNetworkPolicy must be created in specific namespaces, specified via `metadata.namespace`.
- CiliumClusterwideNetworkPolicy is a cluster-level resource with no namespace concept.

**2. Selector Behavior**

- CiliumNetworkPolicy's `endpointSelector` by default only selects Pods in the same namespace.
- CiliumClusterwideNetworkPolicy's `endpointSelector` can select Pods from any namespace in the cluster.

**3. Cross-Namespace Access Control**

- When controlling cross-namespace access, CiliumNetworkPolicy needs to explicitly specify namespace labels in `toEndpoints`/`fromEndpoints`.
- CiliumClusterwideNetworkPolicy can directly manage policies across multiple namespaces through namespace labels.

**4. Management Permissions and Responsibility Separation**

- CiliumNetworkPolicy can be managed by namespace administrators (users with namespace permissions).
- CiliumClusterwideNetworkPolicy requires cluster administrator permissions, suitable for platform teams.

**5. Policy Merging and Priority**

- When the same Pod is selected by both policy types, rules are merged and take effect.
- Deny rules (`egressDeny`/`ingressDeny`) take precedence over allow rules.
- Typically, use CiliumClusterwideNetworkPolicy to set security baselines and CiliumNetworkPolicy to add application-specific rules.

**6. Configuring Node Firewall**

- CiliumClusterwideNetworkPolicy supports applying network policies to nodes for node-level firewall configuration.
- This type of policy can only be configured by CiliumClusterwideNetworkPolicy; CiliumNetworkPolicy does not support it.

### Typical Use Cases

**CiliumNetworkPolicy is suitable for:**

- Access control between microservices.
- Application-specific network isolation requirements.
- Network policies managed autonomously by development teams.
- Fine-grained control within namespaces.

**CiliumClusterwideNetworkPolicy is suitable for:**

- Cluster default deny policies.
- Unified management of network policies across multiple infrastructure namespaces.
- Global security baselines and compliance requirements.
- Unified access control across namespaces.
- Restricting access to sensitive resources (like kube-apiserver).
- Configuring node firewalls.

### Best Practices

**Layered Policy Management:**

1. Use CiliumClusterwideNetworkPolicy to set cluster security baselines (e.g., default deny, DNS access, infrastructure communication).
2. Use CiliumNetworkPolicy to implement application-specific network policies (e.g., service-to-service calls, external API access).

**Permission Separation:**

- Platform teams manage CiliumClusterwideNetworkPolicy to ensure overall cluster security.
- Application teams manage CiliumNetworkPolicy to meet business requirements.

**Naming Conventions:**

- Use descriptive prefixes for cluster policies, like `default-deny-all`, `global-infrastructure`.
- Use application-related names for namespace policies, like `frontend-to-backend`, `allow-external-api`.

## Usage Practices

### Security Baseline: Default Deny

Cluster default denies egress traffic (except DNS resolution, and Pods in kube-system namespace), strictly controlling network access permissions for cluster Pods:

:::tip[Note]

Typically, ingress traffic is not set with global default deny; specific ingress policies can be set for sensitive services separately (e.g., A can only be accessed by B).

:::

```yaml
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
 name: default-deny
spec:
 description: "Block all the traffic (except DNS) by default"
 egress:
 - toEndpoints: # Allow all cluster Pods to resolve domain names via coredns
   - matchLabels:
       io.kubernetes.pod.namespace: kube-system
       k8s-app: kube-dns
   toPorts:
   - ports:
     - port: "53"
       protocol: ANY
     rules:
       dns:
       - matchPattern: "*"
 endpointSelector:
   matchExpressions: # Do not restrict egress traffic for Pods in kube-system namespace
   - key: io.kubernetes.pod.namespace
     operator: NotIn
     values:
     - kube-system
```

### Unified Management of Infrastructure Network Policies

A cluster may deploy many infrastructure-related applications scattered across multiple namespaces. We can use CiliumClusterwideNetworkPolicy and namespace labels to uniformly set network policies for these namespaces (assuming these namespaces have the `role=infrastructure` label):

```yaml
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
 name: default-infrastructure
spec:
 endpointSelector: # Select all Pods in infrastructure namespaces
   matchLabels:
     io.cilium.k8s.namespace.labels.role: infrastructure
 egress: # Configure egress policies
 - toEndpoints: # Allow access to all Pods in infrastructure namespaces
   - matchLabels:
       io.cilium.k8s.namespace.labels.role: infrastructure
 - toEndpoints: # Allow access to coredns for domain resolution
   - matchLabels:
       io.kubernetes.pod.namespace: kube-system
       k8s-app: kube-dns
   toPorts:
   - ports:
     - port: "53"
       protocol: ANY
     rules:
       dns:
       - matchPattern: "*"
 - toFQDNs: # Allow calling Tencent Cloud related APIs
   - matchPattern: '**.tencent.com'
   - matchPattern: '**.tencentcloudapi.com'
   - matchPattern: '**.tencentyun.com'
 - toCIDR: # Allow access to platform services on Tencent Cloud
   - 169.254.0.0/16 # 169.254.0.0/16 is a reserved network segment on Tencent Cloud, used by some platform services like TKE cluster apiserver VIP, COS storage, image repositories, etc. Some TKE built-in components also call the API provided by this network cidr (such as ipamd) and are configured with hostAlias, so they will not go through DNS resolution. Therefore, allowing egress traffic through toFQDNs will not work (toFQDNs depends on the request going through DNS resolution).
 - toEntities: # Allow access to apiserver
   - kube-apiserver
 - toEntities: # Allow access to port 10250 on all nodes in the cluster, useful for monitoring metrics collection
   - host
   - remote-node
   toPorts:
   - ports:
     - port: "10250"
       protocol: TCP
```

### Configuring Node Firewall

```yaml
apiVersion: "cilium.io/v2"
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: default-host-firewall
spec:
  nodeSelector: {} # Select all nodes
  ingress:
  - fromEntities:
    - cluster # Do not restrict traffic within the cluster
  - toPorts:
    - ports: # Allow SSH access
      - port: "22"
        protocol: TCP
  - icmps: # Allow ping requests
    - fields:
      - type: EchoRequest
        family: IPv4
```

### Multi-tenant Isolation

If a cluster is shared by multiple tenants where each tenant uses a separate namespace, the platform can use CiliumNetworkPolicy to restrict tenant business Pods to communicate only within the same namespace:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: tenant-001
spec:
  endpointSelector: {}
  ingress:
  - fromEndpoints:
    - {}
  egress:
  - toEndpoints:
    - {}
```

If each tenant's business Pods are distributed across multiple namespaces but have the same namespace label to identify the tenant, this can be implemented using CiliumClusterwideNetworkPolicy:

```yaml
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
 name: tenant-001
spec:
 endpointSelector: # Select all Pods in all namespaces for tenant 001
   matchLabels:
     io.cilium.k8s.namespace.labels.tenant-id: "001"
 egress: # Only allow tenant 001 Pods to access their own business Pods
 - toEndpoints:
   - matchLabels:
       io.cilium.k8s.namespace.labels.tenant-id: "001"
 ingress: # Only allow tenant 001 Pods to be accessed by their own business Pods
 - fromEndpoints:
   - matchLabels:
       io.cilium.k8s.namespace.labels.tenant-id: "001"
```

### Restricting apiserver Access

To strictly restrict apiserver access and avoid cluster attacks or reduce unnecessary control plane pressure, first configure a global default deny rule (refer to the previous "Security Baseline: Default Deny" example), then configure as needed which Pods are allowed to access it.

Allow all Pods in the `test` namespace to access apiserver:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: default-allow-apiserver
  namespace: test
spec:
  endpointSelector: {}
  egress:
  - toEntities:
    - kube-apiserver
```

Allow service A in the `test` namespace to access apiserver:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: from-a-to-apiserver
  namespace: test
spec:
  endpointSelector:
    matchLabels:
      app: a
  egress:
  - toEntities:
    - kube-apiserver
```

### Restricting Business Ingress Traffic: Protecting Sensitive Services

#### Restricting A to only be accessed by B, and only on port 80/TCP

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: from-b-to-a
spec:
  endpointSelector:
    matchLabels:
      app: a
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: b
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
```

#### Restricting A to only be accessed by B, and only specific endpoints

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
 name: from-b-to-a-api
spec:
 description: "Allow HTTP API from a to b"
 endpointSelector:
   matchLabels:
     role: a
 ingress:
 - fromEndpoints:
   - matchLabels:
       role: b
   toPorts:
   - ports:
     - port: "80"
       protocol: TCP
     rules:
       http:
       - method: "GET" # Allow GET /public
         path: "/public"
       - method: "PUT" # Allow PUT /avatar, but requires X-My-Header: true header
         path: "/avatar$"
         headers:
         - 'X-My-Header: true'
```

#### Restricting A to only be accessed from outside the cluster

If A provides external services with CLB directly connecting to Pods, handling requests from the public internet, and other traffic (like from cluster Pods or nodes) should not be allowed, configure the following policy:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: from-outside-to-a
spec:
  endpointSelector:
    matchLabels:
      app: a
  ingress:
  - fromEntities:
    - world
```

If the CLB is not a directly connected Pod, but is forwarded via NodePort, SNAT will be performed across nodes. In this case, it can be written like this:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: from-outside-to-a
spec:
  endpointSelector:
    matchLabels:
      app: a
  ingress:
  - fromEntities:
    - world
    - remote-node # Allow traffic from NodePort to be forwarded across nodes
```

### Restricting Business Egress Traffic

#### A can only access B

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: egress-a-to-b
spec:
  endpointSelector:
    matchLabels:
      app: a
  egress:
  - toEndpoints:
    - matchLabels:
        app: b
```

#### A can only access Pods in the same namespace

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-all-from-a
spec:
  endpointSelector:
    matchLabels:
      app: a
  egress:
  - toEndpoints:
    - {}
```

#### A can only access services in specified network segments

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-a-to-cidr
spec:
  endpointSelector:
    matchLabels:
      role: a
  egress:
  - toCIDR:
    - 192.0.2.0/24
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
```

#### A can only access services on specified port ranges

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-a-ports
spec:
  endpointSelector:
    matchLabels:
      app: a
  egress:
    - toPorts:
      - ports: # Can only send TCP traffic with destination ports 80-444
        - port: "80"
          endPort: 444
          protocol: TCP
```

#### A can only access services with specified domain names

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: from-a-to-domains
spec:
  endpointSelector:
    matchLabels:
      app: a
  egress:
  - toEndpoints:
    - matchLabels:
        io.kubernetes.pod.namespace: kube-system
        k8s-app: kube-dns
    toPorts:
    - ports:
      - port: "53"
        protocol: ANY
      rules:
        dns:
        - matchPattern: "*"
  - toFQDNs:
    - matchName: 'imroc.cc'
    - matchPattern: '**.imroc.cc'
    - matchPattern: '**.myqcloud.com'
    - matchPattern: '**.tencent.com'
    - matchPattern: '**.tencentcloudapi.com'
    - matchPattern: '**.tencentyun.com'
```

#### Explicit Denial: A cannot access B

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: deny-a-to-b
spec:
  endpointSelector:
    matchLabels:
      app: a
  egressDeny:
  - toEndpoints: # Explicitly deny A from accessing B
    - matchLabels:
        app: b
  egress:
  - toEntities: # Allow other traffic from A
    - all
```

## Reference Materials

- [Cilium NetworkPolicy Examples](https://docs.cilium.io/en/stable/security/policy/language/)

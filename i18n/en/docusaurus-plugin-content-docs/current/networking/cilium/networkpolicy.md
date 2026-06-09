# NetworkPolicy Practices

## NetworkPolicy vs CiliumNetworkPolicy

Kubernetes native NetworkPolicy and Cilium's CiliumNetworkPolicy both define network access control policies between Pods, but CiliumNetworkPolicy is more powerful and flexible in functionality. Although Cilium is compatible with NetworkPolicy, since Cilium is installed, it is recommended to use the more powerful CiliumNetworkPolicy.

### Feature Comparison

| Feature            | NetworkPolicy             | CiliumNetworkPolicy                  |
| ------------------ | ------------------------- | ------------------------------------ |
| **Scope**          | Namespace level           | Namespace level                      |
| **Basic Traffic Control** | ✅ Supports ingress/egress | ✅ Supports ingress/egress    |
| **Pod Selector**   | ✅ Label-based selection  | ✅ Supports more complex expressions |
| **L3/L4 Rules**    | ✅ IP/Port control        | ✅ IP/Port control                   |
| **L7 Protocol Awareness** | ❌ Not supported        | ✅ Supports HTTP/gRPC/Kafka etc.     |
| **FQDN Support**   | ❌ Not supported          | ✅ Supports domain matching          |
| **Explicit Deny Rules** | ❌ Implicit deny only  | ✅ Supports `egressDeny`/`ingressDeny` |
| **Entity Selector** | ❌ Not supported         | ✅ Supports `toEntities`/`fromEntities` |
| **DNS Awareness**  | ❌ Not supported          | ✅ Supports DNS rules                |
| **Service Selector** | ❌ Not supported        | ✅ Supports `toServices`             |

### Key Differences

**1. L7 Protocol Awareness**

- NetworkPolicy can only control up to L3/L4 (IP addresses and ports).
- CiliumNetworkPolicy can go down to L7, controlling HTTP methods, paths, headers, gRPC methods, etc.

**2. FQDN/Domain Support**

- NetworkPolicy can only use IP or CIDR, unable to directly control domain access.
- CiliumNetworkPolicy supports `toFQDNs`, allowing direct use of domains and wildcard patterns.

**3. Explicit Deny Rules**

- NetworkPolicy uses a whitelist model — unmatched traffic is denied by default, but cannot explicitly deny specific traffic.
- CiliumNetworkPolicy supports `egressDeny`/`ingressDeny`, allowing explicit denial of specific targets while permitting most traffic.

**4. Entity Selector**

- NetworkPolicy needs to indirectly specify targets via CIDR or selectors.
- CiliumNetworkPolicy provides `toEntities`/`fromEntities`, allowing direct selection of predefined entities such as `kube-apiserver`, `host`, `remote-node`, `world`, etc.

**5. Selector Flexibility**

- NetworkPolicy uses standard `podSelector` and `namespaceSelector`.
- CiliumNetworkPolicy's `endpointSelector` supports more complex expressions.

### Compatibility

- Cilium is fully compatible with Kubernetes native NetworkPolicy.
- Both policy types can be mixed in the same cluster.

## CiliumClusterwideNetworkPolicy

The core difference between CiliumNetworkPolicy and CiliumClusterwideNetworkPolicy lies in scope and management, while their policy syntax is identical.

### Core Differences

| Feature             | CiliumNetworkPolicy | CiliumClusterwideNetworkPolicy          |
| ------------------- | ------------------- | --------------------------------------- |
| **Scope**           | Namespace level     | Cluster level                           |
| **Resource Type**   | Namespaced resource | Cluster resource (no namespace)         |
| **Management Permission** | Namespace admin | Cluster admin                           |
| **Selector Default Scope** | Same-namespace Pods | All Pods in cluster             |
| **Cross-Namespace Selection** | Requires explicit specification | Naturally supported |
| **Policy Priority** | Normal priority     | Higher priority                         |
| **Node Firewall**   | ❌ Not supported    | ✅ Supported (via nodeSelector)         |
| **Use Cases**       | Application-level policies | Cluster baseline policies             |

### Key Differences

**1. Scope and Resource Location**

- CiliumNetworkPolicy must be created in a specific namespace, specified via `metadata.namespace`.
- CiliumClusterwideNetworkPolicy is a cluster-level resource with no namespace concept.

**2. Selector Behavior**

- CiliumNetworkPolicy's `endpointSelector` defaults to selecting only Pods in the same namespace.
- CiliumClusterwideNetworkPolicy's `endpointSelector` can select Pods in any namespace across the cluster.

**3. Cross-Namespace Access Control**

- When CiliumNetworkPolicy controls cross-namespace access, namespace labels must be explicitly specified in `toEndpoints`/`fromEndpoints`.
- CiliumClusterwideNetworkPolicy can directly manage policies across multiple namespaces using namespace labels.

**4. Management Permissions and Role Separation**

- CiliumNetworkPolicy can be managed by namespace administrators (users with permissions for that namespace).
- CiliumClusterwideNetworkPolicy requires cluster admin permissions, suitable for platform teams.

**5. Policy Merge and Priority**

- When a Pod is selected by both policy types, rules are merged and take effect together.
- Deny rules (`egressDeny`/`ingressDeny`) take precedence over allow rules.
- Typically, CiliumClusterwideNetworkPolicy is used for security baselines, and CiliumNetworkPolicy for application-specific rules.

**6. Node Firewall Configuration**

- CiliumClusterwideNetworkPolicy supports applying network policies to nodes for node-level firewalls.
- This type of policy can only be configured via CiliumClusterwideNetworkPolicy; CiliumNetworkPolicy does not support it.

### Typical Use Cases

**CiliumNetworkPolicy is suitable for:**

- Access control between microservices.
- Application-specific network isolation requirements.
- Network policies managed autonomously by development teams.
- Fine-grained control within a namespace.

**CiliumClusterwideNetworkPolicy is suitable for:**

- Cluster default deny policies.
- Unified network policy management across multiple infrastructure namespaces.
- Global security baselines and compliance requirements.
- Unified cross-namespace access control.
- Restricting access to sensitive resources (e.g., kube-apiserver).
- Configuring node firewalls.

### Best Practices

**Layered Policy Management:**

1. Use CiliumClusterwideNetworkPolicy to set cluster security baselines (e.g., default deny, DNS access, infrastructure communication).
2. Use CiliumNetworkPolicy to implement application-specific network policies (e.g., service-to-service calls, external API access).

**Role Separation:**

- Platform team manages CiliumClusterwideNetworkPolicy to ensure overall cluster security.
- Application teams manage CiliumNetworkPolicy to meet business needs.

**Naming Conventions:**

- Cluster policies use descriptive prefixes, e.g., `default-deny-all`, `global-infrastructure`.
- Namespace policies use application-related names, e.g., `frontend-to-backend`, `allow-external-api`.

## Mode Compatibility

Some capabilities in the usage practices below depend on Cilium's **L7 DNS Proxy** (specifically `toFQDNs` and `toPorts.rules.dns` rules). Cilium uses BPF + iptables TPROXY to redirect DNS queries from selected Pods to the built-in DNS proxy in cilium-agent.

All three recommended deployment approaches in this tutorial series — **Native Routing (VPC-CNI)**, **Overlay (VPC-CNI)**, and **Overlay (GR)** — fully support `toFQDNs` and `rules.dns`. All examples below can be applied directly.

:::note[GR Native Routing Not Available]

The fourth combination, GR + Native Routing, is no longer recommended due to compatibility issues (besides L7/DNS not being supported, cross-node Pod-to-Pod traffic also fails). See [Why GR Native Routing Is Not Provided?](./appendix/gr-native-not-recommended.md). If you have a GR cluster and want to use Cilium, please switch to **Overlay mode**.

:::

## Usage Practices

### Security Baseline: Default Deny

Deny all egress traffic by default (except DNS resolution and Pods in the kube-system namespace), strictly controlling Pod network access:

:::tip[Note]

Typically, a global default deny is not set for ingress traffic. Ingress policies can be configured for sensitive services on a case-by-case basis (e.g., A is only accessible by B).

:::

```yaml
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: default-deny
spec:
  description: "Block all the traffic (except DNS) by default"
  egress:
  - toEndpoints: # Allow all Pods to resolve DNS via coredns
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
    matchExpressions: # Do not restrict egress traffic for Pods in kube-system
    - key: io.kubernetes.pod.namespace
      operator: NotIn
      values:
      - kube-system
```

### Unified Infrastructure Network Policy Management

Clusters may deploy many infrastructure-related applications across multiple namespaces. We can use CiliumClusterwideNetworkPolicy with namespace labels to uniformly manage these namespaces' network policies (assuming these namespaces all have the `role=infrastructure` label):

```yaml
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: default-infrastructure
spec:
  endpointSelector: # Select all Pods in infrastructure namespaces
    matchLabels:
      io.cilium.k8s.namespace.labels.role: infrastructure
  egress: # Configure egress policy
  - toEndpoints: # Allow access to all Pods in infrastructure namespaces
    - matchLabels:
        io.cilium.k8s.namespace.labels.role: infrastructure
  - toEndpoints: # Allow DNS resolution via coredns
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
    - 169.254.0.0/16 # 169.254.0.0/16 is a reserved CIDR on Tencent Cloud used by some platform services, such as the VIP of the TKE cluster apiserver, COS storage, image registry, etc. Some TKE built-in components also call interfaces provided by this CIDR (e.g., ipamd) and use hostAlias, bypassing DNS resolution. Using toFQDNs to allow egress traffic will not work (toFQDNs relies on requests going through DNS resolution).
  - toEntities: # Allow access to apiserver
    - kube-apiserver
  - toEntities: # Allow access to port 10250 on all nodes for metric collection
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
    - cluster # Do not restrict intra-cluster traffic
  - toPorts:
    - ports: # Allow SSH access
      - port: "22"
        protocol: TCP
  - icmps: # Allow ping requests
    - fields:
      - type: EchoRequest
        family: IPv4
```

### Multi-Tenant Isolation

When a cluster is shared by multiple tenants, if each tenant uses one namespace, the platform can use CiliumNetworkPolicy to restrict tenant Pods to communicate only within the same namespace:

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

If each tenant's business Pods are distributed across multiple namespaces but share the same namespace label to identify the tenant, CiliumClusterwideNetworkPolicy can be used:

```yaml
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: tenant-001
spec:
  endpointSelector: # Select Pods in all namespaces of tenant 001
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

### Restricting Access to the Apiserver

To strictly control access to the apiserver, preventing attacks or reducing unnecessary control plane pressure, first configure a global default deny rule (refer to the earlier `Security Baseline: Default Deny` example), then selectively allow specific Pods to access it.

Allow all Pods in the `test` namespace to access the apiserver:

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

Allow only Service A in the `test` namespace to access the apiserver:

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

### Restricting Ingress Traffic: Protecting Sensitive Services

#### Restrict A to Be Accessible Only by B, and Only on Port 80/TCP

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

#### Restrict A to Be Accessible Only by B, and Only on Specific Endpoints

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
        - method: "PUT" # Allow PUT /avatar, requires X-My-Header: true header
          path: "/avatar$"
          headers:
          - 'X-My-Header: true'
```

#### Restrict A to Be Accessible Only from Outside the Cluster

If A provides an external service with CLB directly connected to Pods (refer to [Using LoadBalancer Direct Pod Mode Service](https://cloud.tencent.com/document/product/457/41897)), handling requests from the public internet while disallowing other traffic (e.g., from Pods or nodes within the cluster), configure the following policy:

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

If the CLB does not directly connect to Pods but uses NodePort forwarding, cross-node traffic undergoes SNAT. In this case, configure as follows:

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
    - remote-node # Allow traffic from cross-node NodePort forwarding
```

### Restricting Egress Traffic

#### A Can Only Access B

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

#### A Can Only Access Pods in the Same Namespace

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

#### A Can Only Access Services in a Specific CIDR

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

#### A Can Only Access Services on Specific Ports

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
      - ports: # Only allow TCP traffic to destination ports 80-444
        - port: "80"
          endPort: 444
          protocol: TCP
```

#### A Can Only Access Services on Specific Domains

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

#### Explicit Deny: A Cannot Access B

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
  - toEndpoints: # Explicitly deny A accessing B
    - matchLabels:
        app: b
  egress:
  - toEntities: # Allow other traffic from A
    - all
```

## References

- [Cilium NetworkPolicy Examples](https://docs.cilium.io/en/stable/security/policy/language/)

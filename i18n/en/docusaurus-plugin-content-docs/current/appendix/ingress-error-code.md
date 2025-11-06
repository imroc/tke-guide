---
sidebar_position: 2
---

# Ingress Error Codes

## E4000 CreateLoadBalancer RequestLimitExceeded

API calls exceeded frequency limits in a short period, errors will be retried. Occasional occurrences have no impact on the service.

## E4003 CreateLoadBalancer LimitExceeded

Fault cause: Load balancer resource quantity is limited.

Handling method: Submit a support ticket to request an increase in the load balancer resource quantity limit.

## E4004 CreateListener LimitExceeded

Fault cause: Listener quantity under load balancer resources is limited.

Handling method: Submit a support ticket to request an increase in the listener resource quantity limit under the load balancer.

## E4005 CreateRule LimitExceeded

Fault cause: Rule quantity under load balancer resources is limited.

Handling method: Submit a support ticket to request an increase in the rule resource quantity limit under the load balancer.

## E4006 DeleteListener Redirection config on the listener

Fault cause: Redirection rules were set under the listener managed by Ingress, causing listener deletion to fail.

Handling method: You need to handle the redirection rules yourself. Ingress will retry to delete the listener in subsequent attempts.

## E4007 Norm AssumeTkeCredential -8017 | -8032 Record Not Exist

Fault cause: In most cases, the `ip-masq-agent-config` was modified, causing requests to access Norm to not undergo IP masquerading, resulting in Norm authentication failure.

**Troubleshooting Steps**

1. Check current configuration:

```bash
kubectl get configmap -n kube-system ip-masq-agent-config
```

```txt
nonMasqueradeCIDRs:  // All pod outgoing traffic is not IP masqueraded, Norm authenticates based on source IP (Node)
    - 0.0.0.0/0

nonMasqueradeCIDRs:  // Normal situation, cluster network and VPC network CIDRs are configured here
    - 10.0.0.0/14
    - 172.16.0.0/16
```

2. Check `ip-masq-agent` restart time to see if it was recently updated:

```bash
$ kubectl get pod -n kube-system -l name=ip-masq-agent
NAME                  READY     STATUS    RESTARTS   AGE
ip-masq-agent-n4p9k   1/1       Running   0          4h
ip-masq-agent-qj6rk   1/1       Running   0          4h
```

Handling method:
* Modify `nonMasqueradeCIDRs` in `ip-masq-agent-config` to use a reasonable configuration.
* After confirming Masq configuration is correct, restart the Ingress Controller component.

## E4008 Norm AssumeTkeCredential -8002 Data is nil

Fault cause: Authorization for Tencent Cloud Container Service was revoked, causing the service to fail to run.

Handling method:
* Log in to Access Management service, find the role `TKE_QCSRole` (create if it doesn't exist)
* Create a service preset role and grant Tencent Cloud Container Service related permissions.

## E4009 Ingress: xxx secret name is empty

Fault cause: Ingress template format error. spec.tls.secretName is not filled or is empty.

Handling method:
* Help documentation: https://kubernetes.io/docs/concepts/services-networking/ingress/#tls
* Check and modify the Ingress template.

## E4010 Secret xxx not found

Fault cause: Ingress template information error. The Secrets resource specified in spec.tls.secretName does not exist.

Handling method:
* Help documentation: https://kubernetes.io/docs/concepts/configuration/secret/
* Check and modify the Ingress template.

## E4011 Secret xxx has no qcloud cert id

Fault cause: The Secrets referenced in the Ingress template are missing content. Or the referenced Secrets need to contain the qcloud_cert_id field information.

Handling method:

* Reference K8S official documentation: https://kubernetes.io/docs/concepts/configuration/secret/
* Check certificate configuration:
  ```bash
  $ kubectl get ingress <ingress> -n <namespace> -o yaml
  apiVersion: extensions/v1beta1
  kind: Ingress
  metadata:
    annotations:
      qcloud_cert_id: YCOLTUdr <-- Check if this is the certificate ID
  spec:
    tls:
    - secretName: secret-name <-- Check configured Secret name
  ```
* Check Secret configuration:
  ```bash
  $ kubectl get secret <secret-name> -n <namespace> -o yaml
  apiVersion: v1
  data:
    qcloud_cert_id: WUNPTFRVZHI= <-- Check if this is the Base64 encoding of the certificate ID
  kind: Secret
  metadata:
    name: nginx-service-2 
    namespace: default
  type: Opaque
  
  $ echo -n "WUNPTFRVZHI=" | base64 -d
  YCOLTUdr    <-- Certificate ID matches
  ```

* How to create Secret:
  ```bash
  kubectl create secret generic <secret-name> -n <namespace> --from-literal=qcloud_cert_id=YCOLTUdr   <-- Certificate ID
  ```

## E4012 CreateListener InvalidParameterValue

Fault cause: Most likely Ingress template information error. The qcloud_cert_id described in the Secrets resource specified in spec.tls.secretName does not exist.

Troubleshooting steps: Find the error cause. If the error reason is 'Query certificate 'xxxxxxx' failed.', confirm that the certificate ID is incorrectly filled.

Handling method:
* Log in to the SSL Certificate console to check if the certificate ID is correct.
* Then modify the certificate ID in Secrets.

## E4013 Ingress rules invalid. 'spec.rules.http' is empty.

Fault cause: Ingress template is incorrect, spec.rules.http is not filled with actual content.

Handling method: Correct your Ingress template.

## E4017 Load balancer labels have been tampered with

Fault cause: Load balancer labels were modified, causing failure to locate load balancer resources based on labels.

Handling method:
* Due to label or load balancer resource deletion or tampering, data may be inconsistent. It is recommended to delete the load balancer, or delete all load balancer labels, then recreate the Ingress resource.

## E4018 LB resource specified in kubernetes.io/ingress.existLbId does not exist

Fault cause: Ingress template is incorrect. The LoadBalance specified in Annotation `kubernetes.io/ingress.existLbId` does not exist.

Troubleshooting steps: Check the LBId provided in the logs, check if this LB resource exists in this region for this account.

Handling method:
* If querying the backend system confirms the LB resource does exist. Transfer the ticket to CLB to investigate why resource query failed.
* If querying the backend system confirms the LB resource does not exist. Check if the LBId defined in the template is correct.

## E4019 Can not use lb: created by TKE for ingress: xxx

Fault cause: The LBId specified in kubernetes.io/ingress.existLbId has already been used by Ingress or Service (resource lifecycle managed by TKE cluster), cannot be reused.

Related reference: Ingress lifecycle management.

Handling method:
* Use a different LB
* Delete the Ingress or Service using this LB resource (follow steps below)
  * Delete the tke-createdBy-flag resource on the LB resource
  * Delete the Ingress or Service using this LB resource. (If step one is not done, the LB resource will be automatically destroyed)
  * Specify the new Ingress to use this LB.
  * Add the tke-createdBy-flag=yes label to this LB resource. (If this step is not done, the resource lifecycle will not be managed by Ingress, and this resource will not be automatically destroyed later)

## E4020 Error lb: used by ingress: xxx

Fault cause: The LBId specified in `kubernetes.io/ingress.existLbId` has already been used by Ingress, cannot be reused.

Related reference: Ingress lifecycle management.

Handling method:
* Use a different LB
* Delete the Ingress using this LB resource
  * Delete the tke-createdBy-flag resource on the LB resource (follow steps below)
  * Delete the Ingress or Service using this LB resource. (If step one is not done, the LB resource will be automatically destroyed)
  * Specify the new Ingress to use this LB.
  * Add the tke-createdBy-flag=yes label to this LB resource. (If this step is not done, the resource lifecycle will not be managed by Ingress, and this resource will not be automatically destroyed later)

## E4021 exist lb: xxx listener not empty

Fault cause: The LBId specified in `kubernetes.io/ingress.existLbId` still has listeners that have not been deleted.

Detailed description: When using an existing LB, if there are listeners on the LB, it may cause misoperation of LB resources. Therefore, existing listeners that still have listeners are disabled.

Handling method:
* Use a different LB
* Delete all listeners under this LB

## E4022 Ingress rules invalid.

Fault cause: kubernetes.io/ingress.http-rules label format parsing error.

Detailed description: The kubernetes.io/ingress.http-rules label content should be a Json format string, error occurs when content is incorrect.

Handling method: Check if the http-rules defined in the template are correct.

Format example: 

```yaml
kubernetes.io/ingress.http-rules: '[{"path":"/abc","backend":{"serviceName":"nginx-service-2","servicePort":"8080"}}]'
```

## E4023 create lb error: ResourceInsufficient

Fault cause: kubernetes.io/ingress.https-rules label format parsing error.

Detailed description: The kubernetes.io/ingress.https-rules label content should be a Json format string, error occurs when content is incorrect.

Handling method: Check if the https-rules defined in the template are correct.

Format example:

```yaml
kubernetes.io/ingress.https-rules: '[{"path":"/abc","backend":{"serviceName":"nginx-service-2","servicePort":"8080"}}]'
```

## E4024 create lb error: InvalidParameter or InvalidParameterValue

Fault cause: When creating Ingress LB, parameters configured through annotations have errors.

Detailed description: Annotation configuration deletion, invalid.

Handling method: Check annotation parameters.

## E4025 create lb error: ResourceInsufficient

Fault cause: Insufficient resources when creating Ingress LB.

Detailed description: Usually insufficient IP addresses in the subnet for internal LBs.

Handling method: Check if subnet IPs are exhausted.

## E4026 Ingress extensive parameters invalid.

Fault cause: When creating Ingress LB, kubernetes.io/ingress.extensiveParameters label format parsing error.

Detailed description: The provided annotation content is not a valid JSON string.

Handling method:
* Modify annotation content, provide a reference example: `kubernetes.io/ingress.extensiveParameters: '{"AddressIPVersion":"IPv4","ZoneId":"ap-guangzhou-1"}'`
* Parameter reference documentation: https://cloud.tencent.com/document/product/214/30692 

## E4027 EnsureCreateLoadBalancer Insufficient Account Balance

Fault cause: Account has overdue payment.

Handling method: Just recharge the account.

## E4030 This interface only support HTTP/HTTPS listener

Fault cause: Using traditional CLB through existing LB method cannot create layer 7 rules.

Handling method: Need to modify the specified CLB, or delete labels to let Ingress actively create CLB.

## E4031 Ingress rule invalid. Invalid path.

Fault cause: The Path format of the layer 7 rule filled in the template does not comply with the rules.

Handling method: Check if the path conforms to the following format.

* Default is `/`, must start with `/`, length limit 1-120.
* Non-regular URL path, starting with `/`, supported character set: `a-z A-Z 0-9 . - / = ?`.

## E4032 LoadBalancer AddressIPVersion Error

Fault cause: Used incorrect `AddressIPVersion` parameter.

Detailed description: Currently clusters based on IPv4 networks only support IPv4 and NAT IPv6 type load balancers. Pure IPv6 type load balancers are not supported.

Handling method:
* If creating load balancer. Modify the kubernetes.io/ingress.extensiveParameters parameter.
* If using existing load balancer. Cannot select this load balancer, need to use a different load balancer.

## E4033 LoadBalancer AddressIPVersion do not support

Fault cause: This region does not support IPv6 type load balancers.

Detailed description: Currently not all regions support IPv6 load balancers. Contact load balancer support for strong business requirements.

## E4034 Ingress RuleHostEmpty

Fault cause: Host is not configured in Ingress rules.

Detailed description: Currently for IPv4 load balancers, when Host is not configured, the IPv4 address will be used as Host. When using pure IPv6 load balancers, the default Host logic does not exist, domain name must be specified.

Handling method: Modify Ingress, add the Host field to Ingress.

## E4035 LoadBalancer CertificateId Invalid

Fault cause: Certificate ID format is incorrect. (CertId length is incorrect)

Handling method:
* Reference documentation: https://cloud.tencent.com/document/product/457/45738 
* Log in to load balancer console, confirm certificate ID, modify the certificate ID described in the Secret resource used by Ingress.

## E4036 LoadBalancer CertificateId NotFound

Fault cause: Certificate ID does not exist.

Handling method:
* Reference documentation: https://cloud.tencent.com/document/product/457/45738 
* Log in to load balancer console, confirm certificate ID, modify the certificate ID described in the Secret resource used by Ingress.

## E4037 Annotation 'ingress.cloud.tencent.com/direct-access' Invalid

Fault cause: The valid values for ingress.cloud.tencent.com/direct-access are true or false.

Handling method: Check if the configured `ingress.cloud.tencent.com/direct-access` annotation content is a valid bool value.

## E4038 Certificate Type Error

Fault cause: The configured certificate type needs to be a server certificate. Cannot use client certificate to configure one-way certificate.

Handling method: 
* Log in to load balancer console, check the certificate type used, confirm it's a server certificate.
* If confirmed to be client certificate, needs modification.
* If confirmed to be server certificate, contact load balancer support to troubleshoot certificate usage issues.

## E4038 Certificate Out of Date / E4039 Certificate Out of Date

Fault cause: The configured certificate has expired, check the expiration time of the configured certificate.

Handling method: 
* Reference documentation: https://cloud.tencent.com/document/product/457/45738 
* Log in to load balancer console, check the expiration time of the certificate used.
* Replace with a new certificate, and update the Secret resource used by Ingress to synchronize the certificate.

## E4040 Certificate Not Found for SNI

Fault cause: The domain names described in Ingress have one or more not included in the TLS domain name certificate rules.

Handling method: 
* Reference documentation: https://cloud.tencent.com/document/product/457/45738 
* Check if there are domain names that do not provide corresponding certificate Secret resources.

## E4041 Service Not Found

Fault cause: The Service referenced in Ingress does not exist.

Handling method: Check if all Service resources declared for use in Ingress exist, note that Service and Ingress need to be in the same namespace.

## E4042 Service Port Not Found

Fault cause: The Service port referenced in Ingress does not exist.

Handling method: Check if all Service resources declared for use in Ingress and their used ports exist.

## E4043 TkeServiceConfig Not Found

Fault cause: The TkeServiceConfig resource referenced by Ingress through "ingress.cloud.tencent.com/tke-service-config" annotation does not exist.

Handling method: 
* Reference documentation: https://cloud.tencent.com/document/product/457/45700
* Check if the TkeServiceConfig resource declared in the Ingress annotation exists, note it should be in the same namespace. Query command: `kubectl get tkeserviceconfigs.cloud.tencent.com -n <namespace> <name>`

## E4044 Mixed Rule Invalid

Fault cause: The Ingress annotation "kubernetes.io/ingress.rule-mix" is not a valid JSON string.

Handling method: 
* https://cloud.tencent.com/document/product/457/45693
* Reference documentation to write correct annotation content. Or use Ingress mixed protocol function through the console.

## E4045 InternetChargeType Invalid

Fault cause: The Ingress annotation "kubernetes.io/ingress.internetChargeType" content is invalid.

Handling method: Reference InternetChargeType parameter optional values: https://cloud.tencent.com/document/api/214/30694#InternetAccessible 

## E4046 InternetMaxBandwidthOut Invalid

Fault cause: The Ingress annotation "kubernetes.io/ingress.internetMaxBandwidthOut" content is invalid.

Handling method: Reference InternetMaxBandwidthOut parameter optional values: https://cloud.tencent.com/document/api/214/30694#InternetAccessible 

## E4047 Service Type Invalid

Fault cause: The Service referenced as Ingress backend can only be NodePort or LoadBalancer type.

Handling method: Check Service type, it is recommended to use NodePort or LoadBalancer type Services as Ingress backend.

## E4048 Default Secret conflict.

Fault cause: Multiple default certificates declared in TLS in Ingress, causing conflict.

Handling method: 
* https://cloud.tencent.com/document/product/457/45738
* Check TLS configuration, at most one default certificate can be configured. Will automatically synchronize after modification and update.

## E4049 SNI Secret conflict.

Fault cause: Multiple certificates corresponding to the same domain name declared in TLS in Ingress, causing conflict.

Handling method: 
* https://cloud.tencent.com/document/product/457/45738
* Check TLS configuration, at most one certificate can be configured for a single domain name. Will automatically synchronize after modification and update.

## E4050 Annotation 'ingress.cloud.tencent.com/tke-service-config-auto' Invalid

Fault cause: The valid values for ingress.cloud.tencent.com/tke-service-config-auto are true or false.

Handling method: Check if the configured `ingress.cloud.tencent.com/tke-service-config-auto` annotation content is a valid bool value.

## E4051 Annotation 'ingress.cloud.tencent.com/tke-service-config' Name Invalid

Fault cause: The name of ingress.cloud.tencent.com/tke-service-config cannot end with '-auto-ingress-config' or '-auto-service-config'. Will conflict with automatically synchronized configuration names.

Handling method: Modify the annotation 'ingress.cloud.tencent.com/tke-service-config', use TkeServiceConfig resources with different names.

## E4052 Ingress Host Invalid

Fault cause: According to K8S restrictions, Ingress Host needs to satisfy the regular expression `(\*|[a-z0-9]([-a-z0-9]*[a-z0-9])?)(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)+`.

Handling method: Domain names generally meet the above requirements by default. Just exclude cases where domain names don't have ".", domain names contain special characters, etc.

## E4053 LoadBalancer Subnet IP Insufficient

Fault cause: The IP addresses in the subnet where the load balancer is located have been exhausted, unable to create load balancer in the configured subnet.

Handling method: 
* Determine the annotation used for the selected subnet: "kubernetes.io/ingress.subnetId".
* Recommend using a different subnet, or release some IP resources in that subnet.

## E4091 CreateLoadBalancer Invoke vpc failed: subnet not exists

Fault cause: The subnet specified when creating internal LB is incorrect.

Handling method: Check if the subnet ID described in the kubernetes.io/ingress.subnetId field in the Ingress template is correct.

## E5003 CLB InternalError

Fault cause: CLB internal error.

Handling method: Transfer to CLB to investigate the cause.

## E5004 CVM InternalError

Fault cause: CVM internal error.

Handling method: Immediately transfer the ticket to CVM to investigate the subsequent cause.

## E5005 TAG InternalError

Fault cause: Tag service internal error.

Handling method: Immediately transfer the ticket to tag service to investigate the subsequent cause.

## E5007 Norm InternalError

Fault cause: Service internal error.

Handling method: Immediately transfer the ticket to tag service to investigate the subsequent cause.

## E5008 TKE InternalError

Fault cause: Service internal error.

Handling method: Immediately transfer the ticket to tag service to investigate the subsequent cause.

## E5009 CLB BatchTarget Faild

Fault cause: CLB internal error, partial errors occurred during backend batch binding/unbinding.

Handling method: Immediately transfer the ticket to CLB to investigate the subsequent cause.

## E6001 Failed to get zone from env: TKE_REGION / E6002 Failed to get vpcId from env: TKE_VPC_ID

Fault cause: Cluster resource configmap tke-config configuration missing, causing container startup failure.

Handling method:
  * `kubectl get configmap -n kube-system tke-config` Check if configmap exists
  * `kubectl create configmap tke-config -n kube-system --from-literal=TKE_REGION=<ap-shanghai-fsi> --from-literal=TKE_VPC_ID=<vpc-6z0k7g8b>` Create configmap, region, vpc_id need to be modified according to specific cluster information
  * `kubectl edit deployment -n kube-system l7-lb-controller -o yaml` Ensure the env content in the template is correct.
    ```yaml
    spec:
      containers:
      - args:
        - --cluster-name=<cls-a0lcxsdm>
        env:
        - name: TKE_REGION
          valueFrom:
            configMapKeyRef:
              key: TKE_REGION
              name: tke-config
        - name: TKE_VPC_ID
          valueFrom:
            configMapKeyRef:
              key: TKE_VPC_ID
              name: tke-config
    ```

## E6006 Error during sync: Post https://clb.internal.tencentcloudapi.com/: dial tcp: i/o timeout

Fault cause A: CoreDNS domain name resolution for related API services has errors.

Domain names that may involve the same issue:

```txt
lb.api.qcloud.com
tag.api.qcloud.com
cbs.api.qcloud.com
cvm.api.qcloud.com
snapshot.api.qcloud.com
monitor.api.qcloud.com
scaling.api.qcloud.com
ccs.api.qcloud.com
tke.internal.tencentcloudapi.com
clb.internal.tencentcloudapi.com
cvm.internal.tencentcloudapi.com
```

Handling method: Add the following domain name resolution to l7-lb-controller.

```bash
kubectl patch deployment l7-lb-controller -n kube-system --patch '{"spec":{"template":{"spec":{"hostAliases":[{"hostnames":["lb.api.qcloud.com","tag.api.qcloud.com","cbs.api.qcloud.com","cvm.api.qcloud.com","snapshot.api.qcloud.com","monitor.api.qcloud.com","scaling.api.qcloud.com","ccs.api.qcloud.com"],"ip":"169.254.0.28"},{"hostnames":["tke.internal.tencentcloudapi.com","clb.internal.tencentcloudapi.com","cvm.internal.tencentcloudapi.com"],"ip":"169.254.0.95"}]}}}}'
```

Fault cause B: Cluster network issue.

Handling method: None currently, submit a support ticket and include the exception stack information from the logs.

## E6007 | E6009 Ingress InternalError

Fault cause: Ingress internal error.

Handling method: Immediately transfer the ticket to misakazhou and include the exception stack information from the logs.

## W1000 Service xxx not found in store

Warning cause: The specified Service does not exist, Ingress rules cannot find the corresponding bound backend.

Handling method: Check if the Service resource described by backend.serviceName exists in the cluster Service resources.

## W1001 clean not creatted by TKE loadbalancer: xxx for ingress:

Warning cause: When deleting Ingress, the load balancer used by Ingress was not deleted.

Detailed description: The load balancer resource used by Ingress does not have the tke-createdBy-flag=yes label, its lifecycle is not managed by Ingress. Need to manually delete it yourself.

Handling method: If needed, you can choose to manually delete this load balancer resource.

## W1002 do not clean listener.

Warning cause: When deleting Ingress, the listener under the load balancer used by Ingress was not deleted.

Detailed description: The listener name under the load balancer resource used by Ingress is not TKE-DEDICATED-LISTENER. This listener was not created by Ingress or was modified, its lifecycle is not managed by Ingress. Need to manually delete it yourself.

Handling method: If needed, you can choose to manually delete the listener under this load balancer resource.
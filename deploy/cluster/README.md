# Cluster prerequisites

Every endpoint depends on four things the cluster provides. The hubsingest
scripts do not create them.

| Prerequisite | Used for | Production |
|---|---|---|
| IngressClass `nginx` | TLS termination, routing, upload size limit | ingress-nginx |
| ClusterIssuer `letsencrypt-prod` | One Let's Encrypt certificate per hostname | cert-manager |
| StorageClass `ebs` with ReadWriteOnce volumes | The contribution volume | The cluster's block-storage CSI driver |
| DNS record `*.hubsingest.bioconductor.org` | Every endpoint hostname | A record to the ingress controller |

The ingress controller and cert-manager are installed from their Helm charts;
see [`../../docs/deployment.md`](../../docs/deployment.md).

| File | Contents |
|---|---|
| `10-cluster-issuer.yaml` | `letsencrypt-prod` and `letsencrypt-staging` ClusterIssuers, HTTP-01 |
| `20-storageclass-ebs.yaml` | An `ebs` StorageClass for the AWS EBS CSI driver, as an example |

```bash
export ACME_CONTACT_EMAIL=<team address>
export HUBSINGEST_INGRESS_CLASS=nginx
envsubst < deploy/cluster/10-cluster-issuer.yaml | kubectl apply -f -
```

Check all four before creating an endpoint:

```bash
kubectl get ingressclass nginx
kubectl get clusterissuer letsencrypt-prod
kubectl get storageclass ebs
dig +short test.hubsingest.bioconductor.org
```

A missing ClusterIssuer does not stop endpoint creation: the gateway starts, the
certificate never becomes ready, and the create workflow fails after its
certificate waits.

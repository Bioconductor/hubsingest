# Deployment

Setting up hubsingest on a new cluster: the cluster add-ons, the repository
secrets, and a first endpoint. [architecture.md](architecture.md) describes the
components.

## Requirements

- A Kubernetes cluster whose API server is reachable from GitHub-hosted
  runners, since the workflows run `kubectl` from there.
- Helm 3.14 or later, `kubectl`, `envsubst`, `dig`, `jq`, the AWS CLI and the
  GitHub CLI on the machine used for setup.
- Admin access to the repository, to set secrets and enable workflows.
- Control of DNS for `hubsingest.bioconductor.org`.

## 1. Cluster add-ons

The templates for this step are in [`deploy/cluster/`](../deploy/cluster/).

### Ingress controller

Production runs ingress-nginx with IngressClass `nginx`. ingress-nginx is
retired upstream: its last release was in March 2026 and it receives no
security fixes. A new cluster should use a maintained controller; see
[Other ingress controllers](#other-ingress-controllers).

RKE2 installs ingress-nginx as its packaged component `rke2-ingress-nginx`,
with IngressClass `nginx`. It listens on host ports 80 and 443 of every node,
so the DNS record points at a node address. Each RKE2 release upgrades it, and
a `HelmChartConfig` named `rke2-ingress-nginx` in `kube-system` changes its
settings. On other distributions, install it with Helm:

```bash
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.ingressClassResource.name=nginx
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

The `EXTERNAL-IP` of the controller service is the address the DNS record
points at. On clusters without a cloud load balancer, such as k3s with
ServiceLB, it is a node address.

ingress-nginx accepts request bodies up to 1 MB by default. Each endpoint
Ingress raises this with `nginx.ingress.kubernetes.io/proxy-body-size: 10g`.
The AWS CLI splits files larger than 8 MB into multipart uploads, so the limit
applies only to clients that send a large file in one request.

#### Other ingress controllers

The endpoint Ingresses need an IngressClass name and a request size limit large
enough for uploads.

- Set the class in the defaults of `HUBSINGEST_INGRESS_CLASS` in
  `scripts/hubsingest_create_endpoint.sh` and
  `scripts/hubsingest_launch_rstudio.sh`; the workflows use the defaults.
  Render the ClusterIssuer with the same class.
- The `proxy-body-size` annotation is read only by ingress-nginx. Configure the
  new controller's equivalent.
- Traefik v3, which k3s installs by default with IngressClass `traefik`, has no
  request size limit but stops reading a request after 60 seconds
  (`transport.respondingTimeouts.readTimeout` on the entry point). Raise it for
  uploads sent in one request.

### cert-manager

Install a release that cert-manager lists as supported at
<https://cert-manager.io/docs/releases/>, then create the issuers:

```bash
helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version <version> \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true

export ACME_CONTACT_EMAIL=<team address>
export HUBSINGEST_INGRESS_CLASS=nginx
envsubst < deploy/cluster/10-cluster-issuer.yaml | kubectl apply -f -
kubectl get clusterissuer letsencrypt-prod
```

`READY` must be `True` before the first endpoint is created. The issuer solves
HTTP-01 through the ingress controller, so it needs no DNS provider
credentials.

Let's Encrypt allows 50 certificates per registered domain every 7 days, and
`bioconductor.org` is the registered domain for every Let's Encrypt
certificate under it. It also allows 5 certificates for the same set of
hostnames every 7 days. For repeated tests from a workstation, export
`HUBSINGEST_CLUSTER_ISSUER=letsencrypt-staging` before `hubsingest
create_endpoint`. Staging certificates are not trusted, so `test_endpoint`
fails TLS verification against them.

### Storage class

Endpoint volumes request StorageClass `ebs` with access mode ReadWriteOnce.
Provide that class from the cluster's block-storage CSI driver.
[`deploy/cluster/20-storageclass-ebs.yaml`](../deploy/cluster/20-storageclass-ebs.yaml)
is an example for the AWS EBS CSI driver; on another platform keep the name and
change the provisioner and its parameters.

```bash
kubectl get storageclass ebs
```

`allowVolumeExpansion: true` lets an endpoint grow after creation.
`reclaimPolicy: Delete` releases the disk when the endpoint is deleted; with
`Retain`, the volume and its data stay until removed by hand.

### DNS

```
*.hubsingest.bioconductor.org.  IN  A  <ingress controller external address>
```

Endpoint hostnames are created and deleted with each contribution, so the
record is a wildcard. Point it directly at the ingress controller, with no
proxy or CDN in front: the ingress controller terminates TLS with the endpoint
certificates and answers the HTTP-01 challenges.

The `bioconductor.org` zone is hosted on Cloudflare. Create the wildcard as a
DNS-only record. A proxied record would route uploads through Cloudflare, which
caps request bodies at 100 MB on the Free and Pro plans.

### Check

```bash
kubectl get ingressclass nginx
kubectl get clusterissuer letsencrypt-prod
kubectl get storageclass ebs
dig +short test.hubsingest.bioconductor.org
```

## 2. Repository configuration

### `KUBECONFIG`

The workflows read the cluster credential from the repository secret
`KUBECONFIG`. Use a dedicated service account bound to the `hubsingest-ci`
ClusterRole listed in
[security.md](security.md#kubeconfig-the-cluster-credential); save that
manifest as `hubsingest-ci-clusterrole.yaml`.

```bash
kubectl create serviceaccount hubsingest-ci -n kube-system
kubectl apply -f hubsingest-ci-clusterrole.yaml
kubectl create clusterrolebinding hubsingest-ci \
  --clusterrole=hubsingest-ci \
  --serviceaccount=kube-system:hubsingest-ci

TOKEN=$(kubectl create token hubsingest-ci -n kube-system --duration=8760h)
SERVER=https://<public API server address>:6443
CA=$(kubectl get configmap kube-root-ca.crt -n kube-system \
  -o jsonpath='{.data.ca\.crt}' | base64 | tr -d '\n')

cat > hubsingest-ci.kubeconfig <<EOF
apiVersion: v1
kind: Config
clusters:
- name: hubsingest
  cluster:
    server: ${SERVER}
    certificate-authority-data: ${CA}
contexts:
- name: hubsingest
  context:
    cluster: hubsingest
    user: hubsingest-ci
current-context: hubsingest
users:
- name: hubsingest-ci
  user:
    token: ${TOKEN}
EOF

KUBECONFIG=hubsingest-ci.kubeconfig kubectl version
KUBECONFIG=hubsingest-ci.kubeconfig kubectl auth can-i --list
gh secret set KUBECONFIG --repo Bioconductor/hubsingest < hubsingest-ci.kubeconfig
rm hubsingest-ci.kubeconfig
```

- The two `kubectl` commands check the file before it is stored: the server
  version shows that the token authenticates, and `auth can-i --list` shows
  the permissions it carries.
- `SERVER` is the address GitHub-hosted runners connect to. It must be listed
  in the API server certificate's subject alternative names (`tls-san` in the
  k3s and RKE2 configuration).
- `CA` is read from the cluster, not from the local kubeconfig, which may
  reach the cluster through a proxy such as Rancher.
- The token expires after the requested duration, or earlier if the API server
  sets `--service-account-max-token-expiration`. Record the expiry date;
  [operations.md](operations.md#kubeconfig) covers rotation.

### `S3KEY_<USERNAME>` and `ADMINPASS_<GITHUB-USERNAME>`

One `S3KEY_<USERNAME>` secret per contributor and one
`ADMINPASS_<GITHUB-USERNAME>` secret per admin, names in uppercase. The
[README](../README.md#managing-secrets) describes both.

### Admin RStudio image

Enable the Build RStudio Image workflow and run it once, so that the image for
the current release exists before the first RStudio launch:

```bash
gh workflow enable build_rstudio.yaml --repo Bioconductor/hubsingest
gh workflow run build_rstudio.yaml --repo Bioconductor/hubsingest
```

The image `ghcr.io/bioconductor/hubsingestbiocrstudio` is public, so the
cluster pulls it without credentials.

## 3. First endpoint

Run **Create Hub Ingest Endpoint** with a test username and a small size such
as `1Gi`, then **Scan Data for Viruses**, **Launch RStudio Instance** and
**Delete Hub Ingest Endpoint** with the same username. The four runs confirm
that the `KUBECONFIG` credential has the permissions the workflows need. When no
`S3KEY_<USERNAME>` secret exists, the script generates a random key, which is
enough for a test. The test step at the end of the create workflow uses DNS,
the ingress controller, the certificate, the gateway, the credentials and the
volume; when it passes, the cluster is ready.

The same check from a workstation with cluster access:

```bash
mkdir hubsingest-cli && cd hubsingest-cli
export BIOC_HUBSINGEST_PATH=$PWD
curl -O https://raw.githubusercontent.com/Bioconductor/hubsingest/devel/install_hubsingest.sh
bash install_hubsingest.sh
export PATH="$PATH:$BIOC_HUBSINGEST_PATH"

hubsingest create_endpoint testuser 1Gi
kubectl wait -n testuser-ns --for=condition=ready pod -l app=versitygw --timeout=300s
kubectl wait -n testuser-ns --for=condition=ready \
  certificate testuser-hubsingest-bioconductor-org-key --timeout=600s
hubsingest test_endpoint testuser
hubsingest delete_endpoint testuser
```

`test_endpoint` needs the AWS CLI.

## 4. Without the tooling

[`deploy/README.md`](../deploy/README.md) renders and applies the endpoint
templates with `envsubst` and `kubectl`.

# Deployment templates

The Kubernetes resources that the scripts in [`../scripts/`](../scripts/)
create, as standalone templates with `${VARIABLE}` placeholders. The workflows
and scripts are the supported way to manage endpoints. The templates are for
review, for bringing up an endpoint without the tooling, and for adapting the
stack to another cluster.

```
deploy/
├── cluster/     cluster-wide prerequisites, applied once
└── endpoint/    one contributor endpoint
```

## Rendering

Render with `envsubst` from GNU gettext. Set every variable a template uses:
`envsubst` replaces an unset variable with an empty string.

```bash
export HUBSINGEST_USER=dataowner
export HUBSINGEST_SIZE=50Gi
export HUBSINGEST_SECRET_KEY="$(openssl rand -hex 32)"
export HUBSINGEST_DOMAIN=hubsingest.bioconductor.org
export HUBSINGEST_STORAGE_CLASS=ebs
export HUBSINGEST_VERSITYGW_IMAGE=ghcr.io/versity/versitygw:v1.7.0
export HUBSINGEST_INGRESS_CLASS=nginx
export HUBSINGEST_CLUSTER_ISSUER=letsencrypt-prod
export HUBSINGEST_MAX_BODY_SIZE=10g

envsubst < deploy/endpoint/00-namespace.yaml | kubectl apply -f -
for f in deploy/endpoint/[1-5]*.yaml; do envsubst < "$f"; done \
  | kubectl apply -n "${HUBSINGEST_USER}-ns" -f -
```

The numeric prefix is the apply order. `00` to `50` are the upload endpoint.
`60-rstudio.yaml` and `70-virus-scan-job.yaml` are admin operations and mount
the same ReadWriteOnce volume, so scale the gateway down first:

```bash
kubectl scale deployment versitygw -n "${HUBSINGEST_USER}-ns" --replicas=0
envsubst < deploy/endpoint/70-virus-scan-job.yaml \
  | kubectl apply -n "${HUBSINGEST_USER}-ns" -f -
```

## Variables

| Variable | Templates | Meaning | Production value |
|---|---|---|---|
| `HUBSINGEST_USER` | `00-namespace`, `10-secret`, `50-ingress`, `60-rstudio` | Contributor name: namespace prefix, DNS label and S3 access key. Lowercase | per contributor |
| `HUBSINGEST_SIZE` | `20-pvc` | Volume size, e.g. `50Gi` | per contribution |
| `HUBSINGEST_SECRET_KEY` | `10-secret` | S3 secret key, from `openssl rand -hex 32` | `S3KEY_<USERNAME>` |
| `HUBSINGEST_DOMAIN` | `50-ingress`, `60-rstudio` | DNS zone of the endpoint hostnames | `hubsingest.bioconductor.org` |
| `HUBSINGEST_STORAGE_CLASS` | `20-pvc` | StorageClass of the volume | `ebs` |
| `HUBSINGEST_VERSITYGW_IMAGE` | `30-deployment-versitygw` | S3 gateway image | default in `scripts/hubsingest_create_endpoint.sh` |
| `HUBSINGEST_INGRESS_CLASS` | `50-ingress`, `60-rstudio`, `cluster/10-cluster-issuer` | IngressClass name | `nginx` |
| `HUBSINGEST_CLUSTER_ISSUER` | `50-ingress`, `60-rstudio` | cert-manager ClusterIssuer | `letsencrypt-prod` |
| `HUBSINGEST_MAX_BODY_SIZE` | `50-ingress` | Largest single request the ingress accepts | `10g` |
| `HUBSINGEST_BIOC_VERSION` | `60-rstudio` | Bioconductor release of the admin RStudio image | current release |
| `HUBSINGEST_RSTUDIO_PASSWORD` | `60-rstudio` | RStudio password | `ADMINPASS_<GITHUB-USERNAME>` |
| `ACME_CONTACT_EMAIL` | `cluster/10-cluster-issuer` | ACME account contact | team address |

`scripts/hubsingest_create_endpoint.sh` reads `HUBSINGEST_VERSITYGW_IMAGE`,
`HUBSINGEST_STORAGE_CLASS`, `HUBSINGEST_INGRESS_CLASS`,
`HUBSINGEST_CLUSTER_ISSUER` and `HUBSINGEST_MAX_BODY_SIZE` from the
environment, and `scripts/hubsingest_launch_rstudio.sh` reads the ingress
class and issuer; the defaults are the production values. The scripts always
use `hubsingest.bioconductor.org`.

## Keeping templates and scripts in sync

Each endpoint template mirrors a manifest written by a script in `scripts/`.
Change both in the same commit.

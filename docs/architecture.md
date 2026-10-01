# Architecture

hubsingest gives each contributor to AnnotationHub or ExperimentHub a
short-lived, S3-compatible upload endpoint on Kubernetes. An admin scans and
reviews the upload, copies it to the Hubs' storage, and deletes the endpoint.

## Overview

```
GitHub Actions workflows ── kubectl, KUBECONFIG secret ──► Kubernetes API

Contributor ── HTTPS ──► ingress controller ── TLS certificates from cert-manager
                               │
               namespace <username>-ns
               ├── Ingress versitygw          <username>.hubsingest.bioconductor.org
               ├── Service versitygw          port 80 → 10000
               ├── Deployment versitygw       Versity S3 Gateway, POSIX backend
               ├── Secret versitygw-credentials
               ├── PVC versitygw-data         ReadWriteOnce, StorageClass ebs
               │
               │   admin operations, with versitygw scaled to zero
               ├── Job virus-scan             ClamAV
               └── Deployment, Service and Ingress rstudio
                                              <username>-rstudio.hubsingest.bioconductor.org
```

## Components

| Component | Where it comes from | Role |
|---|---|---|
| Workflows | [`.github/workflows/`](../.github/workflows/) | Operator interface |
| `hubsingest` and `scripts/` | this repository | Write and apply the manifests |
| Versity S3 Gateway | `ghcr.io/versity/versitygw`, tag set in `scripts/hubsingest_create_endpoint.sh` | S3 API over a directory on the volume |
| ClamAV | `clamav/clamav:stable` | Virus scan of the upload |
| Admin RStudio image | `ghcr.io/bioconductor/hubsingestbiocrstudio:<release>`, built from [`Dockerfile`](../Dockerfile) | Review and transfer: the Bioconductor container plus [rclone](https://rclone.org) |
| Ingress controller | cluster add-on, ingress-nginx in production | TLS termination and routing |
| cert-manager | cluster add-on | One Let's Encrypt certificate per hostname |
| StorageClass `ebs` | cluster add-on | One block volume per contribution |

### Workflows

| Workflow | Runs | Effect |
|---|---|---|
| Create Hub Ingest Endpoint | `create_endpoint`, `test_endpoint` | Creates the namespace and its resources, waits for the gateway and the certificate, then uploads, lists and deletes a test object |
| Scan Data for Viruses | `scan_data` | Scales the gateway to zero, scans the volume, prints the report; fails when ClamAV finds infected files or reports errors |
| Launch RStudio Instance | `launch_rstudio` | Scales the gateway to zero and starts RStudio with the volume mounted |
| Delete Hub Ingest Endpoint | `delete_endpoint` | Deletes `<username>-ns`, or every namespace ending in `-ns` for `ALL` |
| Build RStudio Image | `docker/build-push-action` | Builds the admin image for the current Bioconductor release, daily at 00:00 UTC |

The create, scan and launch workflows download `hubsingest` and `scripts/`
from the `devel` branch with `install_hubsingest.sh`, whichever branch they run
on. The delete workflow runs the scripts from its own checkout. Changes to
`scripts/` therefore reach production when they are merged into `devel`.

### Versity S3 Gateway

The gateway runs the POSIX backend: a bucket is a directory and an object is a
file under `/mnt/versitydata`, the mount point of the volume. Uploaded data can
be read with ordinary file tools once the gateway has stopped.

The gateway is started with `ROOT_ACCESS_KEY` and `ROOT_SECRET_KEY` from the
`versitygw-credentials` Secret and no IAM backend, so the root pair is its only
identity. The access key is the contributor's username.

### Namespace per contributor

All resources of an endpoint live in `<username>-ns`. Deleting the namespace
deletes the gateway, the ingresses, the certificates, the credentials and the
volume claim. The workflows lowercase the username, because namespace names and
DNS labels must be lowercase.

### Storage

The volume claim is ReadWriteOnce on StorageClass `ebs`, so the volume attaches
to one node at a time. The gateway, the virus scan and RStudio mount the same
volume and can be scheduled on different nodes, so `scan_data` and
`launch_rstudio` scale the gateway to zero first. The contributor's endpoint is
offline from then until the gateway is scaled back to one replica, and an
upload in progress at that moment fails.

### TLS and DNS

A wildcard record `*.hubsingest.bioconductor.org` points every hostname at the
ingress controller. Each Ingress carries the annotation
`cert-manager.io/cluster-issuer: letsencrypt-prod`, so cert-manager requests a
certificate for each hostname:

| Host | Purpose | TLS Secret and Certificate name |
|---|---|---|
| `<username>.hubsingest.bioconductor.org` | S3 endpoint | `<username>-hubsingest-bioconductor-org-key` |
| `<username>-rstudio.hubsingest.bioconductor.org` | admin RStudio | `<username>-rstudio-tls` |

Each new endpoint is a new certificate order and counts against the Let's
Encrypt rate limits. `scripts/reset_endpoint_ssl.sh` deletes the Order,
CertificateRequest and Certificate of a stuck issuance so that cert-manager
starts again.

### Virus scan

The scan is a Job whose init container runs `clamscan -r` on the read-only
volume and writes the report to an `emptyDir`. A `busybox` container keeps the
pod running so that `scan_data` can copy the report with `kubectl cp`. The init
container records clamscan's exit code in the report and exits 0; `scan_data`
reads the code, prints the report and deletes the Job.

### Admin RStudio

RStudio mounts the volume at `/home/rstudio/shareddata`. The login is user
`rstudio` with the password from the launching admin's
`ADMINPASS_<GITHUB-USERNAME>` repository secret. The admin reviews the data and
copies it to the Hubs' storage with rclone.

## State

| What | Where | Lifetime |
|---|---|---|
| Uploaded data | PVC `versitygw-data` in the endpoint namespace | Until the namespace is deleted; there is no other copy until it is promoted |
| Contributor S3 secret key | Repository secret `S3KEY_<USERNAME>` and Secret `versitygw-credentials` | Repository secret until removed by hand; Secret until the namespace is deleted |
| Admin RStudio passwords | Repository secrets `ADMINPASS_<GITHUB-USERNAME>`; copied into the `rstudio` Deployment | Until removed by hand |
| Cluster credential | Repository secret `KUBECONFIG` | Until rotated |
| Endpoint certificates | TLS Secrets in the endpoint namespace | Until the namespace is deleted |
| Admin RStudio image | GitHub Container Registry | Each build replaces the current release's tag and `latest` |

## External dependencies

| Dependency | Used by |
|---|---|
| GitHub Actions and the `KUBECONFIG`, `S3KEY_*` and `ADMINPASS_*` secrets | Every operation |
| `raw.githubusercontent.com` | `install_hubsingest.sh` in the workflows |
| `dl.k8s.io` | `kubectl` in the workflows |
| Let's Encrypt | Endpoint certificates |
| Docker Hub | `amazon/aws-cli`, `clamav/clamav`, `busybox` |
| GitHub Container Registry | `versitygw`, the Bioconductor base image, the admin RStudio image |
| `bioconductor.org/config.yaml` | Current release for the image build |
| `downloads.rclone.org` | rclone in the admin image |

## Scripts and templates

[`deploy/endpoint/`](../deploy/endpoint/) holds the manifests that the scripts
write, as `envsubst` templates. Both are maintained by hand and must change
together; see [`deploy/README.md`](../deploy/README.md).

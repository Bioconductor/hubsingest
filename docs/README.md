# hubsingest documentation

For maintainers of the Bioconductor Hubs ingest service. The
[README](../README.md) covers day-to-day use by admins and contributors.

| Page | Contents |
|---|---|
| [architecture.md](architecture.md) | Components, workflows, state, external dependencies |
| [deployment.md](deployment.md) | Cluster add-ons, repository secrets and a first endpoint |
| [operations.md](operations.md) | A contribution end to end, health checks, credential rotation, routine tasks |
| [updating.md](updating.md) | Update procedures and cadence for images, workflows and cluster add-ons |
| [troubleshooting.md](troubleshooting.md) | Symptom, cause and fix |
| [security.md](security.md) | Trust boundaries, credentials, exposed services, reporting a vulnerability |
| [examples/](examples/) | Example values for the templates and a worked contribution |
| [`../deploy/`](../deploy/) | Kubernetes templates for the cluster prerequisites and one endpoint |

## Quick facts

| | |
|---|---|
| Hosts | `<username>.hubsingest.bioconductor.org` (S3 endpoint), `<username>-rstudio.hubsingest.bioconductor.org` (admin RStudio) |
| DNS | Wildcard record `*.hubsingest.bioconductor.org` to the ingress controller |
| Cluster | RKE2 with CloudMan and Rancher (`cloudman.hubsingest.bioconductor.org`, `rancher.cloudman.hubsingest.bioconductor.org`); `curl -s https://rancher.cloudman.hubsingest.bioconductor.org/version` shows the Kubernetes version |
| Cluster add-ons | ingress-nginx with IngressClass `nginx`, cert-manager with ClusterIssuer `letsencrypt-prod`, StorageClass `ebs` |
| Operator interface | The GitHub Actions workflows in this repository, with the `KUBECONFIG` secret |
| Images | `ghcr.io/versity/versitygw`, `clamav/clamav:stable` and `busybox` (scan job), `ghcr.io/bioconductor/hubsingestbiocrstudio`, `amazon/aws-cli` (create workflow container) |
| Persistent state | One volume per open contribution, no backups |

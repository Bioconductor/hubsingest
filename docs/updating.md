# Updating

What changes over time in hubsingest, how often to update it, how to check the
update worked, and how to roll it back.

The endpoint workflows download the scripts from `devel` at run time, and
workflows run from `devel` by default. An update to `scripts/` or to
a workflow takes effect when it is merged into `devel`, and reverting the merge
rolls it back.

## Cadence

| Component | Set in | Cadence |
|---|---|---|
| Bioconductor release | `launch_rstudio.yaml`, `scripts/hubsingest_launch_rstudio.sh` | Each Bioconductor release, twice a year |
| Admin RStudio image | Build RStudio Image workflow | Daily and automatic; check monthly that the workflow is enabled |
| rclone | `Dockerfile` | Quarterly, and for security releases |
| ClamAV image and signatures | `scripts/hubsingest_scan_data.sh` | Pulled at every scan; review at each ClamAV feature release |
| versitygw | `scripts/hubsingest_create_endpoint.sh` | Quarterly, and for security releases |
| aws-cli container | `create_endpoint.yaml` | Quarterly |
| GitHub Actions | `uses:` in `.github/workflows/` | New releases, and before GitHub removes a runtime they use |
| kubectl | `KUBECTL_VERSION` in the four endpoint workflows | With every Kubernetes upgrade |
| Kubernetes | the cluster | At least yearly, before the running minor version leaves support |
| Rancher | the cluster | Security releases as published; a minor upgrade before the running line leaves maintenance |
| cert-manager | the cluster | Stay on a supported release; one is published about every four months |
| Ingress controller | the cluster | Security releases; ingress-nginx publishes none and needs replacing |
| Storage driver | the CSI driver behind StorageClass `ebs` | Before each Kubernetes upgrade it does not support, and for security releases |
| Node operating system | the cluster nodes | Monthly security updates |

## Checking an update

Run these against a test endpoint after any update. A test username needs no
`S3KEY_<USERNAME>` secret; the script generates a key. Each run issues new
certificates, and Let's Encrypt issues at most 5 for the same hostname every 7
days, so use a different test username for each run in a week, such as
`testuser1` and `testuser2`.

1. **Create Hub Ingest Endpoint** with the test username and `1Gi`. The run
   passes only when the test object round-trip succeeds.
2. **Scan Data for Viruses** with the test username. An empty volume scans
   clean.
3. **Launch RStudio Instance** with the test username, then log in.
4. **Delete Hub Ingest Endpoint** with the test username.

The **Install Kubectl** step of each run prints the client and server versions.

## Bioconductor release

`build_rstudio.yaml` reads `release_version` from
`https://bioconductor.org/config.yaml` and builds the image for it, so the image
for a new release appears with the first build after release day. The launch
default is a literal and changes by hand.

1. Run **Build RStudio Image**, or wait for the daily run, and confirm the tag
   (the token needs the `read:packages` scope, as in
   [Admin RStudio image](#admin-rstudio-image)):

   ```bash
   gh api /orgs/Bioconductor/packages/container/hubsingestbiocrstudio/versions \
     --jq '.[] | select(any(.metadata.container.tags[]; . == "<release>")) | .created_at'
   ```

2. Set the new release in:
   - the `bioc_version` default and description in `.github/workflows/launch_rstudio.yaml`
   - the `BIOC_VERSION` default and the usage example in
     `scripts/hubsingest_launch_rstudio.sh`
   - `HUBSINGEST_BIOC_VERSION` in `docs/examples/endpoint.env`
   - the `launch_rstudio` examples in `README.md` and `docs/examples/README.md`
3. Launch RStudio on a test endpoint, open a terminal, and run `rclone version`.

Roll back by launching with the previous release in the `bioc_version` input;
the tags of earlier releases stay in the registry.

## Admin RStudio image

**Build RStudio Image** rebuilds `ghcr.io/bioconductor/hubsingestbiocrstudio`
daily at 00:00 UTC from `ghcr.io/bioconductor/bioconductor:<release>` plus
rclone, and pushes the release tag and `latest`. The RStudio deployment uses
`imagePullPolicy: Always`, so each launch gets the latest build. Check a build
by launching RStudio on a test endpoint.

Each build moves the release tag; the registry keeps earlier builds as
untagged versions. To roll back, launch with an earlier build's digest in the
`bioc_version` input, such as `3.23@sha256:<digest>`. List the builds with
their digests and tags (the token needs the `read:packages` scope:
`gh auth refresh -s read:packages`):

```bash
gh api --paginate /orgs/Bioconductor/packages/container/hubsingestbiocrstudio/versions \
  --jq '.[] | [.name, .created_at, (.metadata.container.tags | join(","))] | @tsv'
```

GitHub disables the schedule after 60 days without repository activity. Check
monthly:

```bash
gh workflow list --all --repo Bioconductor/hubsingest
gh run list --workflow build_rstudio.yaml --repo Bioconductor/hubsingest --limit 3
```

Re-enable it as in
[troubleshooting.md](troubleshooting.md#the-admin-rstudio-image-is-out-of-date).

### rclone

The `Dockerfile` installs the rclone release set in `RCLONE_VERSION` and checks
the download against `RCLONE_SHA256`; a mismatch fails the build. To update,
take the newest version from <https://rclone.org/downloads/> and the checksum
of `rclone-<version>-linux-amd64.deb` from
`https://downloads.rclone.org/<version>/SHA256SUMS`, change both, and run
**Build RStudio Image**. Check with `rclone version` in a terminal of a
launched RStudio. Roll back by restoring both values.

## ClamAV image and signatures

The scan runs `clamscan` from `clamav/clamav:stable`. That image contains the
signature databases and is republished with newer ones; the scan does not run
`freshclam`, so the signatures are those of the image. The scan job pulls the
image at every run (`imagePullPolicy: Always`). `stable` follows the current
ClamAV feature release.

- **Check:** the report printed by the scan shows the engine version and the
  number of known signatures, and clamscan warns in the report when its
  database is more than 7 days old. Scan a test endpoint holding the
  [EICAR test file](https://www.eicar.org/download-anti-malware-testfile/): the
  workflow must fail with `Infected files found (clamscan exit 1)`.
- **At a ClamAV feature release:** read the release notes for changes to
  `clamscan` options or exit codes. `scripts/hubsingest_scan_data.sh` treats
  0 as clean, 1 as infected and anything else as not cleared.
- **Roll back** by pinning a specific tag in `scripts/hubsingest_scan_data.sh`
  and `deploy/endpoint/70-virus-scan-job.yaml`.

The scan job's `busybox` container uses the floating `busybox` tag.

## versitygw

The gateway keeps no state outside the volume, so changing its image replaces
the pod and leaves the data untouched.

1. Read the release notes from <https://github.com/versity/versitygw/releases>.
   The deployment depends on the global options `--debug` and `--port`, the
   `posix` backend with a directory argument, and the `ROOT_ACCESS_KEY` and
   `ROOT_SECRET_KEY` variables.
2. Test the new image on a scratch endpoint, with the `hubsingest` CLI
   installed as in [deployment.md](deployment.md#3-first-endpoint) and the AWS
   CLI:

   ```bash
   hubsingest create_endpoint vgwtest 1Gi
   kubectl wait -n vgwtest-ns --for=condition=ready \
     certificate vgwtest-hubsingest-bioconductor-org-key --timeout=600s
   kubectl scale deployment versitygw -n vgwtest-ns --replicas=0
   kubectl set image deployment/versitygw -n vgwtest-ns \
     versitygw=ghcr.io/versity/versitygw:<new-tag>
   kubectl scale deployment versitygw -n vgwtest-ns --replicas=1
   kubectl rollout status deployment/versitygw -n vgwtest-ns
   hubsingest test_endpoint vgwtest
   hubsingest delete_endpoint vgwtest
   ```

3. Change the tag in `scripts/hubsingest_create_endpoint.sh`,
   `docs/examples/endpoint.env` and the example in `deploy/README.md`.

New endpoints use the new tag. Existing endpoints keep their image until
changed with the `kubectl scale` and `kubectl set image` commands above; the
scale-down frees the ReadWriteOnce volume for the new pod. Roll back the same
way with the previous tag.

## aws-cli container

The create workflow runs in `amazon/aws-cli:<version>@sha256:<digest>`, which
is based on Amazon Linux 2023: packages are installed with `dnf`, and `curl` is
provided by `curl-minimal`. The digest pins the image, so a tag moved on Docker
Hub does not change what runs. Pick the newest `2.x` tag from Docker Hub and
read its digest:

```bash
curl -s https://hub.docker.com/v2/repositories/amazon/aws-cli/tags/<version> | jq -r .digest
```

Change both in `.github/workflows/create_endpoint.yaml`, and run the create
step of [Checking an update](#checking-an-update). Roll back by restoring the
previous tag and digest.

## GitHub Actions

`build_rstudio.yaml` uses `actions/checkout`, `docker/login-action` and
`docker/build-push-action`; the delete, launch and scan workflows use
`actions/checkout`. `actions/checkout` is pinned to its major version tag. The
Docker actions are pinned to the commit of a release, named in a comment; the
commit of a new release is:

```bash
gh api repos/docker/build-push-action/commits/<tag> --jq .sha
```

- Run annotations warn when an action uses a Node.js runtime that GitHub is
  deprecating. Move to the major version that uses the current runtime before
  the removal date in the warning.
- Read the release notes of each new version for changed inputs.
- Check with a manual run of **Build RStudio Image** and the steps in
  [Checking an update](#checking-an-update).
- Roll back by restoring the previous tag or commit.

## kubectl in the workflows

`KUBECTL_VERSION` in `create_endpoint.yaml`, `delete_endpoint.yaml`,
`launch_rstudio.yaml` and `scan_data.yaml` must be within one minor version of
the cluster's Kubernetes version. Rancher reports the production cluster's
version without credentials:

```bash
curl -s https://rancher.cloudman.hubsingest.bioconductor.org/version
```

Change all four after each cluster upgrade, to the latest patch of the
cluster's minor version:

```bash
curl -L https://dl.k8s.io/release/stable-<minor>.txt    # e.g. stable-1.32.txt
```

`kubectl version` in the **Install Kubectl** step prints a warning when the
skew is larger than one minor version.

## Kubernetes and Rancher

Kubernetes supports each minor version for about 14 months. Control planes
upgrade one minor version at a time.

The production cluster runs RKE2 with Rancher, whose release limits the
Kubernetes versions the cluster can run. Both versions are public:

```bash
curl -s https://rancher.cloudman.hubsingest.bioconductor.org/version          # Kubernetes
curl -s https://rancher.cloudman.hubsingest.bioconductor.org/rancherversion   # Rancher
```

1. Find the range of Kubernetes versions the running Rancher release supports,
   from the Rancher support matrix. If the target version is above that range,
   upgrade [Rancher](#rancher) first. A cluster below that range is upgraded
   with step 2 until it is inside it.
2. For each minor version up to the target:
   1. Check that cert-manager, the ingress controller and the storage driver
      support the next version (sections below); upgrade them first if not.
   2. Take an etcd snapshot (`rke2 etcd-snapshot save` on a server node).
   3. Upgrade to the latest patch of the next minor version with the RKE2
      upgrade procedure, or with Rancher's cluster upgrade for a cluster that
      Rancher provisioned.
   4. Update `KUBECTL_VERSION` and run [Checking an update](#checking-an-update).

Roll back a minor version upgrade by restoring the snapshot taken before it.

Kubernetes 1.25 removes PodSecurityPolicy; Pod Security Admission replaces
it. Before upgrading from 1.24:

- List the policies with `kubectl get podsecuritypolicy`.
- Turn off PodSecurityPolicy in the values of every Helm release that creates
  one, and upgrade the release. Helm cannot upgrade a release whose stored
  manifest contains a removed API.
- On RKE2 nodes that set `profile` in their configuration, follow the RKE2
  known issue "Upgrading Hardened Clusters from v1.24.x to v1.25.x".

The hubsingest manifests use only stable APIs (`v1`, `apps/v1`, `batch/v1`,
`networking.k8s.io/v1`, `storage.k8s.io/v1`, `cert-manager.io/v1`).

### Rancher

Rancher publishes security fixes as patch releases of its maintained minor
versions. Apply them when they are published, and move to the next minor
version before the running one leaves maintenance.

1. Back up Rancher with the Rancher Backups operator, and take an etcd
   snapshot.
2. Upgrade with `helm upgrade` as in the Rancher upgrade guide: first to the
   latest patch of the running minor version, then to the latest patch of the
   next one. Rancher supports no other path between minor versions.
3. Check that the Rancher UI loads and that `/rancherversion` reports the new
   version.

Roll back by restoring the backup, as in the Rancher rollback guide.

## cert-manager

cert-manager supports at least its two most recent minor releases, publishes a
release about every four months, and lists the Kubernetes versions each release
supports at <https://cert-manager.io/docs/releases/>. An old Kubernetes version
can rule out every supported cert-manager release; upgrade Kubernetes first in
that case.

Upgrade one minor version at a time, to the latest patch of each. Find the
release, and whether the chart manages the CRDs:

```bash
helm list -A | grep cert-manager            # release name and namespace
kubectl get crd certificates.cert-manager.io \
  -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}{"\n"}'
```

When the `kubectl get crd` command prints an empty line, the CRDs were
installed separately; apply the new ones first:

```bash
kubectl apply -f \
  https://github.com/cert-manager/cert-manager/releases/download/<version>/cert-manager.crds.yaml
```

Then upgrade the chart:

```bash
helm upgrade --reset-then-reuse-values --version <version> \
  <release> oci://quay.io/jetstack/charts/cert-manager -n <namespace>
kubectl get pods -n <namespace>
kubectl get clusterissuer letsencrypt-prod
kubectl get certificate -A
```

Then create a test endpoint, which needs a new certificate. Roll back with
`helm rollback <release> -n <namespace>`.

## Ingress controller

Production runs ingress-nginx, which is retired: its last releases were
published in March 2026, and it receives no security fixes. Until it is
replaced, run the newest release that supports the cluster's Kubernetes
version, from the support table in the ingress-nginx README; controller v1.15.1
supports Kubernetes 1.31 to 1.35. Versions before v1.11.5, and v1.12.0, are
vulnerable to CVE-2025-1974. The fixed releases need Kubernetes 1.26 or later,
so an older cluster needs a [Kubernetes upgrade](#kubernetes-and-rancher)
before the controller can be patched.

On RKE2, the packaged `rke2-ingress-nginx` is upgraded with RKE2 and
configured with a `HelmChartConfig`; the Helm command in
[deployment.md](deployment.md#ingress-controller) is for other distributions.
Show the running controller image (`rancher/nginx-ingress-controller` on
RKE2):

```bash
kubectl get pods -A -o jsonpath='{range .items[*]}{.spec.containers[*].image}{"\n"}{end}' \
  | grep -E 'ingress-nginx|nginx-ingress'
```

To move to another controller:

1. Install it alongside ingress-nginx, with its own IngressClass and address.
2. Configure its request size limit and timeouts for uploads; see
   [deployment.md](deployment.md#other-ingress-controllers).
3. Change the `HUBSINGEST_INGRESS_CLASS` defaults in
   `scripts/hubsingest_create_endpoint.sh` and
   `scripts/hubsingest_launch_rstudio.sh`, the value in
   `docs/examples/endpoint.env`, `docs/examples/cluster.env` and
   `deploy/README.md`, and replace the ingress-nginx annotation in the create
   script and `deploy/endpoint/50-ingress.yaml` with the new controller's
   equivalent.
4. Render the ClusterIssuer with the new class.
5. Move the Ingresses of each endpoint to the new class: `versitygw`, and
   `rstudio-ingress` while RStudio runs:

   ```bash
   for ing in $(kubectl get ingress -n <username>-ns -o name); do
     kubectl patch "$ing" -n <username>-ns --type merge \
       -p '{"spec":{"ingressClassName":"<new-class>"}}'
   done
   ```

6. Point `*.hubsingest.bioconductor.org` at the new controller's address and
   run [Checking an update](#checking-an-update).

Run steps 4 to 6 together, when no upload is in progress. Until the DNS change
takes effect, new certificates are not issued after step 4, and endpoints are
unreachable after step 5.

Roll back by pointing the DNS record at ingress-nginx again and restoring the
previous IngressClass on the endpoint Ingresses.

## Storage driver

The CSI driver behind StorageClass `ebs` provisions, attaches and deletes the
endpoint volumes:

```bash
kubectl get storageclass ebs -o jsonpath='{.provisioner}{"\n"}'
kubectl get csidrivers
```

Upgrade it with the tool that installed it, to a release that supports the
cluster's current and next Kubernetes version, before each Kubernetes upgrade.
Creating and deleting a test endpoint checks it: creation provisions, attaches
and mounts a volume, and deletion deletes it. Roll back with the same tool, for
example `helm rollback` for a Helm release.

## Node operating system

Apply security updates on the cluster nodes monthly, one node at a time.
Before rebooting a node, drain it with
`kubectl drain <node> --ignore-daemonsets`; endpoints whose gateway ran on that
node are unreachable until the gateway runs again. After the reboot:

```bash
kubectl get nodes -o wide        # the node is Ready, with the new KERNEL-VERSION
kubectl uncordon <node>
```

Then create and delete a test endpoint. Roll back a kernel update by booting
the previous kernel, and a package update with the distribution's package
manager.

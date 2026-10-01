# Security

hubsingest accepts data from people outside the project and hands it to admins
for review. This page lists the trust boundaries, what each credential grants,
and how to report a problem.

## Trust boundaries

```
Contributor (untrusted)
    │  S3 over HTTPS, one key pair per endpoint
    ▼
Endpoint namespace <username>-ns: gateway, volume, Secret, Ingress
    │  admin scales the gateway down and mounts the same volume
    ▼
ClamAV scan, then RStudio review    ← admin works on contributor data
    │  rclone, with the admin's storage credentials
    ▼
Hubs storage (trusted)
```

The tooling does not enforce the order scan, review, promote. An admin can
launch RStudio on data that was never scanned.

## Credentials

### `S3KEY_<USERNAME>`

Grants full S3 access to one endpoint: create and delete buckets, read, write
and delete objects. It is the gateway's root key and reaches nothing outside
its namespace.

- Generate it with `openssl rand -hex 32`, one per contribution.
- The access key is the username and is public; only the secret key is secret.
- Send it to the contributor over a channel other than email, and never in an
  issue or pull request.
- It exists in the repository secret, the `versitygw-credentials` Secret and
  the contributor's machine. Deleting the endpoint removes the Secret; delete
  the repository secret at the same time.

A leaked key lets anyone write to the endpoint, and an admin later scans and
opens what was written. Rotate it as in
[operations.md](operations.md#s3key_username) or delete the endpoint.

### `ADMINPASS_<GITHUB-USERNAME>`

The RStudio password of every session that admin launches, for any
contributor. RStudio runs as `rstudio` with the contribution mounted and rclone
installed. The launch workflow uses the secret of the admin who dispatches it,
and the run log records who launched which session. Anyone with write access
to the repository can read every `ADMINPASS_*` value, through a modified
workflow or from a running `rstudio` Deployment.

- Use a long, unique password from a password manager.
- `hubsingest_launch_rstudio.sh` writes the password into the `rstudio`
  Deployment as a plain environment value, readable by anyone who can read
  Deployments in the namespace.
- Delete the secret when the admin leaves the team.

### `KUBECONFIG`: the cluster credential

Grants whatever its service account can do. Everyone who can run workflows in
the repository can use it, so repository write access is cluster access.

The tooling needs the following permissions. Bind this ClusterRole instead of
`cluster-admin`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: hubsingest-ci
rules:
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list", "create", "patch", "delete"]
  - apiGroups: [""]
    resources: ["secrets", "services", "persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "create", "patch", "delete"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods/exec"]          # kubectl cp of the scan report
    verbs: ["create"]
  - apiGroups: ["apps"]
    resources: ["deployments", "deployments/scale"]
    verbs: ["get", "list", "watch", "create", "patch", "update", "delete"]
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["get", "list", "watch", "create", "patch", "delete"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["get", "list", "watch", "create", "patch", "delete"]
  - apiGroups: ["cert-manager.io"]
    resources: ["certificates", "certificaterequests"]
    verbs: ["get", "list", "watch", "delete"]
  - apiGroups: ["acme.cert-manager.io"]
    resources: ["orders"]
    verbs: ["get", "list", "delete"]
```

This role can still read every Secret and start workloads in every namespace,
which amounts to control of the cluster. Kubernetes RBAC cannot limit a
ClusterRole to namespaces that do not exist yet.

The API server must accept connections from GitHub-hosted runners, so it is
reachable from the internet. A self-hosted runner inside the cluster network
would allow closing it.

## Exposed services

### S3 endpoint

Public, behind TLS, authenticated by one key pair. There is no rate limit or
address allow-list; the ingress body size limit is the only request limit.
Options, in order of effort:

1. An ingress-nginx rate limit annotation (`nginx.ingress.kubernetes.io/limit-rps`).
2. An address allow-list annotation (`nginx.ingress.kubernetes.io/whitelist-source-range`)
   when the contributor's network is known.
3. Deleting endpoints that are not in use; see
   [operations.md](operations.md#routine-tasks).

The gateway runs with `--debug`, which writes every request's URL, headers
and query arguments, and request and response bodies other than object data,
to the pod log.
Anyone who can read pod logs in the namespace sees bucket and object names.

### Admin RStudio

Public, behind TLS, protected by one password with no second factor, and
running where admin credentials meet contributor data. It runs until the
endpoint is deleted. Delete the endpoint when the review is finished.

### Cluster management UIs

Rancher (`rancher.cloudman.hubsingest.bioconductor.org`) and CloudMan
(`cloudman.hubsingest.bioconductor.org`) are served by the same ingress
controller as the endpoints, and both manage the cluster. Restrict them to
known addresses or put them behind a VPN, and keep Rancher on a release line
that receives security fixes.

### Contributor data in R

ClamAV detects known malware. It does not detect R data built to run code.
Objects read from `.rds`, `.rda` and `.RData` files can contain functions,
environments and formulas that run when used, and R before 4.4.0 could run
code while reading such a file (CVE-2024-27322).

- Do not `source()` contributor scripts.
- Read contributor R objects only in a session that holds no production
  credentials; configure rclone afterwards, in a new RStudio launch if R
  objects were loaded.
- Give rclone a credential for the destination bucket only.

### `delete_endpoint ALL`

Deletes every namespace ending in `-ns`, without confirmation and without
undo, for anyone with repository write access. The workflow lists the
namespaces before deleting them.

### Workflows

- Several steps interpolate `inputs.username` directly into shell commands, so
  a crafted username runs shell code. Anyone who can dispatch a workflow
  already holds the cluster credential through it. Pass inputs and secrets to
  new steps through `env:`.
- Each workflow limits `GITHUB_TOKEN` to `contents: read`; **Build RStudio
  Image** also has `packages: write`.
- `actions/checkout` is pinned to a major version tag, which its publisher can
  move. The Docker actions are pinned to commit SHAs, and the create
  workflow's `amazon/aws-cli` container to an image digest.
- The workflows check the downloaded `kubectl` against the SHA-256 checksum
  published with it.

## Data handling

- **At rest:** depends on the StorageClass. The example class sets
  `encrypted: "true"`; check the driver used in production.
- **In transit:** TLS from the client to the ingress controller, plain HTTP from
  the controller to the gateway inside the cluster.
- **Retention:** data stays until the namespace is deleted. With
  `reclaimPolicy: Delete` the cloud volume is deleted too; with `Retain` it
  remains until removed by hand. Deleting a volume is not a secure erase.
- **Backups:** none. See [operations.md](operations.md#backups).

## Recommended changes

Not applied in the templates or the scripts:

- **A NetworkPolicy in each endpoint namespace** that admits traffic only from
  the ingress controller. Inside the cluster, the gateway and RStudio serve
  plain HTTP to any pod.
- **An egress policy for the `rstudio` pod** that blocks the Kubernetes API and
  the instance metadata address `169.254.169.254`. The pod holds contributor
  data and the admin's rclone credentials. Whether policies are enforced
  depends on the cluster's network plugin.
- **`automountServiceAccountToken: false`** on the gateway, scan and RStudio
  pods. None of them calls the Kubernetes API.
- **A restrictive security context** where the image allows it, such as the
  gateway and the scan's `holder` container: `allowPrivilegeEscalation: false`,
  `capabilities: {drop: [ALL]}` and `runAsNonRoot: true`.
- **Resource requests and limits**; see
  [operations.md](operations.md#known-limitations).

## Reporting a vulnerability

Do not open a public issue. Email the Bioconductor core team at
[bioconductorcoreteam@gmail.com](mailto:bioconductorcoreteam@gmail.com), the
address listed at <https://bioconductor.org/about/>.

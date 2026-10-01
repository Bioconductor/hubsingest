# Operations

Running contributions through the service, checking its health, and rotating
credentials.

## A contribution, start to finish

1. **Agree on size and a completion signal.** Ask the contributor for the
   expected total and add headroom; growing a volume later depends on the
   storage class. Agree how they will say the upload is finished, because the
   next admin step takes the endpoint offline.
2. **Create the key.** Generate one with `openssl rand -hex 32`, store it as the
   repository secret `S3KEY_<USERNAME>` (uppercase), and send it to the
   contributor over a channel other than email.
3. **Create the endpoint.** Actions → **Create Hub Ingest Endpoint** → username
   and size. The run passes when the test object round-trip succeeds.
4. **Contributor uploads** to `https://<username>.hubsingest.bioconductor.org`
   with access key `<username>` and the shared secret key.
5. **Scan.** After the contributor confirms completion: Actions → **Scan Data
   for Viruses** → username. The endpoint goes offline. Read the report in the
   log; a failed run means infected files or scan errors, and the data
   is not cleared.
6. **Review and promote.** Actions → **Launch RStudio Instance** → the
   contributor's username. Log in at
   `https://<username>-rstudio.hubsingest.bioconductor.org` as `rstudio` with
   your `ADMINPASS_<GITHUB-USERNAME>` value. The data is in
   `/home/rstudio/shareddata`; copy it to the Hubs' storage with `rclone`.
   Before opening contributor R files, read
   [security.md](security.md#contributor-data-in-r).
7. **Delete.** After confirming the copy: Actions → **Delete Hub Ingest
   Endpoint** → username. This deletes the data. Then remove the key:
   `gh secret delete S3KEY_<USERNAME> --repo Bioconductor/hubsingest`.

## Restoring an endpoint after a scan or review

When the contributor needs to upload more after step 5 or 6:

```bash
NS=<username>-ns

kubectl delete deployment rstudio -n "$NS" --ignore-not-found
kubectl delete service rstudio -n "$NS" --ignore-not-found
kubectl delete ingress rstudio-ingress -n "$NS" --ignore-not-found
kubectl delete job virus-scan -n "$NS" --ignore-not-found

kubectl scale deployment versitygw -n "$NS" --replicas=1
kubectl wait -n "$NS" --for=condition=ready pod -l app=versitygw --timeout=300s
```

The gateway pod stays `Pending` while a pod on another node holds the volume. The key, the hostname and the certificate are unchanged.

Check access with `aws s3 ls` as in
[troubleshooting.md](troubleshooting.md#test_endpoint-fails). Do not run
`test_endpoint` on an endpoint that holds data: it creates the bucket
`testbucket` and deletes it with everything in it.

## Health checks

```bash
# Endpoint namespaces
kubectl get ns -L app.kubernetes.io/part-of | grep -- '-ns '

# Gateways and their replica counts; 0/0 means an admin operation stopped it
kubectl get deployment -A --field-selector metadata.name=versitygw

# Endpoint certificates
kubectl get certificate -A

# Cluster add-ons
kubectl get pods -A | grep -E 'ingress|cert-manager'
kubectl get clusterissuer letsencrypt-prod

# Workflow state and recent runs, including the scheduled image build
gh workflow list --all --repo Bioconductor/hubsingest
gh run list --repo Bioconductor/hubsingest --limit 10
```

The endpoint workflows print the cluster's Kubernetes version in their
**Install Kubectl** step.

## Backups

There are none. An endpoint holds a contribution only until it is promoted, and
the volume is the only copy until then; deleting the namespace deletes it. The
service itself is restored from this repository: the cluster add-ons from
[deployment.md](deployment.md) and the endpoints from the workflows. Repository
secrets cannot be read back; an endpoint's key is also in its
`versitygw-credentials` Secret.

## Credential rotation

### `KUBECONFIG`

Issue a new token, build the kubeconfig with it as in
[deployment.md](deployment.md#kubeconfig), check it, and replace the secret:

```bash
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

The next workflow run prints the server version in its **Install Kubectl**
step.

A replaced token stays valid until it expires. After a suspected leak, delete
and recreate the service account before issuing the new token. This
invalidates every token issued for it; the ClusterRoleBinding names the
account, so it applies to the new one.

```bash
kubectl delete serviceaccount hubsingest-ci -n kube-system
kubectl create serviceaccount hubsingest-ci -n kube-system
```

### `S3KEY_<USERNAME>`

```bash
NS=<username>-ns
NEW=$(openssl rand -hex 32)
kubectl patch secret versitygw-credentials -n "$NS" \
  -p "{\"stringData\":{\"secret_key\":\"$NEW\"}}"
kubectl scale deployment versitygw -n "$NS" --replicas=0
kubectl wait -n "$NS" --for=delete pod -l app=versitygw --timeout=300s
kubectl scale deployment versitygw -n "$NS" --replicas=1
kubectl wait -n "$NS" --for=condition=ready pod -l app=versitygw --timeout=300s
printf '%s' "$NEW" | gh secret set S3KEY_<USERNAME> --repo Bioconductor/hubsingest
```

The gateway reads the key from its environment at start, so it has to
restart. Stopping the old pod first frees the ReadWriteOnce volume for the new
one; see [Known limitations](#known-limitations).

### `ADMINPASS_<GITHUB-USERNAME>`

Replace the repository secret. The new password applies to the next RStudio
launch. To apply it to a running session, delete the session and launch again:

```bash
kubectl delete deployment rstudio -n <username>-ns
```

## Routine tasks

| When | Task |
|---|---|
| After each contribution | Delete the endpoint and its `S3KEY_<USERNAME>` secret |
| Monthly | Compare the endpoint namespaces with the contributions in progress and delete abandoned ones; check that **Build RStudio Image** is enabled and its last run passed |
| Before the `KUBECONFIG` token expires | Rotate it |
| Yearly | Review who has write access to the repository, which is access to the cluster; delete `ADMINPASS_*` secrets of former admins |

## Known limitations

- **The endpoint is offline during admin operations.** The volume is
  ReadWriteOnce. A ReadWriteMany storage class would let the scan and RStudio
  mount the volume while the gateway runs, and the scale-down in
  `scripts/hubsingest_scan_data.sh` and `scripts/hubsingest_launch_rstudio.sh`
  could be removed.
- **Rolling updates can stall.** The gateway and RStudio Deployments use the
  default RollingUpdate strategy, which starts the new pod before stopping the
  old one. On another node, the new pod cannot attach the ReadWriteOnce
  volume. Scale the Deployment to zero and back instead of
  `kubectl rollout restart`; `strategy: Recreate` would remove the problem.
- **No resource requests or limits.** A large scan or an RStudio session
  competes with every other workload on the node.
- **Endpoints do not expire.** Abandoned endpoints keep their storage and a
  valid key until someone deletes them.
- **`delete_endpoint ALL` selects namespaces by the `-ns` suffix**, which also
  matches namespaces that are not endpoints. The create script labels endpoint
  namespaces `app.kubernetes.io/part-of=hubsingest`; once every endpoint
  carries the label, the selector can use it.
- **Scripts and templates are kept in sync by hand.**

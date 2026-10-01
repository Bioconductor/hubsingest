# Troubleshooting

Each entry gives the symptom, the cause and the fix. Most problems show up in:

```bash
NS=<username>-ns
kubectl get all,pvc,ingress,certificate -n "$NS"
kubectl get events -n "$NS" --sort-by=.lastTimestamp | tail -30
```

## Creating an endpoint

### The create workflow fails waiting for the certificate

The gateway pod is ready, but the certificate wait times out, the workflow
resets the order with `reset_endpoint_ssl.sh`, and the second wait times out
too. Follow the cert-manager objects down to the challenge:

```bash
kubectl describe certificate -n "$NS"
kubectl describe certificaterequest -n "$NS"
kubectl describe order -n "$NS"
kubectl describe challenge -n "$NS"
```

| Challenge reports | Cause | Fix |
|---|---|---|
| DNS problem, NXDOMAIN | The wildcard record is missing | Fix DNS, then reset the order |
| 404 on `/.well-known/acme-challenge/` | The solver Ingress is not served by the controller | Check the IngressClass in the ClusterIssuer and the endpoint Ingress |
| Connection refused or timeout | Port 80 of the ingress controller is not reachable from the internet | Check the controller service address and the firewall |
| `too many certificates already issued` | Let's Encrypt rate limit | Wait for the 7-day window; use `letsencrypt-staging` for tests |

When the ClusterIssuer uses a DNS-01 solver instead, its DNS provider
credentials must be for the provider that serves `bioconductor.org`.

To reset the order by hand:

```bash
bash scripts/reset_endpoint_ssl.sh <username>
```

The script deletes every Order, CertificateRequest and Certificate whose name
contains the username, which includes the RStudio certificate when one exists.

### The gateway pod does not become ready

```bash
kubectl describe pod -n "$NS" -l app=versitygw
kubectl logs -n "$NS" -l app=versitygw
```

| State | Cause | Fix |
|---|---|---|
| `Pending`, volume not bound | No StorageClass `ebs`, or no capacity | `kubectl get pvc,storageclass`; see [deployment.md](deployment.md#storage-class) |
| `Pending`, `Multi-Attach error` | An `rstudio` pod or `virus-scan` job on another node holds the ReadWriteOnce volume | Delete them, then scale the gateway up |
| `ImagePullBackOff` | The image tag does not exist | Check the tag in `scripts/hubsingest_create_endpoint.sh` |
| `CrashLoopBackOff` | The gateway rejects its arguments | Read the log; compare the arguments with the gateway's release notes |

### `test_endpoint` fails

The test creates a bucket, uploads a file, lists it and deletes the bucket.
Repeat a step by hand to see which one fails:

```bash
export AWS_ACCESS_KEY_ID=<username>
export AWS_SECRET_ACCESS_KEY=$(kubectl get secret -n "$NS" versitygw-credentials \
  -o jsonpath='{.data.secret_key}' | base64 -d)
aws --endpoint-url "https://<username>.hubsingest.bioconductor.org" s3 ls
```

| Error | Cause |
|---|---|
| `SignatureDoesNotMatch` or `InvalidAccessKeyId` | Wrong key pair; the access key is the lowercase username |
| `502` or `503` | The gateway is scaled to zero or still starting |
| TLS error | The certificate is not ready yet |

### The contributor's key is rejected on a new endpoint

The `S3KEY_<USERNAME>` secret did not exist when the endpoint was created, so
`create_endpoint` generated a random key. The key in use is in the
`versitygw-credentials` Secret (command above). Send that key, or rotate it to
a new value as in [operations.md](operations.md#s3key_username).

## Uploads

### Uploads fail with `413 Request Entity Too Large`

A single request exceeded the ingress body size limit: 1 MB when the
`proxy-body-size` annotation is missing, otherwise `10g`.

```bash
kubectl get ingress versitygw -n "$NS" -o jsonpath='{.metadata.annotations}'
```

Clients that use multipart uploads, such as the AWS CLI for files over 8 MB,
send parts well below the limit.

### A large single-request upload ends with `504`

ingress-nginx waits 60 seconds by default for the gateway to answer after
sending it the request body. Use multipart uploads, or raise
`proxy-read-timeout` on the controller.

### `No space left on device` during an upload

The volume is full. If the StorageClass allows expansion:

```bash
kubectl patch pvc versitygw-data -n "$NS" \
  -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'
kubectl get pvc versitygw-data -n "$NS"
```

Depending on the CSI driver, the file system grows while mounted or only after
the gateway restarts:

```bash
kubectl scale deployment versitygw -n "$NS" --replicas=0
kubectl wait -n "$NS" --for=delete pod -l app=versitygw --timeout=300s
kubectl scale deployment versitygw -n "$NS" --replicas=1
```

Without expansion, the contribution needs a larger endpoint and a new upload.

### The endpoint stopped responding

```bash
kubectl get deployment versitygw -n "$NS"
```

`0/0` replicas means a scan or RStudio launch stopped the gateway. Restore it
as in [operations.md](operations.md#restoring-an-endpoint-after-a-scan-or-review).

## Admin operations

### The scan workflow fails after printing the report

The last line says why:

| Message | Meaning |
|---|---|
| `Infected files found (clamscan exit 1)` | ClamAV matched a signature; the report lists the files. Do not review or promote the data; contact the contributor |
| `clamscan reported errors (exit 2)` | A scan error, for example an unreadable file; the report shows it. The data is not cleared |
| `No clamscan exit code in the report` | The report is incomplete. The data is unscanned |

### The scan workflow times out waiting for the pod

`scan_data` waits 600 seconds for the scan; large contributions take longer.

```bash
kubectl get pods -n "$NS" -l job-name=virus-scan
```

While the init container `clamav-scan` is running, the scan is still going.
Run the workflow again: it applies the same Job, waits for the running scan
and prints the report. To read the report by hand once the pod is `Running`:

```bash
POD=$(kubectl get pods -n "$NS" -l job-name=virus-scan -o jsonpath='{.items[0].metadata.name}')
kubectl cp "$NS/$POD:/results/av-scan-report.txt" ./av-scan-report.txt -c holder
kubectl delete job virus-scan -n "$NS"
```

### The RStudio pod stays `Pending`

Another pod holds the ReadWriteOnce volume on a different node, and the pod
events show `Multi-Attach error`:

```bash
kubectl get pods -n "$NS" -o wide
kubectl describe pod -n "$NS" -l app=rstudio | tail -20
```

| Holder | Fix |
|---|---|
| A `virus-scan` pod, left when a scan times out | Read the report as above if needed, then `kubectl delete job virus-scan -n "$NS"` |
| The previous `rstudio` pod, during a relaunch | `kubectl delete deployment rstudio -n "$NS"`, then launch again |
| A `versitygw` pod | `kubectl scale deployment versitygw -n "$NS" --replicas=0` |

### The RStudio login is rejected

- The user is always `rstudio`.
- The password is the `ADMINPASS_<GITHUB-USERNAME>` secret of the admin who ran
  the launch workflow, not the contributor's S3 key.
- A password changed after the launch applies only after deleting the
  `rstudio` Deployment and launching again.

Check that the deployment received a password, without printing it:

```bash
kubectl get deployment rstudio -n "$NS" \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="PASSWORD")].value}' | wc -c
```

### The RStudio launch takes a long time

The image is about 1.6 GB compressed. A node pulls all of it on its first
launch. After a daily build, `imagePullPolicy: Always` pulls only the changed
layers: the rclone layer, and the base layers when the Bioconductor image has
changed. The workflow waits up to two hours for the pod.

```bash
kubectl describe pod -n "$NS" -l app=rstudio | tail -20
```

### The RStudio image tag does not exist

`ghcr.io/bioconductor/hubsingestbiocrstudio:<release>` is pushed by **Build
RStudio Image** for the current release only. After a new Bioconductor release,
run that workflow before launching with the new version.

### The admin RStudio image is out of date

GitHub disables scheduled workflows in a public repository after 60 days
without repository activity, and **Build RStudio Image** stops running. Its
state is then `disabled_inactivity`:

```bash
gh workflow list --all --repo Bioconductor/hubsingest
gh workflow enable build_rstudio.yaml --repo Bioconductor/hubsingest
gh workflow run build_rstudio.yaml --repo Bioconductor/hubsingest
```

## Deleting

### `delete_endpoint` does not finish

The namespace is waiting on finalizers:

```bash
kubectl get ns "$NS" -o jsonpath='{.status.conditions}'
kubectl api-resources --verbs=list --namespaced -o name \
  | xargs -n1 kubectl get -n "$NS" --show-kind --ignore-not-found
```

The usual causes are a volume the CSI driver cannot detach and cert-manager
objects whose controller is down. Fix the controller. Removing finalizers by
hand can leave the cloud volume behind.

### `delete_endpoint ALL` matched more than endpoints

`ALL` deletes every namespace whose name ends in `-ns`. The workflow lists them
in its **Show what will be deleted** step. Deleted namespaces and their volumes
cannot be recovered.

## Cluster

### Every workflow fails with `Unauthorized`

The credential in `KUBECONFIG` expired or was revoked. Rotate it as in
[operations.md](operations.md#kubeconfig).

### Every workflow fails with a connection timeout

GitHub-hosted runners cannot reach the `server:` address in `KUBECONFIG`: a
private or loopback address, a firewall rule, or a changed API server address.
From a machine outside the cluster network:

```bash
curl -sk -o /dev/null -w '%{http_code}\n' https://<api-server>:6443/version
```

`401` shows the API server is reachable.

### Certificates of existing endpoints stop renewing

cert-manager renews a certificate when two thirds of its lifetime has passed,
so renewal failures show a third of the lifetime before expiry.

```bash
kubectl get certificate -A
kubectl describe clusterissuer letsencrypt-prod
```

Then follow [the certificate entry](#the-create-workflow-fails-waiting-for-the-certificate).

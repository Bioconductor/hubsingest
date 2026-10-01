# Example configuration

Example values for the templates in [`../../deploy/`](../../deploy/).

| File | Templates | Applied |
|---|---|---|
| [`cluster.env`](cluster.env) | `deploy/cluster/` | Once per cluster |
| [`endpoint.env`](endpoint.env) | `deploy/endpoint/` | Once per contribution |

A filled-in `endpoint.env` contains the contributor's key and an admin
password. In normal operation both come from repository secrets. Fill in a
copy outside the checkout; the two secret values are empty in this file.

## A contribution with the command-line tool

The workflows run the same commands. This assumes the cluster from
[deployment.md](../deployment.md), `kubectl` access, and `hubsingest` installed
as in the [README](../../README.md#installation).

```bash
# 1. Key for the contributor, stored as a repository secret
KEY=$(openssl rand -hex 32)
printf '%s' "$KEY" | gh secret set S3KEY_DATAOWNER --repo Bioconductor/hubsingest

# 2. Endpoint, then the round-trip test
hubsingest create_endpoint dataowner 50Gi "$KEY"
kubectl wait -n dataowner-ns --for=condition=ready pod -l app=versitygw --timeout=300s
kubectl wait -n dataowner-ns --for=condition=ready \
  certificate dataowner-hubsingest-bioconductor-org-key --timeout=600s
hubsingest test_endpoint dataowner
```

Details for the contributor, with the key sent separately:

```
Endpoint:   https://dataowner.hubsingest.bioconductor.org
Access key: dataowner
Secret key: <KEY>
```

The contributor's upload:

```bash
aws configure --profile biochubs      # access key dataowner, secret key as sent
aws --profile biochubs --endpoint-url https://dataowner.hubsingest.bioconductor.org \
  s3 mb s3://contribution
aws --profile biochubs --endpoint-url https://dataowner.hubsingest.bioconductor.org \
  s3 sync ./mydata s3://contribution/
```

`s3 sync` copies only missing or changed files, so an interrupted upload
continues where it stopped when run again.

After the contributor confirms the upload is complete:

```bash
# 3. Scan; the endpoint goes offline here
hubsingest scan_data dataowner

# 4. Review at https://dataowner-rstudio.hubsingest.bioconductor.org,
#    user rstudio; the data is in /home/rstudio/shareddata
hubsingest launch_rstudio dataowner "$ADMINPASS" 3.23

# 5. After the data is copied to the Hubs' storage
hubsingest delete_endpoint dataowner
gh secret delete S3KEY_DATAOWNER --repo Bioconductor/hubsingest
```

## The same endpoint from the templates

```bash
cp docs/examples/endpoint.env ../dataowner.env
# In ../dataowner.env, set HUBSINGEST_SECRET_KEY to the contributor's key and
# HUBSINGEST_RSTUDIO_PASSWORD to your ADMINPASS_<GITHUB-USERNAME> value
set -a; source ../dataowner.env; set +a

envsubst < deploy/endpoint/00-namespace.yaml | kubectl apply -f -
: "${HUBSINGEST_SECRET_KEY:?not set}" &&
  for f in deploy/endpoint/[1-5]*.yaml; do envsubst < "$f"; done \
  | kubectl apply -n "${HUBSINGEST_USER}-ns" -f -

# Review, after stopping the gateway
kubectl scale deployment versitygw -n "${HUBSINGEST_USER}-ns" --replicas=0
: "${HUBSINGEST_RSTUDIO_PASSWORD:?not set}" &&
  envsubst < deploy/endpoint/60-rstudio.yaml \
  | kubectl apply -n "${HUBSINGEST_USER}-ns" -f -
```

The `:` lines stop the apply when a secret value is empty.

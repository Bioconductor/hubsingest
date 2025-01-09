#!/bin/bash
DEFAULTCMD="hubsingest launch_rstudio"
set -e

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "Usage: $DEFAULTCMD <username> <password> [bioc_version]"
    echo "Example: $DEFAULTCMD testuser myrstudiopassword 3.18"
    exit 1
fi

USERNAME=$1
PASSWORD=$2
BIOC_VERSION="${3:-3.20}"
NAMESPACE="${USERNAME}-ns"

# Scale down existing deployment
kubectl scale deployment -n "$NAMESPACE" versitygw --replicas=0

# Create RStudio deployment
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rstudio
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rstudio
  template:
    metadata:
      labels:
        app: rstudio
    spec:
      initContainers:
      - name: clamav-scan
        image: clamav/clamav:stable
        command: ["sh", "-c", "clamscan -r /scandir 2>&1 > /results/av-scan-report.txt"]
        volumeMounts:
        - name: data-volume
          mountPath: /scandir
          readOnly: true
        - name: scan-results
          mountPath: /results
      containers:
      - name: rstudio
        image: ghcr.io/bioconductor/bioconductor:$BIOC_VERSION
        ports:
        - containerPort: 8787
        env:
        - name: PASSWORD
          value: "$PASSWORD"
        volumeMounts:
        - name: data-volume
          mountPath: /home/rstudio/shareddata
        - name: scan-results
          mountPath: /home/rstudio/av-scan-report
      volumes:
      - name: data-volume
        persistentVolumeClaim:
          claimName: versitygw-data
      - name: scan-results
        emptyDir: {}
EOF

# Create Service
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: rstudio
  namespace: $NAMESPACE
spec:
  ports:
  - port: 8787
    targetPort: 8787
  selector:
    app: rstudio
EOF

# Create Ingress
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rstudio-ingress
  namespace: $NAMESPACE
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    kubernetes.io/tls-acme: 'true'
    nginx.ingress.kubernetes.io/secure-backends: 'true'
    kubernetes.io/ingress.class: nginx
spec:
  tls:
  - hosts:
    - ${USERNAME}-rstudio.hubsingest.bioconductor.org
    secretName: ${USERNAME}-rstudio-tls
  rules:
  - host: ${USERNAME}-rstudio.hubsingest.bioconductor.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: rstudio
            port:
              number: 8787
EOF

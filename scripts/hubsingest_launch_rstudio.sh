#!/bin/bash
DEFAULTCMD="hubsingest launch_rstudio"
set -e

if [ "$#" -ne 2 ]; then
    echo "Usage: $DEFAULTCMD <username> <password>"
    echo "Example: $DEFAULTCMD testuser myrstudiopassword"
    exit 1
fi

USERNAME=$1
PASSWORD=$2
NAMESPACE="${USERNAME}-ns"

# Scale down existing deployment
kubectl scale deployment -n "$NAMESPACE" versitygw --replicas=0

# Create NFS PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-data-pvc
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: nfs
  mountOptions:
    - nfsvers=4.1
  resources:
    requests:
      storage: 50Gi
EOF

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
      - name: init-mount
        image: busybox
        command: ['sh', '-c', 'cp -r /mnt/data/* /mnt/shareddata/ || true']
        volumeMounts:
        - name: versitygw-volume
          mountPath: /mnt/data
        - name: shared-data
          mountPath: /mnt/shareddata
      containers:
      - name: rstudio
        image: ghcr.io/bioconductor/bioconductor:latest
        ports:
        - containerPort: 8787
        env:
        - name: PASSWORD
          value: "$PASSWORD"
        volumeMounts:
        - name: versitygw-volume
          mountPath: /home/rstudio/data
        - name: shared-data
          mountPath: /home/rstudio/shareddata
      volumes:
      - name: versitygw-volume
        persistentVolumeClaim:
          claimName: versitygw-data
      - name: shared-data
        persistentVolumeClaim:
          claimName: shared-data-pvc
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

echo "Waiting for RStudio deployment to be ready..."
kubectl wait -n "$NAMESPACE" --for=condition=ready pod -l app=rstudio --timeout=300s

echo "RStudio is available at: https://${USERNAME}-rstudio.hubsingest.bioconductor.org"

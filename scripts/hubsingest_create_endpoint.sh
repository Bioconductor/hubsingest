#!/bin/bash
DEFAULTCMD="hubsingest create_endpoint"

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "Usage: $DEFAULTCMD <username> <size> [password]"
    echo "Example: $DEFAULTCMD testuser 50Gi mysecretkey"
    exit 1
fi

PLACEHOLDERUSER="$1"
PLACEHOLDERSIZE="$2"
PLACEHOLDERPASS="${3:-$(openssl rand -hex 32)}"

echo "Username: $PLACEHOLDERUSER"
echo "Size: $PLACEHOLDERSIZE"

cat << EOF > /tmp/hubsingest.yaml
apiVersion: v1
kind: Secret
metadata:
  name: versitygw-credentials
type: Opaque
stringData:
  access_key: '$PLACEHOLDERUSER'
  secret_key: '$PLACEHOLDERPASS'
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: versitygw-data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ebs
  resources:
    requests:
      storage: $PLACEHOLDERSIZE
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: versitygw
spec:
  replicas: 1
  selector:
    matchLabels:
      app: versitygw
  template:
    metadata:
      labels:
        app: versitygw
    spec:
      containers:
      - name: versitygw
        image: ghcr.io/versity/versitygw:v1.0.9
        args: ["--debug", "--port", ":10000", "posix", "/mnt/versitydata"]
        ports:
        - containerPort: 10000
        env:
        - name: ROOT_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: versitygw-credentials
              key: access_key
        - name: ROOT_SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: versitygw-credentials
              key: secret_key
        volumeMounts:
        - name: data
          mountPath: /mnt/versitydata
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: versitygw-data
---
apiVersion: v1
kind: Service
metadata:
  name: versitygw
spec:
  ports:
  - port: 80
    targetPort: 10000
  selector:
    app: versitygw
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    kubernetes.io/tls-acme: 'true'
    nginx.ingress.kubernetes.io/secure-backends: 'true'
    nginx.ingress.kubernetes.io/client-max-body-size: 10g
    nginx.ingress.kubernetes.io/proxy-body-size: 10g
  name: versitygw
spec:
  tls:
    - hosts:
        - $PLACEHOLDERUSER.hubsingest.bioconductor.org
      secretName: $PLACEHOLDERUSER-hubsingest-bioconductor-org-key
  ingressClassName: nginx
  rules:
  - host: $PLACEHOLDERUSER.hubsingest.bioconductor.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: versitygw
            port:
              number: 80
EOF

kubectl create ns $PLACEHOLDERUSER-ns
kubectl apply -f /tmp/hubsingest.yaml -n $PLACEHOLDERUSER-ns
rm /tmp/hubsingest.yaml

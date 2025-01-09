#!/bin/bash
DEFAULTCMD="hubsingest scan_data"
set -e

if [ "$#" -ne 1 ]; then
    echo "Usage: $DEFAULTCMD <username>"
    echo "Example: $DEFAULTCMD testuser"
    exit 1
fi

USERNAME=$1
NAMESPACE="${USERNAME}-ns"

kubectl scale deployment -n "$NAMESPACE" versitygw --replicas=0

cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: virus-scan
  namespace: $NAMESPACE
spec:
  template:
    spec:
      initContainers:
      - name: clamav-scan
        image: clamav/clamav:stable
        command: ["sh", "-c", "clamscan -r /scandir > /results/av-scan-report.txt 2>&1"]
        volumeMounts:
        - name: data-volume
          mountPath: /scandir
          readOnly: true
        - name: results
          mountPath: /results
      containers:
      - name: holder
        image: busybox
        command: ['sh', '-c', 'sleep infinity']
        volumeMounts:
        - name: results
          mountPath: /results
      volumes:
      - name: data-volume
        persistentVolumeClaim:
          claimName: versitygw-data
      - name: results
        emptyDir: {}
      restartPolicy: Never
  backoffLimit: 1
EOF

echo "Waiting for scan init container to complete..."
kubectl wait -n "$NAMESPACE" --for=condition=ready pod -l job-name=virus-scan --timeout=600s

echo "Extracting scan report..."
POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l job-name=virus-scan -o jsonpath='{.items[0].metadata.name}')
kubectl cp "$NAMESPACE/$POD_NAME:/results/av-scan-report.txt" /tmp/av-scan-report.txt -c holder

echo "==================== VIRUS SCAN REPORT ===================="
cat /tmp/av-scan-report.txt
echo "========================================================"

rm /tmp/av-scan-report.txt
kubectl delete job virus-scan -n "$NAMESPACE"


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
        # Exit 0 so the pod reaches Ready; the exit code is read from the report
        command:
          - sh
          - -c
          - |
            clamscan -r /scandir > /results/av-scan-report.txt 2>&1
            echo "CLAMSCAN_EXIT_CODE=\$?" >> /results/av-scan-report.txt
            exit 0
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

SCAN_EXIT=$(grep '^CLAMSCAN_EXIT_CODE=' /tmp/av-scan-report.txt | tail -n1 | cut -d= -f2)

rm /tmp/av-scan-report.txt
kubectl delete job virus-scan -n "$NAMESPACE"

case "$SCAN_EXIT" in
  0)
    echo "Scan clean: no infected files found."
    ;;
  1)
    echo "Infected files found (clamscan exit 1). Do not launch RStudio against this data or promote it."
    exit 1
    ;;
  2)
    echo "clamscan reported errors (exit 2). The data is not cleared."
    exit 1
    ;;
  *)
    echo "No clamscan exit code in the report. Treat the data as unscanned."
    exit 1
    ;;
esac


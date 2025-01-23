#!/bin/bash
DEFAULTCMD="hubsingest test_endpoint"
if [ "$#" -ne 1 ]; then
    echo "Usage: $DEFAULTCMD <username>"
    echo "Example: $DEFAULTCMD testuser"
    exit 1
fi

PLACEHOLDERUSER="$1"

echo "Username: $PLACEHOLDERUSER"

export AWS_ACCESS_KEY_ID=$PLACEHOLDERUSER
export AWS_SECRET_ACCESS_KEY=$(kubectl get secret -n $PLACEHOLDERUSER-ns versitygw-credentials -o jsonpath='{.data.secret_key}' | base64 -d)
export ENDPOINTURL="https://$PLACEHOLDERUSER.hubsingest.bioconductor.org"

aws --endpoint-url $ENDPOINTURL s3 mb s3://testbucket
sleep 5
echo 'test' > /tmp/newtestfile
aws --endpoint-url $ENDPOINTURL s3 cp /tmp/newtestfile s3://testbucket/
sleep 5
aws --endpoint-url $ENDPOINTURL s3 ls s3://testbucket/ | grep 'newtestfile' && echo 'success' > /tmp/vgwtest || echo 'fail'  > /tmp/vgwtest
aws --endpoint-url $ENDPOINTURL s3 rb s3://testbucket --force
grep -q 'success' /tmp/vgwtest && echo "Endpoint test successful" && exit 0
grep -q 'fail' /tmp/vgwtest && echo "Endpoint test failed" && exit 1

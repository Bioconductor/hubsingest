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
echo 'test' > /tmp/newtestfile
aws --endpoint-url $ENDPOINTURL s3 cp /tmp/newtestfile s3://testbucket/
aws --endpoint-url $ENDPOINTURL s3 ls s3://testbucket/ | grep 'newtestfile' && echo 'Test File Found' && aws --endpoint-url $ENDPOINTURL s3 rb s3://testbucket --force || echo 'Not found' && aws --endpoint-url $ENDPOINTURL s3 rb s3://testbucket --force

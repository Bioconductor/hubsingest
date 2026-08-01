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

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

aws --endpoint-url $ENDPOINTURL s3 mb s3://testbucket
echo 'test' > "$WORKDIR/newtestfile"
sleep 5
aws --endpoint-url $ENDPOINTURL s3 cp "$WORKDIR/newtestfile" s3://testbucket/
sleep 5
if aws --endpoint-url $ENDPOINTURL s3 ls s3://testbucket/ | grep -q 'newtestfile'; then
    RESULT=success
else
    RESULT=fail
fi
aws --endpoint-url $ENDPOINTURL s3 rb s3://testbucket --force

if [ "$RESULT" = success ]; then
    echo "Endpoint test successful"
    exit 0
fi
echo "Endpoint test failed"
exit 1

#!/bin/bash
DEFAULTCMD="hubsingest delete_endpoint"
if [ "$#" -ne 1 ]; then
    echo "Usage: $DEFAULTCMD <username>"
    echo "Example: $DEFAULTCMD testuser"
    exit 1
fi

PLACEHOLDERUSER="$1"

echo "Username: $PLACEHOLDERUSER"

kubectl delete ns $PLACEHOLDERUSER-ns


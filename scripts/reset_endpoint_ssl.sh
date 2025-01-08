#!/bin/bash
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <username>"
    echo "Example: $0 testuser"
    exit 1
fi

PLACEHOLDERUSER="$1"

ORDERNAME=$(kubectl get -n $PLACEHOLDERUSER-ns order | grep $PLACEHOLDERUSER | awk '{print $1}')
CERTREQNAME=$(kubectl get -n $PLACEHOLDERUSER-ns certificaterequest | grep $PLACEHOLDERUSER | awk '{print $1}')
CERTNAME=$(kubectl get -n $PLACEHOLDERUSER-ns certificate | grep $PLACEHOLDERUSER | awk '{print $1}')


kubectl delete -n $PLACEHOLDERUSER-ns order $ORDERNAME
kubectl delete -n $PLACEHOLDERUSER-ns certificaterequest $CERTREQNAME
kubectl delete -n $PLACEHOLDERUSER-ns certificate $CERTNAME

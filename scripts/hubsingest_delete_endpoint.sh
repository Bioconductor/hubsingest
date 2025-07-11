#!/bin/bash
DEFAULTCMD="hubsingest delete_endpoint"
if [ "$#" -ne 1 ]; then
    echo "Usage: $DEFAULTCMD <username|ALL>"
    echo "Example: $DEFAULTCMD testuser"
    echo "Example: $DEFAULTCMD ALL (to delete all endpoints)"
    exit 1
fi

PLACEHOLDERUSER="$1"

if [ "$PLACEHOLDERUSER" = "ALL" ]; then
    echo "Deleting ALL endpoints with '-ns' suffix..."
    
    # Get all namespaces with -ns suffix
    NAMESPACES=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep '\-ns$')
    
    if [ -z "$NAMESPACES" ]; then
        echo "No namespaces found with '-ns' suffix"
        exit 0
    fi
    
    echo "Found the following namespaces to delete:"
    echo "$NAMESPACES"
    
    # Delete all namespaces with -ns suffix
    for namespace in $NAMESPACES; do
        echo "Deleting namespace: $namespace"
        kubectl delete ns "$namespace"
    done
    
    echo "All endpoints deleted successfully"
else
    echo "Username: $PLACEHOLDERUSER"
    kubectl delete ns $PLACEHOLDERUSER-ns
fi


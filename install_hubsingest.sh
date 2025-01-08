#!/bin/bash
HUBSINGESTPATH=${BIOC_HUBSINGEST_PATH:-/usr/local/bin/hubsingest}
mkdir -p $HUBSINGESTPATH/scripts

curl -o $HUBSINGESTPATH/hubsingest https://raw.githubusercontent.com/Bioconductor/hubsingest/refs/heads/devel/hubsingest
curl -o $HUBSINGESTPATH/scripts/hubsingest_create_endpoint.sh https://raw.githubusercontent.com/Bioconductor/hubsingest/refs/heads/devel/scripts/hubsingest_create_endpoint.sh
curl -o $HUBSINGESTPATH/scripts/hubsingest_delete_endpoint.sh https://raw.githubusercontent.com/Bioconductor/hubsingest/refs/heads/devel/scripts/hubsingest_delete_endpoint.sh
curl -o $HUBSINGESTPATH/scripts/hubsingest_test_endpoint.sh https://raw.githubusercontent.com/Bioconductor/hubsingest/refs/heads/devel/scripts/hubsingest_test_endpoint.sh

chmod +x $HUBSINGESTPATH/hubsingest
echo 'In order to persist the path, you may want to run, and/or add to your `rc` files:'
echo "export PATH=\"\$PATH:$HUBSINGESTPATH\""


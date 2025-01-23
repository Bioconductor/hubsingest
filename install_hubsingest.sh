#!/bin/bash
HUBSINGESTPATH=${BIOC_HUBSINGEST_PATH:-/usr/local/bin/hubsingest}
mkdir -p $HUBSINGESTPATH/scripts

# Download main script
curl -o $HUBSINGESTPATH/hubsingest https://raw.githubusercontent.com/Bioconductor/hubsingest/refs/heads/devel/hubsingest
chmod +x $HUBSINGESTPATH/hubsingest

# Download all script files
SCRIPTS=(
  "hubsingest_create_endpoint.sh"
  "hubsingest_delete_endpoint.sh"
  "hubsingest_test_endpoint.sh"
  "hubsingest_scan_data.sh"
  "hubsingest_launch_rstudio.sh"
  "reset_endpoint_ssl.sh"
)

for script in "${SCRIPTS[@]}"; do
  curl -o "$HUBSINGESTPATH/scripts/$script" "https://raw.githubusercontent.com/Bioconductor/hubsingest/refs/heads/devel/scripts/$script"
  chmod +x "$HUBSINGESTPATH/scripts/$script"
done

echo 'In order to persist the path, you may want to run, and/or add to your `rc` files:'
echo "export PATH=\"\$PATH:$HUBSINGESTPATH\""


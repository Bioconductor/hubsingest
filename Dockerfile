ARG BIOC_VERSION
FROM ghcr.io/bioconductor/bioconductor:${BIOC_VERSION}
# Checksum from https://downloads.rclone.org/<version>/SHA256SUMS
ARG RCLONE_VERSION=v1.75.1
ARG RCLONE_SHA256=09c9f7606ed9e31eecc1eec26a89992cf2931a8d2d1a5f0ae2bb1c11630ffb15
RUN curl -fsSLo /tmp/rclone.deb \
      "https://downloads.rclone.org/${RCLONE_VERSION}/rclone-${RCLONE_VERSION}-linux-amd64.deb" \
    && echo "${RCLONE_SHA256}  /tmp/rclone.deb" | sha256sum -c - \
    && dpkg -i /tmp/rclone.deb \
    && rm /tmp/rclone.deb

ARG BIOC_VERSION
FROM ghcr.io/bioconductor/bioconductor:${BIOC_VERSION}
RUN sudo -v ; curl https://rclone.org/install.sh | sudo bash

ARG BIOC_VERSION
FROM ghcr.io/bioconductor/bioconductor:${BIOC_VERSION}
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

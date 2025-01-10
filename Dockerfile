ARG BIOC_VERSION
FROM ghcr.io/bioconductor/bioconductor:${BIOC_VERSION}
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash &&\
    curl -sSL -O https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb &&\
    dpkg -i packages-microsoft-prod.deb &&\
    rm packages-microsoft-prod.deb &&\
    apt-get update -yq && apt-get install -y azcopy

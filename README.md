# Bioconductor Hubs Ingest Tools

This repository contains automation tools to simplify the use of the new experimental Bioconductor Hubs Ingest stack. These tools streamline the process of creating and managing temporary endpoints for ingesting data for the Bioconductor Hubs.

## Quickstart

### Installation

You can install the Bioconductor Hubs Ingest Tools using the following command:

**Note:** You can customize the installation path by exporting the `BIOC_HUBSINGEST_PATH` environment variable before running the installation command. If not specified, the tools will be installed in the default directory (/usr/local/bin/hubsingest).

```bash
curl https://raw.githubusercontent.com/Bioconductor/hubsingest/refs/heads/devel/install_hubsingest.sh | sudo bash
```

This script will:

1. Create a directory for the tools (default: /usr/local/bin/hubsingest)
2. Download the necessary scripts
3. Make the main script runnable
4. Provide instructions for updating your PATH


For those interested in the installation process, please examine the [installation script](install_hubsingest.sh).

## Usage

After installation, you can use the `hubsingest` command with two main subcommands: `create_endpoint` and `delete_endpoint`.

### Creating an Endpoint

To create a new endpoint:

```bash
hubsingest create_endpoint <username> <size>
```

Example:
```bash
hubsingest create_endpoint testuser 50Gi
```

This command creates a new endpoint for the specified user with the given storage size.

### Deleting an Endpoint

To delete an existing endpoint:

```bash
hubsingest delete_endpoint <username>
```

Example:
```bash
hubsingest delete_endpoint testuser
```

This command removes the endpoint associated with the specified username.


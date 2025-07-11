# Bioconductor Hubs Ingest Tools

This repository contains automation tools to simplify the use of the new experimental Bioconductor Hubs Ingest stack. These tools streamline the process of creating and managing temporary endpoints for ingesting data for the Bioconductor Hubs.

## Using GitHub Actions Workflows (Recommended)

The easiest way to manage endpoints is through our provided GitHub Actions workflows.

### Prerequisites
- The following repository secrets must be configured by an administrator:
  - `KUBECONFIG`: Kubernetes configuration for cluster access

### Managing Secrets

Two distinct types of secrets are used in this system:
1. **User S3 Keys** (`S3KEY_<USERUSER>`): 
   - One unique key per data submitter
   - Used only for their specific endpoint
   - Should be randomly generated for security
   
2. **Admin Access Password** (`ADMINPASS_<ADMINUSER>`):
   - One password per administrator
   - Used for ALL RStudio instances launched by that admin
   - Should be a secure, memorable password you'll reuse
   - Same password works on any endpoint you examine

#### Setting Up User S3 Keys
Generate a random key for each data submitter using one of these methods:

1. Using OpenSSL (recommended):
   ```bash
   openssl rand -hex 32
   ```

2. Using /dev/urandom:
   ```bash
   cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1
   ```

3. Manual method: Randomly type at least 32 letters and numbers on your keyboard

Add the generated key as a GitHub secret:
- Name it `S3KEY_<USERUSER>` (e.g., `S3KEY_DATAOWNER`)
- Share this random key securely with the data submitter
- They'll need it for S3 endpoint access

#### Setting Up Your Admin Password
As an administrator:
1. Choose a secure password you want to reuse
2. Create a secret named `ADMINPASS_<ADMINUSER>`
   - Where ADMINUSER is YOUR GitHub username in uppercase
   - Example: GitHub user 'almahmoud' creates `ADMINPASS_ALMAHMOUD`
3. This will be your password for ALL RStudio instances you launch
   - Username will always be `rstudio`
   - Password will always be your ADMINPASS value
   - Works on any rstudio endpoint when you run the launch workflow

### Creating an Endpoint

1. Navigate to the "Actions" tab
2. Select the "Create Hub Ingest Endpoint" workflow
3. Click "Run workflow"
4. Fill in the parameters:
   - Username: Your username (must match the `S3KEY_<USERUSER>` secret)
   - Size: Storage size (e.g., "50Gi")
5. Click "Run workflow"

The workflow will:
- Create your endpoint with the specified storage
- Automatically test the endpoint by:
  - Creating a test bucket
  - Uploading a test file
  - Retrieving the file
- Confirm the S3 credentials and endpoint are working properly

### Examining Contributor Data (Admin Tools)

These tools are for administrators to examine data that contributors have uploaded to their endpoints:

**Note:** This will stop the contributor's ingestion endpoint. Only run these steps after confirming they have completed their data uploads.

#### Virus Scanning

Run a virus scan on a contributor's uploaded data:

1. Navigate to the "Actions" tab
2. Select the "Scan Data for Viruses" workflow
3. Enter the contributor's username
4. Click "Run workflow"

The scan results will be displayed directly in the GitHub Actions workflow log, clearly marked between separator lines for easy viewing.

1. Click on the Job
2. Expand "Run virus scan"
3. Find and investigate "Virus Scan Report"

#### RStudio Environment

Launch an RStudio instance to examine a contributor's data:

1. First, ensure you have set up your admin password:
   - Secret name: `ADMINPASS_<ADMINUSER>` where ADMINUSER is YOUR GitHub username in uppercase
   - Example: GitHub user 'almahmoud' needs secret `ADMINPASS_ALMAHMOUD`

2. Launch RStudio:
   - Enter the CONTRIBUTOR'S username
   - The workflow will use YOUR admin password for RStudio access
   - Example: Admin 'almahmoud' examining contributor 'dataowner's data:
     - Username parameter: dataowner
     - RStudio password: Value from `ADMINPASS_ALMAHMOUD`

3. Access RStudio:
   - URL: `https://<contributor>-rstudio.hubsingest.bioconductor.org`
      - Example: `https://dataowner-rstudio.hubsingest.bioconductor.org`
   - Login with:
     - Username: Always `rstudio`
     - Password: Your `ADMINPASS_<ADMINUSER>` value

### Deleting an Endpoint

1. Navigate to the "Actions" tab
2. Select the "Delete Hub Endpoint" workflow
3. Click "Run workflow"
4. Enter your username (or "ALL" to delete all endpoints)
5. Click "Run workflow"

**Note:** Using "ALL" will delete all endpoints in the cluster (all namespaces ending with "-ns"). This is intended for administrators who need to clean up multiple endpoints at once. Use with caution as this action cannot be undone.

## Using Local Scripts (Advanced)

### Prerequisites

- Kubernetes configuration file (kubeconfig)
  - Contact your Kubernetes administrator to obtain this file
  - The file should be placed at `~/.kube/config`
  - The configuration must have permissions to create namespaces and deploy resources

### Installation

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

### Command-Line Usage

#### Creating an Endpoint

```bash
hubsingest create_endpoint <username> <size> [<password>]
```

Example:
```bash
# With auto-generated password
hubsingest create_endpoint testuser 50Gi

# With specific password
hubsingest create_endpoint testuser 50Gi myspecificpassword
```

#### Deleting an Endpoint

```bash
hubsingest delete_endpoint <username>
```

Example:
```bash
hubsingest delete_endpoint testuser
```

To delete all endpoints at once (for administrators):
```bash
hubsingest delete_endpoint ALL
```

**Warning:** The `ALL` option will delete all namespaces ending with "-ns" in the cluster. This is intended for administrative cleanup and should be used with caution as it cannot be undone.

#### Virus Scanning
To scan a contributor's data for viruses:
```bash
hubsingest scan_data <username>
```

#### RStudio Access
To launch an RStudio instance for examining data:
```bash
hubsingest launch_rstudio <username> <password> [bioc_version]
```
Example:
```bash
hubsingest launch_rstudio dataowner mypassword 3.18
```


### Testing Your Endpoint

After creating an endpoint, you can test it using the built-in test function or manually using the AWS CLI.

#### Prerequisites
- AWS CLI installed (`aws` command available in your terminal)
- Your S3 access key (username) and secret key (password)

#### Automatic Testing
```bash
hubsingest test_endpoint <username>
```

This will automatically:
- Create a test bucket
- Upload a test file
- Verify the file exists
- Clean up the test bucket


### Manual AWS Operations

#### AWS CLI Configuration (Optional)
For manual testing or data upload, configure an AWS profile:
```bash
aws configure --profile hubsingestusername
# Enter your access key (username) when prompted
# Enter your secret key (password) when prompted
# Leave region blank (just press Enter)
# Leave output format blank (just press Enter)
```

When using AWS CLI commands manually, you would then have to include the profile and endpoint URL:
```bash
aws --profile hubsingestusername --endpoint-url https://<username>.hubsingest.bioconductor.org s3 <command>
```

Example commands:
```bash
# Make bucket and upload a file
aws --profile hubsingestusername --endpoint-url https://username.hubsingest.bioconductor.org s3 mb s3://mybucket
aws --profile hubsingestusername --endpoint-url https://username.hubsingest.bioconductor.org s3 cp myfile.txt s3://mybucket/

# List buckets
aws --profile hubsingestusername --endpoint-url https://username.hubsingest.bioconductor.org s3 ls

# Download a file
aws --profile hubsingestusername --endpoint-url https://username.hubsingest.bioconductor.org s3 cp s3://mybucket/myfile.txt ./
```

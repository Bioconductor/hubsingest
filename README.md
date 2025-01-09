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
2. Select the "Create Hub Endpoint" workflow
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
4. Enter your username
5. Click "Run workflow"

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

### Testing Your Endpoint

After creating an endpoint, you can verify it's working properly using the AWS CLI. The generated endpoint URL will be `https://<username>.hubsingest.bioconductor.org`.

#### Prerequisites for Testing
- AWS CLI installed (`aws` command available in your terminal)
- Your S3 access key (username) and secret key (password)

#### Configure AWS Profile
You can set up a named profile:
```bash
aws configure --profile hubsingestusername
# Enter your access key (username) when prompted
# Enter your secret key (password) when prompted
# Leave region blank (just press Enter)
# Leave output format blank (just press Enter)
```

#### Basic Testing Steps
1. Create a test bucket:
```bash
aws --profile hubsingestusername --endpoint-url https://username.hubsingest.bioconductor.org s3 mb s3://testbucket
```

2. Create and upload a test file:
```bash
echo 'test' > /tmp/newtestfile
aws --profile hubsingestusername --endpoint-url https://username.hubsingest.bioconductor.org s3 cp /tmp/newtestfile s3://testbucket/
```

3. Verify the file exists:
```bash
aws --profile hubsingestusername --endpoint-url https://username.hubsingest.bioconductor.org s3 ls s3://testbucket/
```

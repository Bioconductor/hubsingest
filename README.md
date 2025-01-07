# Bioconductor Hubs Ingest Tools

This repository contains automation tools to simplify the use of the new experimental Bioconductor Hubs Ingest stack. These tools streamline the process of creating and managing temporary endpoints for ingesting data for the Bioconductor Hubs.

## Using GitHub Actions Workflows (Recommended)

The easiest way to manage endpoints is through our provided GitHub Actions workflows.

### Prerequisites
- The following repository secrets must be configured by an administrator:
  - `KUBECONFIG`: Kubernetes configuration for cluster access

### Managing S3 Keys

1. Generate random S3 keys for each user. You can use various methods:
   ```bash
   # Using OpenSSL (recommended)
   openssl rand -hex 32

   # Or using /dev/urandom
   cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1
   ```
   Alternatively, you can create a random string by randomly typing characters on your keyboard. Aim for at least 32 characters mixing letters and numbers.

2. Add the key as a GitHub repository secret:
   - Go to Settings → Secrets and variables → Actions
   - Create a new secret named `S3KEY_<USERNAME>` (e.g., `S3KEY_TESTUSER`)
   - Paste the generated key as the value

3. Share the key securely with the user


### Creating an Endpoint

1. Navigate to the "Actions" tab
2. Select the "Create Hub Endpoint" workflow
3. Click "Run workflow"
4. Fill in the parameters:
   - Username: Your username (must match the `S3KEY_<USERNAME>` secret)
   - Size: Storage size (e.g., "50Gi")
5. Click "Run workflow"

The workflow will automatically use your corresponding `S3KEY_<USERNAME>` secret as the password.

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

### Deleting an Endpoint

1. Navigate to the "Actions" tab
2. Select the "Delete Hub Endpoint" workflow
3. Click "Run workflow"
4. Enter your username
5. Click "Run workflow"

## Using Local Scripts

If you need to manage endpoints directly from your machine, you can use our command-line tools.

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

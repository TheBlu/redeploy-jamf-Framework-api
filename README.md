# redeploy-jamf-Framework-api
# Jamf Framework Redeploy Script - Implementation Guide

A bash script that uses the Jamf Pro API to automatically redeploy the Jamf management framework to multiple computers from a CSV file.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Jamf Pro Setup](#jamf-pro-setup)
- [Installation](#installation)
- [Usage](#usage)
- [CSV File Format](#csv-file-format)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)
- [Advanced Usage](#advanced-usage)

## Overview

This script automates the process of redeploying the Jamf management framework to computers that may have lost device trust or are experiencing communication issues with your Jamf Pro server. Instead of manually triggering redeploys through the Jamf Pro console, you can process multiple computers at once using a CSV file.

**Key Features:**
- OAuth 2.0 authentication using client credentials
- Support for both modern Jamf Pro API and Classic API
- Batch processing from CSV files
- Comprehensive error handling and progress reporting
- Validation of computer IDs before sending commands

## Prerequisites

**System Requirements:**
- macOS, Linux, or Unix-like system with bash
- `curl` command-line tool
- `base64` command-line tool
- Network access to your Jamf Pro server

**Jamf Pro Requirements:**
- Jamf Pro version 10.49.0 or later (for OAuth client credentials)
- Administrative access to create API roles and clients
- Computers must be MDM-managed and able to receive MDM commands

## Jamf Pro Setup

### Step 1: Create API Role

1. Log into your Jamf Pro server as an administrator
2. Navigate to **Settings** → **System** → **API Roles and Clients**
3. Click the **New** button in the API Roles section
4. Configure the API Role:
   - **Display Name**: `Framework Redeploy Role`
   - **Privileges**: Select the following minimum required privileges:

#### Required Privileges:

**Computers:**
- ✅ **Read**

**Computer Commands:**
- ✅ **Create**

**Jamf Pro Server Actions:**
- ✅ **Send Computer Remote Command to Install Package**

**Jamf Pro Server Settings:**
- ✅ **Check-In** (Read)
- ✅ **Computer Check-in Setting** (Read)

5. Click **Save**

### Step 2: Create API Client

1. In the same **API Roles and Clients** section, click **New** in the API Clients area
2. Configure the API Client:
   - **Display Name**: `Framework Redeploy Client`
   - **Access Token Lifetime**: `1800` seconds (30 minutes) - adjust as needed
   - **Enabled**: ✅ Checked
   - **API Roles**: Select the `Framework Redeploy Role` created in Step 1

3. Click **Save**
4. **Important**: Copy and securely store the **Client ID** and **Client Secret** - you won't be able to see the Client Secret again

### Step 3: Test API Access

Verify your API client works by testing authentication:

```bash
curl --request POST "https://yourserver.jamfcloud.com/api/oauth/token" \
     --header "Content-Type: application/x-www-form-urlencoded" \
     --data-urlencode "grant_type=client_credentials" \
     --data-urlencode "client_id=YOUR_CLIENT_ID" \
     --data-urlencode "client_secret=YOUR_CLIENT_SECRET"
```

You should receive a JSON response with an `access_token`.

## Installation

### Download the Script

1. Download `jamf_redeploy.sh` from this repository
2. Make it executable:
   ```bash
   chmod +x jamf_redeploy.sh
   ```

### Configure the Script

Edit the script and update the configuration variables at the top:

```bash
# Configuration
JAMF_URL="https://yourcompany.jamfcloud.com"  # Your Jamf Pro server URL
CLIENT_ID="your-client-id-here"               # API Client ID from Step 2
CLIENT_SECRET="your-client-secret-here"       # API Client Secret from Step 2
```

**Important Security Notes:**
- Never commit API credentials to version control
- Consider using environment variables or external config files for production use
- Store credentials securely with appropriate file permissions

## Usage

### Basic Usage

```bash
./jamf_redeploy.sh /path/to/computers.csv
```

### Examples

```bash
# Process computers from a CSV file in the current directory
./jamf_redeploy.sh computers.csv

# Process computers from an absolute path
./jamf_redeploy.sh /Users/admin/Desktop/redeploy_list.csv

# Show help
./jamf_redeploy.sh --help
```

### Expected Output

```
Jamf Framework Redeploy Script
======================================
Attempting authentication with Jamf Pro...
Using Client ID: ee5f7569... (first 8 chars)
Client Secret length: 64 characters
HTTP Status Code: 200
Successfully authenticated with Jamf Pro using client credentials

Processing CSV file: computers.csv

Processing: ID 123 (John-MacBook-Pro)
Sending redeploy command with token: eyJhbGciOiJIUzI1NiJ9...
✓ Framework redeploy command sent successfully for ID: 123 (John-MacBook-Pro) [Modern API - HTTP: 202]

Processing: ID 456 (Jane-iMac)
Sending redeploy command with token: eyJhbGciOiJIUzI1NiJ9...
✓ Framework redeploy command sent successfully for ID: 456 (Jane-iMac) [Modern API - HTTP: 202]

Processing complete!
Total processed: 2
Successful: 2
Errors: 0
Script execution completed
```

## CSV File Format

### Required Format

The CSV file must have a header row and contain computer information:

```csv
computer_id,computer_name
123,John-MacBook-Pro
456,Jane-iMac
789,Conference-Room-Mac
```

### Field Descriptions

- **computer_id** (Required): The Jamf Pro computer ID (numeric)
- **computer_name** (Optional): Computer name for display purposes only

### Getting Computer IDs

#### Method 1: Export from Jamf Pro Console
1. Go to **Computers** → **Search Results**
2. Select the computers you want to redeploy
3. Click **Export** → choose CSV format
4. The exported file will include the computer ID in the `ID` column

#### Method 2: Smart Group Export
1. Create a Smart Group with your target computers
2. Export the Smart Group to CSV
3. Extract the computer IDs from the exported data

#### Method 3: API Query
Use the Jamf Pro API to get computer IDs programmatically:

```bash
# Get all computers (requires proper API credentials)
curl -H "Authorization: Bearer YOUR_TOKEN" \
     "https://yourserver.jamfcloud.com/JSSResource/computers" \
     -H "Accept: application/json"
```

### CSV File Tips

- Save as UTF-8 encoding to avoid character issues
- Avoid using Excel if possible (can add unwanted characters)
- Use a plain text editor for best results
- Remove any extra spaces or special characters

## Troubleshooting

### Common Issues

#### Authentication Failed (HTTP 401)
**Problem**: `Error: Authentication failed with HTTP 401`

**Solutions**:
1. Verify your `CLIENT_ID` and `CLIENT_SECRET` are correct
2. Check that the API client is enabled in Jamf Pro
3. Ensure no extra spaces or characters in credentials
4. Test authentication manually with curl

#### Permission Denied (HTTP 401 on Commands)
**Problem**: `401 Unauthorized - Need 'Send Computer Remote Command to Install Package' privilege`

**Solutions**:
1. Verify your API Role has all required privileges (see setup section)
2. Ensure the API client is assigned to the correct API role
3. Check that the role includes **Jamf Pro Server Actions** privileges

#### Computer Not Found
**Problem**: `Computer ID not found in Jamf Pro: XXX`

**Solutions**:
1. Verify the computer ID exists in Jamf Pro
2. Check that the computer hasn't been deleted
3. Ensure you're using the correct Jamf Pro server

#### CSV Parsing Issues
**Problem**: `Skipping invalid computer ID: '﻿computer_id'`

**Solutions**:
1. Remove BOM (Byte Order Mark) from CSV file
2. Recreate CSV using a plain text editor
3. Ensure proper UTF-8 encoding without BOM

### Debug Mode

For additional debugging, you can modify the script to show more verbose output:

```bash
# Add this line after the authentication success
print_status $YELLOW "Debug: Full token = $token"

# Or run curl commands with -v flag for verbose output
```

### Log Files

The script outputs to stdout/stderr. To capture logs:

```bash
./jamf_redeploy.sh computers.csv 2>&1 | tee redeploy.log
```

## Security Considerations

### Credential Security

1. **Never commit credentials to version control**
2. **Use environment variables for production**:
   ```bash
   export JAMF_CLIENT_ID="your-client-id"
   export JAMF_CLIENT_SECRET="your-client-secret"
   
   # Modify script to use: CLIENT_ID="${JAMF_CLIENT_ID}"
   ```

3. **Set appropriate file permissions**:
   ```bash
   chmod 700 jamf_redeploy.sh  # Only owner can read/write/execute
   ```

4. **Use a dedicated API client** with minimal required privileges

### Network Security

- Ensure HTTPS is used for all API communications
- Consider running from a secure, managed system
- Use VPN if accessing Jamf Pro externally

### Audit Trail

- The script actions are logged in Jamf Pro's management history
- Consider logging script execution for audit purposes
- Monitor API client usage in Jamf Pro

## Advanced Usage

### Environment-Based Configuration

Create a more secure version using environment variables:

```bash
#!/bin/bash

# Configuration from environment variables
JAMF_URL="${JAMF_URL:-}"
CLIENT_ID="${JAMF_CLIENT_ID:-}"
CLIENT_SECRET="${JAMF_CLIENT_SECRET:-}"

# Check if variables are set
if [[ -z "$JAMF_URL" || -z "$CLIENT_ID" || -z "$CLIENT_SECRET" ]]; then
    echo "Error: Required environment variables not set"
    echo "Please set: JAMF_URL, JAMF_CLIENT_ID, JAMF_CLIENT_SECRET"
    exit 1
fi
```

### Batch Processing Multiple Files

Process multiple CSV files:

```bash
#!/bin/bash
for csv_file in /path/to/csv/files/*.csv; do
    echo "Processing $csv_file..."
    ./jamf_redeploy.sh "$csv_file"
    echo "Completed $csv_file"
    echo "---"
done
```

### Integration with Other Tools

#### Slack Notifications

Add Slack webhook notifications:

```bash
# Add after processing completion
curl -X POST -H 'Content-type: application/json' \
    --data "{\"text\":\"Framework redeploy completed: $success_count successful, $error_count errors\"}" \
    "$SLACK_WEBHOOK_URL"
```

#### Cron Job Automation

Schedule regular execution:

```bash
# Add to crontab for daily execution at 2 AM
0 2 * * * /path/to/jamf_redeploy.sh /path/to/computers.csv >> /var/log/jamf_redeploy.log 2>&1
```

### Customization Options

The script can be modified to:
- Process different computer criteria (serial numbers, asset tags, etc.)
- Send different types of commands
- Integrate with ITSM tools for ticket creation
- Generate detailed reports
- Include additional validation checks

## API Endpoints Used

The script utilizes these Jamf Pro API endpoints:

### Authentication
- `POST /api/oauth/token` - OAuth 2.0 token generation

### Modern API (Primary)
- `POST /api/v1/jamf-management-framework/redeploy/{id}` - Redeploy framework command

### Classic API (Fallback)
- `GET /JSSResource/computers/id/{id}` - Computer verification
- `POST /JSSResource/computercommands/command/RedeployFramework/id/{id}` - Redeploy command

## Contributing

Contributions are welcome! Please:

1. Fork this repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For issues and questions:

1. Check the [Troubleshooting](#troubleshooting) section
2. Search existing GitHub issues
3. Create a new issue with:
   - Script version
   - Jamf Pro version
   - Error messages (with credentials redacted)
   - Steps to reproduce

## Changelog

### v1.0.0
- Initial release
- OAuth 2.0 client credentials authentication
- Support for both modern and Classic APIs
- CSV batch processing
- Comprehensive error handling

---

**Disclaimer**: This script is provided as-is. Always test in a non-production environment first. The authors are not responsible for any issues that may arise from using this script.

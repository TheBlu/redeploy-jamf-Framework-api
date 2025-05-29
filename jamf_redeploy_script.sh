#!/bin/bash

# Jamf Framework Redeploy Script
# This script reads computer information from a CSV file and redeploys the Jamf framework

# Configuration
JAMF_URL=""       # Set your Jamf Pro server URL (e.g., https://yourcompany.jamfcloud.com)
CLIENT_ID=""      # Set your Jamf Pro API client ID
CLIENT_SECRET=""  # Set your Jamf Pro API client secret

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check if required variables are set
check_config() {
    if [[ -z "$JAMF_URL" || -z "$CLIENT_ID" || -z "$CLIENT_SECRET" ]]; then
        print_status $RED "Error: Please configure JAMF_URL, CLIENT_ID, and CLIENT_SECRET variables in the script"
        exit 1
    fi
    
    if [[ -z "$CSV_FILE" ]]; then
        print_status $RED "Error: Please provide CSV file path as an argument"
        usage
        exit 1
    fi
    
    if [[ ! -f "$CSV_FILE" ]]; then
        print_status $RED "Error: CSV file '$CSV_FILE' not found"
        exit 1
    fi
}

# Function to get Bearer token using client credentials
get_token() {
    local response_body
    local http_code
    local temp_file
    
    print_status $YELLOW "Attempting authentication with Jamf Pro..."
    print_status $YELLOW "Using Client ID: ${CLIENT_ID:0:8}... (first 8 chars)"
    print_status $YELLOW "Client Secret length: ${#CLIENT_SECRET} characters"
    
    # Remove any trailing slash from JAMF_URL
    JAMF_URL="${JAMF_URL%/}"
    
    # Create temporary file for response
    temp_file=$(mktemp)
    
    # Make the token request using form data (correct method for Jamf Pro)
    http_code=$(curl -s -w "%{http_code}" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -X POST \
        -o "$temp_file" \
        --data-urlencode "grant_type=client_credentials" \
        --data-urlencode "client_id=$CLIENT_ID" \
        --data-urlencode "client_secret=$CLIENT_SECRET" \
        "$JAMF_URL/api/oauth/token")
    
    if [[ $? -ne 0 ]]; then
        print_status $RED "Error: curl command failed"
        print_status $RED "HTTP Code: $http_code"
        rm -f "$temp_file"
        exit 1
    fi
    
    # Read response body from temp file
    response_body=$(cat "$temp_file")
    rm -f "$temp_file"
    
    print_status $YELLOW "HTTP Status Code: $http_code"
    
    # Check HTTP status code
    if [[ "$http_code" != "200" ]]; then
        print_status $RED "Error: Authentication failed with HTTP $http_code"
        print_status $RED "URL: $JAMF_URL/api/oauth/token"
        print_status $RED "Response: $response_body"
        
        case $http_code in
            400)
                print_status $RED "Bad Request - Check your client credentials and grant_type"
                ;;
            401)
                print_status $RED "Unauthorized - Invalid client ID or client secret"
                print_status $YELLOW "Verify your API client is enabled and credentials are correct"
                ;;
            403)
                print_status $RED "Forbidden - Client may not have required permissions"
                ;;
            404)
                print_status $RED "Not Found - Check your Jamf Pro URL"
                ;;
            *)
                print_status $RED "Unexpected HTTP status code"
                ;;
        esac
        exit 1
    fi
    
    # Extract access token from JSON response
    token=$(echo "$response_body" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
    
    if [[ -z "$token" ]]; then
        print_status $RED "Error: Failed to extract access token from response"
        print_status $RED "Response body: $response_body"
        
        # Check if response contains error information
        error_desc=$(echo "$response_body" | grep -o '"error_description":"[^"]*' | cut -d'"' -f4)
        if [[ -n "$error_desc" ]]; then
            print_status $RED "Error description: $error_desc"
        fi
        
        error_type=$(echo "$response_body" | grep -o '"error":"[^"]*' | cut -d'"' -f4)
        if [[ -n "$error_type" ]]; then
            print_status $RED "Error type: $error_type"
        fi
        
        exit 1
    fi
    
    print_status $GREEN "Successfully authenticated with Jamf Pro using client credentials"
}

# Function to invalidate token (OAuth tokens expire automatically)
invalidate_token() {
    if [[ -n "$token" ]]; then
        # OAuth tokens don't need explicit invalidation like basic auth tokens
        # They expire automatically based on the token lifetime
        print_status $YELLOW "OAuth token will expire automatically"
    fi
}

# Function to verify computer ID exists
verify_computer_id() {
    local computer_id=$1
    local response
    
    response=$(curl -s -w "%{http_code}" -o /dev/null \
        -H "Authorization: Bearer $token" \
        -H "Accept: application/json" \
        "$JAMF_URL/JSSResource/computers/id/$computer_id")
    
    if [[ "$response" == "200" ]]; then
        return 0
    else
        return 1
    fi
}

# Function to redeploy Jamf framework
redeploy_framework() {
    local computer_id=$1
    local computer_name=$2
    
    print_status $YELLOW "Sending redeploy command with token: ${token:0:20}..."
    
    # Try the modern API first (v1/jamf-management-framework/redeploy)
    local response
    response=$(curl -s -w "%{http_code}" -o /dev/null \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -X POST \
        "$JAMF_URL/api/v1/jamf-management-framework/redeploy/$computer_id")
    
    if [[ "$response" == "200" || "$response" == "201" || "$response" == "202" ]]; then
        print_status $GREEN "✓ Framework redeploy command sent successfully for ID: $computer_id${computer_name:+ ($computer_name)} [Modern API - HTTP: $response]"
        return 0
    else
        print_status $YELLOW "Modern API failed (HTTP: $response), trying Classic API..."
        
        # Fall back to Classic API
        response=$(curl -s -w "%{http_code}" -o /dev/null \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: text/xml" \
            -X POST \
            "$JAMF_URL/JSSResource/computercommands/command/RedeployFramework/id/$computer_id")
        
        if [[ "$response" == "201" ]]; then
            print_status $GREEN "✓ Framework redeploy command sent successfully for ID: $computer_id${computer_name:+ ($computer_name)} [Classic API]"
            return 0
        else
            print_status $RED "✗ Failed to send redeploy command for ID: $computer_id${computer_name:+ ($computer_name)} - HTTP: $response"
            
            # Debug: Try to get more details about the error
            if [[ "$response" == "401" ]]; then
                print_status $RED "401 Unauthorized - Need 'Send Computer Remote Command to Install Package' privilege"
            fi
            
            return 1
        fi
    fi
}

# Function to process CSV file
process_csv() {
    local line_count=0
    local success_count=0
    local error_count=0
    local computer_id
    local computer_name
    
    print_status $YELLOW "Processing CSV file: $CSV_FILE"
    echo
    
    # Use process substitution to avoid subshell issues with counters
    while IFS=',' read -r computer_id computer_name || [[ -n "$computer_id" ]]; do
        # Skip header line
        if [[ "$computer_id" == "computer_id" ]]; then
            continue
        fi
        
        # Remove whitespace and quotes
        computer_id=$(echo "$computer_id" | tr -d ' "')
        computer_name=$(echo "$computer_name" | tr -d ' "')
        
        # Skip empty lines or invalid IDs
        if [[ -z "$computer_id" || ! "$computer_id" =~ ^[0-9]+$ ]]; then
            print_status $YELLOW "Skipping invalid computer ID: '$computer_id'"
            continue
        fi
        
        line_count=$((line_count + 1))
        print_status $YELLOW "Processing: ID $computer_id${computer_name:+ ($computer_name)}"
        
        # Verify computer ID exists
        if ! verify_computer_id "$computer_id"; then
            print_status $RED "✗ Computer ID not found in Jamf Pro: $computer_id"
            error_count=$((error_count + 1))
            continue
        fi
        
        # Redeploy framework
        if redeploy_framework "$computer_id" "$computer_name"; then
            success_count=$((success_count + 1))
        else
            error_count=$((error_count + 1))
        fi
        
        # Small delay to avoid overwhelming the API
        sleep 1
    done < "$CSV_FILE"
    
    echo
    print_status $GREEN "Processing complete!"
    print_status $YELLOW "Total processed: $line_count"
    print_status $GREEN "Successful: $success_count"
    print_status $RED "Errors: $error_count"
}

# Function to display usage
usage() {
    echo "Usage: $0 <csv_file_path>"
    echo
    echo "Arguments:"
    echo "  csv_file_path   Path to CSV file containing computer information"
    echo
    echo "Before running, configure the following variables in the script:"
    echo "  JAMF_URL       - Your Jamf Pro server URL"
    echo "  CLIENT_ID      - Your Jamf Pro API client ID"
    echo "  CLIENT_SECRET  - Your Jamf Pro API client secret"
    echo
    echo "CSV Format:"
    echo "  The CSV file should have a header row with:"
    echo "  computer_id,computer_name"
    echo "  123,John-MacBook-Pro"
    echo "  456,Jane-iMac"
    echo
    echo "Note: computer_id must be the Jamf Pro computer ID (numeric)."
    echo "      computer_name is optional and used only for display purposes."
    echo
    echo "Examples:"
    echo "  $0 /path/to/computers.csv"
    echo "  $0 ./my-computers.csv"
    echo "  $0 computers.csv"
}

# Trap to ensure token cleanup
trap invalidate_token EXIT

# Main execution
main() {
    print_status $YELLOW "Jamf Framework Redeploy Script"
    echo "======================================"
    
    # Check if help is requested
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        usage
        exit 0
    fi
    
    # Check if CSV file argument is provided
    if [[ $# -eq 0 ]]; then
        print_status $RED "Error: No CSV file path provided"
        usage
        exit 1
    fi
    
    # Set CSV file from command line argument
    CSV_FILE="$1"
    
    # Check configuration
    check_config
    
    # Get authentication token
    get_token
    
    # Process CSV file
    process_csv
    
    print_status $GREEN "Script execution completed"
}

# Run main function
main "$@"
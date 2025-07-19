#!/bin/bash

# get_branch_version.sh
# Script to get the Odoo version for a specific branch
# Usage: ./get_branch_version.sh <client_name> [branch_name]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CLIENT_DIR="$ROOT_DIR/clients"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 <client_name> [branch_name]"
    echo
    echo "Get the Odoo version for a specific branch"
    echo
    echo "Arguments:"
    echo "  client_name    Name of the client"
    echo "  branch_name    Branch name (optional, uses current branch if not specified)"
    echo
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -q, --quiet    Only output the version number"
    echo
    echo "Examples:"
    echo "  $0 myclient master"
    echo "  $0 myclient"
    echo "  $0 myclient production --quiet"
}

# Parse command line arguments
CLIENT_NAME=""
BRANCH_NAME=""
QUIET=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        *)
            if [[ -z "$CLIENT_NAME" ]]; then
                CLIENT_NAME="$1"
            elif [[ -z "$BRANCH_NAME" ]]; then
                BRANCH_NAME="$1"
            else
                echo -e "${RED}Error: Unknown argument: $1${NC}"
                usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate client name
if [[ -z "$CLIENT_NAME" ]]; then
    echo -e "${RED}Error: Missing client name${NC}"
    usage
    exit 1
fi

# Validate client exists
if [[ ! -d "$CLIENT_DIR/$CLIENT_NAME" ]]; then
    echo -e "${RED}Error: Client '$CLIENT_NAME' does not exist${NC}"
    echo "Available clients:"
    ls -1 "$CLIENT_DIR" 2>/dev/null || echo "No clients found"
    exit 1
fi

# Navigate to client directory
cd "$CLIENT_DIR/$CLIENT_NAME"

# Check if it's a git repository
if [[ ! -d ".git" ]]; then
    echo -e "${RED}Error: Client directory is not a git repository${NC}"
    exit 1
fi

# Get branch name if not specified
if [[ -z "$BRANCH_NAME" ]]; then
    BRANCH_NAME=$(git branch --show-current)
    if [[ -z "$BRANCH_NAME" ]]; then
        echo -e "${RED}Error: Could not determine current branch${NC}"
        exit 1
    fi
fi

CONFIG_FILE=".odoo_branch_config"

# Check if configuration file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    if [[ "$QUIET" == true ]]; then
        echo "unknown"
    else
        echo -e "${YELLOW}No branch-version configuration found${NC}"
        echo -e "${YELLOW}Use configure_branch_version.sh to set up branch mappings${NC}"
    fi
    exit 1
fi

# Get version for branch
VERSION=$(grep "^$BRANCH_NAME=" "$CONFIG_FILE" | cut -d'=' -f2)

if [[ -z "$VERSION" ]]; then
    if [[ "$QUIET" == true ]]; then
        echo "unknown"
    else
        echo -e "${YELLOW}No version configured for branch '$BRANCH_NAME'${NC}"
        echo -e "${YELLOW}Use configure_branch_version.sh to set up the mapping${NC}"
    fi
    exit 1
fi

if [[ "$QUIET" == true ]]; then
    echo "$VERSION"
else
    echo -e "${GREEN}Branch '$BRANCH_NAME' is configured for Odoo $VERSION${NC}"
fi
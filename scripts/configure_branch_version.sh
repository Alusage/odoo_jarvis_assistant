#!/bin/bash

# configure_branch_version.sh
# Script to configure Odoo version mapping for client branches
# Usage: ./configure_branch_version.sh <client_name> <branch_name> <odoo_version>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CLIENT_DIR="$ROOT_DIR/clients"
CONFIG_DIR="$ROOT_DIR/config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 <client_name> <branch_name> <odoo_version>"
    echo
    echo "Configure Odoo version mapping for a client branch"
    echo
    echo "Arguments:"
    echo "  client_name    Name of the client"
    echo "  branch_name    Branch name to configure"
    echo "  odoo_version   Odoo version for this branch (16.0, 17.0, or 18.0)"
    echo
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -l, --list     List current branch-version mappings"
    echo "  -r, --remove   Remove branch-version mapping"
    echo "  --current      Set mapping for current branch"
    echo
    echo "Examples:"
    echo "  $0 myclient master 18.0"
    echo "  $0 myclient production 17.0"
    echo "  $0 myclient --list"
    echo "  $0 myclient dev 18.0 --current"
}

# Parse command line arguments
CLIENT_NAME=""
BRANCH_NAME=""
ODOO_VERSION=""
LIST_MAPPINGS=false
REMOVE_MAPPING=false
USE_CURRENT_BRANCH=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -l|--list)
            LIST_MAPPINGS=true
            shift
            ;;
        -r|--remove)
            REMOVE_MAPPING=true
            shift
            ;;
        --current)
            USE_CURRENT_BRANCH=true
            shift
            ;;
        *)
            if [[ -z "$CLIENT_NAME" ]]; then
                CLIENT_NAME="$1"
            elif [[ -z "$BRANCH_NAME" ]]; then
                BRANCH_NAME="$1"
            elif [[ -z "$ODOO_VERSION" ]]; then
                ODOO_VERSION="$1"
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

CONFIG_FILE=".odoo_branch_config"

# List mappings
if [[ "$LIST_MAPPINGS" == true ]]; then
    echo -e "${BLUE}Branch-Version Mappings for Client: $CLIENT_NAME${NC}"
    echo
    if [[ -f "$CONFIG_FILE" ]]; then
        echo -e "${YELLOW}Current mappings:${NC}"
        while IFS='=' read -r branch version; do
            if [[ -n "$branch" && -n "$version" ]]; then
                # Check if branch exists
                if git show-ref --verify --quiet "refs/heads/$branch"; then
                    echo -e "  ${GREEN}$branch${NC} → $version"
                else
                    echo -e "  ${YELLOW}$branch${NC} → $version (branch not found)"
                fi
            fi
        done < "$CONFIG_FILE"
    else
        echo -e "${YELLOW}No branch-version mappings configured${NC}"
    fi
    
    echo
    echo -e "${BLUE}Available branches:${NC}"
    git branch -a | sed 's/^/  /'
    exit 0
fi

# Get current branch if needed
if [[ "$USE_CURRENT_BRANCH" == true ]]; then
    BRANCH_NAME=$(git branch --show-current)
    if [[ -z "$BRANCH_NAME" ]]; then
        echo -e "${RED}Error: Could not determine current branch${NC}"
        exit 1
    fi
    echo -e "${BLUE}Using current branch: $BRANCH_NAME${NC}"
fi

# Validate branch name
if [[ -z "$BRANCH_NAME" ]]; then
    echo -e "${RED}Error: Missing branch name${NC}"
    usage
    exit 1
fi

# Remove mapping
if [[ "$REMOVE_MAPPING" == true ]]; then
    if [[ -f "$CONFIG_FILE" ]]; then
        # Remove the mapping
        sed -i "/^$BRANCH_NAME=/d" "$CONFIG_FILE"
        echo -e "${GREEN}Removed mapping for branch '$BRANCH_NAME'${NC}"
        
        # Remove empty file
        if [[ ! -s "$CONFIG_FILE" ]]; then
            rm "$CONFIG_FILE"
            echo -e "${YELLOW}Removed empty configuration file${NC}"
        fi
    else
        echo -e "${YELLOW}No configuration file found${NC}"
    fi
    exit 0
fi

# Validate Odoo version
if [[ -z "$ODOO_VERSION" ]]; then
    echo -e "${RED}Error: Missing Odoo version${NC}"
    usage
    exit 1
fi

# Validate version exists in config
if ! jq -e ".odoo_versions.\"$ODOO_VERSION\"" "$CONFIG_DIR/odoo_versions.json" > /dev/null 2>&1; then
    echo -e "${RED}Error: Invalid Odoo version '$ODOO_VERSION'${NC}"
    echo "Available versions:"
    jq -r '.odoo_versions | keys[]' "$CONFIG_DIR/odoo_versions.json" | sed 's/^/  - /'
    exit 1
fi

# Check if branch exists
if ! git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    echo -e "${YELLOW}Warning: Branch '$BRANCH_NAME' does not exist locally${NC}"
    echo -n "Create the branch? (y/N): "
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        git checkout -b "$BRANCH_NAME"
        echo -e "${GREEN}Created branch '$BRANCH_NAME'${NC}"
    else
        echo "Configuration cancelled"
        exit 1
    fi
fi

# Update or create configuration
if [[ -f "$CONFIG_FILE" ]]; then
    # Update existing mapping or add new one
    if grep -q "^$BRANCH_NAME=" "$CONFIG_FILE"; then
        # Update existing mapping
        sed -i "s/^$BRANCH_NAME=.*/$BRANCH_NAME=$ODOO_VERSION/" "$CONFIG_FILE"
        echo -e "${GREEN}Updated mapping: $BRANCH_NAME → $ODOO_VERSION${NC}"
    else
        # Add new mapping
        echo "$BRANCH_NAME=$ODOO_VERSION" >> "$CONFIG_FILE"
        echo -e "${GREEN}Added mapping: $BRANCH_NAME → $ODOO_VERSION${NC}"
    fi
else
    # Create new configuration file
    echo "$BRANCH_NAME=$ODOO_VERSION" > "$CONFIG_FILE"
    echo -e "${GREEN}Created configuration and added mapping: $BRANCH_NAME → $ODOO_VERSION${NC}"
fi

# Sort the configuration file
sort "$CONFIG_FILE" -o "$CONFIG_FILE"

echo
echo -e "${BLUE}Current branch-version mappings:${NC}"
while IFS='=' read -r branch version; do
    if [[ -n "$branch" && -n "$version" ]]; then
        echo "  $branch → $version"
    fi
done < "$CONFIG_FILE"

echo
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Use 'git checkout $BRANCH_NAME' to switch to this branch"
echo "2. Add/modify modules as needed for Odoo $ODOO_VERSION"
echo "3. The Docker configuration will use Odoo $ODOO_VERSION when on this branch"
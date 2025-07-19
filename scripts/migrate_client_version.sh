#!/bin/bash

# migrate_client_version.sh
# Script to migrate an existing client to a different Odoo version
# Usage: ./migrate_client_version.sh <client_name> <target_version>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CLIENT_DIR="$ROOT_DIR/clients"
CONFIG_DIR="$ROOT_DIR/config"

# Source utility functions if available
if [[ -f "$ROOT_DIR/scripts/utils.sh" ]]; then
    source "$ROOT_DIR/scripts/utils.sh"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 <client_name> <target_version>"
    echo
    echo "Migrate an existing client to a different Odoo version"
    echo
    echo "Arguments:"
    echo "  client_name    Name of the client to migrate"
    echo "  target_version Target Odoo version (16.0, 17.0, or 18.0)"
    echo
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -y, --yes      Skip confirmation prompts"
    echo "  -b, --backup   Create backup before migration"
    echo "  --dry-run      Show what would be done without executing"
    echo
    echo "Examples:"
    echo "  $0 myclient 17.0"
    echo "  $0 myclient 18.0 --backup"
    echo "  $0 myclient 17.0 --dry-run"
}

# Parse command line arguments
CLIENT_NAME=""
TARGET_VERSION=""
SKIP_CONFIRMATION=false
CREATE_BACKUP=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -b|--backup)
            CREATE_BACKUP=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            if [[ -z "$CLIENT_NAME" ]]; then
                CLIENT_NAME="$1"
            elif [[ -z "$TARGET_VERSION" ]]; then
                TARGET_VERSION="$1"
            else
                echo -e "${RED}Error: Unknown argument: $1${NC}"
                usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate arguments
if [[ -z "$CLIENT_NAME" || -z "$TARGET_VERSION" ]]; then
    echo -e "${RED}Error: Missing required arguments${NC}"
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

# Validate target version
if [[ ! -f "$CONFIG_DIR/odoo_versions.json" ]]; then
    echo -e "${RED}Error: Version configuration file not found${NC}"
    exit 1
fi

if ! jq -e ".odoo_versions.\"$TARGET_VERSION\"" "$CONFIG_DIR/odoo_versions.json" > /dev/null 2>&1; then
    echo -e "${RED}Error: Invalid target version '$TARGET_VERSION'${NC}"
    echo "Available versions:"
    jq -r '.odoo_versions | keys[]' "$CONFIG_DIR/odoo_versions.json"
    exit 1
fi

# Get current version
CURRENT_VERSION=""
if [[ -f "$CLIENT_DIR/$CLIENT_NAME/.odoo_version" ]]; then
    CURRENT_VERSION=$(cat "$CLIENT_DIR/$CLIENT_NAME/.odoo_version")
elif [[ -f "$CLIENT_DIR/$CLIENT_NAME/config/odoo.conf" ]]; then
    # Try to extract version from config or guess from directory structure
    CURRENT_VERSION=$(grep -o "^#.*version.*[0-9]\+\.[0-9]\+" "$CLIENT_DIR/$CLIENT_NAME/config/odoo.conf" | grep -o "[0-9]\+\.[0-9]\+" | head -1 || echo "")
fi

if [[ -z "$CURRENT_VERSION" ]]; then
    echo -e "${YELLOW}Warning: Could not determine current version${NC}"
    echo "This might be an older client without version tracking"
    if [[ "$SKIP_CONFIRMATION" == false ]]; then
        echo -n "Continue anyway? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Migration cancelled"
            exit 1
        fi
    fi
else
    echo -e "${BLUE}Current version: $CURRENT_VERSION${NC}"
fi

echo -e "${BLUE}Target version: $TARGET_VERSION${NC}"

# Check if already on target version
if [[ "$CURRENT_VERSION" == "$TARGET_VERSION" ]]; then
    echo -e "${GREEN}Client is already on version $TARGET_VERSION${NC}"
    exit 0
fi

# Load version configurations
TARGET_CONFIG=$(jq -r ".odoo_versions.\"$TARGET_VERSION\"" "$CONFIG_DIR/odoo_versions.json")
TARGET_PYTHON=$(echo "$TARGET_CONFIG" | jq -r '.python_version')
TARGET_REQUIREMENTS=$(echo "$TARGET_CONFIG" | jq -r '.requirements[]')

echo -e "${YELLOW}Migration Plan:${NC}"
echo "  Client: $CLIENT_NAME"
echo "  From: ${CURRENT_VERSION:-"unknown"} -> To: $TARGET_VERSION"
echo "  Python version: $TARGET_PYTHON"
echo "  Docker base image will be updated"
echo "  All submodules will be switched to $TARGET_VERSION branch"
echo "  Requirements will be regenerated"

if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}DRY RUN MODE - No changes will be made${NC}"
fi

# Confirmation
if [[ "$SKIP_CONFIRMATION" == false ]]; then
    echo
    echo -e "${YELLOW}This operation will modify the client repository.${NC}"
    if [[ "$CREATE_BACKUP" == false ]]; then
        echo -e "${YELLOW}Consider using --backup option to create a backup first.${NC}"
    fi
    echo -n "Continue with migration? (y/N): "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Migration cancelled"
        exit 1
    fi
fi

# Create backup if requested
if [[ "$CREATE_BACKUP" == true && "$DRY_RUN" == false ]]; then
    echo -e "${BLUE}Creating backup...${NC}"
    BACKUP_NAME="${CLIENT_NAME}_backup_$(date +%Y%m%d_%H%M%S)"
    cp -r "$CLIENT_DIR/$CLIENT_NAME" "$CLIENT_DIR/$BACKUP_NAME"
    echo -e "${GREEN}Backup created: $BACKUP_NAME${NC}"
fi

# Navigate to client directory
cd "$CLIENT_DIR/$CLIENT_NAME"

echo -e "${BLUE}Starting migration...${NC}"

# Function to execute or show commands
execute_or_show() {
    local cmd="$1"
    local desc="$2"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}Would execute: $desc${NC}"
        echo "  $cmd"
    else
        echo -e "${BLUE}$desc${NC}"
        eval "$cmd"
    fi
}

# Step 1: Update version tracking
execute_or_show "echo '$TARGET_VERSION' > .odoo_version" "Update version tracking file"

# Step 2: Create new branch for target version
CURRENT_BRANCH=$(git branch --show-current)
TARGET_BRANCH="$TARGET_VERSION"

if [[ "$CURRENT_BRANCH" != "$TARGET_BRANCH" ]]; then
    if git show-ref --verify --quiet "refs/heads/$TARGET_BRANCH"; then
        execute_or_show "git checkout '$TARGET_BRANCH'" "Switch to existing $TARGET_BRANCH branch"
    else
        execute_or_show "git checkout -b '$TARGET_BRANCH'" "Create new $TARGET_BRANCH branch"
    fi
fi

# Step 3: Update Docker configuration
DOCKERFILE_PATH="docker/Dockerfile"
if [[ -f "$DOCKERFILE_PATH" ]]; then
    if [[ "$DRY_RUN" == false ]]; then
        # Update base image version
        sed -i "s/FROM odoo:[0-9]\+\.[0-9]\+/FROM odoo:$TARGET_VERSION/" "$DOCKERFILE_PATH"
        echo -e "${GREEN}Updated Docker base image to odoo:$TARGET_VERSION${NC}"
    else
        echo -e "${YELLOW}Would update Docker base image to odoo:$TARGET_VERSION${NC}"
    fi
fi

# Step 4: Update odoo.conf
ODOO_CONF_PATH="config/odoo.conf"
if [[ -f "$ODOO_CONF_PATH" ]]; then
    if [[ "$DRY_RUN" == false ]]; then
        # Add version comment if not present
        if ! grep -q "# Odoo version: $TARGET_VERSION" "$ODOO_CONF_PATH"; then
            sed -i "1i# Odoo version: $TARGET_VERSION" "$ODOO_CONF_PATH"
        fi
        echo -e "${GREEN}Updated odoo.conf with version information${NC}"
    else
        echo -e "${YELLOW}Would update odoo.conf with version $TARGET_VERSION${NC}"
    fi
fi

# Step 5: Update all submodules to target version
echo -e "${BLUE}Updating submodules to $TARGET_VERSION...${NC}"

# Get list of submodules
SUBMODULES=$(git config --file .gitmodules --get-regexp path | awk '{print $2}')

for submodule in $SUBMODULES; do
    if [[ -d "$submodule" ]]; then
        echo -e "${BLUE}  Updating $submodule...${NC}"
        if [[ "$DRY_RUN" == false ]]; then
            cd "$submodule"
            
            # Fetch latest changes
            git fetch origin
            
            # Try to checkout target branch
            if git show-ref --verify --quiet "refs/remotes/origin/$TARGET_VERSION"; then
                git checkout -B "$TARGET_VERSION" "origin/$TARGET_VERSION"
                echo -e "${GREEN}    ✓ Updated to $TARGET_VERSION${NC}"
            else
                echo -e "${YELLOW}    ⚠ Branch $TARGET_VERSION not found, staying on current branch${NC}"
            fi
            
            cd "$CLIENT_DIR/$CLIENT_NAME"
            
            # Update submodule reference
            git add "$submodule"
        else
            echo -e "${YELLOW}    Would update $submodule to $TARGET_VERSION${NC}"
        fi
    fi
done

# Step 6: Update requirements.txt
echo -e "${BLUE}Updating requirements.txt...${NC}"
if [[ "$DRY_RUN" == false ]]; then
    # Regenerate requirements using the update script
    if [[ -f "scripts/update_requirements.sh" ]]; then
        bash scripts/update_requirements.sh
    else
        # Fallback: use main script
        bash "$ROOT_DIR/scripts/update_client_requirements.sh" "$CLIENT_NAME"
    fi
    echo -e "${GREEN}Requirements updated${NC}"
else
    echo -e "${YELLOW}Would regenerate requirements.txt${NC}"
fi

# Step 7: Update symbolic links
echo -e "${BLUE}Updating module symbolic links...${NC}"
if [[ "$DRY_RUN" == false ]]; then
    if [[ -f "scripts/link_modules.sh" ]]; then
        bash scripts/link_modules.sh
        echo -e "${GREEN}Symbolic links updated${NC}"
    fi
else
    echo -e "${YELLOW}Would update symbolic links${NC}"
fi

# Step 8: Commit changes
if [[ "$DRY_RUN" == false ]]; then
    git add .
    git commit -m "Migrate client to Odoo $TARGET_VERSION

- Updated base Docker image to odoo:$TARGET_VERSION
- Switched all submodules to $TARGET_VERSION branch
- Regenerated requirements.txt
- Updated configuration files"
    
    echo -e "${GREEN}Changes committed${NC}"
else
    echo -e "${YELLOW}Would commit migration changes${NC}"
fi

echo
echo -e "${GREEN}Migration completed successfully!${NC}"
echo -e "${BLUE}Client '$CLIENT_NAME' migrated to Odoo $TARGET_VERSION${NC}"

if [[ "$DRY_RUN" == false ]]; then
    echo
    echo "Next steps:"
    echo "1. Test the migrated client:"
    echo "   cd clients/$CLIENT_NAME"
    echo "   docker-compose up -d"
    echo "2. Verify all modules are compatible with $TARGET_VERSION"
    echo "3. Run any necessary data migrations"
    
    if [[ "$CREATE_BACKUP" == true ]]; then
        echo "4. If everything works, you can remove the backup: $BACKUP_NAME"
    fi
fi
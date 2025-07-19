#!/bin/bash

# switch_client_branch.sh
# Script to switch an existing client to a different branch
# Usage: ./switch_client_branch.sh <client_name> <branch_name>

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
    echo "Usage: $0 <client_name> <branch_name>"
    echo
    echo "Switch an existing client to a different branch"
    echo
    echo "Arguments:"
    echo "  client_name    Name of the client"
    echo "  branch_name    Branch name to switch to"
    echo
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -c, --create   Create branch if it doesn't exist"
    echo "  -f, --force    Force switch even with uncommitted changes"
    echo "  --dry-run      Show what would be done without executing"
    echo
    echo "Examples:"
    echo "  $0 myclient feature-branch"
    echo "  $0 myclient staging --create"
    echo "  $0 myclient dev --force"
}

# Parse command line arguments
CLIENT_NAME=""
BRANCH_NAME=""
CREATE_BRANCH=false
FORCE_SWITCH=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -c|--create)
            CREATE_BRANCH=true
            shift
            ;;
        -f|--force)
            FORCE_SWITCH=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
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

# Validate arguments
if [[ -z "$CLIENT_NAME" || -z "$BRANCH_NAME" ]]; then
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

# Navigate to client directory
cd "$CLIENT_DIR/$CLIENT_NAME"

# Check if it's a git repository
if [[ ! -d ".git" ]]; then
    echo -e "${RED}Error: Client directory is not a git repository${NC}"
    exit 1
fi

# Get current branch
CURRENT_BRANCH=$(git branch --show-current)
echo -e "${BLUE}Current branch: $CURRENT_BRANCH${NC}"
echo -e "${BLUE}Target branch: $BRANCH_NAME${NC}"

# Check for branch-version configuration
CONFIG_FILE=".odoo_branch_config"
if [[ -f "$CONFIG_FILE" ]]; then
    # Get version for current branch
    CURRENT_VERSION=$(grep "^$CURRENT_BRANCH=" "$CONFIG_FILE" | cut -d'=' -f2 2>/dev/null || echo "")
    TARGET_VERSION=$(grep "^$BRANCH_NAME=" "$CONFIG_FILE" | cut -d'=' -f2 2>/dev/null || echo "")
    
    if [[ -n "$CURRENT_VERSION" ]]; then
        echo -e "${BLUE}Current branch Odoo version: $CURRENT_VERSION${NC}"
    fi
    if [[ -n "$TARGET_VERSION" ]]; then
        echo -e "${BLUE}Target branch Odoo version: $TARGET_VERSION${NC}"
    fi
fi

# Check if already on target branch
if [[ "$CURRENT_BRANCH" == "$BRANCH_NAME" ]]; then
    echo -e "${GREEN}Already on branch $BRANCH_NAME${NC}"
    exit 0
fi

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

# Check for uncommitted changes
if [[ "$FORCE_SWITCH" == false ]]; then
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo -e "${RED}Error: You have uncommitted changes${NC}"
        echo "Please commit your changes or use --force to continue"
        git status --short
        exit 1
    fi
fi

# Check if branch exists
BRANCH_EXISTS=false
if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    BRANCH_EXISTS=true
    echo -e "${GREEN}Branch $BRANCH_NAME exists locally${NC}"
elif git show-ref --verify --quiet "refs/remotes/origin/$BRANCH_NAME"; then
    echo -e "${YELLOW}Branch $BRANCH_NAME exists on remote${NC}"
    BRANCH_EXISTS=true
fi

# Switch to branch
if [[ "$BRANCH_EXISTS" == true ]]; then
    if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
        # Local branch exists
        execute_or_show "git checkout '$BRANCH_NAME'" "Switch to local branch $BRANCH_NAME"
    else
        # Remote branch exists, create local tracking branch
        execute_or_show "git checkout -b '$BRANCH_NAME' 'origin/$BRANCH_NAME'" "Create local tracking branch $BRANCH_NAME"
    fi
elif [[ "$CREATE_BRANCH" == true ]]; then
    # Create new branch
    execute_or_show "git checkout -b '$BRANCH_NAME'" "Create new branch $BRANCH_NAME"
else
    echo -e "${RED}Error: Branch $BRANCH_NAME does not exist${NC}"
    echo "Use --create option to create a new branch"
    echo
    echo "Available branches:"
    git branch -a
    exit 1
fi

# Update submodules to match the branch if they exist
if [[ -f ".gitmodules" ]]; then
    echo -e "${BLUE}Updating submodules...${NC}"
    
    # Get list of submodules
    SUBMODULES=$(git config --file .gitmodules --get-regexp path | awk '{print $2}')
    
    for submodule in $SUBMODULES; do
        if [[ -d "$submodule" ]]; then
            echo -e "${BLUE}  Checking $submodule...${NC}"
            if [[ "$DRY_RUN" == false ]]; then
                cd "$submodule"
                
                # Get the current commit from the parent repo
                cd "$CLIENT_DIR/$CLIENT_NAME"
                SUBMODULE_COMMIT=$(git ls-tree HEAD "$submodule" | cut -d' ' -f3 | cut -f1)
                
                if [[ -n "$SUBMODULE_COMMIT" ]]; then
                    cd "$submodule"
                    # Check if the commit exists
                    if git cat-file -e "$SUBMODULE_COMMIT" 2>/dev/null; then
                        git checkout "$SUBMODULE_COMMIT"
                        echo -e "${GREEN}    ✓ Updated to commit $SUBMODULE_COMMIT${NC}"
                    else
                        echo -e "${YELLOW}    ⚠ Commit $SUBMODULE_COMMIT not found${NC}"
                    fi
                fi
                
                cd "$CLIENT_DIR/$CLIENT_NAME"
            else
                echo -e "${YELLOW}    Would update $submodule${NC}"
            fi
        fi
    done
    
    if [[ "$DRY_RUN" == false ]]; then
        # Initialize and update submodules
        git submodule update --init --recursive
        echo -e "${GREEN}Submodules updated${NC}"
    else
        echo -e "${YELLOW}Would update all submodules${NC}"
    fi
fi

# Update symbolic links if script exists
if [[ -f "scripts/link_modules.sh" ]]; then
    echo -e "${BLUE}Updating module symbolic links...${NC}"
    if [[ "$DRY_RUN" == false ]]; then
        bash scripts/link_modules.sh
        echo -e "${GREEN}Symbolic links updated${NC}"
    else
        echo -e "${YELLOW}Would update symbolic links${NC}"
    fi
fi

echo
echo -e "${GREEN}Branch switch completed successfully!${NC}"
echo -e "${BLUE}Client '$CLIENT_NAME' is now on branch '$BRANCH_NAME'${NC}"

if [[ "$DRY_RUN" == false ]]; then
    echo
    echo "Current status:"
    git status --short
    echo
    echo "Recent commits on this branch:"
    git log --oneline -5
fi
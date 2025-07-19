#!/bin/bash

# check_version_compatibility.sh
# Script to check module compatibility across different Odoo versions
# Usage: ./check_version_compatibility.sh <client_name> [target_version]

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
    echo "Usage: $0 <client_name> [target_version]"
    echo
    echo "Check module compatibility for a client across Odoo versions"
    echo
    echo "Arguments:"
    echo "  client_name     Name of the client to check"
    echo "  target_version  Target Odoo version to check compatibility for"
    echo "                  (optional, will check all versions if not specified)"
    echo
    echo "Options:"
    echo "  -h, --help      Show this help message"
    echo "  -v, --verbose   Show detailed information"
    echo "  -o, --output    Output format (text, json, csv)"
    echo "  --only-issues   Only show modules with compatibility issues"
    echo
    echo "Examples:"
    echo "  $0 myclient"
    echo "  $0 myclient 17.0"
    echo "  $0 myclient 18.0 --verbose"
    echo "  $0 myclient --output json"
}

# Parse command line arguments
CLIENT_NAME=""
TARGET_VERSION=""
VERBOSE=false
OUTPUT_FORMAT="text"
ONLY_ISSUES=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -o|--output)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --only-issues)
            ONLY_ISSUES=true
            shift
            ;;
        -*)
            echo -e "${RED}Error: Unknown option: $1${NC}"
            usage
            exit 1
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

# Validate output format
if [[ "$OUTPUT_FORMAT" != "text" && "$OUTPUT_FORMAT" != "json" && "$OUTPUT_FORMAT" != "csv" ]]; then
    echo -e "${RED}Error: Invalid output format '$OUTPUT_FORMAT'${NC}"
    echo "Valid formats: text, json, csv"
    exit 1
fi

# Get available versions
if [[ ! -f "$CONFIG_DIR/odoo_versions.json" ]]; then
    echo -e "${RED}Error: Version configuration file not found: $CONFIG_DIR/odoo_versions.json${NC}"
    exit 1
fi
AVAILABLE_VERSIONS=($(jq -r '.odoo_versions | keys[]' "$CONFIG_DIR/odoo_versions.json"))

# If target version specified, validate it
if [[ -n "$TARGET_VERSION" ]]; then
    if ! jq -e ".odoo_versions.\"$TARGET_VERSION\"" "$CONFIG_DIR/odoo_versions.json" > /dev/null 2>&1; then
        echo -e "${RED}Error: Invalid target version '$TARGET_VERSION'${NC}"
        echo "Available versions: ${AVAILABLE_VERSIONS[*]}"
        exit 1
    fi
    VERSIONS_TO_CHECK=("$TARGET_VERSION")
else
    VERSIONS_TO_CHECK=("${AVAILABLE_VERSIONS[@]}")
fi

# Navigate to client directory
cd "$CLIENT_DIR/$CLIENT_NAME"

# Check if it's a git repository
if [[ ! -d ".git" ]]; then
    echo -e "${RED}Error: Client directory is not a git repository${NC}"
    exit 1
fi

# Get current version
CURRENT_VERSION=""
if [[ -f ".odoo_version" ]]; then
    CURRENT_VERSION=$(cat .odoo_version)
fi

# Function to check if a branch exists in a repository
check_branch_exists() {
    local repo_path="$1"
    local branch="$2"
    
    if [[ -d "$repo_path" ]]; then
        cd "$repo_path"
        if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
            echo "yes"
        else
            echo "no"
        fi
        cd "$CLIENT_DIR/$CLIENT_NAME"
    else
        echo "no_repo"
    fi
}

# Function to get module manifest info
get_module_info() {
    local module_path="$1"
    local manifest_file=""
    
    if [[ -f "$module_path/__manifest__.py" ]]; then
        manifest_file="$module_path/__manifest__.py"
    elif [[ -f "$module_path/__openerp__.py" ]]; then
        manifest_file="$module_path/__openerp__.py"
    else
        echo "no_manifest"
        return
    fi
    
    # Extract version and dependencies (simplified)
    python3 -c "
import ast
import sys
try:
    with open('$manifest_file', 'r') as f:
        manifest = ast.literal_eval(f.read())
    print('version:', manifest.get('version', 'unknown'))
    print('depends:', ','.join(manifest.get('depends', [])))
    print('installable:', manifest.get('installable', True))
except Exception as e:
    print('error:', str(e))
" 2>/dev/null || echo "parse_error"
}

# Initialize results
declare -A COMPATIBILITY_RESULTS
declare -A MODULE_INFO

# Get list of submodules
if [[ -f ".gitmodules" ]]; then
    SUBMODULES=$(git config --file .gitmodules --get-regexp path | awk '{print $2}')
else
    SUBMODULES=""
fi

# Get list of modules from extra-addons
EXTRA_MODULES=""
if [[ -d "extra-addons" ]]; then
    EXTRA_MODULES=$(ls -1 extra-addons/ 2>/dev/null || echo "")
fi

# Combine all modules
ALL_MODULES=""
for submodule in $SUBMODULES; do
    if [[ -d "$submodule" ]]; then
        # Get individual modules within the submodule
        MODULES_IN_SUBMODULE=$(ls -1 "$submodule"/ 2>/dev/null | grep -v -E '\.(md|rst|txt|py|cfg|yml|yaml|json)$|^(\.|setup|requirements|test|doc|hook|prettier|eslint|checklog)' || echo "")
        for module in $MODULES_IN_SUBMODULE; do
            if [[ -d "$submodule/$module" && (-f "$submodule/$module/__manifest__.py" || -f "$submodule/$module/__openerp__.py") ]]; then
                ALL_MODULES="$ALL_MODULES $submodule/$module"
            fi
        done
    fi
done

# Add extra-addons modules
for module in $EXTRA_MODULES; do
    if [[ -d "extra-addons/$module" ]]; then
        ALL_MODULES="$ALL_MODULES extra-addons/$module"
    fi
done

# If no modules found, exit
if [[ -z "$ALL_MODULES" ]]; then
    echo -e "${YELLOW}No modules found in client $CLIENT_NAME${NC}"
    exit 0
fi

# Header for text output
if [[ "$OUTPUT_FORMAT" == "text" ]]; then
    echo -e "${BLUE}Compatibility Check for Client: $CLIENT_NAME${NC}"
    if [[ -n "$CURRENT_VERSION" ]]; then
        echo -e "${BLUE}Current Version: $CURRENT_VERSION${NC}"
    fi
    echo -e "${BLUE}Checking versions: ${VERSIONS_TO_CHECK[*]}${NC}"
    echo
fi

# Check compatibility for each version
for version in "${VERSIONS_TO_CHECK[@]}"; do
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo -e "${YELLOW}=== Checking Odoo $version ===${NC}"
    fi
    
    for module_path in $ALL_MODULES; do
        module_name=$(basename "$module_path")
        
        # Get module information
        module_info=$(get_module_info "$module_path")
        
        if [[ "$module_info" == "no_manifest" ]]; then
            status="no_manifest"
        elif [[ "$module_info" == "parse_error" ]]; then
            status="parse_error"
        else
            # Parse module info
            module_version=$(echo "$module_info" | grep "^version:" | cut -d' ' -f2)
            module_depends=$(echo "$module_info" | grep "^depends:" | cut -d' ' -f2)
            module_installable=$(echo "$module_info" | grep "^installable:" | cut -d' ' -f2)
            
            # Check if module is installable
            if [[ "$module_installable" == "False" ]]; then
                status="not_installable"
            else
                # Check if the parent repository has the target version branch
                if [[ "$module_path" == extra-addons/* ]]; then
                    # Extra addon, assume compatible
                    status="compatible"
                else
                    # Get parent repository path
                    parent_repo=$(echo "$module_path" | cut -d'/' -f1)
                    branch_exists=$(check_branch_exists "$parent_repo" "$version")
                    
                    if [[ "$branch_exists" == "yes" ]]; then
                        status="compatible"
                    elif [[ "$branch_exists" == "no" ]]; then
                        status="branch_missing"
                    else
                        status="repo_missing"
                    fi
                fi
            fi
        fi
        
        # Store results
        COMPATIBILITY_RESULTS["$module_name|$version"]="$status"
        MODULE_INFO["$module_name"]="$module_path|$module_version|$module_depends|$module_installable"
        
        # Output based on format
        if [[ "$OUTPUT_FORMAT" == "text" ]]; then
            if [[ "$ONLY_ISSUES" == "true" && "$status" == "compatible" ]]; then
                continue
            fi
            
            case "$status" in
                "compatible")
                    echo -e "  ${GREEN}✓${NC} $module_name"
                    ;;
                "branch_missing")
                    echo -e "  ${RED}✗${NC} $module_name (branch $version not found)"
                    ;;
                "not_installable")
                    echo -e "  ${YELLOW}⚠${NC} $module_name (not installable)"
                    ;;
                "no_manifest")
                    echo -e "  ${RED}✗${NC} $module_name (no manifest file)"
                    ;;
                "parse_error")
                    echo -e "  ${RED}✗${NC} $module_name (manifest parse error)"
                    ;;
                "repo_missing")
                    echo -e "  ${RED}✗${NC} $module_name (repository missing)"
                    ;;
                *)
                    echo -e "  ${RED}✗${NC} $module_name (unknown error)"
                    ;;
            esac
            
            if [[ "$VERBOSE" == "true" ]]; then
                echo "      Path: $module_path"
                if [[ -n "$module_version" ]]; then
                    echo "      Version: $module_version"
                fi
                if [[ -n "$module_depends" ]]; then
                    echo "      Depends: $module_depends"
                fi
            fi
        fi
    done
    
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo
    fi
done

# Generate summary
TOTAL_MODULES=$(echo "$ALL_MODULES" | wc -w)
COMPATIBLE_COUNT=0
INCOMPATIBLE_COUNT=0

for version in "${VERSIONS_TO_CHECK[@]}"; do
    for module_path in $ALL_MODULES; do
        module_name=$(basename "$module_path")
        status="${COMPATIBILITY_RESULTS["$module_name|$version"]}"
        
        if [[ "$status" == "compatible" ]]; then
            ((COMPATIBLE_COUNT++))
        else
            ((INCOMPATIBLE_COUNT++))
        fi
    done
done

# Output results based on format
case "$OUTPUT_FORMAT" in
    "json")
        echo "{"
        echo "  \"client\": \"$CLIENT_NAME\","
        echo "  \"current_version\": \"$CURRENT_VERSION\","
        echo "  \"checked_versions\": [$(printf '\"%s\",' "${VERSIONS_TO_CHECK[@]}" | sed 's/,$//')],"
        echo "  \"total_modules\": $TOTAL_MODULES,"
        echo "  \"results\": {"
        
        first_module=true
        for module_path in $ALL_MODULES; do
            module_name=$(basename "$module_path")
            
            if [[ "$first_module" == "true" ]]; then
                first_module=false
            else
                echo ","
            fi
            
            echo -n "    \"$module_name\": {"
            echo -n "\"path\": \"$module_path\""
            
            for version in "${VERSIONS_TO_CHECK[@]}"; do
                status="${COMPATIBILITY_RESULTS["$module_name|$version"]}"
                echo -n ", \"$version\": \"$status\""
            done
            
            echo -n "}"
        done
        
        echo
        echo "  }"
        echo "}"
        ;;
        
    "csv")
        echo "Module,Path,$(printf '%s,' "${VERSIONS_TO_CHECK[@]}" | sed 's/,$//')"
        
        for module_path in $ALL_MODULES; do
            module_name=$(basename "$module_path")
            echo -n "$module_name,$module_path"
            
            for version in "${VERSIONS_TO_CHECK[@]}"; do
                status="${COMPATIBILITY_RESULTS["$module_name|$version"]}"
                echo -n ",$status"
            done
            
            echo
        done
        ;;
        
    "text")
        echo -e "${BLUE}=== Summary ===${NC}"
        echo "Total modules: $TOTAL_MODULES"
        echo "Total checks: $((COMPATIBLE_COUNT + INCOMPATIBLE_COUNT))"
        echo -e "${GREEN}Compatible: $COMPATIBLE_COUNT${NC}"
        echo -e "${RED}Issues found: $INCOMPATIBLE_COUNT${NC}"
        
        if [[ "$INCOMPATIBLE_COUNT" -gt 0 ]]; then
            echo
            echo -e "${YELLOW}Modules with issues:${NC}"
            for version in "${VERSIONS_TO_CHECK[@]}"; do
                for module_path in $ALL_MODULES; do
                    module_name=$(basename "$module_path")
                    status="${COMPATIBILITY_RESULTS["$module_name|$version"]}"
                    
                    if [[ "$status" != "compatible" ]]; then
                        echo "  $module_name ($version): $status"
                    fi
                done
            done
        fi
        ;;
esac
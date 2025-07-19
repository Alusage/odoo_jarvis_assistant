#!/bin/bash

# build_branch_image.sh
# Script pour construire une image Docker pour une branche spécifique d'un client
# Usage: ./build_branch_image.sh <client_name> <branch_name> [options]

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
    echo "Usage: $0 <client_name> <branch_name> [options]"
    echo
    echo "Build a Docker image for a specific branch of a client"
    echo
    echo "Arguments:"
    echo "  client_name    Name of the client"
    echo "  branch_name    Branch name to build"
    echo
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -f, --force         Force rebuild (no cache)"
    echo "  -t, --tag TAG       Custom tag for the image"
    echo "  -v, --version VER   Odoo version override"
    echo "  --pull              Pull latest base image"
    echo "  --push              Push image to registry after build"
    echo "  --dry-run           Show what would be built without building"
    echo
    echo "Examples:"
    echo "  $0 testclient master"
    echo "  $0 testclient dev-feature --force"
    echo "  $0 testclient staging --tag my-staging-image"
    echo "  $0 testclient production --version 17.0"
}

# Parse command line arguments
CLIENT_NAME=""
BRANCH_NAME=""
FORCE_BUILD=false
CUSTOM_TAG=""
ODOO_VERSION=""
PULL_BASE=false
PUSH_IMAGE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -f|--force)
            FORCE_BUILD=true
            shift
            ;;
        -t|--tag)
            CUSTOM_TAG="$2"
            shift 2
            ;;
        -v|--version)
            ODOO_VERSION="$2"
            shift 2
            ;;
        --pull)
            PULL_BASE=true
            shift
            ;;
        --push)
            PUSH_IMAGE=true
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

# Check if branch exists
if ! git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    echo -e "${RED}Error: Branch '$BRANCH_NAME' does not exist${NC}"
    echo "Available branches:"
    git branch -a
    exit 1
fi

# Get branch version if not specified
if [[ -z "$ODOO_VERSION" ]]; then
    if [[ -f ".odoo_branch_config" ]]; then
        ODOO_VERSION=$(grep "^$BRANCH_NAME=" ".odoo_branch_config" | cut -d'=' -f2 2>/dev/null || echo "")
    fi
    
    if [[ -z "$ODOO_VERSION" ]]; then
        ODOO_VERSION="18.0"  # Default version
        echo -e "${YELLOW}Using default Odoo version: $ODOO_VERSION${NC}"
    fi
fi

# Validate Odoo version
if [[ -f "$CONFIG_DIR/odoo_versions.json" ]]; then
    if ! jq -e ".odoo_versions.\"$ODOO_VERSION\"" "$CONFIG_DIR/odoo_versions.json" > /dev/null 2>&1; then
        echo -e "${RED}Error: Invalid Odoo version '$ODOO_VERSION'${NC}"
        echo "Available versions:"
        jq -r '.odoo_versions | keys[]' "$CONFIG_DIR/odoo_versions.json" | sed 's/^/  - /'
        exit 1
    fi
fi

# Clean branch name for image tag
CLEAN_BRANCH=$(echo "$BRANCH_NAME" | sed 's/[^a-zA-Z0-9]/-/g')

# Generate image name
if [[ -n "$CUSTOM_TAG" ]]; then
    IMAGE_NAME="$CUSTOM_TAG"
else
    IMAGE_NAME="odoo-alusage-${CLIENT_NAME}-${CLEAN_BRANCH}:${ODOO_VERSION}"
fi

# Build date
BUILD_DATE=$(date -Iseconds)

echo -e "${BLUE}=== Docker Build Configuration ===${NC}"
echo -e "${BLUE}Client: $CLIENT_NAME${NC}"
echo -e "${BLUE}Branch: $BRANCH_NAME${NC}"
echo -e "${BLUE}Odoo Version: $ODOO_VERSION${NC}"
echo -e "${BLUE}Image Name: $IMAGE_NAME${NC}"
echo -e "${BLUE}Build Date: $BUILD_DATE${NC}"
echo

# Check if Dockerfile exists
DOCKERFILE_PATH="docker/Dockerfile"
if [[ ! -f "$DOCKERFILE_PATH" ]]; then
    echo -e "${RED}Error: Dockerfile not found at $DOCKERFILE_PATH${NC}"
    exit 1
fi

# Show current commit info
echo -e "${BLUE}=== Git Repository Information ===${NC}"
echo -e "${BLUE}Current branch: $(git branch --show-current)${NC}"
echo -e "${BLUE}Last commit: $(git log -1 --oneline)${NC}"
echo -e "${BLUE}Target branch: $BRANCH_NAME${NC}"

# Get target branch commit info
TARGET_COMMIT=$(git rev-parse "$BRANCH_NAME")
TARGET_COMMIT_SHORT=$(git rev-parse --short "$BRANCH_NAME")
TARGET_COMMIT_MSG=$(git log -1 --pretty=format:"%s" "$BRANCH_NAME")

echo -e "${BLUE}Target commit: $TARGET_COMMIT_SHORT - $TARGET_COMMIT_MSG${NC}"
echo

if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}=== DRY RUN - Would execute the following ===${NC}"
    echo "docker build \\"
    echo "  --build-arg ODOO_VERSION=$ODOO_VERSION \\"
    echo "  --build-arg CLIENT_BRANCH=$BRANCH_NAME \\"
    echo "  --build-arg BUILD_DATE=$BUILD_DATE \\"
    if [[ "$FORCE_BUILD" == true ]]; then
        echo "  --no-cache \\"
    fi
    if [[ "$PULL_BASE" == true ]]; then
        echo "  --pull \\"
    fi
    echo "  -v \$(pwd):/mnt/client \\"
    echo "  -t $IMAGE_NAME \\"
    echo "  -f $DOCKERFILE_PATH \\"
    echo "  ."
    echo
    if [[ "$PUSH_IMAGE" == true ]]; then
        echo "docker push $IMAGE_NAME"
    fi
    exit 0
fi

# Build the image
echo -e "${BLUE}=== Building Docker Image ===${NC}"

BUILD_ARGS=(
    "--build-arg" "ODOO_VERSION=$ODOO_VERSION"
    "--build-arg" "CLIENT_BRANCH=$BRANCH_NAME"
    "--build-arg" "BUILD_DATE=$BUILD_DATE"
    "-v" "$(pwd):/mnt/client"
    "-t" "$IMAGE_NAME"
    "-f" "$DOCKERFILE_PATH"
)

if [[ "$FORCE_BUILD" == true ]]; then
    BUILD_ARGS+=("--no-cache")
fi

if [[ "$PULL_BASE" == true ]]; then
    BUILD_ARGS+=("--pull")
fi

BUILD_ARGS+=(".")

# Execute build
echo -e "${BLUE}Executing: docker build ${BUILD_ARGS[*]}${NC}"
docker build "${BUILD_ARGS[@]}"

BUILD_EXIT_CODE=$?

if [[ $BUILD_EXIT_CODE -eq 0 ]]; then
    echo -e "${GREEN}=== Build Successful ===${NC}"
    echo -e "${GREEN}Image: $IMAGE_NAME${NC}"
    
    # Show image info
    echo -e "${BLUE}=== Image Information ===${NC}"
    docker images "$IMAGE_NAME" --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}\t{{.Size}}"
    
    # Show image labels
    echo -e "${BLUE}=== Image Labels ===${NC}"
    docker inspect "$IMAGE_NAME" --format '{{range $key, $value := .Config.Labels}}{{$key}}: {{$value}}{{"\n"}}{{end}}' | grep -E "(client|branch|odoo|build)" | sort
    
    # Push image if requested
    if [[ "$PUSH_IMAGE" == true ]]; then
        echo -e "${BLUE}=== Pushing Image ===${NC}"
        docker push "$IMAGE_NAME"
        
        if [[ $? -eq 0 ]]; then
            echo -e "${GREEN}Image pushed successfully${NC}"
        else
            echo -e "${RED}Failed to push image${NC}"
            exit 1
        fi
    fi
    
    echo
    echo -e "${GREEN}=== Build Complete ===${NC}"
    echo -e "${GREEN}You can now run the container with:${NC}"
    echo -e "${GREEN}docker run -d --name ${CLIENT_NAME}-${CLEAN_BRANCH} -p 8069:8069 -v \$(pwd)/data:/data $IMAGE_NAME${NC}"
    
else
    echo -e "${RED}=== Build Failed ===${NC}"
    echo -e "${RED}Exit code: $BUILD_EXIT_CODE${NC}"
    exit $BUILD_EXIT_CODE
fi
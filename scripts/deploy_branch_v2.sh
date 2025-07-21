#!/bin/bash

# deploy_branch_v2.sh
# Script pour déployer une branche avec la nouvelle architecture (Git clone dans Docker)
# Usage: ./deploy_branch_v2.sh <client_name> <branch_name> [action]

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
    echo "Usage: $0 <client_name> <branch_name> [action]"
    echo
    echo "Deploy a branch with embedded Git repository architecture"
    echo
    echo "Arguments:"
    echo "  client_name    Name of the client"
    echo "  branch_name    Branch name to deploy"
    echo "  action         Action to perform (up, down, restart, logs, shell, status, build)"
    echo
    echo "Actions:"
    echo "  up      Build image if needed and start deployment (default)"
    echo "  down    Stop and remove the deployment"
    echo "  restart Restart the deployment"
    echo "  logs    Show logs"
    echo "  shell   Open shell in container"
    echo "  status  Show deployment status"
    echo "  build   Build/rebuild the Docker image"
    echo "  rebuild Force rebuild the Docker image"
    echo
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -d, --detach   Run in detached mode"
    echo "  -f, --force    Force rebuild image"
    echo "  -p, --port     Custom port (default: auto-assign)"
    echo
    echo "Examples:"
    echo "  $0 testclient master"
    echo "  $0 testclient dev-feature up"
    echo "  $0 testclient staging restart"
    echo "  $0 testclient production logs"
    echo "  $0 testclient dev build --force"
}

# Parse command line arguments
CLIENT_NAME=""
BRANCH_NAME=""
ACTION="up"
DETACH=true
FORCE_BUILD=false
CUSTOM_PORT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--detach)
            DETACH=true
            shift
            ;;
        -f|--force)
            FORCE_BUILD=true
            shift
            ;;
        -p|--port)
            CUSTOM_PORT="$2"
            shift 2
            ;;
        *)
            if [[ -z "$CLIENT_NAME" ]]; then
                CLIENT_NAME="$1"
            elif [[ -z "$BRANCH_NAME" ]]; then
                BRANCH_NAME="$1"
            elif [[ -z "$ACTION" || "$ACTION" == "up" ]]; then
                ACTION="$1"
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

# Get branch version
get_branch_version() {
    local branch="$1"
    local version=""
    
    if [[ -f ".odoo_branch_config" ]]; then
        version=$(grep "^$branch=" ".odoo_branch_config" | cut -d'=' -f2 2>/dev/null || echo "")
    fi
    
    if [[ -z "$version" ]]; then
        version="18.0"  # Default version
    fi
    
    echo "$version"
}

# Get next available port
get_next_port() {
    local base_port=8100
    local port=$base_port
    
    while netstat -ln 2>/dev/null | grep -q ":$port " || docker ps --format "{{.Ports}}" | grep -q "$port"; do
        ((port++))
        if [[ $port -gt 8200 ]]; then
            echo -e "${RED}Error: No available ports in range 8100-8200${NC}"
            exit 1
        fi
    done
    
    echo "$port"
}

# Variables
VERSION=$(get_branch_version "$BRANCH_NAME")
CLEAN_BRANCH=$(echo "$BRANCH_NAME" | sed 's/[^a-zA-Z0-9]/-/g')
IMAGE_NAME="odoo-alusage-${CLIENT_NAME}:${VERSION}"

# Container naming: branche-odoo-client format
CONTAINER_NAME="${CLEAN_BRANCH}-odoo-${CLIENT_NAME}"
POSTGRES_CONTAINER_NAME="${CLEAN_BRANCH}-postgres-${CLIENT_NAME}"
NETWORK_NAME="${CLIENT_NAME}-${CLEAN_BRANCH}-network"

# Traefik URLs
TRAEFIK_URL="${CLEAN_BRANCH}.${CLIENT_NAME}.local"

# Get port
if [[ -z "$CUSTOM_PORT" ]]; then
    CUSTOM_PORT=$(get_next_port)
fi

echo -e "${BLUE}=== Deployment Configuration ===${NC}"
echo -e "${BLUE}Client: $CLIENT_NAME${NC}"
echo -e "${BLUE}Branch: $BRANCH_NAME${NC}"
echo -e "${BLUE}Version: $VERSION${NC}"
echo -e "${BLUE}Image: $IMAGE_NAME${NC}"
echo -e "${BLUE}Container: $CONTAINER_NAME${NC}"
echo -e "${BLUE}Port: $CUSTOM_PORT${NC}"
echo -e "${BLUE}URL: http://localhost:$CUSTOM_PORT${NC}"
echo -e "${BLUE}Traefik URL: http://$TRAEFIK_URL${NC}"
echo

# Function to check if image exists
image_exists() {
    # For branches other than production, look for any image with branch pattern
    if [[ "$BRANCH_NAME" != "18.0" ]]; then
        docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^odoo-alusage-${CLIENT_NAME}:${CLEAN_BRANCH}-"
    else
        docker images -q "$IMAGE_NAME" 2>/dev/null | grep -q .
    fi
}

# Function to check if container exists
container_exists() {
    docker ps -a --format "{{.Names}}" | grep -q "^$CONTAINER_NAME$"
}

# Function to check if container is running
container_running() {
    docker ps --format "{{.Names}}" | grep -q "^$CONTAINER_NAME$"
}

# Function to build image
build_image() {
    local force_flag=""
    if [[ "$FORCE_BUILD" == true ]]; then
        force_flag="--force"
    fi
    
    echo -e "${BLUE}Building image for $CLIENT_NAME/$BRANCH_NAME...${NC}"
    "$SCRIPT_DIR/build_branch_image.sh" "$CLIENT_NAME" "$BRANCH_NAME" $force_flag
}

# Function to create network if it doesn't exist
create_network() {
    if ! docker network ls --format "{{.Name}}" | grep -q "^$NETWORK_NAME$"; then
        echo -e "${BLUE}Creating network: $NETWORK_NAME${NC}"
        docker network create "$NETWORK_NAME"
    fi
}

# Function to start postgres
start_postgres() {
    if ! docker ps --format "{{.Names}}" | grep -q "^$POSTGRES_CONTAINER_NAME$"; then
        echo -e "${BLUE}Starting PostgreSQL container...${NC}"
        
        # Create data directory
        mkdir -p "data/${CLEAN_BRANCH}/postgresql"
        
        docker run -d \
            --name "$POSTGRES_CONTAINER_NAME" \
            --network "$NETWORK_NAME" \
            -e POSTGRES_DB=postgres \
            -e POSTGRES_USER=odoo \
            -e POSTGRES_PASSWORD=odoo \
            -e PGDATA=/var/lib/postgresql/data/pgdata \
            -v "$(pwd)/data/${CLEAN_BRANCH}/postgresql:/var/lib/postgresql/data" \
            --restart unless-stopped \
            postgres:15
    fi
}

# Function to deploy
deploy_branch() {
    # Check if image exists or build needed
    if ! image_exists || [[ "$FORCE_BUILD" == true ]]; then
        build_image
    fi
    
    # Create network
    create_network
    
    # Start postgres
    start_postgres
    
    # Create data directory
    mkdir -p "data/${CLEAN_BRANCH}"
    
    # Stop existing container if running
    if container_running; then
        echo -e "${BLUE}Stopping existing container...${NC}"
        docker stop "$CONTAINER_NAME"
    fi
    
    # Remove existing container if it exists
    if container_exists; then
        echo -e "${BLUE}Removing existing container...${NC}"
        docker rm "$CONTAINER_NAME"
    fi
    
    # Start new container with Traefik integration
    echo -e "${BLUE}Starting new container...${NC}"
    docker run -d \
        --name "$CONTAINER_NAME" \
        --network "$NETWORK_NAME" \
        -p "$CUSTOM_PORT:8069" \
        -v "$(pwd)/data/${CLEAN_BRANCH}:/data" \
        -e HOST="$POSTGRES_CONTAINER_NAME" \
        -e USER=odoo \
        -e PASSWORD=odoo \
        --restart unless-stopped \
        --label "deployment.client=$CLIENT_NAME" \
        --label "deployment.branch=$BRANCH_NAME" \
        --label "deployment.version=$VERSION" \
        --label "deployment.port=$CUSTOM_PORT" \
        --label "deployment.created=$(date -Iseconds)" \
        --label "traefik.enable=true" \
        --label "traefik.docker.network=traefik-local" \
        --label "traefik.http.routers.${CLEAN_BRANCH}-${CLIENT_NAME}.rule=Host(\`${TRAEFIK_URL}\`)" \
        --label "traefik.http.routers.${CLEAN_BRANCH}-${CLIENT_NAME}.entrypoints=web" \
        --label "traefik.http.services.${CLEAN_BRANCH}-${CLIENT_NAME}.loadbalancer.server.port=8069" \
        --label "traefik.http.routers.${CLEAN_BRANCH}-${CLIENT_NAME}.middlewares=odoo-headers,odoo-compress" \
        --label "traefik.http.routers.${CLEAN_BRANCH}-${CLIENT_NAME}-ws.rule=Host(\`${TRAEFIK_URL}\`) && PathPrefix(\`/websocket\`)" \
        --label "traefik.http.routers.${CLEAN_BRANCH}-${CLIENT_NAME}-ws.entrypoints=web" \
        --label "traefik.http.services.${CLEAN_BRANCH}-${CLIENT_NAME}-ws.loadbalancer.server.port=8072" \
        --label "traefik.http.routers.${CLEAN_BRANCH}-${CLIENT_NAME}-ws.middlewares=odoo-headers,odoo-compress" \
        "$IMAGE_NAME"
    
    # Connect to traefik network
    echo -e "${BLUE}Connecting to traefik network...${NC}"
    docker network connect traefik-local "$CONTAINER_NAME" 2>/dev/null || true
    
    echo -e "${GREEN}Deployment started successfully!${NC}"
    echo -e "${GREEN}Direct URL: http://localhost:$CUSTOM_PORT${NC}"
    echo -e "${GREEN}Traefik URL: http://$TRAEFIK_URL${NC}"
    echo -e "${GREEN}Container: $CONTAINER_NAME${NC}"
}

# Function to stop deployment
stop_deployment() {
    if container_running; then
        echo -e "${BLUE}Stopping container: $CONTAINER_NAME${NC}"
        docker stop "$CONTAINER_NAME"
    fi
    
    if docker ps --format "{{.Names}}" | grep -q "^$POSTGRES_CONTAINER_NAME$"; then
        echo -e "${BLUE}Stopping PostgreSQL container: $POSTGRES_CONTAINER_NAME${NC}"
        docker stop "$POSTGRES_CONTAINER_NAME"
    fi
    
    echo -e "${GREEN}Deployment stopped${NC}"
}

# Function to restart deployment
restart_deployment() {
    if container_exists; then
        echo -e "${BLUE}Restarting container: $CONTAINER_NAME${NC}"
        docker restart "$CONTAINER_NAME"
        
        if docker ps -a --format "{{.Names}}" | grep -q "^$POSTGRES_CONTAINER_NAME$"; then
            docker restart "$POSTGRES_CONTAINER_NAME"
        fi
    else
        echo -e "${YELLOW}Container doesn't exist, creating new deployment...${NC}"
        deploy_branch
    fi
}

# Function to show logs
show_logs() {
    if container_exists; then
        echo -e "${BLUE}Showing logs for: $CONTAINER_NAME${NC}"
        docker logs -f "$CONTAINER_NAME"
    else
        echo -e "${RED}Container doesn't exist${NC}"
        exit 1
    fi
}

# Function to open shell
open_shell() {
    if container_running; then
        echo -e "${BLUE}Opening shell in: $CONTAINER_NAME${NC}"
        docker exec -it "$CONTAINER_NAME" bash
    else
        echo -e "${RED}Container is not running${NC}"
        exit 1
    fi
}

# Function to show status
show_status() {
    echo -e "${BLUE}=== Deployment Status ===${NC}"
    
    if image_exists; then
        if [[ "$BRANCH_NAME" != "18.0" ]]; then
            # Show actual images found for this branch
            local found_images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^odoo-alusage-${CLIENT_NAME}:${CLEAN_BRANCH}-")
            echo -e "${GREEN}✓ Image exists: $found_images${NC}"
        else
            echo -e "${GREEN}✓ Image exists: $IMAGE_NAME${NC}"
        fi
    else
        if [[ "$BRANCH_NAME" != "18.0" ]]; then
            echo -e "${RED}✗ Image not found: odoo-alusage-${CLIENT_NAME}:${CLEAN_BRANCH}-*${NC}"
        else
            echo -e "${RED}✗ Image not found: $IMAGE_NAME${NC}"
        fi
    fi
    
    if container_exists; then
        local status=$(docker inspect --format='{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "unknown")
        echo -e "${GREEN}✓ Container exists: $CONTAINER_NAME${NC}"
        echo -e "${BLUE}  Status: $status${NC}"
        
        if [[ "$status" == "running" ]]; then
            echo -e "${GREEN}  Direct URL: http://localhost:$CUSTOM_PORT${NC}"
            echo -e "${GREEN}  Traefik URL: http://$TRAEFIK_URL${NC}"
        fi
    else
        echo -e "${RED}✗ Container not found: $CONTAINER_NAME${NC}"
    fi
    
    # Show postgres status
    if docker ps -a --format "{{.Names}}" | grep -q "^$POSTGRES_CONTAINER_NAME$"; then
        local pg_status=$(docker inspect --format='{{.State.Status}}' "$POSTGRES_CONTAINER_NAME" 2>/dev/null || echo "unknown")
        echo -e "${GREEN}✓ PostgreSQL container: $POSTGRES_CONTAINER_NAME${NC}"
        echo -e "${BLUE}  Status: $pg_status${NC}"
    else
        echo -e "${RED}✗ PostgreSQL container not found: $POSTGRES_CONTAINER_NAME${NC}"
    fi
}

# Main action dispatcher
case "$ACTION" in
    up)
        deploy_branch
        ;;
    down)
        stop_deployment
        ;;
    restart)
        restart_deployment
        ;;
    logs)
        show_logs
        ;;
    shell)
        open_shell
        ;;
    status)
        show_status
        ;;
    build)
        build_image
        ;;
    rebuild)
        FORCE_BUILD=true
        build_image
        ;;
    *)
        echo -e "${RED}Unknown action: $ACTION${NC}"
        usage
        exit 1
        ;;
esac
#!/bin/bash

# manage_multi_branch_deployment.sh
# Script to manage multi-branch deployments with isolated Docker environments
# Usage: ./manage_multi_branch_deployment.sh <client_name> <action> [branch_name]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CLIENT_DIR="$ROOT_DIR/clients"
DEPLOYMENTS_DIR="$ROOT_DIR/deployments"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 <client_name> <action> [branch_name]"
    echo
    echo "Manage multi-branch deployments with isolated Docker environments"
    echo
    echo "Arguments:"
    echo "  client_name    Name of the client"
    echo "  action         Action to perform"
    echo "  branch_name    Branch name (required for most actions)"
    echo
    echo "Actions:"
    echo "  list           List all deployments for client"
    echo "  status         Show status of all deployments"
    echo "  deploy         Deploy a specific branch"
    echo "  start          Start a deployment"
    echo "  stop           Stop a deployment"
    echo "  restart        Restart a deployment"
    echo "  remove         Remove a deployment"
    echo "  logs           Show logs for a deployment"
    echo "  shell          Open shell in deployment container"
    echo "  url            Get URL for deployment"
    echo
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -f, --force    Force action without confirmation"
    echo "  --port PORT    Custom port for deployment (default: auto-assign)"
    echo
    echo "Examples:"
    echo "  $0 myclient list"
    echo "  $0 myclient deploy master"
    echo "  $0 myclient start staging"
    echo "  $0 myclient stop dev"
    echo "  $0 myclient logs production"
    echo "  $0 myclient shell master"
}

# Parse command line arguments
CLIENT_NAME=""
ACTION=""
BRANCH_NAME=""
FORCE=false
CUSTOM_PORT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        --port)
            CUSTOM_PORT="$2"
            shift 2
            ;;
        *)
            if [[ -z "$CLIENT_NAME" ]]; then
                CLIENT_NAME="$1"
            elif [[ -z "$ACTION" ]]; then
                ACTION="$1"
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
if [[ -z "$CLIENT_NAME" || -z "$ACTION" ]]; then
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

# Create deployments directory if it doesn't exist
mkdir -p "$DEPLOYMENTS_DIR"

# Function to get next available port
get_next_port() {
    local base_port=8100
    local port=$base_port
    
    while netstat -ln | grep -q ":$port "; do
        ((port++))
        if [[ $port -gt 8200 ]]; then
            echo -e "${RED}Error: No available ports in range 8100-8200${NC}"
            exit 1
        fi
    done
    
    echo "$port"
}

# Function to get branch version
get_branch_version() {
    local client="$1"
    local branch="$2"
    local version=""
    
    if [[ -f "$CLIENT_DIR/$client/.odoo_branch_config" ]]; then
        version=$(grep "^$branch=" "$CLIENT_DIR/$client/.odoo_branch_config" | cut -d'=' -f2 2>/dev/null || echo "")
    fi
    
    if [[ -z "$version" ]]; then
        version="18.0"  # Default version
    fi
    
    echo "$version"
}

# Function to create deployment environment
create_deployment_env() {
    local client="$1"
    local branch="$2"
    local port="$3"
    local version="$4"
    
    local deployment_name="${client}-${branch}"
    local deployment_dir="$DEPLOYMENTS_DIR/$deployment_name"
    
    echo -e "${BLUE}Creating deployment environment for $client/$branch...${NC}"
    
    # Create deployment directory
    mkdir -p "$deployment_dir"/{config,data,logs}
    
    # Copy client repository files (without .git)
    echo -e "${BLUE}Copying client files...${NC}"
    rsync -av --exclude='.git' --exclude='data' --exclude='logs' "$CLIENT_DIR/$client/" "$deployment_dir/"
    
    # Checkout specific branch in deployment
    cd "$deployment_dir"
    git init
    git remote add origin "$CLIENT_DIR/$client"
    git fetch origin "$branch"
    git checkout -b "$branch" "origin/$branch"
    
    # Generate deployment-specific Docker Compose
    generate_docker_compose "$client" "$branch" "$port" "$version" "$deployment_dir"
    
    echo -e "${GREEN}Deployment environment created: $deployment_dir${NC}"
}

# Function to generate Docker Compose file
generate_docker_compose() {
    local client="$1"
    local branch="$2"
    local port="$3"
    local version="$4"
    local deployment_dir="$5"
    
    local deployment_name="${client}-${branch}"
    local postgres_port=$((port + 1000))
    
    cat > "$deployment_dir/docker-compose.yml" << EOF
# Docker Compose for deployment: $deployment_name
# Branch: $branch | Version: $version | Port: $port

version: '3.8'

services:
  odoo:
    build: 
      context: ./docker
      args:
        ODOO_VERSION: $version
    image: odoo-alusage-$deployment_name:$version
    
    container_name: odoo-$deployment_name
    restart: unless-stopped
    
    ports:
      - "$port:8069"
      - "$((port + 1)):8072"
    
    labels:
      - traefik.enable=true
      # Odoo
      - traefik.http.routers.odoo-$deployment_name.entrypoints=web
      - traefik.http.routers.odoo-$deployment_name.rule=Host(\`$branch.$client.localhost\`)
      - traefik.http.services.odoo-$deployment_name.loadbalancer.server.port=8069
      - traefik.http.routers.odoo-$deployment_name.service=odoo-$deployment_name@docker
      - traefik.http.routers.odoo-$deployment_name.middlewares=odoo-forward@docker,odoo-compress@docker
      # Odoo Websocket
      - traefik.http.routers.odoo-$deployment_name-ws.entrypoints=web
      - traefik.http.routers.odoo-$deployment_name-ws.rule=Path(\`/websocket\`) && Host(\`$branch.$client.localhost\`)
      - traefik.http.services.odoo-$deployment_name-ws.loadbalancer.server.port=8072
      - traefik.http.routers.odoo-$deployment_name-ws.service=odoo-$deployment_name-ws@docker
      - traefik.http.routers.odoo-$deployment_name-ws.middlewares=odoo-headers@docker,odoo-forward@docker,odoo-compress@docker
    
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - ./config:/mnt/config:ro
      - ./extra-addons:/mnt/extra-addons:ro
      - ./addons:/mnt/addons:ro
      - ./requirements.txt:/mnt/requirements.txt:ro
      - ./data:/data
    
    environment:
      - HOST=postgresql-$deployment_name
      - USER=odoo
      - PASSWORD=odoo
      - CLIENT_NAME=$client
      - BRANCH_NAME=$branch
      - ODOO_VERSION=$version
      - DEPLOYMENT_NAME=$deployment_name
    
    depends_on:
      - postgresql-$deployment_name
    
    networks:
      - traefik-local
    
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8069/web/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

  postgresql-$deployment_name:
    image: postgres:15
    container_name: postgresql-$deployment_name
    restart: unless-stopped
    
    ports:
      - "$postgres_port:5432"
    
    environment:
      - POSTGRES_DB=postgres
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=odoo
      - PGDATA=/var/lib/postgresql/data/pgdata
      - POSTGRES_HOST_AUTH_METHOD=trust
    
    volumes:
      - ./data/postgresql:/var/lib/postgresql/data
    
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U odoo"]
      interval: 10s
      timeout: 5s
      retries: 5
    
    networks:
      - traefik-local

networks:
  traefik-local:
    external: true
EOF

    # Create deployment info file
    cat > "$deployment_dir/.deployment_info" << EOF
CLIENT_NAME=$client
BRANCH_NAME=$branch
ODOO_VERSION=$version
PORT=$port
POSTGRES_PORT=$postgres_port
DEPLOYMENT_NAME=$deployment_name
URL=http://localhost:$port
TRAEFIK_URL=http://$branch.$client.localhost
CREATED=$(date -Iseconds)
EOF

    echo -e "${GREEN}Docker Compose generated for $deployment_name${NC}"
}

# Function to list deployments
list_deployments() {
    local client="$1"
    
    echo -e "${BLUE}Deployments for client: $client${NC}"
    echo
    
    local found=false
    for deployment_dir in "$DEPLOYMENTS_DIR"/${client}-*; do
        if [[ -d "$deployment_dir" ]]; then
            found=true
            local deployment_name=$(basename "$deployment_dir")
            local branch_name=${deployment_name#${client}-}
            
            if [[ -f "$deployment_dir/.deployment_info" ]]; then
                source "$deployment_dir/.deployment_info"
                local status="stopped"
                if docker ps --format "table {{.Names}}" | grep -q "^odoo-$deployment_name$"; then
                    status="running"
                fi
                
                echo -e "${YELLOW}Branch: $branch_name${NC}"
                echo "  Status: $status"
                echo "  Version: $ODOO_VERSION"
                echo "  Port: $PORT"
                echo "  URL: $URL"
                echo "  Traefik URL: $TRAEFIK_URL"
                echo "  Created: $CREATED"
                echo
            fi
        fi
    done
    
    if [[ "$found" == false ]]; then
        echo -e "${YELLOW}No deployments found for client $client${NC}"
    fi
}

# Function to show deployment status
show_status() {
    local client="$1"
    local branch="$2"
    local deployment_name="${client}-${branch}"
    local deployment_dir="$DEPLOYMENTS_DIR/$deployment_name"
    
    if [[ ! -d "$deployment_dir" ]]; then
        echo -e "${RED}Deployment $deployment_name not found${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Status for deployment: $deployment_name${NC}"
    
    cd "$deployment_dir"
    docker-compose ps
}

# Function to deploy branch
deploy_branch() {
    local client="$1"
    local branch="$2"
    local deployment_name="${client}-${branch}"
    local deployment_dir="$DEPLOYMENTS_DIR/$deployment_name"
    
    # Check if branch exists in client repo
    cd "$CLIENT_DIR/$client"
    if ! git show-ref --verify --quiet "refs/heads/$branch"; then
        echo -e "${RED}Branch '$branch' not found in client repository${NC}"
        return 1
    fi
    
    # Get branch version
    local version=$(get_branch_version "$client" "$branch")
    
    # Get port
    local port="$CUSTOM_PORT"
    if [[ -z "$port" ]]; then
        port=$(get_next_port)
    fi
    
    echo -e "${BLUE}Deploying $client/$branch (Odoo $version) on port $port...${NC}"
    
    # Create or update deployment
    if [[ -d "$deployment_dir" ]]; then
        echo -e "${YELLOW}Deployment already exists, updating...${NC}"
        cd "$deployment_dir"
        docker-compose down
        rm -rf "$deployment_dir"
    fi
    
    create_deployment_env "$client" "$branch" "$port" "$version"
    
    # Start deployment
    cd "$deployment_dir"
    docker-compose up -d
    
    echo -e "${GREEN}Deployment started successfully!${NC}"
    echo -e "${GREEN}URL: http://localhost:$port${NC}"
    echo -e "${GREEN}Traefik URL: http://$branch.$client.localhost${NC}"
}

# Function to start deployment
start_deployment() {
    local client="$1"
    local branch="$2"
    local deployment_name="${client}-${branch}"
    local deployment_dir="$DEPLOYMENTS_DIR/$deployment_name"
    
    if [[ ! -d "$deployment_dir" ]]; then
        echo -e "${RED}Deployment $deployment_name not found${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Starting deployment: $deployment_name${NC}"
    
    cd "$deployment_dir"
    docker-compose up -d
    
    echo -e "${GREEN}Deployment started${NC}"
}

# Function to stop deployment
stop_deployment() {
    local client="$1"
    local branch="$2"
    local deployment_name="${client}-${branch}"
    local deployment_dir="$DEPLOYMENTS_DIR/$deployment_name"
    
    if [[ ! -d "$deployment_dir" ]]; then
        echo -e "${RED}Deployment $deployment_name not found${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Stopping deployment: $deployment_name${NC}"
    
    cd "$deployment_dir"
    docker-compose down
    
    echo -e "${GREEN}Deployment stopped${NC}"
}

# Function to show logs
show_logs() {
    local client="$1"
    local branch="$2"
    local deployment_name="${client}-${branch}"
    local deployment_dir="$DEPLOYMENTS_DIR/$deployment_name"
    
    if [[ ! -d "$deployment_dir" ]]; then
        echo -e "${RED}Deployment $deployment_name not found${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Logs for deployment: $deployment_name${NC}"
    
    cd "$deployment_dir"
    docker-compose logs -f
}

# Function to open shell
open_shell() {
    local client="$1"
    local branch="$2"
    local deployment_name="${client}-${branch}"
    local deployment_dir="$DEPLOYMENTS_DIR/$deployment_name"
    
    if [[ ! -d "$deployment_dir" ]]; then
        echo -e "${RED}Deployment $deployment_name not found${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Opening shell for deployment: $deployment_name${NC}"
    
    cd "$deployment_dir"
    docker-compose exec odoo bash
}

# Function to get URL
get_url() {
    local client="$1"
    local branch="$2"
    local deployment_name="${client}-${branch}"
    local deployment_dir="$DEPLOYMENTS_DIR/$deployment_name"
    
    if [[ ! -d "$deployment_dir" ]]; then
        echo -e "${RED}Deployment $deployment_name not found${NC}"
        return 1
    fi
    
    if [[ -f "$deployment_dir/.deployment_info" ]]; then
        source "$deployment_dir/.deployment_info"
        echo -e "${GREEN}Direct URL: $URL${NC}"
        echo -e "${GREEN}Traefik URL: $TRAEFIK_URL${NC}"
    fi
}

# Function to remove deployment
remove_deployment() {
    local client="$1"
    local branch="$2"
    local deployment_name="${client}-${branch}"
    local deployment_dir="$DEPLOYMENTS_DIR/$deployment_name"
    
    if [[ ! -d "$deployment_dir" ]]; then
        echo -e "${RED}Deployment $deployment_name not found${NC}"
        return 1
    fi
    
    if [[ "$FORCE" == false ]]; then
        echo -n "Are you sure you want to remove deployment $deployment_name? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Operation cancelled"
            return 0
        fi
    fi
    
    echo -e "${BLUE}Removing deployment: $deployment_name${NC}"
    
    cd "$deployment_dir"
    docker-compose down -v
    docker rmi "odoo-alusage-$deployment_name" 2>/dev/null || true
    
    cd "$DEPLOYMENTS_DIR"
    rm -rf "$deployment_name"
    
    echo -e "${GREEN}Deployment removed${NC}"
}

# Main action dispatcher
case "$ACTION" in
    list)
        list_deployments "$CLIENT_NAME"
        ;;
    status)
        if [[ -z "$BRANCH_NAME" ]]; then
            list_deployments "$CLIENT_NAME"
        else
            show_status "$CLIENT_NAME" "$BRANCH_NAME"
        fi
        ;;
    deploy)
        if [[ -z "$BRANCH_NAME" ]]; then
            echo -e "${RED}Branch name required for deploy action${NC}"
            exit 1
        fi
        deploy_branch "$CLIENT_NAME" "$BRANCH_NAME"
        ;;
    start)
        if [[ -z "$BRANCH_NAME" ]]; then
            echo -e "${RED}Branch name required for start action${NC}"
            exit 1
        fi
        start_deployment "$CLIENT_NAME" "$BRANCH_NAME"
        ;;
    stop)
        if [[ -z "$BRANCH_NAME" ]]; then
            echo -e "${RED}Branch name required for stop action${NC}"
            exit 1
        fi
        stop_deployment "$CLIENT_NAME" "$BRANCH_NAME"
        ;;
    restart)
        if [[ -z "$BRANCH_NAME" ]]; then
            echo -e "${RED}Branch name required for restart action${NC}"
            exit 1
        fi
        stop_deployment "$CLIENT_NAME" "$BRANCH_NAME"
        start_deployment "$CLIENT_NAME" "$BRANCH_NAME"
        ;;
    logs)
        if [[ -z "$BRANCH_NAME" ]]; then
            echo -e "${RED}Branch name required for logs action${NC}"
            exit 1
        fi
        show_logs "$CLIENT_NAME" "$BRANCH_NAME"
        ;;
    shell)
        if [[ -z "$BRANCH_NAME" ]]; then
            echo -e "${RED}Branch name required for shell action${NC}"
            exit 1
        fi
        open_shell "$CLIENT_NAME" "$BRANCH_NAME"
        ;;
    url)
        if [[ -z "$BRANCH_NAME" ]]; then
            echo -e "${RED}Branch name required for url action${NC}"
            exit 1
        fi
        get_url "$CLIENT_NAME" "$BRANCH_NAME"
        ;;
    remove)
        if [[ -z "$BRANCH_NAME" ]]; then
            echo -e "${RED}Branch name required for remove action${NC}"
            exit 1
        fi
        remove_deployment "$CLIENT_NAME" "$BRANCH_NAME"
        ;;
    *)
        echo -e "${RED}Unknown action: $ACTION${NC}"
        usage
        exit 1
        ;;
esac
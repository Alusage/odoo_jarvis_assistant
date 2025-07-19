#!/bin/bash

# deploy_branch.sh
# Script to deploy a specific branch with dynamic Docker Compose + Traefik
# Usage: ./deploy_branch.sh <client_name> <branch_name> [action]

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
    echo "Deploy a specific branch with dynamic Docker Compose + Traefik"
    echo
    echo "Arguments:"
    echo "  client_name    Name of the client"
    echo "  branch_name    Branch name to deploy"
    echo "  action         Action to perform (up, down, restart, logs, shell, status)"
    echo
    echo "Actions:"
    echo "  up      Start the deployment (default)"
    echo "  down    Stop and remove the deployment"
    echo "  restart Restart the deployment"
    echo "  logs    Show logs"
    echo "  shell   Open shell in container"
    echo "  status  Show deployment status"
    echo
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -d, --detach   Run in detached mode"
    echo "  -f, --force    Force recreate containers"
    echo
    echo "Examples:"
    echo "  $0 testclient master up"
    echo "  $0 testclient dev-feature restart"
    echo "  $0 testclient staging logs"
    echo "  $0 testclient production shell"
}

# Parse command line arguments
CLIENT_NAME=""
BRANCH_NAME=""
ACTION="up"
DETACH=false
FORCE=false

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
            FORCE=true
            shift
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

# Generate dynamic docker-compose file
generate_docker_compose() {
    local client="$1"
    local branch="$2"
    local version="$3"
    local compose_file="docker-compose.${branch}.yml"
    
    # Clean branch name for container names (replace special chars)
    local clean_branch=$(echo "$branch" | sed 's/[^a-zA-Z0-9]/-/g')
    local deployment_name="${client}-${clean_branch}"
    
    echo -e "${BLUE}Generating docker-compose for $client/$branch (Odoo $version)${NC}"
    
    cat > "$compose_file" << EOF
# Dynamic Docker Compose for $client/$branch
# Generated at $(date)
# Odoo Version: $version

version: '3.8'

services:
  odoo-$deployment_name:
    build: 
      context: ./docker
      args:
        ODOO_VERSION: $version
    image: odoo-$deployment_name:$version
    
    container_name: odoo-$deployment_name
    restart: unless-stopped
    
    labels:
      - traefik.enable=true
      - traefik.docker.network=traefik-local
      
      # Main Odoo service
      - traefik.http.routers.odoo-$deployment_name.rule=Host(\`$branch.$client.localhost\`)
      - traefik.http.routers.odoo-$deployment_name.entrypoints=web
      - traefik.http.routers.odoo-$deployment_name.service=odoo-$deployment_name
      - traefik.http.services.odoo-$deployment_name.loadbalancer.server.port=8069
      
      # Websocket service
      - traefik.http.routers.odoo-$deployment_name-ws.rule=Host(\`$branch.$client.localhost\`) && PathPrefix(\`/websocket\`)
      - traefik.http.routers.odoo-$deployment_name-ws.entrypoints=web
      - traefik.http.routers.odoo-$deployment_name-ws.service=odoo-$deployment_name-ws
      - traefik.http.services.odoo-$deployment_name-ws.loadbalancer.server.port=8072
      
      # Middleware for proper headers
      - traefik.http.middlewares.odoo-$deployment_name-headers.headers.customRequestHeaders.X-Forwarded-Proto=http
      - traefik.http.middlewares.odoo-$deployment_name-headers.headers.customRequestHeaders.X-Forwarded-Port=80
      - traefik.http.routers.odoo-$deployment_name.middlewares=odoo-$deployment_name-headers
      - traefik.http.routers.odoo-$deployment_name-ws.middlewares=odoo-$deployment_name-headers
      
      # Deployment metadata
      - deployment.client=$client
      - deployment.branch=$branch
      - deployment.version=$version
      - deployment.created=$(date -Iseconds)
    
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - ./config:/mnt/config:ro
      - ./extra-addons:/mnt/extra-addons:ro
      - ./addons:/mnt/addons:ro
      - ./requirements.txt:/mnt/requirements.txt:ro
      - ./data/$clean_branch:/data
    
    environment:
      - HOST=postgres-$deployment_name
      - USER=odoo
      - PASSWORD=odoo
      - CLIENT_NAME=$client
      - BRANCH_NAME=$branch
      - ODOO_VERSION=$version
      - DEPLOYMENT_NAME=$deployment_name
    
    depends_on:
      - postgres-$deployment_name
    
    networks:
      - traefik-local
      - $deployment_name-network
    
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8069/web/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

  postgres-$deployment_name:
    image: postgres:15
    container_name: postgres-$deployment_name
    restart: unless-stopped
    
    environment:
      - POSTGRES_DB=postgres
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=odoo
      - PGDATA=/var/lib/postgresql/data/pgdata
    
    volumes:
      - ./data/$clean_branch/postgresql:/var/lib/postgresql/data
    
    networks:
      - $deployment_name-network
    
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U odoo"]
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  traefik-local:
    external: true
  $deployment_name-network:
    driver: bridge

volumes:
  $deployment_name-data:
    driver: local
EOF

    echo -e "${GREEN}Generated: $compose_file${NC}"
    echo "$compose_file"
}

# Get branch version
VERSION=$(get_branch_version "$BRANCH_NAME")

# Generate compose file
COMPOSE_FILE=$(generate_docker_compose "$CLIENT_NAME" "$BRANCH_NAME" "$VERSION")

# Create data directory for branch
CLEAN_BRANCH=$(echo "$BRANCH_NAME" | sed 's/[^a-zA-Z0-9]/-/g')
mkdir -p "data/$CLEAN_BRANCH"

# Checkout branch
echo -e "${BLUE}Checking out branch: $BRANCH_NAME${NC}"
git checkout "$BRANCH_NAME"

# Execute action
case "$ACTION" in
    up)
        echo -e "${BLUE}Starting deployment for $CLIENT_NAME/$BRANCH_NAME${NC}"
        
        if [[ "$FORCE" == true ]]; then
            docker-compose -f "$COMPOSE_FILE" up --force-recreate -d
        elif [[ "$DETACH" == true ]]; then
            docker-compose -f "$COMPOSE_FILE" up -d
        else
            docker-compose -f "$COMPOSE_FILE" up
        fi
        
        if [[ "$DETACH" == true || "$FORCE" == true ]]; then
            echo -e "${GREEN}Deployment started successfully!${NC}"
            echo -e "${GREEN}URL: http://$BRANCH_NAME.$CLIENT_NAME.localhost${NC}"
            echo -e "${YELLOW}Use '$0 $CLIENT_NAME $BRANCH_NAME logs' to see logs${NC}"
        fi
        ;;
    
    down)
        echo -e "${BLUE}Stopping deployment for $CLIENT_NAME/$BRANCH_NAME${NC}"
        docker-compose -f "$COMPOSE_FILE" down
        echo -e "${GREEN}Deployment stopped${NC}"
        ;;
    
    restart)
        echo -e "${BLUE}Restarting deployment for $CLIENT_NAME/$BRANCH_NAME${NC}"
        docker-compose -f "$COMPOSE_FILE" restart
        echo -e "${GREEN}Deployment restarted${NC}"
        ;;
    
    logs)
        echo -e "${BLUE}Showing logs for $CLIENT_NAME/$BRANCH_NAME${NC}"
        docker-compose -f "$COMPOSE_FILE" logs -f
        ;;
    
    shell)
        echo -e "${BLUE}Opening shell for $CLIENT_NAME/$BRANCH_NAME${NC}"
        DEPLOYMENT_NAME="${CLIENT_NAME}-${CLEAN_BRANCH}"
        docker exec -it "odoo-$DEPLOYMENT_NAME" bash
        ;;
    
    status)
        echo -e "${BLUE}Status for $CLIENT_NAME/$BRANCH_NAME${NC}"
        docker-compose -f "$COMPOSE_FILE" ps
        echo
        echo -e "${YELLOW}URL: http://$BRANCH_NAME.$CLIENT_NAME.localhost${NC}"
        ;;
    
    *)
        echo -e "${RED}Unknown action: $ACTION${NC}"
        usage
        exit 1
        ;;
esac
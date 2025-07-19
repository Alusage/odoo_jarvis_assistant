#!/bin/bash

# manage_deployments.sh
# Script to manage all branch deployments
# Usage: ./manage_deployments.sh <action> [client_name] [branch_name]

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
    echo "Usage: $0 <action> [client_name] [branch_name]"
    echo
    echo "Manage all branch deployments"
    echo
    echo "Actions:"
    echo "  list         List all deployments"
    echo "  status       Show status of all deployments"
    echo "  start        Start a specific deployment"
    echo "  stop         Stop a specific deployment"
    echo "  restart      Restart a specific deployment"
    echo "  stop-all     Stop all deployments"
    echo "  clean        Clean up stopped containers"
    echo "  urls         Show all deployment URLs"
    echo "  logs         Show logs for a specific deployment"
    echo
    echo "Options:"
    echo "  -h, --help   Show this help message"
    echo "  -v, --verbose Show verbose output"
    echo
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 status"
    echo "  $0 start testclient master"
    echo "  $0 stop testclient dev-feature"
    echo "  $0 urls"
    echo "  $0 stop-all"
}

# Parse command line arguments
ACTION=""
CLIENT_NAME=""
BRANCH_NAME=""
VERBOSE=false

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
        *)
            if [[ -z "$ACTION" ]]; then
                ACTION="$1"
            elif [[ -z "$CLIENT_NAME" ]]; then
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

# Validate action
if [[ -z "$ACTION" ]]; then
    echo -e "${RED}Error: Missing action${NC}"
    usage
    exit 1
fi

# Function to get deployment containers
get_deployment_containers() {
    docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.CreatedAt}}" \
        --filter "name=odoo-" \
        --filter "label=deployment.client" 2>/dev/null || echo ""
}

# Function to get deployment info from container labels
get_container_info() {
    local container_name="$1"
    local client=""
    local branch=""
    local version=""
    local created=""
    
    if docker inspect "$container_name" &>/dev/null; then
        client=$(docker inspect "$container_name" --format '{{index .Config.Labels "deployment.client"}}' 2>/dev/null || echo "")
        branch=$(docker inspect "$container_name" --format '{{index .Config.Labels "deployment.branch"}}' 2>/dev/null || echo "")
        version=$(docker inspect "$container_name" --format '{{index .Config.Labels "deployment.version"}}' 2>/dev/null || echo "")
        created=$(docker inspect "$container_name" --format '{{index .Config.Labels "deployment.created"}}' 2>/dev/null || echo "")
    fi
    
    echo "$client|$branch|$version|$created"
}

# Function to list all deployments
list_deployments() {
    echo -e "${BLUE}Active Deployments:${NC}"
    echo
    
    local found=false
    local containers=$(docker ps -a --format "{{.Names}}" --filter "name=odoo-" --filter "label=deployment.client" 2>/dev/null)
    
    if [[ -n "$containers" ]]; then
        printf "%-20s %-15s %-10s %-10s %-20s %s\n" "CLIENT" "BRANCH" "VERSION" "STATUS" "CREATED" "URL"
        printf "%-20s %-15s %-10s %-10s %-20s %s\n" "------" "------" "-------" "------" "-------" "---"
        
        for container in $containers; do
            found=true
            local info=$(get_container_info "$container")
            local client=$(echo "$info" | cut -d'|' -f1)
            local branch=$(echo "$info" | cut -d'|' -f2)
            local version=$(echo "$info" | cut -d'|' -f3)
            local created=$(echo "$info" | cut -d'|' -f4)
            
            local status=$(docker inspect "$container" --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
            local url="http://$branch.$client.localhost"
            
            # Format created date
            if [[ -n "$created" ]]; then
                created=$(date -d "$created" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$created")
            fi
            
            printf "%-20s %-15s %-10s %-10s %-20s %s\n" "$client" "$branch" "$version" "$status" "$created" "$url"
        done
    fi
    
    if [[ "$found" == false ]]; then
        echo -e "${YELLOW}No deployments found${NC}"
    fi
}

# Function to show deployment status
show_status() {
    echo -e "${BLUE}Deployment Status:${NC}"
    echo
    
    local total=0
    local running=0
    local stopped=0
    
    local containers=$(docker ps -a --format "{{.Names}}" --filter "name=odoo-" --filter "label=deployment.client" 2>/dev/null)
    
    for container in $containers; do
        ((total++))
        local status=$(docker inspect "$container" --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
        
        if [[ "$status" == "running" ]]; then
            ((running++))
        else
            ((stopped++))
        fi
    done
    
    echo "Total deployments: $total"
    echo -e "${GREEN}Running: $running${NC}"
    echo -e "${YELLOW}Stopped: $stopped${NC}"
    echo
    
    if [[ "$total" -gt 0 ]]; then
        list_deployments
    fi
}

# Function to start deployment
start_deployment() {
    local client="$1"
    local branch="$2"
    
    if [[ -z "$client" || -z "$branch" ]]; then
        echo -e "${RED}Error: Client and branch name required${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Starting deployment: $client/$branch${NC}"
    "$SCRIPT_DIR/deploy_branch.sh" "$client" "$branch" up -d
}

# Function to stop deployment
stop_deployment() {
    local client="$1"
    local branch="$2"
    
    if [[ -z "$client" || -z "$branch" ]]; then
        echo -e "${RED}Error: Client and branch name required${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Stopping deployment: $client/$branch${NC}"
    "$SCRIPT_DIR/deploy_branch.sh" "$client" "$branch" down
}

# Function to restart deployment
restart_deployment() {
    local client="$1"
    local branch="$2"
    
    if [[ -z "$client" || -z "$branch" ]]; then
        echo -e "${RED}Error: Client and branch name required${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Restarting deployment: $client/$branch${NC}"
    "$SCRIPT_DIR/deploy_branch.sh" "$client" "$branch" restart
}

# Function to stop all deployments
stop_all_deployments() {
    echo -e "${BLUE}Stopping all deployments...${NC}"
    
    local containers=$(docker ps --format "{{.Names}}" --filter "name=odoo-" --filter "label=deployment.client" 2>/dev/null)
    
    if [[ -n "$containers" ]]; then
        for container in $containers; do
            local info=$(get_container_info "$container")
            local client=$(echo "$info" | cut -d'|' -f1)
            local branch=$(echo "$info" | cut -d'|' -f2)
            
            if [[ -n "$client" && -n "$branch" ]]; then
                echo -e "${YELLOW}Stopping $client/$branch...${NC}"
                stop_deployment "$client" "$branch"
            fi
        done
        echo -e "${GREEN}All deployments stopped${NC}"
    else
        echo -e "${YELLOW}No running deployments found${NC}"
    fi
}

# Function to clean up stopped containers
clean_deployments() {
    echo -e "${BLUE}Cleaning up stopped containers...${NC}"
    
    # Remove stopped deployment containers
    local stopped_containers=$(docker ps -a --format "{{.Names}}" \
        --filter "name=odoo-" \
        --filter "label=deployment.client" \
        --filter "status=exited" 2>/dev/null)
    
    if [[ -n "$stopped_containers" ]]; then
        for container in $stopped_containers; do
            echo -e "${YELLOW}Removing $container...${NC}"
            docker rm "$container"
        done
    fi
    
    # Remove stopped postgres containers
    local stopped_postgres=$(docker ps -a --format "{{.Names}}" \
        --filter "name=postgres-" \
        --filter "status=exited" 2>/dev/null)
    
    if [[ -n "$stopped_postgres" ]]; then
        for container in $stopped_postgres; do
            echo -e "${YELLOW}Removing $container...${NC}"
            docker rm "$container"
        done
    fi
    
    # Clean up unused networks
    echo -e "${BLUE}Cleaning up unused networks...${NC}"
    docker network prune -f
    
    echo -e "${GREEN}Cleanup completed${NC}"
}

# Function to show URLs
show_urls() {
    echo -e "${BLUE}Deployment URLs:${NC}"
    echo
    
    local containers=$(docker ps --format "{{.Names}}" --filter "name=odoo-" --filter "label=deployment.client" 2>/dev/null)
    
    if [[ -n "$containers" ]]; then
        for container in $containers; do
            local info=$(get_container_info "$container")
            local client=$(echo "$info" | cut -d'|' -f1)
            local branch=$(echo "$info" | cut -d'|' -f2)
            
            if [[ -n "$client" && -n "$branch" ]]; then
                local url="http://$branch.$client.localhost"
                echo -e "${GREEN}$client/$branch${NC} → $url"
            fi
        done
    else
        echo -e "${YELLOW}No running deployments found${NC}"
    fi
}

# Function to show logs
show_logs() {
    local client="$1"
    local branch="$2"
    
    if [[ -z "$client" || -z "$branch" ]]; then
        echo -e "${RED}Error: Client and branch name required${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Showing logs for: $client/$branch${NC}"
    "$SCRIPT_DIR/deploy_branch.sh" "$client" "$branch" logs
}

# Main action dispatcher
case "$ACTION" in
    list)
        list_deployments
        ;;
    status)
        show_status
        ;;
    start)
        start_deployment "$CLIENT_NAME" "$BRANCH_NAME"
        ;;
    stop)
        stop_deployment "$CLIENT_NAME" "$BRANCH_NAME"
        ;;
    restart)
        restart_deployment "$CLIENT_NAME" "$BRANCH_NAME"
        ;;
    stop-all)
        stop_all_deployments
        ;;
    clean)
        clean_deployments
        ;;
    urls)
        show_urls
        ;;
    logs)
        show_logs "$CLIENT_NAME" "$BRANCH_NAME"
        ;;
    *)
        echo -e "${RED}Unknown action: $ACTION${NC}"
        usage
        exit 1
        ;;
esac
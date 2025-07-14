#!/bin/bash

# Script pour arrêter Traefik et la stack d'infrastructure
# Usage: ./stop-traefik.sh [--remove-network]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOVE_NETWORK=false

# Parser les arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --remove-network)
            REMOVE_NETWORK=true
            shift
            ;;
        *)
            echo "Usage: $0 [--remove-network]"
            exit 1
            ;;
    esac
done

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
echo_success() { echo -e "${GREEN}✅ $1${NC}"; }
echo_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
echo_error() { echo -e "${RED}❌ $1${NC}"; }

cd "$SCRIPT_DIR"

echo_info "Arrêt de l'infrastructure Traefik..."

# Arrêter Traefik
docker compose down

# Supprimer le réseau si demandé
if [ "$REMOVE_NETWORK" = true ]; then
    echo_warning "Suppression du réseau traefik-local..."
    echo_warning "Cela coupera tous les clients Odoo connectés !"
    
    # Vérifier s'il y a d'autres conteneurs utilisant le réseau
    CONTAINERS_USING_NETWORK=$(docker network inspect traefik-local --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || echo "")
    
    if [ -n "$CONTAINERS_USING_NETWORK" ]; then
        echo_warning "Conteneurs encore connectés au réseau: $CONTAINERS_USING_NETWORK"
        echo_warning "Arrêtez-les d'abord ou ils seront déconnectés"
        sleep 3
    fi
    
    docker network rm traefik-local 2>/dev/null || echo_info "Le réseau était déjà supprimé"
    echo_success "Réseau traefik-local supprimé"
else
    echo_info "Réseau traefik-local conservé (utilisez --remove-network pour le supprimer)"
fi

echo_success "Infrastructure Traefik arrêtée"
#!/bin/bash

# Script pour ajouter le support des repositories en mode dev aux clients existants
# Usage: update_docker_dev_support.sh [client_name]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
echo_success() { echo -e "${GREEN}✅ $1${NC}"; }
echo_error() { echo -e "${RED}❌ $1${NC}"; }
echo_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }

CLIENT_NAME="$1"

if [ -n "$CLIENT_NAME" ]; then
    # Mise à jour d'un client spécifique
    if [ ! -d "$ROOT_DIR/clients/$CLIENT_NAME" ]; then
        echo_error "Client '$CLIENT_NAME' n'existe pas"
        exit 1
    fi
    CLIENTS=("$CLIENT_NAME")
else
    # Mise à jour de tous les clients
    echo_info "Mise à jour de tous les clients existants..."
    CLIENTS=()
    if [ -d "$ROOT_DIR/clients" ]; then
        for client_dir in "$ROOT_DIR/clients"/*; do
            if [ -d "$client_dir" ] && [ -f "$client_dir/docker-compose.yml" ]; then
                CLIENTS+=($(basename "$client_dir"))
            fi
        done
    fi
fi

if [ ${#CLIENTS[@]} -eq 0 ]; then
    echo_warning "Aucun client à mettre à jour"
    exit 0
fi

echo_info "Clients à mettre à jour: ${CLIENTS[*]}"

update_docker_compose() {
    local client_name="$1"
    local client_dir="$ROOT_DIR/clients/$client_name"
    local compose_file="$client_dir/docker-compose.yml"
    
    echo_info "Mise à jour de $client_name..."
    
    # Vérifier si le fichier existe
    if [ ! -f "$compose_file" ]; then
        echo_warning "docker-compose.yml introuvable pour $client_name"
        return 1
    fi
    
    # Vérifier si le volume .dev-repos est déjà présent
    if grep -q "\.dev-repos:/mnt/\.dev-repos" "$compose_file"; then
        echo_success "$client_name déjà à jour"
        return 0
    fi
    
    # Créer une sauvegarde
    cp "$compose_file" "${compose_file}.backup"
    echo_info "Sauvegarde créée: ${compose_file}.backup"
    
    # Ajouter le volume .dev-repos après la ligne ./addons:/mnt/addons:ro
    if grep -q "      - ./addons:/mnt/addons:ro" "$compose_file"; then
        # Utiliser sed pour ajouter le volume après la ligne addons
        sed -i '/      - \.\/addons:\/mnt\/addons:ro/a\      \n      # Repositories en mode dev (nécessaire pour les liens symboliques)\n      - ./.dev-repos:/mnt/.dev-repos:ro' "$compose_file"
        echo_success "Volume .dev-repos ajouté pour $client_name"
        
        # Créer le répertoire .dev-repos s'il n'existe pas
        if [ ! -d "$client_dir/.dev-repos" ]; then
            mkdir -p "$client_dir/.dev-repos"
            echo_info "Répertoire .dev-repos créé pour $client_name"
        fi
        
        return 0
    else
        echo_error "Structure de docker-compose.yml non reconnue pour $client_name"
        # Restaurer la sauvegarde
        mv "${compose_file}.backup" "$compose_file"
        return 1
    fi
}

# Mise à jour de tous les clients
updated_count=0
failed_count=0

for client in "${CLIENTS[@]}"; do
    if update_docker_compose "$client"; then
        ((updated_count++))
    else
        ((failed_count++))
    fi
done

echo ""
echo_success "✨ Mise à jour terminée:"
echo_info "- Clients mis à jour: $updated_count"
if [ $failed_count -gt 0 ]; then
    echo_warning "- Clients en échec: $failed_count"
fi

echo ""
echo_info "📝 Actions recommandées:"
echo "1. Redémarrer les containers Docker des clients modifiés:"
for client in "${CLIENTS[@]}"; do
    echo "   cd clients/$client && docker-compose restart"
done
echo ""
echo "2. Les containers redémarrés auront accès au répertoire .dev-repos"
echo "3. Les liens symboliques en mode dev fonctionneront correctement"
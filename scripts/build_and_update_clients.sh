#!/bin/bash

# Script pour construire l'image Docker et mettre à jour les clients
# Usage: ./build_and_update_clients.sh [version_odoo]

ODOO_VERSION="${1:-18.0}"
TAG_NAME="odoo-alusage:$ODOO_VERSION"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CLIENTS_DIR="$ROOT_DIR/clients"

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo_info() { echo -e "${BLUE}-  $1${NC}"; }
echo_success() { echo -e "${GREEN}✅ $1${NC}"; }
echo_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
echo_error() { echo -e "${RED}❌ $1${NC}"; }

echo_info "🚀 Construction de l'image Docker et mise à jour des clients"
echo

# Étape 1 : Construire l'image Docker
echo_info "📋 Étape 1 : Construction de l'image Docker"
if ! "$SCRIPT_DIR/build_docker_image.sh" "$ODOO_VERSION" "$TAG_NAME"; then
    echo_error "❌ Échec de la construction de l'image Docker"
    exit 1
fi
echo

# Étape 2 : Mettre à jour les docker-compose.yml des clients existants
echo_info "📋 Étape 2 : Mise à jour des clients existants"

if [ ! -d "$CLIENTS_DIR" ] || [ -z "$(ls -A "$CLIENTS_DIR" 2>/dev/null)" ]; then
    echo_warning "Aucun client trouvé dans $CLIENTS_DIR"
    exit 0
fi

for client_dir in "$CLIENTS_DIR"/*; do
    if [ -d "$client_dir" ]; then
        client_name=$(basename "$client_dir")
        docker_compose_file="$client_dir/docker-compose.yml"
        
        if [ -f "$docker_compose_file" ]; then
            echo_info "🔄 Mise à jour du client : $client_name"
            
            # Sauvegarder l'ancien fichier
            backup_file="${docker_compose_file}.backup.$(date +%Y%m%d_%H%M%S)"
            cp "$docker_compose_file" "$backup_file"
            
            # Remplacer l'image dans le docker-compose.yml
            if sed -i "s|image: odoo:.*|image: $TAG_NAME|g; s|image: odoo-custom:.*|image: $TAG_NAME|g" "$docker_compose_file"; then
                echo_success "✅ Client $client_name mis à jour (sauvegarde: $(basename "$backup_file"))"
            else
                echo_error "❌ Erreur lors de la mise à jour du client $client_name"
            fi
        else
            echo_warning "   - $client_name : pas de docker-compose.yml"
        fi
    fi
done

echo
echo_success "🎯 Processus terminé !"
echo_info "💡 Pour démarrer un client :"
echo_info "   cd clients/<nom_client>"
echo_info "   docker compose up -d"

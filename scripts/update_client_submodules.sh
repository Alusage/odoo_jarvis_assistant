#!/bin/bash

# Script pour mettre à jour tous les submodules d'un dépôt client
# Usage: update_client_submodules.sh [client_name]

set -e

CLIENT_NAME="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CLIENTS_DIR="$ROOT_DIR/clients"

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
echo_success() { echo -e "${GREEN}✅ $1${NC}"; }
echo_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }

# Si aucun client spécifié, lister les clients disponibles
if [ -z "$CLIENT_NAME" ]; then
    echo_info "Clients disponibles :"
    if [ -d "$CLIENTS_DIR" ]; then
        ls -1 "$CLIENTS_DIR" 2>/dev/null || echo "Aucun client trouvé"
    else
        echo "Aucun client trouvé"
    fi
    echo
    read -p "Nom du client à mettre à jour: " CLIENT_NAME
fi

CLIENT_DIR="$CLIENTS_DIR/$CLIENT_NAME"

if [ ! -d "$CLIENT_DIR" ]; then
    echo_error "Client '$CLIENT_NAME' non trouvé dans $CLIENTS_DIR"
    exit 1
fi

echo_info "Mise à jour des submodules pour le client: $CLIENT_NAME"
echo_info "Répertoire: $CLIENT_DIR"

cd "$CLIENT_DIR"

# Vérifier si c'est un dépôt Git
if [ ! -d ".git" ]; then
    echo_error "Le répertoire client n'est pas un dépôt Git"
    exit 1
fi

# Mettre à jour les submodules
echo_info "Initialisation et mise à jour des submodules..."
git submodule update --init --recursive

echo_info "Mise à jour vers les dernières versions..."
git submodule foreach '
    echo "Mise à jour de $name..."
    git fetch origin
    git checkout $(git symbolic-ref refs/remotes/origin/HEAD | sed "s@^refs/remotes/origin/@@")
    git pull origin $(git symbolic-ref refs/remotes/origin/HEAD | sed "s@^refs/remotes/origin/@@")
'

echo_success "Mise à jour terminée pour le client $CLIENT_NAME"
echo_warning "N'oubliez pas de tester les modules après la mise à jour"

#!/bin/bash

# Script pour corriger les permissions d'un client
# Usage: fix_client_permissions.sh <client_name>

set -e

CLIENT_NAME="$1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CLIENTS_DIR="$ROOT_DIR/clients"
CLIENT_DIR="$CLIENTS_DIR/$CLIENT_NAME"

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

if [ -z "$CLIENT_NAME" ]; then
    echo_error "Nom du client requis"
    echo "Usage: $0 <client_name>"
    exit 1
fi

if [ ! -d "$CLIENT_DIR" ]; then
    echo_error "Client '$CLIENT_NAME' non trouvé"
    exit 1
fi

echo_info "Correction des permissions pour le client '$CLIENT_NAME'..."

# Changer le propriétaire récursivement
if [ -w "$CLIENT_DIR" ]; then
    echo_info "Permissions déjà correctes"
    exit 0
fi

# Vérifier si on peut utiliser sudo sans mot de passe
if sudo -n true 2>/dev/null; then
    echo_info "Utilisation de sudo pour corriger les permissions..."
    sudo chown -R "$(whoami):$(whoami)" "$CLIENT_DIR" 2>/dev/null || true
    sudo chmod -R u+w "$CLIENT_DIR" 2>/dev/null || true
    echo_success "Permissions corrigées avec sudo"
else
    echo_warning "Impossible de corriger automatiquement les permissions"
    echo_info "Commande manuelle nécessaire :"
    echo "  sudo chown -R $(whoami):$(whoami) '$CLIENT_DIR'"
    echo "  sudo chmod -R u+w '$CLIENT_DIR'"
fi
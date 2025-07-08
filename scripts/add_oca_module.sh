#!/bin/bash

# Script pour ajouter un nouveau dépôt OCA à un client existant
# Usage: add_oca_module.sh <client_name> <module_key> [custom_url]

set -e

CLIENT_NAME="$1"
MODULE_KEY="$2"
CUSTOM_URL="$3"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$ROOT_DIR/config"
CLIENTS_DIR="$ROOT_DIR/clients"
CLIENT_DIR="$CLIENTS_DIR/$CLIENT_NAME"

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo_info() { echo -e "${BLUE}-  $1${NC}"; }
echo_success() { echo -e "${GREEN}✅ $1${NC}"; }
echo_error() { echo -e "${RED}❌ $1${NC}"; }

# Vérifications
if [ -z "$CLIENT_NAME" ] || [ -z "$MODULE_KEY" ]; then
    echo_error "Usage: $0 <client_name> <module_key> [custom_url]"
    echo_info "Modules OCA disponibles :"
    jq -r '.oca_repositories | to_entries[] | "\(.key) - \(.value.description)"' "$CONFIG_DIR/templates.json"
    exit 1
fi

if [ ! -d "$CLIENT_DIR" ]; then
    echo_error "Client '$CLIENT_NAME' non trouvé"
    exit 1
fi

cd "$CLIENT_DIR"

# Déterminer l'URL du module
if [ -n "$CUSTOM_URL" ]; then
    MODULE_URL="$CUSTOM_URL"
    echo_info "Utilisation de l'URL personnalisée: $MODULE_URL"
else
    MODULE_URL=$(jq -r ".oca_repositories[\"$MODULE_KEY\"].url" "$CONFIG_DIR/templates.json")
    if [ "$MODULE_URL" = "null" ]; then
        echo_error "Module '$MODULE_KEY' non trouvé dans la configuration"
        exit 1
    fi
fi

# Détecter la version Odoo du client
ODOO_VERSION=$(grep "image: odoo:" docker-compose.yml | sed 's/.*odoo:\([0-9]\+\.[0-9]\+\).*/\1/' || echo "16.0")
echo_info "Version Odoo détectée: $ODOO_VERSION"

# Ajouter le submodule
SUBMODULE_PATH="addons/$MODULE_KEY"
echo_info "Ajout du submodule: $MODULE_KEY"
echo_info "URL: $MODULE_URL"
echo_info "Branche: $ODOO_VERSION"
echo_info "Chemin: $SUBMODULE_PATH"

if [ -d "$SUBMODULE_PATH" ]; then
    echo_error "Le submodule existe déjà: $SUBMODULE_PATH"
    exit 1
fi

git submodule add -b "$ODOO_VERSION" "$MODULE_URL" "$SUBMODULE_PATH"

echo_success "Submodule '$MODULE_KEY' ajouté avec succès"
echo_info "Pour activer des modules de ce dépôt, utilisez:"
echo_info "  ./scripts/link_modules.sh $SUBMODULE_PATH <nom_du_module>"

#!/bin/bash

# Script pour lister tous les modules disponibles dans les submodules d'un client
# Usage: list_available_modules.sh <client_name>

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
    echo_error "Usage: $0 <client_name>"
    exit 1
fi

if [ ! -d "$CLIENT_DIR" ]; then
    echo_error "Client '$CLIENT_NAME' non trouvé"
    exit 1
fi

cd "$CLIENT_DIR"

echo_info "Modules disponibles pour le client: $CLIENT_NAME"
echo "================================================"

# Parcourir tous les submodules
for submodule_path in addons/*/; do
    if [ -d "$submodule_path" ]; then
        submodule_name=$(basename "$submodule_path")
        echo_warning "📦 Submodule: $submodule_name"
        
        # Lister les modules dans ce submodule
        for module_path in "$submodule_path"*/; do
            if [ -d "$module_path" ] && [ -f "$module_path/__manifest__.py" ]; then
                module_name=$(basename "$module_path")
                
                # Vérifier si le module est déjà lié
                if [ -L "extra-addons/$module_name" ]; then
                    echo_success "  ✓ $module_name (activé)"
                else
                    echo "    $module_name"
                fi
            fi
        done
        echo
    fi
done

echo_info "Légende:"
echo "  ✓ Module activé (lien symbolique dans extra-addons/)"
echo "    Module disponible mais non activé"
echo
echo_info "Pour activer un module:"
echo "  ./scripts/link_modules.sh addons/<submodule>/<module> <module>"

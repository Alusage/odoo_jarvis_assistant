#!/bin/bash

# Script pour ajouter un nouveau dépôt OCA à un client existant
# Usage: add_oca_module.sh <client_name> <module_key> [custom_url] [--all | --link module1,module2,...]

set -e

# Variables par défaut
CLIENT_NAME=""
MODULE_KEY=""
CUSTOM_URL=""
LINK_ALL=false
LINK_MODULES=""

# Parser les arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            LINK_ALL=true
            shift
            ;;
        --link)
            LINK_MODULES="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 <client_name> <module_key> [custom_url] [--all | --link module1,module2,...]"
            echo ""
            echo "Options:"
            echo "  --all                    Linker tous les modules du dépôt dans extra-addons"
            echo "  --link module1,module2   Linker les modules spécifiés dans extra-addons"
            echo ""
            echo "Exemple: $0 mon_client account-analytic --link account_analytic_parent"
            exit 0
            ;;
        *)
            if [[ -z "$CLIENT_NAME" ]]; then
                CLIENT_NAME="$1"
            elif [[ -z "$MODULE_KEY" ]]; then
                MODULE_KEY="$1"
            elif [[ -z "$CUSTOM_URL" ]]; then
                CUSTOM_URL="$1"
            fi
            shift
            ;;
    esac
done

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
    echo_error "Usage: $0 <client_name> <module_key> [custom_url] [--all | --link module1,module2,...]"
    echo_info "Modules OCA disponibles :"
    jq -r '.oca_repositories | to_entries[] | "\(.key) - \(.value.description)"' "$CONFIG_DIR/repositories.json"
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
    MODULE_URL=$(jq -r ".oca_repositories[\"$MODULE_KEY\"].url" "$CONFIG_DIR/repositories.json")
    if [ "$MODULE_URL" = "null" ]; then
        echo_error "Module '$MODULE_KEY' non trouvé dans la configuration"
        exit 1
    fi
fi

# Détecter la version Odoo du client
ODOO_VERSION=$(grep -v "^#" docker-compose.yml | grep "image:.*odoo" | head -1 | sed 's/.*:\([0-9]\+\.[0-9]\+\).*/\1/' 2>/dev/null || echo "18.0")
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

# Fonction pour lister les modules disponibles dans un dépôt
list_available_modules() {
    local submodule_path="$1"
    local modules=()
    
    if [ -d "$submodule_path" ]; then
        for dir in "$submodule_path"/*; do
            if [ -d "$dir" ] && [ -f "$dir/__manifest__.py" ]; then
                modules+=($(basename "$dir"))
            fi
        done
    fi
    
    printf '%s\n' "${modules[@]}"
}

# Fonction pour linker les modules
link_modules() {
    local submodule_path="$1"
    local modules_to_link=("${@:2}")
    
    if [ ! -d "extra-addons" ]; then
        mkdir -p extra-addons
        echo_info "Création du répertoire extra-addons"
    fi
    
    for module in "${modules_to_link[@]}"; do
        if [ -d "$submodule_path/$module" ] && [ -f "$submodule_path/$module/__manifest__.py" ]; then
            ln -sf "../$submodule_path/$module" "extra-addons/$module"
            echo_success "Module '$module' lié dans extra-addons"
        else
            echo_error "Module '$module' non trouvé dans $submodule_path"
        fi
    done
}

# Initialiser et mettre à jour le submodule
git submodule update --init "$SUBMODULE_PATH"

# Gérer le linking des modules si demandé
if [ "$LINK_ALL" = true ]; then
    echo_info "Linking de tous les modules disponibles..."
    available_modules=($(list_available_modules "$SUBMODULE_PATH"))
    if [ ${#available_modules[@]} -gt 0 ]; then
        link_modules "$SUBMODULE_PATH" "${available_modules[@]}"
        echo_success "Tous les modules (${#available_modules[@]}) ont été liés dans extra-addons"
    else
        echo_error "Aucun module trouvé dans $SUBMODULE_PATH"
    fi
elif [ -n "$LINK_MODULES" ]; then
    echo_info "Linking des modules spécifiés..."
    IFS=',' read -ra modules_array <<< "$LINK_MODULES"
    link_modules "$SUBMODULE_PATH" "${modules_array[@]}"
else
    echo_info "Pour activer des modules de ce dépôt, utilisez:"
    echo_info "  ./scripts/link_modules.sh $SUBMODULE_PATH <nom_du_module>"
    echo_info "Ou relancez ce script avec --all ou --link module1,module2"
fi

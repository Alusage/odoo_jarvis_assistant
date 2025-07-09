#!/bin/bash

# Script pour ajouter un dépôt de module Odoo externe (non-OCA) à un client
# Usage: add_external_module.sh <client_name> <repo_key_or_url> [branch] [--all | --link module1,module2,...]

set -e

# Variables par défaut
CLIENT_NAME=""
REPO_KEY_OR_URL=""
BRANCH=""
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
            echo "Usage: $0 <client_name> <repo_key_or_url> [branch] [--all | --link module1,module2,...]"
            echo ""
            echo "Options:"
            echo "  --all                    Linker tous les modules du dépôt dans extra-addons"
            echo "  --link module1,module2   Linker les modules spécifiés dans extra-addons"
            echo ""
            echo "Exemple: $0 mon_client odoo-alusage-addons 18.0 --link module_custom"
            exit 0
            ;;
        *)
            if [[ -z "$CLIENT_NAME" ]]; then
                CLIENT_NAME="$1"
            elif [[ -z "$REPO_KEY_OR_URL" ]]; then
                REPO_KEY_OR_URL="$1"
            elif [[ -z "$BRANCH" ]]; then
                BRANCH="$1"
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
if [ -z "$CLIENT_NAME" ] || [ -z "$REPO_KEY_OR_URL" ]; then
    echo_error "Usage: $0 <client_name> <repo_key_or_url> [branch] [--all | --link module1,module2,...]"
    echo_info "Dépôts externes disponibles :"
    jq -r '.external_repositories | to_entries[] | "\(.key) - \(.value.description)"' "$CONFIG_DIR/repositories.json"
    exit 1
fi

if [ ! -d "$CLIENT_DIR" ]; then
    echo_error "Client '$CLIENT_NAME' non trouvé"
    exit 1
fi

cd "$CLIENT_DIR"

# Déterminer l'URL du dépôt
if [[ "$REPO_KEY_OR_URL" =~ ^(https?://|git@) ]]; then
    # C'est une URL directe
    REPO_URL="$REPO_KEY_OR_URL"
    REPO_NAME=$(basename "$REPO_URL" .git)
    echo_info "Utilisation de l'URL directe: $REPO_URL"
else
    # C'est une clé dans repositories.json
    REPO_URL=$(jq -r ".external_repositories[\"$REPO_KEY_OR_URL\"].url" "$CONFIG_DIR/repositories.json")
    if [ "$REPO_URL" = "null" ]; then
        echo_error "Dépôt externe '$REPO_KEY_OR_URL' non trouvé dans la configuration"
        echo_info "Dépôts externes disponibles :"
        jq -r '.external_repositories | to_entries[] | "\(.key) - \(.value.description)"' "$CONFIG_DIR/repositories.json"
        exit 1
    fi
    REPO_NAME="$REPO_KEY_OR_URL"
fi

# Détecter la version Odoo du client
ODOO_VERSION=$(grep "image:.*odoo" docker-compose.yml | sed 's/.*:\([0-9]\+\.[0-9]\+\).*/\1/' 2>/dev/null || echo "18.0")
echo_info "Version Odoo détectée: $ODOO_VERSION"

# Si aucune branche n'est spécifiée, proposer la version Odoo détectée
if [ -z "$BRANCH" ]; then
    BRANCH="$ODOO_VERSION"
    echo_info "Utilisation de la branche par défaut: $BRANCH"
fi

SUBMODULE_PATH="addons/$REPO_NAME"

echo_info "Ajout du dépôt externe: $REPO_NAME"
echo_info "URL: $REPO_URL"
echo_info "Branche: $BRANCH"
echo_info "Chemin: $SUBMODULE_PATH"

# Nettoyer les références existantes si nécessaire
if [ -d "$SUBMODULE_PATH" ] || git ls-files --error-unmatch "$SUBMODULE_PATH" >/dev/null 2>&1; then
    echo_info "Nettoyage des références existantes pour $REPO_NAME..."
    git rm --cached "$SUBMODULE_PATH" 2>/dev/null || true
    rm -rf "$SUBMODULE_PATH"
    rm -rf ".git/modules/$SUBMODULE_PATH" 2>/dev/null || true
fi

# Tenter d'ajouter le submodule avec la branche spécifiée
if [ -n "$BRANCH" ]; then
    echo_info "Vérification de l'existence de la branche '$BRANCH'..."
    if git ls-remote --heads "$REPO_URL" "$BRANCH" | grep -q "$BRANCH"; then
        echo_info "Branche '$BRANCH' trouvée, ajout en cours..."
        git submodule add -b "$BRANCH" "$REPO_URL" "$SUBMODULE_PATH"
    else
        echo_error "La branche '$BRANCH' n'existe pas dans le dépôt '$REPO_URL'"
        echo_info "Branches disponibles :"
        git ls-remote --heads "$REPO_URL" | sed 's/.*refs\/heads\//  - /'
        # Nettoyer les éventuels répertoires créés
        rm -rf "$SUBMODULE_PATH" 2>/dev/null || true
        rm -rf ".git/modules/$SUBMODULE_PATH" 2>/dev/null || true
        exit 1
    fi
else
    git submodule add "$REPO_URL" "$SUBMODULE_PATH"
fi
git submodule update --init "$SUBMODULE_PATH"

echo_success "Dépôt externe '$REPO_NAME' ajouté avec succès"

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
            ln -sf "../../$submodule_path/$module" "extra-addons/$module"
            echo_success "Module '$module' lié dans extra-addons"
        else
            echo_error "Module '$module' non trouvé dans $submodule_path"
        fi
    done
}

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

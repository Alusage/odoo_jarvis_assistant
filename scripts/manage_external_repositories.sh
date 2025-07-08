#!/bin/bash

# Script pour gérer les dépôts externes dans templates.json
# Usage: manage_external_repositories.sh <action> [args...]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$ROOT_DIR/config"
TEMPLATES_FILE="$CONFIG_DIR/templates.json"

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo_info() { echo -e "${BLUE}-  $1${NC}"; }
echo_success() { echo -e "${GREEN}✅ $1${NC}"; }
echo_error() { echo -e "${RED}❌ $1${NC}"; }

show_help() {
    echo "Usage: $0 <action> [args...]"
    echo ""
    echo "Actions disponibles:"
    echo "  list                           - Lister tous les dépôts externes"
    echo "  add <name> <url> [description] - Ajouter un dépôt externe"
    echo "  remove <name>                  - Supprimer un dépôt externe"
    echo "  update <name> <url>           - Mettre à jour l'URL d'un dépôt externe"
}

list_external_repos() {
    echo_info "Dépôts externes configurés :"
    jq -r '.external_repositories | to_entries[] | "\(.key) - \(.value.description) (\(.value.url))"' "$TEMPLATES_FILE"
}

add_external_repo() {
    local name="$1"
    local url="$2"
    local description="${3:-Dépôt externe}"
    
    if [ -z "$name" ] || [ -z "$url" ]; then
        echo_error "Usage: $0 add <name> <url> [description]"
        exit 1
    fi
    
    # Vérifier si le dépôt existe déjà
    if jq -e ".external_repositories[\"$name\"]" "$TEMPLATES_FILE" > /dev/null; then
        echo_error "Le dépôt '$name' existe déjà"
        exit 1
    fi
    
    # Ajouter le dépôt
    jq --arg name "$name" --arg url "$url" --arg desc "$description" \
       '.external_repositories[$name] = {"url": $url, "description": $desc, "type": "custom"}' \
       "$TEMPLATES_FILE" > "$TEMPLATES_FILE.tmp" && mv "$TEMPLATES_FILE.tmp" "$TEMPLATES_FILE"
    
    echo_success "Dépôt externe '$name' ajouté avec succès"
}

remove_external_repo() {
    local name="$1"
    
    if [ -z "$name" ]; then
        echo_error "Usage: $0 remove <name>"
        exit 1
    fi
    
    # Vérifier si le dépôt existe
    if ! jq -e ".external_repositories[\"$name\"]" "$TEMPLATES_FILE" > /dev/null; then
        echo_error "Le dépôt '$name' n'existe pas"
        exit 1
    fi
    
    # Supprimer le dépôt
    jq --arg name "$name" 'del(.external_repositories[$name])' \
       "$TEMPLATES_FILE" > "$TEMPLATES_FILE.tmp" && mv "$TEMPLATES_FILE.tmp" "$TEMPLATES_FILE"
    
    echo_success "Dépôt externe '$name' supprimé avec succès"
}

update_external_repo() {
    local name="$1"
    local url="$2"
    
    if [ -z "$name" ] || [ -z "$url" ]; then
        echo_error "Usage: $0 update <name> <url>"
        exit 1
    fi
    
    # Vérifier si le dépôt existe
    if ! jq -e ".external_repositories[\"$name\"]" "$TEMPLATES_FILE" > /dev/null; then
        echo_error "Le dépôt '$name' n'existe pas"
        exit 1
    fi
    
    # Mettre à jour l'URL
    jq --arg name "$name" --arg url "$url" \
       '.external_repositories[$name].url = $url' \
       "$TEMPLATES_FILE" > "$TEMPLATES_FILE.tmp" && mv "$TEMPLATES_FILE.tmp" "$TEMPLATES_FILE"
    
    echo_success "URL du dépôt externe '$name' mise à jour avec succès"
}

ACTION="$1"

case "$ACTION" in
    list)
        list_external_repos
        ;;
    add)
        shift
        add_external_repo "$@"
        ;;
    remove)
        shift
        remove_external_repo "$@"
        ;;
    update)
        shift
        update_external_repo "$@"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo_error "Action inconnue: $ACTION"
        show_help
        exit 1
        ;;
esac

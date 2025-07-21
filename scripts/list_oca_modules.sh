#!/bin/bash

# Script pour lister tous les modules OCA disponibles
# Usage: list_oca_modules.sh [--json] [--pattern PATTERN]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$ROOT_DIR/config"
REPOSITORIES_FILE="$CONFIG_DIR/repositories.json"

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${BLUE}-  $1${NC}"; }
echo_success() { echo -e "${GREEN}✅ $1${NC}"; }

# Parse arguments
JSON_OUTPUT=false
SEARCH_PATTERN=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --pattern)
            SEARCH_PATTERN="$2"
            shift 2
            ;;
        *)
            # For backward compatibility, treat first argument as pattern if no --pattern used
            if [[ -z "$SEARCH_PATTERN" && "$JSON_OUTPUT" == false ]]; then
                SEARCH_PATTERN="$1"
            fi
            shift
            ;;
    esac
done

# Mode JSON pour API/Dashboard
if [[ "$JSON_OUTPUT" == true ]]; then
    if [ -n "$SEARCH_PATTERN" ]; then
        # Filtrer par pattern et retourner JSON
        jq -c --arg pattern "$SEARCH_PATTERN" '
        {
            "success": true,
            "modules": [
                .oca_repositories | to_entries[] | 
                select(.key | test($pattern; "i")) | 
                {
                    "key": .key,
                    "description": .value.description
                }
            ]
        } | . + {"total": (.modules | length)}' "$REPOSITORIES_FILE"
    else
        # Tous les modules en JSON
        jq -c '
        {
            "success": true,
            "modules": [
                .oca_repositories | to_entries[] | 
                {
                    "key": .key,
                    "description": .value.description
                }
            ]
        } | . + {"total": (.modules | length)}' "$REPOSITORIES_FILE"
    fi
else
    # Mode affichage coloré traditionnel
    echo_info "📋 Modules OCA disponibles:"
    echo_info "=========================="

    if [ -n "$SEARCH_PATTERN" ]; then
        echo_info "🔍 Filtrage avec le pattern: '$SEARCH_PATTERN'"
        echo
    fi

    # Compter le total
    TOTAL_COUNT=$(jq '.oca_repositories | length' "$REPOSITORIES_FILE")

    # Lister les modules avec descriptions
    if [ -n "$SEARCH_PATTERN" ]; then
        # Filtrer par pattern
        jq -r ".oca_repositories | to_entries[] | select(.key | test(\"$SEARCH_PATTERN\"; \"i\")) | \"  📦 \\(.key)\\n     \\(.value.description)\\n\"" "$REPOSITORIES_FILE"
        
        # Compter les résultats filtrés
        FILTERED_COUNT=$(jq -r ".oca_repositories | to_entries[] | select(.key | test(\"$SEARCH_PATTERN\"; \"i\")) | .key" "$REPOSITORIES_FILE" | wc -l)
        echo_info "Trouvé $FILTERED_COUNT modules correspondant à '$SEARCH_PATTERN' sur $TOTAL_COUNT total"
    else
        # Lister tous les modules
        jq -r '.oca_repositories | to_entries[] | "  📦 \(.key)\n     \(.value.description)\n"' "$REPOSITORIES_FILE"
        echo_info "Total: $TOTAL_COUNT modules OCA disponibles"
    fi

    echo
    echo_info "💡 Conseils d'utilisation:"
    echo "   • Pour filtrer: $0 <pattern>"
    echo "     Exemple: $0 account"
    echo "   • Pour ajouter un module: scripts/add_oca_module.sh <client> <module>"
    echo "   • Pour mettre à jour la liste: make update-oca-repos"
fi

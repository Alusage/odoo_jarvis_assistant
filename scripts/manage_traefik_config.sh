#!/bin/bash

# Script de gestion de la configuration Traefik
# Usage: ./manage_traefik_config.sh [get|set] [options]

set -e

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
echo_success() { echo -e "${GREEN}✅ $1${NC}"; }
echo_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
echo_error() { echo -e "${RED}❌ $1${NC}"; }

# Détection automatique du répertoire de base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$BASE_DIR/config/traefik_config.json"

# Aide
show_help() {
    echo "Usage: $0 [COMMAND] [options]"
    echo ""
    echo "Commands:"
    echo "  get                  Afficher la configuration actuelle"
    echo "  set DOMAIN [PROTOCOL] Définir le domaine (et optionnellement le protocole)"
    echo "  examples             Afficher les exemples de configuration"
    echo ""
    echo "Exemples:"
    echo "  $0 get"
    echo "  $0 set local"
    echo "  $0 set dev http"
    echo "  $0 examples"
}

# Créer le fichier de config par défaut s'il n'existe pas
create_default_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo_info "Création du fichier de configuration par défaut..."
        mkdir -p "$(dirname "$CONFIG_FILE")"
        cat > "$CONFIG_FILE" << 'EOF'
{
  "domain": "local",
  "protocol": "http",
  "description": "Configuration du domaine Traefik pour les URLs des branches",
  "examples": {
    "local": "http://18.0.testclient.local (nécessite *.local dans /etc/hosts)",
    "localhost": "http://18.0.testclient.localhost (peut fonctionner directement)",
    "dev": "http://18.0.testclient.dev (nécessite *.dev dans /etc/hosts)"
  },
  "hosts_file_example": "127.0.0.1 *.local",
  "url_pattern": "{protocol}://{branch}.{client}.{domain}"
}
EOF
        echo_success "Fichier de configuration créé: $CONFIG_FILE"
    fi
}

# Afficher la configuration
get_config() {
    create_default_config
    
    DOMAIN=$(jq -r '.domain' "$CONFIG_FILE")
    PROTOCOL=$(jq -r '.protocol' "$CONFIG_FILE")
    
    echo_info "📋 Configuration Traefik actuelle:"
    echo "   - Domaine: $DOMAIN"
    echo "   - Protocole: $PROTOCOL"
    echo "   - Pattern URL: $PROTOCOL://{branch}.{client}.$DOMAIN"
    echo ""
    echo_info "📝 Fichier hosts suggéré:"
    echo "   127.0.0.1 *.$DOMAIN"
    echo ""
    echo_info "🌐 Exemple d'URL:"
    echo "   $PROTOCOL://18.0.testclient.$DOMAIN"
}

# Définir la configuration
set_config() {
    local new_domain="$1"
    local new_protocol="${2:-http}"
    
    if [[ -z "$new_domain" ]]; then
        echo_error "Domaine requis"
        show_help
        exit 1
    fi
    
    create_default_config
    
    # Mettre à jour la configuration
    jq --arg domain "$new_domain" --arg protocol "$new_protocol" \
       '.domain = $domain | .protocol = $protocol' \
       "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    
    echo_success "Configuration mise à jour:"
    echo "   - Domaine: $new_domain"
    echo "   - Protocole: $new_protocol"
    echo ""
    echo_warning "N'oubliez pas de mettre à jour votre fichier /etc/hosts:"
    echo "   127.0.0.1 *.$new_domain"
    echo ""
    echo_info "💡 Les services existants devront être redémarrés pour utiliser la nouvelle configuration"
}

# Afficher les exemples
show_examples() {
    create_default_config
    
    echo_info "📚 Exemples de configuration:"
    echo ""
    
    jq -r '.examples | to_entries[] | "  \(.key): \(.value)"' "$CONFIG_FILE"
    
    echo ""
    echo_info "💡 Pour changer la configuration:"
    echo "   $0 set DOMAINE [PROTOCOLE]"
}

# Parsing des arguments
case "${1:-}" in
    get)
        get_config
        ;;
    set)
        set_config "$2" "$3"
        ;;
    examples)
        show_examples
        ;;
    --help|-h|"")
        show_help
        ;;
    *)
        echo_error "Commande inconnue: $1"
        show_help
        exit 1
        ;;
esac
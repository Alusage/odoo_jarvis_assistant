#!/bin/bash

# Script pour démarrer les services avec le domaine Traefik configuré
# Usage: ./scripts/start_with_traefik_domain.sh [service_name]

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

# Répertoire de base du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$BASE_DIR/config/traefik_config.json"

# Lire la configuration Traefik
if [[ -f "$CONFIG_FILE" ]]; then
    TRAEFIK_DOMAIN=$(jq -r '.domain // "localhost"' "$CONFIG_FILE")
    echo_info "Configuration Traefik trouvée: domain=$TRAEFIK_DOMAIN"
else
    TRAEFIK_DOMAIN="localhost"
    echo_warning "Aucune configuration Traefik trouvée, utilisation de 'localhost'"
fi

# Exporter la variable d'environnement
export TRAEFIK_DOMAIN

echo_info "🚀 Démarrage des services avec domaine: $TRAEFIK_DOMAIN"

# Variables d'environnement pour le docker-compose
export TRAEFIK_DOMAIN

# Changer vers le répertoire de base
cd "$BASE_DIR"

# Démarrer le(s) service(s)
if [[ $# -eq 0 ]]; then
    echo_info "Démarrage de tous les services..."
    docker compose up -d
else
    SERVICE_NAME="$1"
    echo_info "Démarrage du service: $SERVICE_NAME"
    docker compose up -d "$SERVICE_NAME"
fi

echo_success "✅ Services démarrés avec succès !"

# Afficher les URLs disponibles
echo_info "🌐 URLs disponibles :"
echo "   - Dashboard: http://dashboard.$TRAEFIK_DOMAIN"
echo "   - MCP Server: http://mcp.$TRAEFIK_DOMAIN"
echo "   - Traefik Dashboard: http://traefik.$TRAEFIK_DOMAIN"

if [[ "$TRAEFIK_DOMAIN" != "localhost" ]]; then
    echo_warning "⚠️  N'oubliez pas d'ajouter à votre fichier /etc/hosts :"
    echo "   127.0.0.1 dashboard.$TRAEFIK_DOMAIN mcp.$TRAEFIK_DOMAIN traefik.$TRAEFIK_DOMAIN"
fi
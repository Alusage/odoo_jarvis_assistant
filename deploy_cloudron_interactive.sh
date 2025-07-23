#!/bin/bash

# Script wrapper pour déploiement Cloudron en mode interactif
# Usage: ./deploy_cloudron_interactive.sh <client_name>

set -e

# Configuration
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
echo_success() { echo -e "${GREEN}✅ $1${NC}"; }
echo_error() { echo -e "${RED}❌ $1${NC}"; }
echo_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }

# Vérifier les paramètres
if [ -z "$1" ]; then
    echo_error "Usage: $0 <client_name>"
    echo_info "Exemple: $0 njtest"
    exit 1
fi

CLIENT_NAME="$1"
CLIENT_CLOUDRON_DIR="$ROOT_DIR/clients/$CLIENT_NAME/cloudron"

# Vérifier que le client existe
if [ ! -d "$ROOT_DIR/clients/$CLIENT_NAME" ]; then
    echo_error "Client '$CLIENT_NAME' non trouvé dans clients/"
    echo_info "Clients disponibles:"
    ls "$ROOT_DIR/clients/" 2>/dev/null | head -10
    exit 1
fi

# Vérifier que Cloudron est configuré pour ce client
if [ ! -d "$CLIENT_CLOUDRON_DIR" ]; then
    echo_error "Configuration Cloudron non trouvée pour le client '$CLIENT_NAME'"
    echo_info "Le client doit avoir le support Cloudron activé"
    echo_info "Utilisez: ./scripts/enable_cloudron.sh $CLIENT_NAME"
    exit 1
fi

# Vérifier que les fichiers Cloudron sont présents
if [ ! -f "$CLIENT_CLOUDRON_DIR/deploy.sh" ]; then
    echo_error "Script deploy.sh manquant pour le client '$CLIENT_NAME'"
    exit 1
fi

echo_info "🚀 Déploiement Cloudron pour le client: $CLIENT_NAME"
echo_info "📁 Répertoire: $CLIENT_CLOUDRON_DIR"
echo ""

# Vérifier que nous sommes dans un terminal interactif
if [ ! -t 0 ] || [ ! -t 1 ] || [ -z "$TERM" ]; then
    echo_warning "Ce script doit être exécuté dans un terminal interactif"
    echo_info "Assurez-vous d'avoir un terminal avec TTY activé"
    exit 1
fi

echo_success "Mode interactif confirmé"
echo ""

# Se déplacer dans le répertoire Cloudron et exécuter le déploiement
cd "$CLIENT_CLOUDRON_DIR"
echo_info "🔄 Exécution du déploiement depuis: $(pwd)"
echo ""

# Exécuter le script de déploiement
exec ./deploy.sh
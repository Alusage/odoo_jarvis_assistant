#!/bin/bash

# Script pour construire l'image Docker Odoo personnalisée
# Usage: ./build_docker_image.sh [version_odoo] [tag_name]

ODOO_VERSION="${1:-18.0}"
TAG_NAME="${2:-odoo-alusage:$ODOO_VERSION}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="$ROOT_DIR/docker"

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

echo_info "🐳 Construction de l'image Docker Odoo personnalisée"
echo_info "   Version Odoo : $ODOO_VERSION"
echo_info "   Tag de l'image : $TAG_NAME"
echo_info "   Dossier Docker : $DOCKER_DIR"
echo

# Vérifier que le dossier docker existe
if [ ! -d "$DOCKER_DIR" ]; then
    echo_error "Dossier docker non trouvé : $DOCKER_DIR"
    exit 1
fi

# Vérifier que Docker est disponible
if ! command -v docker &> /dev/null; then
    echo_error "Docker n'est pas installé ou non disponible"
    exit 1
fi

# Aller dans le dossier docker
cd "$DOCKER_DIR"

# Construire l'image
echo_info "🔨 Construction de l'image..."
if docker build --build-arg ODOO_VERSION="$ODOO_VERSION" -t "$TAG_NAME" .; then
    echo_success "✅ Image construite avec succès : $TAG_NAME"
    echo
    echo_info "📋 Pour utiliser cette image dans un dépôt client :"
    echo_info "   1. Modifiez le docker-compose.yml du client pour utiliser '$TAG_NAME'"
    echo_info "   2. Lancez avec 'docker-compose up -d'"
    echo
    echo_info "🔍 Informations sur l'image :"
    docker images "$TAG_NAME"
else
    echo_error "❌ Erreur lors de la construction de l'image"
    exit 1
fi

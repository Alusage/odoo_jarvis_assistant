#!/bin/bash

# Script de build pour Cloudron Odoo
# Client: {{CLIENT_NAME}}

set -e

# Configuration
CLIENT_NAME="{{CLIENT_NAME}}"
ODOO_VERSION="{{ODOO_VERSION}}"
DOCKER_REGISTRY="{{DOCKER_REGISTRY}}"
DOCKER_USERNAME="{{DOCKER_USERNAME}}"
DOCKER_PASSWORD="{{DOCKER_PASSWORD}}"
APP_VERSION="{{APP_VERSION}}"

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

echo_info "🐳 Construction de l'image Docker Cloudron pour $CLIENT_NAME"

# Vérifier qu'on est dans le bon répertoire
if [ ! -f "Dockerfile" ] || [ ! -f "CloudronManifest.json" ]; then
    echo_error "Fichiers Cloudron manquants. Assurez-vous d'être dans le répertoire cloudron/"
    exit 1
fi

# Vérifier qu'on est sur une branche de production
cd ../
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
PRODUCTION_BRANCHES=("18.0" "master" "main")

if [[ ! " ${PRODUCTION_BRANCHES[@]} " =~ " ${CURRENT_BRANCH} " ]]; then
    echo_error "Publication Cloudron uniquement autorisée sur les branches de production"
    echo_warning "Branche actuelle: $CURRENT_BRANCH"
    echo_warning "Branches autorisées: ${PRODUCTION_BRANCHES[*]}"
    exit 1
fi

cd cloudron/

# Copier les fichiers nécessaires
echo_info "📋 Copie des fichiers client..."

# Copier depuis le répertoire parent
cp -r ../extra-addons ./extra-addons
cp -r ../addons ./addons  
cp -r ../config ./config
cp ../requirements.txt ./requirements.txt

echo_success "Fichiers copiés"

# Construire l'image Docker
DOCKER_IMAGE="$DOCKER_REGISTRY/$CLIENT_NAME-odoo"
DOCKER_TAG="$DOCKER_IMAGE:$APP_VERSION"

echo_info "🔨 Construction de l'image: $DOCKER_TAG"

docker build \
    --build-arg CLIENT_NAME="$CLIENT_NAME" \
    --build-arg ODOO_VERSION="$ODOO_VERSION" \
    -t "$DOCKER_TAG" \
    -t "$DOCKER_IMAGE:latest" \
    .

echo_success "✨ Image construite avec succès: $DOCKER_TAG"

# Nettoyer les fichiers temporaires
echo_info "🧹 Nettoyage des fichiers temporaires..."
rm -rf extra-addons addons config requirements.txt

# Push vers le registry (automatique si non-interactif, ou si --push est spécifié)
SHOULD_PUSH=false
if [[ "$1" == "--push" ]] || [[ ! -t 0 ]]; then
    SHOULD_PUSH=true
    echo_info "📤 Push automatique vers le registry..."
else
    read -p "Voulez-vous pousser l'image vers le registry Docker ? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        SHOULD_PUSH=true
    fi
fi

if [[ "$SHOULD_PUSH" == "true" ]]; then
    echo_info "📤 Push vers le registry..."
    
    # Connexion au registry Docker si les identifiants sont fournis
    if [[ -n "$DOCKER_USERNAME" && -n "$DOCKER_PASSWORD" ]]; then
        echo_info "🔐 Connexion au registry Docker..."
        echo "$DOCKER_PASSWORD" | docker login "$DOCKER_REGISTRY" -u "$DOCKER_USERNAME" --password-stdin
        echo_success "Connecté au registry Docker"
    fi
    
    docker push "$DOCKER_TAG"
    docker push "$DOCKER_IMAGE:latest"
    echo_success "✨ Image poussée vers $DOCKER_REGISTRY"
    
    # Déconnexion du registry Docker
    if [[ -n "$DOCKER_USERNAME" && -n "$DOCKER_PASSWORD" ]]; then
        docker logout "$DOCKER_REGISTRY"
    fi
fi

echo ""
echo_success "🎉 Build Cloudron terminé !"
echo_info "Image: $DOCKER_TAG"
echo_info "Pour déployer: ./deploy.sh"
#!/bin/bash

# Script de déploiement Cloudron pour Odoo
# Client: {{CLIENT_NAME}}

set -e

# Configuration
CLIENT_NAME="{{CLIENT_NAME}}"
APP_ID="{{APP_ID}}"
CLOUDRON_SERVER="{{CLOUDRON_SERVER}}"
CLOUDRON_USERNAME="{{CLOUDRON_USERNAME}}"
CLOUDRON_PASSWORD="{{CLOUDRON_PASSWORD}}"
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

echo_info "🚀 Déploiement Cloudron pour $CLIENT_NAME"

# Vérifier les prérequis
if ! command -v cloudron &> /dev/null; then
    echo_error "Cloudron CLI non installé. Installez-le avec: npm install -g cloudron"
    exit 1
fi

# Vérifier qu'on est sur une branche de production
cd ../
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
PRODUCTION_BRANCHES=("18.0" "master" "main")

if [[ ! " ${PRODUCTION_BRANCHES[@]} " =~ " ${CURRENT_BRANCH} " ]]; then
    echo_error "Déploiement Cloudron uniquement autorisé sur les branches de production"
    echo_warning "Branche actuelle: $CURRENT_BRANCH"
    echo_warning "Branches autorisées: ${PRODUCTION_BRANCHES[*]}"
    exit 1
fi

cd cloudron/

# Configuration de l'image
DOCKER_IMAGE="$DOCKER_REGISTRY/$CLIENT_NAME-odoo:$APP_VERSION"

# Vérifier la connexion Cloudron
echo_info "🔐 Vérification de la connexion Cloudron..."
if ! cloudron status --server "$CLOUDRON_SERVER" &>/dev/null; then
    echo_warning "Non connecté à Cloudron. Connexion..."
    
    # Utiliser les identifiants si fournis
    if [[ -n "$CLOUDRON_USERNAME" && -n "$CLOUDRON_PASSWORD" ]]; then
        echo_info "🔐 Connexion avec identifiants..."
        cloudron login --server "$CLOUDRON_SERVER" --username "$CLOUDRON_USERNAME" --password "$CLOUDRON_PASSWORD"
    else
        cloudron login --server "$CLOUDRON_SERVER"
    fi
fi

echo_success "Connecté à Cloudron: $CLOUDRON_SERVER"

# Vérifier si l'app existe déjà
echo_info "🔍 Vérification si l'app existe: $APP_ID"

if cloudron list --server "$CLOUDRON_SERVER" | grep -q "$APP_ID"; then
    echo_info "📦 Application existante trouvée. Mise à jour..."
    
    # Mettre à jour l'application existante
    cloudron update \
        --server "$CLOUDRON_SERVER" \
        --app "$APP_ID" \
        --image "$DOCKER_IMAGE"
        
    echo_success "✨ Application mise à jour avec succès !"
    
else
    echo_info "🆕 Nouvelle installation..."
    
    # Extraire le subdomain de l'APP_ID pour l'installation
    LOCATION=$(echo "$APP_ID" | cut -d'.' -f1)
    
    # Installer une nouvelle application
    cloudron install \
        --server "$CLOUDRON_SERVER" \
        --image "$DOCKER_IMAGE" \
        --location "$LOCATION" \
        --accessRestriction "" \
        --portBindings "" \
        --label "production"
        
    echo_success "✨ Application installée avec succès !"
fi

# Afficher l'URL de l'application
APP_URL="https://$APP_ID"
echo ""
echo_success "🎉 Déploiement Cloudron terminé !"
echo_info "URL: $APP_URL"
echo_info "Image: $DOCKER_IMAGE"

# Optionnel: ouvrir dans le navigateur
read -p "Voulez-vous ouvrir l'application dans le navigateur ? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if command -v xdg-open &> /dev/null; then
        xdg-open "$APP_URL"
    elif command -v open &> /dev/null; then
        open "$APP_URL"
    else
        echo_info "Ouvrez manuellement: $APP_URL"
    fi
fi

echo ""
echo_info "📋 Commandes utiles:"
echo "  cloudron logs --server $CLOUDRON_SERVER --app $APP_ID"
echo "  cloudron exec --server $CLOUDRON_SERVER --app $APP_ID"
echo "  cloudron restart --server $CLOUDRON_SERVER --app $APP_ID"
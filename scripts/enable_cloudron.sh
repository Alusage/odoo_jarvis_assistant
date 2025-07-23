#!/bin/bash

# Script pour activer Cloudron sur un client existant
# Usage: ./enable_cloudron.sh <client_name>

set -euo pipefail

# Couleurs pour les messages
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Fonctions utilitaires
echo_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
echo_success() { echo -e "${GREEN}✅ $1${NC}"; }
echo_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
echo_error() { echo -e "${RED}❌ $1${NC}"; }

# Variables globales
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATES_DIR="${REPO_ROOT}/templates"

# Vérification des paramètres
if [[ $# -ne 1 ]]; then
    echo_error "Usage: $0 <client_name>"
    echo "Exemple: $0 njtest"
    exit 1
fi

CLIENT_NAME="$1"
CLIENT_DIR="${REPO_ROOT}/clients/${CLIENT_NAME}"

# Vérification de l'existence du client
if [[ ! -d "$CLIENT_DIR" ]]; then
    echo_error "Le client '$CLIENT_NAME' n'existe pas dans clients/"
    echo_info "Clients disponibles:"
    ls -1 "${REPO_ROOT}/clients/" 2>/dev/null || echo "Aucun client trouvé"
    exit 1
fi

echo_info "🚀 Activation de Cloudron pour le client: $CLIENT_NAME"

# Vérification si Cloudron est déjà activé
PROJECT_CONFIG="$CLIENT_DIR/project_config.json"
if [[ -f "$PROJECT_CONFIG" ]]; then
    CLOUDRON_ENABLED=$(jq -r '.publication.providers.cloudron.enabled // false' "$PROJECT_CONFIG")
    if [[ "$CLOUDRON_ENABLED" == "true" ]]; then
        echo_warning "Cloudron est déjà activé pour ce client"
        echo_info "Répertoire: $CLIENT_DIR/cloudron/"
        if [[ -d "$CLIENT_DIR/cloudron" ]]; then
            echo_success "Structure Cloudron présente"
        else
            echo_warning "Structure Cloudron manquante, régénération..."
        fi
    fi
fi

# Récupération des informations du client
if [[ ! -f "$PROJECT_CONFIG" ]]; then
    echo_error "Fichier project_config.json manquant pour ce client"
    echo_info "Veuillez d'abord exécuter: make configure-client CLIENT=$CLIENT_NAME"
    exit 1
fi

ODOO_VERSION=$(jq -r '.odoo_version // "18.0"' "$PROJECT_CONFIG")
CLIENT_DISPLAY_NAME=$(jq -r '.project_name' "$PROJECT_CONFIG" | sed 's/_/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')

echo_info "📋 Informations du client:"
echo "   - Nom: $CLIENT_NAME"
echo "   - Nom d'affichage: $CLIENT_DISPLAY_NAME"
echo "   - Version Odoo: $ODOO_VERSION"

# Création du répertoire cloudron
CLOUDRON_DIR="$CLIENT_DIR/cloudron"
if [[ ! -d "$CLOUDRON_DIR" ]]; then
    echo_info "📁 Création du répertoire cloudron/"
    mkdir -p "$CLOUDRON_DIR"
fi

# Template substitution function
substitute_template() {
    local template_file="$1"
    local output_file="$2"
    
    sed -e "s/{{CLIENT_NAME}}/$CLIENT_NAME/g" \
        -e "s/{{CLIENT_DISPLAY_NAME}}/$CLIENT_DISPLAY_NAME/g" \
        -e "s/{{ODOO_VERSION}}/$ODOO_VERSION/g" \
        -e "s/{{CLOUDRON_VERSION}}/1.0.0/g" \
        -e "s/{{CLOUDRON_DOMAIN}}/localhost/g" \
        "$template_file" > "$output_file"
}

# Copie et substitution des templates Cloudron
echo_info "📝 Génération des fichiers Cloudron à partir des templates..."

# Dockerfile
substitute_template "$TEMPLATES_DIR/cloudron/Dockerfile" "$CLOUDRON_DIR/Dockerfile"
echo_success "   - Dockerfile créé"

# CloudronManifest.json
substitute_template "$TEMPLATES_DIR/cloudron/CloudronManifest.json" "$CLOUDRON_DIR/CloudronManifest.json"
echo_success "   - CloudronManifest.json créé"

# Scripts
cp "$TEMPLATES_DIR/cloudron/build.sh" "$CLOUDRON_DIR/build.sh"
chmod +x "$CLOUDRON_DIR/build.sh"
echo_success "   - build.sh créé et rendu exécutable"

cp "$TEMPLATES_DIR/cloudron/deploy.sh" "$CLOUDRON_DIR/deploy.sh"
chmod +x "$CLOUDRON_DIR/deploy.sh"
echo_success "   - deploy.sh créé et rendu exécutable"

cp "$TEMPLATES_DIR/cloudron/cloudron-entrypoint.sh" "$CLOUDRON_DIR/cloudron-entrypoint.sh"
chmod +x "$CLOUDRON_DIR/cloudron-entrypoint.sh"
echo_success "   - cloudron-entrypoint.sh créé et rendu exécutable"

# Configuration Cloudron avec timestamp actuel
cat > "$CLOUDRON_DIR/cloudron_config.json" << EOF
{
  "enabled": true,
  "client_name": "$CLIENT_NAME",
  "client_display_name": "$CLIENT_DISPLAY_NAME",
  "odoo_version": "$ODOO_VERSION",
  "cloudron": {
    "server": "https://my.cloudron.me",
    "domain": "localhost",
    "subdomain": "$CLIENT_NAME",
    "docker_registry": "docker.io/username",
    "app_version": "1.0.0",
    "contact_email": "admin@example.com",
    "author_name": "Admin",
    "client_website": "https://example.com"
  },
  "deployment": {
    "production_only": true,
    "allowed_branches": ["18.0", "master", "main"],
    "auto_deploy": false,
    "backup_before_deploy": true
  },
  "docker": {
    "memory_limit": "2GB", 
    "cpu_limit": "1",
    "health_check_enabled": true,
    "restart_policy": "unless-stopped"
  },
  "metadata": {
    "created": "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")",
    "last_updated": "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")",
    "version": "1.0.0"
  }
}
EOF
echo_success "   - cloudron_config.json créé avec configuration par défaut"

# Mise à jour du project_config.json pour activer Cloudron
echo_info "🔧 Mise à jour de project_config.json..."

# Backup du fichier original
cp "$PROJECT_CONFIG" "$PROJECT_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"

# Mise à jour avec jq
CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%S+02:00")
jq --arg current_time "$CURRENT_TIME" \
   '.publication.enabled_modes += ["cloudron"] | 
    .publication.enabled_modes |= unique |
    .publication.providers.cloudron.enabled = true |
    .publication.providers.cloudron.config_file = "cloudron/cloudron_config.json" |
    .metadata.last_updated = $current_time |
    .metadata.updated_by = "enable_cloudron_script"' \
    "$PROJECT_CONFIG" > "$PROJECT_CONFIG.tmp" && mv "$PROJECT_CONFIG.tmp" "$PROJECT_CONFIG"

echo_success "   - Configuration de publication Cloudron activée"

# Vérification de l'activation
CLOUDRON_ENABLED_CHECK=$(jq -r '.publication.providers.cloudron.enabled' "$PROJECT_CONFIG")
if [[ "$CLOUDRON_ENABLED_CHECK" == "true" ]]; then
    echo_success "✅ Cloudron activé avec succès pour le client $CLIENT_NAME"
    
    echo_info "📂 Structure créée:"
    echo "   $CLOUDRON_DIR/"
    echo "   ├── 📄 Dockerfile"
    echo "   ├── 📄 CloudronManifest.json"
    echo "   ├── 🔧 build.sh"
    echo "   ├── 🔧 deploy.sh"
    echo "   ├── 🔧 cloudron-entrypoint.sh"
    echo "   └── ⚙️  cloudron_config.json"
    
    echo_info "🚀 Pour déployer sur Cloudron:"
    echo "   1. Configurez les paramètres dans: $CLOUDRON_DIR/cloudron_config.json"
    echo "   2. Assurez-vous d'être sur une branche de production (18.0, master, main)"
    echo "   3. Exécutez: cd $CLIENT_DIR && ./cloudron/build.sh"
    echo "   4. Puis: ./cloudron/deploy.sh install"
    
    echo_info "🌐 Ou utilisez l'interface web dashboard pour configurer et déployer"
    
else
    echo_error "Erreur lors de l'activation de Cloudron"
    exit 1
fi

echo_success "🎉 Cloudron configuré avec succès pour $CLIENT_NAME !"
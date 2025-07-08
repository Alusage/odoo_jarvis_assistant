#!/bin/bash

# Script d'entrée pour synchroniser odoo.conf et installer les dépendances

ODOO_CONF_DIR="/etc/odoo"
CUSTOM_CONF_DIR="/mnt/config"
CUSTOM_CONF_FILE="${CUSTOM_CONF_DIR}/odoo.conf"
REQUIREMENTS_FILE="/mnt/requirements.txt"
EXTRA_ADDONS_DIR="/mnt/extra-addons"
ADDONS_DIR="/mnt/addons"

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

echo_info "🚀 Initialisation du conteneur Odoo personnalisé..."

# Si le fichier odoo.conf n'existe pas dans le dossier client, le copier depuis l'image officielle
if [ ! -f "$CUSTOM_CONF_FILE" ]; then
    echo_info "📄 Copie du fichier odoo.conf depuis l'image officielle..."
    cp "$ODOO_CONF_DIR/odoo.conf" "$CUSTOM_CONF_FILE"
    echo_success "✅ Fichier odoo.conf créé dans $CUSTOM_CONF_DIR"
fi

# Installer les dépendances Python si le fichier requirements.txt existe
if [ -f "$REQUIREMENTS_FILE" ]; then
    echo_info "📦 Installation des dépendances Python..."
    /usr/local/bin/install_requirements.sh
fi

# Construire le chemin des addons
ADDONS_PATH="/usr/lib/python3/dist-packages/odoo/addons"

# Ajouter extra-addons au chemin s'il existe
if [ -d "$EXTRA_ADDONS_DIR" ] && [ "$(ls -A $EXTRA_ADDONS_DIR 2>/dev/null)" ]; then
    ADDONS_PATH="$EXTRA_ADDONS_DIR,$ADDONS_PATH"
    echo_info "📁 Modules extra-addons détectés et ajoutés au chemin"
fi

# Ajouter tous les sous-dossiers d'addons/ au chemin
if [ -d "$ADDONS_DIR" ]; then
    for addon_dir in "$ADDONS_DIR"/*; do
        if [ -d "$addon_dir" ]; then
            ADDONS_PATH="$addon_dir,$ADDONS_PATH"
            echo_info "📁 Ajout du dossier addons: $(basename "$addon_dir")"
        fi
    done
fi

echo_info "🔧 Chemin des addons: $ADDONS_PATH"

# Lancer Odoo avec le fichier de configuration personnalisé et le chemin des addons
echo_info "🚀 Démarrage d'Odoo..."
exec odoo --config "$CUSTOM_CONF_FILE" --addons-path="$ADDONS_PATH" "$@"

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

# S'assurer que les répertoires montés ont les bonnes permissions
echo_info "🔧 Vérification des permissions..."
if [ -d "$CUSTOM_CONF_DIR" ] && [ ! -w "$CUSTOM_CONF_DIR" ]; then
    echo_warning "Permissions insuffisantes sur $CUSTOM_CONF_DIR"
fi

# Si le fichier odoo.conf n'existe pas dans le dossier client, le copier depuis l'image officielle
if [ ! -f "$CUSTOM_CONF_FILE" ]; then
    echo_info "📄 Création du fichier odoo.conf..."
    
    # Vérifier que le répertoire de destination existe
    if [ ! -d "$CUSTOM_CONF_DIR" ]; then
        echo_warning "Répertoire $CUSTOM_CONF_DIR n'existe pas, création..."
        mkdir -p "$CUSTOM_CONF_DIR" || {
            echo_error "Impossible de créer le répertoire $CUSTOM_CONF_DIR"
            exit 1
        }
    fi
    
    # Générer un fichier de configuration minimal directement
    echo_info "Génération d'un fichier de configuration minimal..."
    cat > "$CUSTOM_CONF_FILE" << EOF
[options]
addons_path = /usr/lib/python3/dist-packages/odoo/addons
data_dir = /var/lib/odoo
logfile = /var/log/odoo/odoo.log
log_level = info
db_host = db
db_port = 5432
db_user = odoo
db_password = odoo
EOF
    
    if [ $? -eq 0 ]; then
        echo_success "✅ Fichier odoo.conf créé dans $CUSTOM_CONF_DIR"
    else
        echo_error "❌ Impossible de créer le fichier odoo.conf"
        echo_warning "Tentative avec un fichier temporaire..."
        
        # Si échec, utiliser un fichier temporaire et démarrer sans config personnalisée
        CUSTOM_CONF_FILE="/tmp/odoo.conf"
        cat > "$CUSTOM_CONF_FILE" << EOF
[options]
addons_path = /usr/lib/python3/dist-packages/odoo/addons
data_dir = /var/lib/odoo
logfile = /var/log/odoo/odoo.log
log_level = info
db_host = db
db_port = 5432
db_user = odoo
db_password = odoo
EOF
        echo_warning "⚠️  Utilisation d'un fichier de configuration temporaire"
    fi
fi

# Installer les dépendances Python si le fichier requirements.txt existe
if [ -f "$REQUIREMENTS_FILE" ]; then
    echo_info "📦 Installation des dépendances Python..."
    /usr/local/bin/install_requirements.sh
fi

# Construire le chemin des addons
ADDONS_PATH="/usr/lib/python3/dist-packages/odoo/addons"

# Ajouter extra-addons au chemin s'il existe (contient les liens symboliques vers les modules)
if [ -d "$EXTRA_ADDONS_DIR" ] && [ "$(ls -A $EXTRA_ADDONS_DIR 2>/dev/null)" ]; then
    ADDONS_PATH="$EXTRA_ADDONS_DIR,$ADDONS_PATH"
    echo_info "📁 Modules extra-addons détectés et ajoutés au chemin"
fi

echo_info "🔧 Chemin des addons: $ADDONS_PATH"

# Lancer Odoo avec le fichier de configuration personnalisé et le chemin des addons
echo_info "🚀 Démarrage d'Odoo..."

# Si aucun argument ou si l'argument est "odoo", lancer odoo normalement
if [ $# -eq 0 ] || [ "$1" = "odoo" ]; then
    exec odoo --config "$CUSTOM_CONF_FILE" --addons-path="$ADDONS_PATH"
else
    # Sinon, passer tous les arguments à odoo
    exec odoo --config "$CUSTOM_CONF_FILE" --addons-path="$ADDONS_PATH" "$@"
fi

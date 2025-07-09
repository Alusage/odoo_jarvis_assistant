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

# S'assurer que le répertoire de données Odoo existe et a les bonnes permissions
if [ ! -d "/data" ]; then
    echo_info "📁 Création du répertoire de données /data..."
    mkdir -p /data
fi

# Créer les sous-répertoires nécessaires pour Odoo
echo_info "📁 Création des sous-répertoires de données..."
mkdir -p /data/filestore /data/sessions /data/addons

# Gérer les permissions du répertoire de données
echo_info "🔧 Configuration des permissions pour /data..."
if [ "$(id -u)" = "0" ]; then
    # Si on est root, configurer les permissions correctement
    chown -R odoo:odoo /data
    chmod -R 755 /data
    echo_success "✅ Permissions configurées en tant que root"
else
    # Si on n'est pas root, vérifier si on peut écrire
    if [ ! -w "/data" ] || [ ! -w "/data/sessions" ] || [ ! -w "/data/filestore" ]; then
        echo_warning "⚠️ Permissions insuffisantes sur /data, tentative de correction..."
        chmod -R 755 /data 2>/dev/null || true
        
        # Test d'écriture
        if [ ! -w "/data/sessions" ]; then
            echo_error "❌ Impossible d'obtenir les permissions d'écriture sur /data/sessions"
            echo_info "💡 Solution: relancez avec -e DEBUG_MODE=true pour investigation"
            echo_info "💡 Ou configurez les permissions sur l'hôte: sudo chown -R 101:101 ./data"
        else
            echo_success "✅ Permissions corrigées"
        fi
    else
        echo_success "✅ Permissions correctes sur /data"
    fi
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
data_dir = /data
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
data_dir = /data
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

# Vérification finale des permissions sur le répertoire de données
if [ ! -w "/data" ]; then
    echo_warning "⚠️ Permissions insuffisantes sur /data, tentative de correction..."
    if [ "$(id -u)" = "0" ]; then
        chown -R odoo:odoo /data
        chmod -R 755 /data
    else
        chmod -R 755 /data 2>/dev/null || true
    fi
    if [ ! -w "/data" ]; then
        echo_error "❌ Impossible d'obtenir les permissions d'écriture sur /data"
        echo_info "💡 Vérifiez que le volume /data est monté avec les bonnes permissions"
        echo_info "💡 Commande suggérée: sudo chown -R 101:101 ./data"
    else
        echo_success "✅ Permissions corrigées sur /data"
    fi
fi

# Créer les sous-répertoires nécessaires dans /data
echo_info "📁 Création des sous-répertoires nécessaires..."
mkdir -p /data/sessions /data/filestore /data/addons
if [ "$(id -u)" = "0" ]; then
    chown -R odoo:odoo /data/sessions /data/filestore /data/addons
fi
chmod -R 755 /data/sessions /data/filestore /data/addons 2>/dev/null || true

# Fonction pour démarrer Odoo avec gestion d'erreur
start_odoo() {
    echo_info "🚀 Démarrage d'Odoo..."
    
    # Basculer vers l'utilisateur odoo pour lancer Odoo
    echo_info "👤 Basculement vers l'utilisateur odoo..."
    
    # Configurer l'environnement pour l'utilisateur odoo
    export HOME=/var/lib/odoo
    export PATH="/var/lib/odoo/.local/bin:$PATH"
    
    # Si aucun argument ou si l'argument est "odoo", lancer odoo normalement
    if [ $# -eq 0 ] || [ "$1" = "odoo" ]; then
        gosu odoo odoo --config "$CUSTOM_CONF_FILE" --addons-path="$ADDONS_PATH"
    else
        # Sinon, passer tous les arguments à odoo
        gosu odoo odoo --config "$CUSTOM_CONF_FILE" --addons-path="$ADDONS_PATH" "$@"
    fi
    
    # Capturer le code de sortie
    local exit_code=$?
    
    # Si Odoo a échoué et que le mode debug est activé, démarrer un shell pour le débogage
    if [ $exit_code -ne 0 ] && [ "${DEBUG_MODE:-false}" = "true" ]; then
        echo_error "❌ Odoo s'est arrêté avec le code d'erreur: $exit_code"
        echo_warning "🔍 Mode débogage activé - Démarrage du shell de débogage..."
        echo_info "📝 Informations de débogage:"
        echo_info "   - Fichier de configuration: $CUSTOM_CONF_FILE"
        echo_info "   - Chemin des addons: $ADDONS_PATH"
        echo_info "   - Utilisateur actuel: $(whoami)"
        echo_info "   - Répertoire actuel: $(pwd)"
        echo_info "   - Variables d'environnement:"
        echo_info "     ODOO_CONF_DIR=$ODOO_CONF_DIR"
        echo_info "     CUSTOM_CONF_DIR=$CUSTOM_CONF_DIR"
        echo_info "     REQUIREMENTS_FILE=$REQUIREMENTS_FILE"
        echo_info "     EXTRA_ADDONS_DIR=$EXTRA_ADDONS_DIR"
        echo_info "     ADDONS_DIR=$ADDONS_DIR"
        echo_info "     DEBUG_MODE=$DEBUG_MODE"
        echo_info ""
        echo_info "💡 Utilisez 'docker exec -it <container_name> bash' pour accéder au shell"
        echo_info "💡 Pour relancer Odoo manuellement: gosu odoo odoo --config $CUSTOM_CONF_FILE --addons-path=$ADDONS_PATH"
        echo_info "💡 Ou en tant que root: odoo --config $CUSTOM_CONF_FILE --addons-path=$ADDONS_PATH"
        echo_info ""
        echo_warning "⏳ Maintien du conteneur en vie pour le débogage..."
        
        # Maintenir le conteneur en vie avec un shell interactif en tant que root
        exec /bin/bash
    elif [ $exit_code -ne 0 ]; then
        echo_error "❌ Odoo s'est arrêté avec le code d'erreur: $exit_code"
        echo_info "💡 Pour activer le mode débogage, définissez DEBUG_MODE=true"
        echo_info "💡 Exemple: docker run -e DEBUG_MODE=true ..."
        exit $exit_code
    fi
    
    return $exit_code
}

# Lancer Odoo avec le fichier de configuration personnalisé et le chemin des addons
start_odoo "$@"

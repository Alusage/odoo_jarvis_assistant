#!/bin/bash

# Script pour basculer un dépôt entre mode production (submodule) et mode dev (clone)
# Usage: toggle_dev_mode.sh <client_name> <repo_name> [branch_name]

set -e

CLIENT_NAME="$1"
REPO_NAME="$2"
TARGET_BRANCH="$3"

if [[ -z "$CLIENT_NAME" || -z "$REPO_NAME" ]]; then
    echo "Usage: $0 <client_name> <repo_name> [branch_name]"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CLIENT_DIR="$ROOT_DIR/clients/$CLIENT_NAME"

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

# Vérifier que le client existe
if [ ! -d "$CLIENT_DIR" ]; then
    echo_error "Client '$CLIENT_NAME' n'existe pas"
    exit 1
fi

cd "$CLIENT_DIR"

# Détecter la branche actuelle si non fournie
if [[ -z "$TARGET_BRANCH" ]]; then
    if [ -f ".odoo_branch_config" ]; then
        CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")
        TARGET_BRANCH=$(jq -r ".[\"$CURRENT_BRANCH\"] // \"18.0\"" .odoo_branch_config 2>/dev/null || echo "18.0")
    else
        TARGET_BRANCH="18.0"
    fi
fi

echo_info "Client: $CLIENT_NAME"
echo_info "Repository: $REPO_NAME"
echo_info "Target Branch: $TARGET_BRANCH"

# Fichiers et dossiers
DEV_CONFIG_FILE=".dev-config.json"
ADDONS_DIR="addons"
DEV_REPOS_DIR=".dev-repos"
EXTRA_ADDONS_DIR="extra-addons"
SUBMODULE_PATH="$ADDONS_DIR/$REPO_NAME"
DEV_REPO_PATH="$DEV_REPOS_DIR/$TARGET_BRANCH/$REPO_NAME"
EXTRA_ADDON_LINK="$EXTRA_ADDONS_DIR/${REPO_NAME//-/_}"

# Vérifier que le dépôt existe
if [ ! -d "$SUBMODULE_PATH" ]; then
    echo_error "Repository '$REPO_NAME' n'existe pas dans addons/"
    exit 1
fi

# Initialiser le fichier de config dev si inexistant
if [ ! -f "$DEV_CONFIG_FILE" ]; then
    echo_info "Initialisation du fichier de configuration dev"
    echo '{"repositories": {}}' > "$DEV_CONFIG_FILE"
fi

# Lire le mode actuel
CURRENT_MODE=$(jq -r ".repositories[\"$REPO_NAME\"].branches[\"$TARGET_BRANCH\"].mode // \"production\"" "$DEV_CONFIG_FILE" 2>/dev/null || echo "production")

echo_info "Mode actuel: $CURRENT_MODE"

if [ "$CURRENT_MODE" = "production" ]; then
    # BASCULER EN MODE DEV
    echo_info "🛠️  Activation du mode développement..."
    
    # Créer les répertoires nécessaires
    mkdir -p "$DEV_REPOS_DIR/$TARGET_BRANCH"
    
    # Cloner le dépôt si pas déjà fait
    if [ ! -d "$DEV_REPO_PATH" ]; then
        echo_info "Clone du repository..."
        
        # Récupérer l'URL du submodule
        cd "$SUBMODULE_PATH"
        REPO_URL=$(git config --get remote.origin.url 2>/dev/null || echo "")
        
        if [[ -z "$REPO_URL" ]]; then
            echo_error "Impossible de récupérer l'URL du repository"
            exit 1
        fi
        
        cd "$CLIENT_DIR"
        
        # Cloner vers le répertoire dev avec gestion d'erreurs réseau
        echo_info "Clonage du repository avec gestion d'erreurs réseau..."
        
        # Configuration git pour résistance aux erreurs réseau
        git config --global http.lowSpeedLimit 1000
        git config --global http.lowSpeedTime 30
        git config --global http.postBuffer 524288000
        
        # Tentatives de clone avec retry
        MAX_RETRIES=3
        RETRY=0
        
        while [ $RETRY -lt $MAX_RETRIES ]; do
            echo_info "Tentative de clonage ${RETRY+1}/$MAX_RETRIES..."
            
            # Clone shallow pour réduire le transfert
            if git clone --depth 1 --single-branch "$REPO_URL" "$DEV_REPO_PATH" 2>/dev/null; then
                echo_success "Clone réussi !"
                break
            else
                echo_warning "Échec du clone shallow, tentative de clone complet..."
                rm -rf "$DEV_REPO_PATH" 2>/dev/null
                
                if git clone "$REPO_URL" "$DEV_REPO_PATH"; then
                    echo_success "Clone complet réussi !"
                    break
                else
                    RETRY=$((RETRY + 1))
                    if [ $RETRY -lt $MAX_RETRIES ]; then
                        echo_warning "Tentative échouée, nouvelle tentative dans 5 secondes..."
                        sleep 5
                    else
                        echo_error "Impossible de cloner le repository après $MAX_RETRIES tentatives"
                        echo_error "URL du repository: $REPO_URL"
                        echo_error "Vérifiez votre connexion réseau et réessayez"
                        exit 1
                    fi
                fi
            fi
        done
        
        cd "$DEV_REPO_PATH"
        
        # Si le clone était shallow, récupérer l'historique complet si nécessaire
        if [ -f .git/shallow ]; then
            echo_info "Récupération de l'historique complet..."
            git fetch --unshallow || echo_warning "Impossible de récupérer l'historique complet, continuons..."
        fi
        
        # Créer une branche de développement unique
        DEV_BRANCH="dev-$TARGET_BRANCH-$(date +%Y%m%d-%H%M%S)"
        git checkout -b "$DEV_BRANCH"
        
        echo_success "Repository cloné et branche '$DEV_BRANCH' créée"
        
        cd "$CLIENT_DIR"
    else
        DEV_BRANCH=$(cd "$DEV_REPO_PATH" && git branch --show-current)
        echo_info "Repository dev existant trouvé (branche: $DEV_BRANCH)"
    fi
    
    # Mettre à jour le lien symbolique
    if [ -L "$EXTRA_ADDON_LINK" ] || [ -e "$EXTRA_ADDON_LINK" ]; then
        rm "$EXTRA_ADDON_LINK"
    fi
    
    # Trouver le bon module dans le repository
    MODULE_PATH=""
    if [ -d "$DEV_REPO_PATH/${REPO_NAME//-/_}" ]; then
        MODULE_PATH="$DEV_REPO_PATH/${REPO_NAME//-/_}"
    elif [ -d "$DEV_REPO_PATH/$(ls "$DEV_REPO_PATH" | head -1)" ]; then
        # Prendre le premier dossier qui ressemble à un module
        for dir in "$DEV_REPO_PATH"*/; do
            if [ -f "$dir/__manifest__.py" ] || [ -f "$dir/__openerp__.py" ]; then
                MODULE_PATH="$dir"
                break
            fi
        done
    fi
    
    if [ -n "$MODULE_PATH" ]; then
        ln -sf "../../$MODULE_PATH" "$EXTRA_ADDON_LINK"
        echo_success "Lien symbolique créé: $EXTRA_ADDON_LINK -> $MODULE_PATH"
    else
        echo_warning "Aucun module trouvé dans le repository dev"
    fi
    
    # Mettre à jour la configuration
    jq ".repositories[\"$REPO_NAME\"].branches[\"$TARGET_BRANCH\"] = {
        \"mode\": \"dev\",
        \"dev_branch\": \"$DEV_BRANCH\",
        \"uncommitted_changes\": false,
        \"created_at\": \"$(date -u +%Y-%m-%dT%H:%M:%S)Z\"
    }" "$DEV_CONFIG_FILE" > "$DEV_CONFIG_FILE.tmp" && mv "$DEV_CONFIG_FILE.tmp" "$DEV_CONFIG_FILE"
    
    echo_success "🛠️  Mode développement activé pour '$REPO_NAME' sur branche '$TARGET_BRANCH'"
    echo_info "Répertoire dev: $DEV_REPO_PATH"
    
else
    # BASCULER EN MODE PRODUCTION
    echo_info "🏭 Retour au mode production..."
    
    # Vérifier les modifications non commitées
    if [ -d "$DEV_REPO_PATH" ]; then
        cd "$DEV_REPO_PATH"
        if [ -n "$(git status --porcelain)" ]; then
            echo_warning "⚠️  Modifications non commitées détectées!"
            read -p "Continuer? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo_info "Opération annulée"
                exit 0
            fi
        fi
        cd "$CLIENT_DIR"
    fi
    
    # Restaurer le lien vers le submodule
    if [ -L "$EXTRA_ADDON_LINK" ] || [ -e "$EXTRA_ADDON_LINK" ]; then
        rm "$EXTRA_ADDON_LINK"
    fi
    
    # Recréer le lien vers le submodule original
    if [ -d "$SUBMODULE_PATH" ]; then
        # Trouver le module dans le submodule
        MODULE_PATH=""
        if [ -d "$SUBMODULE_PATH/${REPO_NAME//-/_}" ]; then
            MODULE_PATH="$SUBMODULE_PATH/${REPO_NAME//-/_}"
        else
            # Chercher le premier module valide
            for dir in "$SUBMODULE_PATH"*/; do
                if [ -f "$dir/__manifest__.py" ] || [ -f "$dir/__openerp__.py" ]; then
                    MODULE_PATH="$dir"
                    break
                fi
            done
        fi
        
        if [ -n "$MODULE_PATH" ]; then
            ln -sf "../../$MODULE_PATH" "$EXTRA_ADDON_LINK"
            echo_success "Lien symbolique restauré: $EXTRA_ADDON_LINK -> $MODULE_PATH"
        fi
    fi
    
    # Mettre à jour la configuration
    jq ".repositories[\"$REPO_NAME\"].branches[\"$TARGET_BRANCH\"].mode = \"production\"" "$DEV_CONFIG_FILE" > "$DEV_CONFIG_FILE.tmp" && mv "$DEV_CONFIG_FILE.tmp" "$DEV_CONFIG_FILE"
    
    echo_success "🏭 Mode production activé pour '$REPO_NAME' sur branche '$TARGET_BRANCH'"
fi

# Synchroniser les liens symboliques
echo_info "Synchronisation des liens symboliques..."
"$SCRIPT_DIR/sync_dev_links.sh" "$CLIENT_NAME" "$TARGET_BRANCH"

echo_info "✨ Opération terminée avec succès"
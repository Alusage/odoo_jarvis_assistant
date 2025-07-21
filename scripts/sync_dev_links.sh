#!/bin/bash

# Script pour synchroniser les liens symboliques selon le mode dev/production
# Usage: sync_dev_links.sh <client_name> <branch_name>

# set -e désactivé - il y a encore une erreur silencieuse quelque part

CLIENT_NAME="$1"
BRANCH_NAME="$2"

if [[ -z "$CLIENT_NAME" || -z "$BRANCH_NAME" ]]; then
    echo "Usage: $0 <client_name> <branch_name>"
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

echo_info() { echo -e "${BLUE}🔗 $1${NC}"; }
echo_success() { echo -e "${GREEN}✅ $1${NC}"; }
echo_error() { echo -e "${RED}❌ $1${NC}"; }

# Vérifier que le client existe
if [ ! -d "$CLIENT_DIR" ]; then
    echo_error "Client '$CLIENT_NAME' n'existe pas"
    exit 1
fi

cd "$CLIENT_DIR"

DEV_CONFIG_FILE=".dev-config.json"
ADDONS_DIR="addons"
DEV_REPOS_DIR=".dev-repos"
EXTRA_ADDONS_DIR="extra-addons"

# Initialiser le fichier de config si inexistant
if [ ! -f "$DEV_CONFIG_FILE" ]; then
    echo '{"repositories": {}}' > "$DEV_CONFIG_FILE"
fi

echo_info "Synchronisation des liens pour le client '$CLIENT_NAME' sur la branche '$BRANCH_NAME'"

LINK_COUNT=0

# Parcourir tous les dépôts dans addons/
if [ -d "$ADDONS_DIR" ]; then
    for REPO_PATH in "$ADDONS_DIR"/*; do
        if [ -d "$REPO_PATH" ]; then
            REPO_NAME=$(basename "$REPO_PATH")
            
            # Ignorer les dossiers cachés et non-git
            if [[ "$REPO_NAME" == .* ]] || [ ! -e "$REPO_PATH/.git" ]; then
                continue
            fi
            
            echo_info "Traitement du dépôt: $REPO_NAME"
            
            # Vérifier le mode pour ce dépôt sur cette branche
            DEV_MODE=$(jq -r ".repositories[\"$REPO_NAME\"].branches[\"$BRANCH_NAME\"].mode // \"production\"" "$DEV_CONFIG_FILE" 2>/dev/null)
            
            # Trouver tous les liens symboliques existants pour ce dépôt dans extra-addons
            EXISTING_LINKS=()
            if [ -d "$EXTRA_ADDONS_DIR" ]; then
                for link in "$EXTRA_ADDONS_DIR"/*; do
                    if [ -L "$link" ]; then
                        TARGET=$(readlink "$link")
                        if [[ "$TARGET" == *"$REPO_NAME"* ]]; then
                            EXISTING_LINKS+=("$(basename "$link")")
                        fi
                    fi
                done
            fi
            
            if [ "$DEV_MODE" = "dev" ]; then
                # MODE DEV: Pointer vers le clone dev
                DEV_REPO_PATH="$DEV_REPOS_DIR/$BRANCH_NAME/$REPO_NAME"
                
                if [ -d "$DEV_REPO_PATH" ]; then
                    echo_info "Trouvé ${#EXISTING_LINKS[@]} liens à rediriger vers le dev: ${EXISTING_LINKS[*]}"
                    # Recréer tous les liens existants vers le clone dev
                    for LINK_NAME in "${EXISTING_LINKS[@]}"; do
                        echo_info "Traitement du lien: $LINK_NAME"
                        EXTRA_ADDON_LINK="$EXTRA_ADDONS_DIR/$LINK_NAME"
                        
                        # Supprimer le lien existant
                        if [ -L "$EXTRA_ADDON_LINK" ]; then
                            rm "$EXTRA_ADDON_LINK"
                        fi
                        
                        # Essayer de trouver le module dans le clone dev
                        MODULE_PATH=""
                        if [ -d "$DEV_REPO_PATH/$LINK_NAME" ]; then
                            MODULE_PATH="$DEV_REPO_PATH/$LINK_NAME"
                        fi
                        
                        if [ -n "$MODULE_PATH" ]; then
                            # Créer le lien relatif vers le clone dev (depuis extra-addons vers .dev-repos)
                            RELATIVE_PATH="../$MODULE_PATH"
                            ln -sf "$RELATIVE_PATH" "$EXTRA_ADDON_LINK"
                            echo_success "🛠️  DEV: $LINK_NAME -> $MODULE_PATH"
                            ((LINK_COUNT++))
                        else
                            echo_error "Module $LINK_NAME introuvable dans $DEV_REPO_PATH"
                        fi
                    done
                else
                    echo_error "Repository dev introuvable: $DEV_REPO_PATH"
                fi
                
            else
                # MODE PRODUCTION: Recréer tous les liens vers les submodules
                echo_info "Trouvé ${#EXISTING_LINKS[@]} liens à rediriger vers le submodule: ${EXISTING_LINKS[*]}"
                for LINK_NAME in "${EXISTING_LINKS[@]}"; do
                    echo_info "Traitement du lien: $LINK_NAME"
                    EXTRA_ADDON_LINK="$EXTRA_ADDONS_DIR/$LINK_NAME"
                    
                    # Supprimer le lien existant
                    if [ -L "$EXTRA_ADDON_LINK" ]; then
                        rm "$EXTRA_ADDON_LINK"
                    fi
                    
                    # Essayer de trouver le module dans le submodule
                    MODULE_PATH=""
                    if [ -d "$REPO_PATH/$LINK_NAME" ]; then
                        MODULE_PATH="$REPO_PATH/$LINK_NAME"
                    fi
                    
                    if [ -n "$MODULE_PATH" ]; then
                        # Créer le lien relatif vers le submodule (depuis extra-addons vers addons)
                        RELATIVE_PATH="../$MODULE_PATH"
                        ln -sf "$RELATIVE_PATH" "$EXTRA_ADDON_LINK"
                        echo_success "🏭 PROD: $LINK_NAME -> $MODULE_PATH"
                        ((LINK_COUNT++))
                    else
                        echo_error "Module $LINK_NAME introuvable dans $REPO_PATH"
                    fi
                done
            fi
        fi
    done
fi

echo_success "✨ Synchronisation terminée: $LINK_COUNT liens créés"
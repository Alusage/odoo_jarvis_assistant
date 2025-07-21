#!/bin/bash

# Script pour renommer une branche dev dans un dépôt en mode dev
# Usage: rename_dev_branch.sh <client_name> <repo_name> <new_branch_name> [current_branch]

set -e

CLIENT_NAME="$1"
REPO_NAME="$2"
NEW_BRANCH_NAME="$3"
TARGET_BRANCH="$4"

if [[ -z "$CLIENT_NAME" || -z "$REPO_NAME" || -z "$NEW_BRANCH_NAME" ]]; then
    echo "Usage: $0 <client_name> <repo_name> <new_branch_name> [current_branch]"
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
        TARGET_BRANCH=$(jq -r ".\"$CURRENT_BRANCH\" // \"18.0\"" .odoo_branch_config 2>/dev/null || echo "18.0")
    else
        TARGET_BRANCH="18.0"
    fi
fi

echo_info "Client: $CLIENT_NAME"
echo_info "Repository: $REPO_NAME"
echo_info "Target Branch: $TARGET_BRANCH"
echo_info "New Branch Name: $NEW_BRANCH_NAME"

# Fichiers et dossiers
DEV_CONFIG_FILE=".dev-config.json"
DEV_REPOS_DIR=".dev-repos"
DEV_REPO_PATH="$DEV_REPOS_DIR/$TARGET_BRANCH/$REPO_NAME"

# Vérifier que le fichier de config dev existe
if [ ! -f "$DEV_CONFIG_FILE" ]; then
    echo_error "Fichier de configuration dev introuvable"
    exit 1
fi

# Lire le mode et la branche actuelle
CURRENT_MODE=$(jq -r ".repositories[\"$REPO_NAME\"].branches[\"$TARGET_BRANCH\"].mode // \"production\"" "$DEV_CONFIG_FILE" 2>/dev/null || echo "production")
CURRENT_DEV_BRANCH=$(jq -r ".repositories[\"$REPO_NAME\"].branches[\"$TARGET_BRANCH\"].dev_branch // \"\"" "$DEV_CONFIG_FILE" 2>/dev/null || echo "")

if [ "$CURRENT_MODE" != "dev" ]; then
    echo_error "Le dépôt '$REPO_NAME' n'est pas en mode dev"
    exit 1
fi

if [ -z "$CURRENT_DEV_BRANCH" ]; then
    echo_error "Impossible de trouver la branche dev actuelle"
    exit 1
fi

# Vérifier que le dépôt dev existe
if [ ! -d "$DEV_REPO_PATH" ]; then
    echo_error "Repository dev introuvable: $DEV_REPO_PATH"
    exit 1
fi

echo_info "Branche dev actuelle: $CURRENT_DEV_BRANCH"

# Renommer la branche dans le dépôt git
cd "$DEV_REPO_PATH"

# Vérifier qu'on est sur la bonne branche
CURRENT_GIT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_GIT_BRANCH" != "$CURRENT_DEV_BRANCH" ]; then
    echo_warning "Branche Git actuelle ($CURRENT_GIT_BRANCH) différente de la config ($CURRENT_DEV_BRANCH)"
    echo_info "Basculement vers la branche $CURRENT_DEV_BRANCH"
    git checkout "$CURRENT_DEV_BRANCH"
fi

# Renommer la branche
echo_info "Renommage de la branche '$CURRENT_DEV_BRANCH' vers '$NEW_BRANCH_NAME'..."
git branch -m "$CURRENT_DEV_BRANCH" "$NEW_BRANCH_NAME"
echo_success "Branche renommée avec succès"

cd "$CLIENT_DIR"

# Mettre à jour la configuration
echo_info "Mise à jour de la configuration..."
jq ".repositories[\"$REPO_NAME\"].branches[\"$TARGET_BRANCH\"].dev_branch = \"$NEW_BRANCH_NAME\"" "$DEV_CONFIG_FILE" > "$DEV_CONFIG_FILE.tmp" && mv "$DEV_CONFIG_FILE.tmp" "$DEV_CONFIG_FILE"

echo_success "✨ Branche dev renommée avec succès!"
echo_info "Ancienne branche: $CURRENT_DEV_BRANCH"
echo_info "Nouvelle branche: $NEW_BRANCH_NAME"
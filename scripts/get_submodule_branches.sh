#!/bin/bash
# Script pour obtenir les branches d'un submodule

if [ $# -ne 2 ]; then
    echo "Usage: $0 <client_name> <submodule_path>"
    exit 1
fi

CLIENT_NAME=$1
SUBMODULE_PATH=$2
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
REPO_NAME=$(basename "$SUBMODULE_PATH")

# Vérifier si le dépôt est en mode dev
DEV_CONFIG_FILE="$REPO_ROOT/clients/$CLIENT_NAME/.dev-config.json"
IS_DEV_MODE=false
DEV_BRANCH="18.0"

if [ -f "$DEV_CONFIG_FILE" ]; then
    # Extraire le mode et la branche pour ce dépôt
    MODE=$(jq -r ".repositories.\"$REPO_NAME\".branches.\"18.0\".mode // \"production\"" "$DEV_CONFIG_FILE" 2>/dev/null)
    if [ "$MODE" = "dev" ]; then
        IS_DEV_MODE=true
        DEV_DIR="$REPO_ROOT/clients/$CLIENT_NAME/.dev-repos/18.0/$REPO_NAME"
    fi
fi

# Déterminer le répertoire à utiliser
if [ "$IS_DEV_MODE" = true ] && [ -d "$DEV_DIR" ]; then
    WORK_DIR="$DEV_DIR"
else
    WORK_DIR="$REPO_ROOT/clients/$CLIENT_NAME/$SUBMODULE_PATH"
fi

# Aller dans le bon répertoire
cd "$WORK_DIR" 2>/dev/null || {
    echo "Error: Cannot access $WORK_DIR"
    exit 1
}

# Si on est en mode dev, récupérer toutes les branches distantes
if [ "$IS_DEV_MODE" = true ]; then
    # Configurer git pour récupérer toutes les branches
    git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*" 2>/dev/null
    # Récupérer toutes les branches (silencieusement)
    git fetch origin --quiet 2>/dev/null
fi

# Lister toutes les branches (locales et distantes)
{
  # D'abord les branches locales
  git branch --format='%(refname:short)' 2>/dev/null || git branch | sed 's/^[* ] //'
  
  # Puis les branches distantes (sans le préfixe origin/)
  git branch -r | grep -v HEAD | sed 's/.*origin\///'
} | sort -V | uniq
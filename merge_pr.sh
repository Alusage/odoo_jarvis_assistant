#!/bin/bash

SUBMODULE_PATH=$1
PR_NUMBER=$2
BASE_BRANCH=${3:-16.0}

if [ -z "$SUBMODULE_PATH" ] || [ -z "$PR_NUMBER" ]; then
  echo "❌ Usage : bash merge_pr.sh <submodule_path> <pr_number> [base_branch]"
  echo "Exemple : bash merge_pr.sh addons/oca_partner_contact 1234 16.0"
  exit 1
fi

# Résoudre le chemin absolu du submodule
REPO_PATH=$(realpath "$SUBMODULE_PATH")

# Aller dans le dossier
cd "$REPO_PATH" || { echo "❌ Répertoire $REPO_PATH introuvable."; exit 1; }

# Récupérer l'URL du dépôt d'origine
REPO_URL=$(git config --get remote.origin.url)
REPO_NAME=$(basename -s .git "$REPO_URL")

echo "📦 Dépôt : $REPO_NAME"
echo "🌱 Branche de base : $BASE_BRANCH"
echo "🔢 PR à merger : #$PR_NUMBER"

echo "🔄 Récupération de la PR depuis GitHub..."
git fetch origin pull/$PR_NUMBER/head:pr-$PR_NUMBER

echo "🧪 Merge de la PR dans $BASE_BRANCH..."
git checkout "$BASE_BRANCH"
git pull origin "$BASE_BRANCH"
git merge --no-ff pr-$PR_NUMBER -m "Merge PR #$PR_NUMBER from $REPO_NAME"

if [ $? -eq 0 ]; then
  echo "✅ PR #$PR_NUMBER mergée avec succès dans $BASE_BRANCH."
else
  echo "⚠️ Conflits détectés. Veuillez les résoudre manuellement dans $REPO_PATH."
fi

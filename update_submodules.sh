#!/bin/bash

# Script pour mettre à jour tous les submodules (version historique)
# Ce script était utilisé pour merger des PR - gardé pour compatibilité
# Utilisez plutôt les nouveaux scripts dans ./scripts/

BASE_BRANCH=${1:-16.0}

echo "🔄 Mise à jour des submodules vers la branche $BASE_BRANCH..."

# Initialiser et mettre à jour tous les submodules
git submodule update --init --recursive

# Pour chaque submodule, pull la branche spécifiée
git submodule foreach "
  echo \"Mise à jour de \$name vers $BASE_BRANCH...\"
  git fetch origin
  git checkout $BASE_BRANCH 2>/dev/null || git checkout -b $BASE_BRANCH origin/$BASE_BRANCH 2>/dev/null || echo \"Branche $BASE_BRANCH non trouvée pour \$name\"
  git pull origin $BASE_BRANCH 2>/dev/null || echo \"Impossible de pull $BASE_BRANCH pour \$name\"
"

echo "✅ Mise à jour des submodules terminée"
echo "💡 Astuce: Utilisez ./scripts/update_client_submodules.sh pour une gestion plus avancée"
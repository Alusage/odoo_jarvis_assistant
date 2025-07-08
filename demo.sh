#!/bin/bash

# Script de démonstration du générateur de clients Odoo
# Usage: ./demo.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${BLUE}-  $1${NC}"; }
echo_success() { echo -e "${GREEN}✅ $1${NC}"; }
echo_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }

echo_info "🎭 Démonstration du générateur de clients Odoo"
echo_info "=============================================="
echo

echo_info "Cette démonstration va :"
echo "1. Créer un client de test 'demo_client'"
echo "2. Montrer la structure générée"
echo "3. Lister les modules disponibles"
echo "4. Ajouter un module OCA supplémentaire"
echo "5. Nettoyer (supprimer le client de démonstration)"
echo

read -p "🚀 Continuer avec la démonstration ? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo_warning "Démonstration annulée"
    exit 0
fi

echo
echo_info "📝 Création du client 'demo_client' (version 18.0, template ecommerce)..."

# Simuler la création d'un client avec des paramètres prédéfinis
./scripts/generate_client_repo.sh "demo_client" "18.0" "ecommerce" "false"

echo
echo_success "✨ Client de démonstration créé !"

echo
echo_info "📁 Structure du client généré :"
tree clients/demo_client -L 2 2>/dev/null || find clients/demo_client -type d | head -20

echo
echo_info "📋 Contenu du README du client :"
head -30 clients/demo_client/README.md

echo
echo_info "🐳 Configuration Docker Compose :"
echo_warning "Services configurés :"
grep -A 5 "services:" clients/demo_client/docker-compose.yml

echo
echo_info "📦 Modules OCA ajoutés automatiquement :"
./scripts/list_available_modules.sh demo_client 2>/dev/null | head -20

echo
echo_info "➕ Ajout d'un module supplémentaire (project)..."
./scripts/add_oca_module.sh demo_client project

echo
echo_success "🎉 Démonstration terminée !"
echo
echo_info "Le client 'demo_client' a été créé dans clients/demo_client"
echo_info "Vous pouvez :"
echo "  - Examiner la structure : cd clients/demo_client"
echo "  - Démarrer l'environnement : cd clients/demo_client && ./scripts/start.sh"
echo "  - Supprimer la démo : rm -rf clients/demo_client"
echo

read -p "🗑️  Supprimer le client de démonstration maintenant ? (y/N): " CLEANUP
if [[ "$CLEANUP" =~ ^[Yy]$ ]]; then
    rm -rf clients/demo_client
    echo_success "🧹 Client de démonstration supprimé"
else
    echo_warning "Client de démonstration conservé dans clients/demo_client"
fi

echo
echo_info "🎯 Pour créer un vrai client, utilisez : ./create_client.sh"

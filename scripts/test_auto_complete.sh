#!/bin/bash

# Script de test pour la fonction auto-complete
# Usage: ./test_auto_complete.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$ROOT_DIR/config"

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

# Sauvegarder le fichier original
echo_info "Sauvegarde du fichier original..."
cp "$CONFIG_DIR/oca_descriptions.json" "$CONFIG_DIR/oca_descriptions.json.backup.$(date +%Y%m%d_%H%M%S)"

# Utiliser le fichier de test
echo_info "Utilisation du fichier de test..."
cp "/tmp/test_oca_descriptions.json" "$CONFIG_DIR/oca_descriptions.json"

# Afficher l'état avant
echo_info "État avant auto-complete:"
$SCRIPT_DIR/manage_oca_descriptions.sh stats

echo
echo_info "Descriptions manquantes en français:"
$SCRIPT_DIR/manage_oca_descriptions.sh missing fr

echo
echo_warning "Lancement de l'auto-complete en français..."
echo_warning "Ceci va faire des appels aux APIs de traduction..."
read -p "Continuer ? (y/N) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Lancer auto-complete
    $SCRIPT_DIR/manage_oca_descriptions.sh auto-complete fr
    
    echo
    echo_info "État après auto-complete:"
    $SCRIPT_DIR/manage_oca_descriptions.sh stats
    
    echo
    echo_info "Contenu final du fichier:"
    cat "$CONFIG_DIR/oca_descriptions.json"
else
    echo_info "Test annulé"
fi

echo
echo_warning "ATTENTION: Le fichier de descriptions a été modifié pour le test."
echo_info "Pour restaurer l'original, exécutez: make update-oca-repos"

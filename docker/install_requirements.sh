#!/bin/bash

# Script pour installer les dépendances Python depuis requirements.txt

REQUIREMENTS_FILE="/mnt/requirements.txt"

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

# Vérifier si le fichier requirements.txt existe
if [ ! -f "$REQUIREMENTS_FILE" ]; then
    echo_warning "Fichier requirements.txt non trouvé dans /mnt/"
    echo_info "Aucune dépendance supplémentaire à installer"
    exit 0
fi

echo_info "📦 Installation des dépendances Python depuis requirements.txt..."

# Installer les dépendances avec pip (contournement PEP 668 pour conteneur)
if pip3 install --break-system-packages --user -r "$REQUIREMENTS_FILE"; then
    echo_success "✅ Dépendances installées avec succès"
else
    echo_error "❌ Erreur lors de l'installation des dépendances"
    exit 1
fi

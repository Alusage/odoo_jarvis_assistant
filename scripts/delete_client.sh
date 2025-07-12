#!/bin/bash

# Script pour supprimer un client
# Usage: delete_client.sh <client_name> [--force]

set -e

CLIENT_NAME="$1"
FORCE="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CLIENTS_DIR="$ROOT_DIR/clients"
CLIENT_DIR="$CLIENTS_DIR/$CLIENT_NAME"

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

# Gestion de l'aide
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $0 <client_name> [--force]"
    echo ""
    echo "Paramètres:"
    echo "  client_name  - Nom du client à supprimer"
    echo "  --force      - Supprimer sans demander confirmation (optionnel)"
    echo ""
    echo "Exemple: $0 mon_client"
    echo "Exemple: $0 mon_client --force"
    exit 0
fi

# Validation du nom du client
if [ -z "$CLIENT_NAME" ]; then
    echo_error "Nom du client requis"
    echo "Usage: $0 <client_name> [--force]"
    exit 1
fi

# Vérifier que le client existe
if [ ! -d "$CLIENT_DIR" ]; then
    echo_error "Client '$CLIENT_NAME' non trouvé dans $CLIENTS_DIR/"
    echo_info "Clients disponibles :"
    ls -1 "$CLIENTS_DIR" 2>/dev/null | sed 's/^/  - /' || echo "  Aucun client trouvé"
    exit 1
fi

echo_info "Client trouvé : $CLIENT_DIR"

# Afficher les informations du client
echo_info "Informations du client '$CLIENT_NAME' :"

# Compter les modules
MODULE_COUNT=0
if [ -d "$CLIENT_DIR/extra-addons" ]; then
    MODULE_COUNT=$(ls -1 "$CLIENT_DIR/extra-addons" 2>/dev/null | wc -l)
fi

# Compter les submodules
SUBMODULE_COUNT=0
if [ -f "$CLIENT_DIR/.gitmodules" ]; then
    SUBMODULE_COUNT=$(grep -c '\[submodule' "$CLIENT_DIR/.gitmodules" 2>/dev/null || echo 0)
fi

# Taille du répertoire
if command -v du >/dev/null 2>&1; then
    CLIENT_SIZE=$(du -sh "$CLIENT_DIR" 2>/dev/null | cut -f1 || echo "Unknown")
else
    CLIENT_SIZE="Unknown"
fi

echo "  📁 Chemin : $CLIENT_DIR"
echo "  📦 Modules liés : $MODULE_COUNT"
echo "  🔗 Submodules : $SUBMODULE_COUNT"
echo "  💾 Taille : $CLIENT_SIZE"

# Si template configuré, l'afficher
if [ -f "$CLIENT_DIR/.client_template" ]; then
    TEMPLATE=$(cat "$CLIENT_DIR/.client_template" 2>/dev/null || echo "Unknown")
    echo "  🎨 Template : $TEMPLATE"
fi

# Si version Odoo configurée, l'afficher
if [ -f "$CLIENT_DIR/config/odoo.conf" ]; then
    if grep -q "version" "$CLIENT_DIR/config/odoo.conf" 2>/dev/null; then
        VERSION=$(grep "version" "$CLIENT_DIR/config/odoo.conf" | cut -d'=' -f2 | tr -d ' ' 2>/dev/null || echo "Unknown")
        echo "  🔧 Version Odoo : $VERSION"
    fi
fi

echo ""

# Demander confirmation si --force n'est pas utilisé
if [ "$FORCE" != "--force" ]; then
    echo_warning "ATTENTION : Cette action va supprimer définitivement le client '$CLIENT_NAME'"
    echo_warning "Toutes les données, configurations et historique Git seront perdus !"
    echo ""
    read -p "Êtes-vous sûr de vouloir supprimer ce client ? (tapez 'SUPPRIMER' pour confirmer) : " confirmation
    
    if [ "$confirmation" != "SUPPRIMER" ]; then
        echo_info "Suppression annulée"
        exit 0
    fi
fi

echo_info "Suppression du client '$CLIENT_NAME' en cours..."

# Changer les permissions récursivement pour permettre la suppression
echo_info "Correction des permissions..."
if chmod -R u+w "$CLIENT_DIR" 2>/dev/null; then
    echo_info "Permissions corrigées"
else
    echo_warning "Impossible de corriger certaines permissions, tentative avec sudo si nécessaire"
fi

# Tenter la suppression normale d'abord
if rm -rf "$CLIENT_DIR" 2>/dev/null; then
    echo_success "Client '$CLIENT_NAME' supprimé avec succès !"
    echo_info "Le répertoire $CLIENT_DIR a été complètement supprimé"
elif command -v sudo >/dev/null 2>&1; then
    # Si échec, tenter avec sudo
    echo_warning "Suppression normale échouée, utilisation de sudo..."
    if sudo rm -rf "$CLIENT_DIR"; then
        echo_success "Client '$CLIENT_NAME' supprimé avec succès (avec sudo) !"
        echo_info "Le répertoire $CLIENT_DIR a été complètement supprimé"
    else
        echo_error "Erreur lors de la suppression du client '$CLIENT_NAME' même avec sudo"
        exit 1
    fi
else
    echo_error "Erreur lors de la suppression du client '$CLIENT_NAME'"
    echo_error "Permissions insuffisantes et sudo non disponible"
    echo_info "Essayez manuellement : sudo rm -rf '$CLIENT_DIR'"
    exit 1
fi

# Vérifier s'il reste des clients
REMAINING_CLIENTS=$(ls -1 "$CLIENTS_DIR" 2>/dev/null | wc -l || echo 0)
if [ "$REMAINING_CLIENTS" -eq 0 ]; then
    echo_info "Aucun client restant dans $CLIENTS_DIR"
else
    echo_info "Clients restants : $REMAINING_CLIENTS"
    echo "  $(ls -1 "$CLIENTS_DIR" 2>/dev/null | sed 's/^/  - /' || echo '  Aucun')"
fi
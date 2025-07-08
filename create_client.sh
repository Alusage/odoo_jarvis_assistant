#!/bin/bash

# Script principal pour créer un nouveau dépôt client
# Usage: ./create_client.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
TEMPLATES_DIR="$SCRIPT_DIR/templates"
CLIENTS_DIR="$SCRIPT_DIR/clients"

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction d'affichage coloré
echo_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
echo_success() { echo -e "${GREEN}✅ $1${NC}"; }
echo_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
echo_error() { echo -e "${RED}❌ $1${NC}"; }

# Fonction pour afficher le menu des templates
show_templates() {
    echo_info "Templates disponibles :"
    echo "1) basic      - Configuration de base"
    echo "2) ecommerce  - E-commerce complet"
    echo "3) manufacturing - Entreprise manufacturière"
    echo "4) services   - Entreprise de services"
    echo "5) custom     - Configuration personnalisée"
}

# Fonction pour afficher les versions Odoo disponibles
show_odoo_versions() {
    echo_info "Versions Odoo disponibles :"
    echo "1) 16.0"
    echo "2) 17.0" 
    echo "3) 18.0"
}

# Fonction pour valider le nom du client
validate_client_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo_error "Le nom du client doit contenir uniquement des lettres, chiffres, tirets et underscores"
        return 1
    fi
    if [ -d "$CLIENTS_DIR/$name" ]; then
        echo_error "Un client avec ce nom existe déjà"
        return 1
    fi
    return 0
}

# Fonction principale
main() {
    echo_info "🚀 Générateur de dépôt client Odoo"
    echo_info "=================================="
    echo

    # Demander le nom du client
    while true; do
        read -p "📝 Nom du client (ex: client_abc): " CLIENT_NAME
        if validate_client_name "$CLIENT_NAME"; then
            break
        fi
    done

    # Demander la version Odoo
    echo
    show_odoo_versions
    while true; do
        read -p "🔢 Choisissez la version Odoo (1-3): " VERSION_CHOICE
        case $VERSION_CHOICE in
            1) ODOO_VERSION="16.0"; break;;
            2) ODOO_VERSION="17.0"; break;;
            3) ODOO_VERSION="18.0"; break;;
            *) echo_error "Choix invalide";;
        esac
    done

    # Demander le template
    echo
    show_templates
    while true; do
        read -p "📋 Choisissez un template (1-5): " TEMPLATE_CHOICE
        case $TEMPLATE_CHOICE in
            1) TEMPLATE="basic"; break;;
            2) TEMPLATE="ecommerce"; break;;
            3) TEMPLATE="manufacturing"; break;;
            4) TEMPLATE="services"; break;;
            5) TEMPLATE="custom"; break;;
            *) echo_error "Choix invalide";;
        esac
    done

    # Demander si Odoo Enterprise est nécessaire
    echo
    read -p "🏢 Utiliser Odoo Enterprise ? (y/N): " USE_ENTERPRISE
    if [[ "$USE_ENTERPRISE" =~ ^[Yy]$ ]]; then
        HAS_ENTERPRISE=true
        echo_warning "N'oubliez pas d'ajouter manuellement le submodule enterprise après création"
    else
        HAS_ENTERPRISE=false
    fi

    # Récapitulatif
    echo
    echo_info "📋 Récapitulatif de la configuration :"
    echo "   Client: $CLIENT_NAME"
    echo "   Version Odoo: $ODOO_VERSION"
    echo "   Template: $TEMPLATE"
    echo "   Enterprise: $([ "$HAS_ENTERPRISE" = true ] && echo "Oui" || echo "Non")"
    echo

    read -p "⚡ Continuer avec cette configuration ? (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo_warning "Opération annulée"
        exit 0
    fi

    # Créer le dépôt client
    echo
    echo_info "🏗️  Création du dépôt client..."
    
    "$SCRIPT_DIR/scripts/generate_client_repo.sh" \
        "$CLIENT_NAME" \
        "$ODOO_VERSION" \
        "$TEMPLATE" \
        "$HAS_ENTERPRISE"

    echo
    echo_success "🎉 Dépôt client '$CLIENT_NAME' créé avec succès !"
    echo_info "📁 Emplacement: $CLIENTS_DIR/$CLIENT_NAME"
    echo_info "📝 Consultez le README.md du client pour les instructions d'utilisation"
}

# Vérifier les dépendances
if ! command -v jq &> /dev/null; then
    echo_error "jq est requis pour ce script. Installez-le avec: sudo apt-get install jq"
    exit 1
fi

# Créer les dossiers nécessaires
mkdir -p "$CLIENTS_DIR" "$CONFIG_DIR" "$TEMPLATES_DIR" "$SCRIPT_DIR/scripts"

# Lancer le script principal
main "$@"

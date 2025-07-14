#!/bin/bash

# Script principal pour créer un nouveau dépôt client
# Usage: ./create_client.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
TEMPLATES_DIR="$SCRIPT_DIR/templates"
CLIENTS_DIR="$SCRIPT_DIR/clients"

# Source des fonctions GitHub
source "$SCRIPT_DIR/scripts/github_operations.sh"

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction d'affichage coloré
echo_info() { echo -e "${BLUE}-  $1${NC}"; }
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

    # Demander l'intégration GitHub
    echo
    USE_GITHUB=false
    read -p "🐙 Intégrer avec GitHub ? (y/N): " GITHUB_CHOICE
    if [[ "$GITHUB_CHOICE" =~ ^[Yy]$ ]]; then
        USE_GITHUB=true
        
        # Vérifier si la configuration GitHub existe
        if ! verify_github_config; then
            echo_warning "Configuration GitHub manquante"
            read -p "📝 Voulez-vous configurer GitHub maintenant ? (y/N): " SETUP_GITHUB
            if [[ "$SETUP_GITHUB" =~ ^[Yy]$ ]]; then
                "$SCRIPT_DIR/scripts/setup_github.sh"
                if ! verify_github_config; then
                    echo_error "Configuration GitHub échouée"
                    USE_GITHUB=false
                fi
            else
                echo_info "Le client sera créé sans intégration GitHub"
                USE_GITHUB=false
            fi
        fi
        
        if [ "$USE_GITHUB" = true ]; then
            GITHUB_ORG=$(get_github_org)
            echo_info "🔍 Vérification du dépôt GitHub: $GITHUB_ORG/$CLIENT_NAME"
            echo_info "   URL sera: git@github.com:$GITHUB_ORG/$CLIENT_NAME.git"
            echo_info "   Branche: $ODOO_VERSION"
        fi
    fi

    # Récapitulatif
    echo
    echo_info "📋 Récapitulatif de la configuration :"
    echo "   Client: $CLIENT_NAME"
    echo "   Version Odoo: $ODOO_VERSION"
    echo "   Template: $TEMPLATE"
    echo "   Enterprise: $([ "$HAS_ENTERPRISE" = true ] && echo "Oui" || echo "Non")"
    echo "   GitHub: $([ "$USE_GITHUB" = true ] && echo "Oui ($GITHUB_ORG/$CLIENT_NAME)" || echo "Non")"
    echo

    read -p "⚡ Continuer avec cette configuration ? (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo_warning "Opération annulée"
        exit 0
    fi

    # Gestion GitHub et création du client
    echo
    GITHUB_CLONED=false
    
    if [ "$USE_GITHUB" = true ]; then
        echo_info "🐙 Gestion GitHub..."
        
        case $(manage_client_with_github "$CLIENT_NAME" "$ODOO_VERSION" "$TEMPLATE" "$CLIENTS_DIR") in
            0)
                echo_success "Client cloné depuis GitHub avec succès !"
                GITHUB_CLONED=true
                ;;
            2)
                echo_info "Dépôt GitHub n'existe pas, création locale puis push..."
                ;;
            *)
                echo_error "Erreur lors de la gestion GitHub"
                echo_info "Création locale sans GitHub..."
                USE_GITHUB=false
                ;;
        esac
    fi
    
    # Créer le client localement si pas cloné depuis GitHub
    if [ "$GITHUB_CLONED" = false ]; then
        echo_info "🏗️  Création du dépôt client..."
        
        "$SCRIPT_DIR/scripts/generate_client_repo.sh" \
            "$CLIENT_NAME" \
            "$ODOO_VERSION" \
            "$TEMPLATE" \
            "$HAS_ENTERPRISE"
        
        # Configuration GitHub post-création si demandée
        if [ "$USE_GITHUB" = true ]; then
            echo
            echo_info "🐙 Configuration GitHub post-création..."
            
            if post_create_github_setup "$CLIENT_NAME" "$ODOO_VERSION" "$CLIENTS_DIR/$CLIENT_NAME"; then
                echo_success "Client configuré avec GitHub !"
                echo_info "📤 Pour pousser sur GitHub:"
                echo_info "   cd $CLIENTS_DIR/$CLIENT_NAME"
                echo_info "   git push -u origin $ODOO_VERSION"
            else
                echo_warning "Configuration GitHub échouée, client créé en local uniquement"
            fi
        fi
    fi

    echo
    echo_success "🎉 Dépôt client '$CLIENT_NAME' créé avec succès !"
    echo_info "📁 Emplacement: $CLIENTS_DIR/$CLIENT_NAME"
    echo_info "📝 Consultez le README.md du client pour les instructions d'utilisation"
    
    if [ "$USE_GITHUB" = true ] && [ "$GITHUB_CLONED" = false ]; then
        echo_info "🐙 Dépôt GitHub: git@github.com:$GITHUB_ORG/$CLIENT_NAME.git"
        echo_info "🌿 Branche: $ODOO_VERSION"
    fi
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

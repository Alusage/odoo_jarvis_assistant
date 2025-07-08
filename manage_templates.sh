#!/bin/bash

# Script pour créer ou modifier des templates clients
# Usage: ./manage_templates.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config/templates.json"

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

# Vérifier que jq est installé
if ! command -v jq &> /dev/null; then
    echo_error "jq est requis pour ce script. Installez-le avec: sudo apt-get install jq"
    exit 1
fi

show_menu() {
    echo_info "🛠️  Gestionnaire de templates Odoo"
    echo_info "================================="
    echo
    echo "1) Lister les templates existants"
    echo "2) Lister les modules OCA disponibles"
    echo "3) Créer un nouveau template"
    echo "4) Modifier un template existant"
    echo "5) Ajouter un nouveau module OCA"
    echo "6) Supprimer un template"
    echo "7) Valider la configuration JSON"
    echo "8) Quitter"
    echo
}

list_templates() {
    echo_info "📋 Templates clients existants :"
    jq -r '.client_templates | to_entries[] | "  \(.key) - \(.value.description)"' "$CONFIG_FILE"
    echo
    
    echo_info "Détails des templates :"
    jq -r '.client_templates | to_entries[] | "
🏷️  Template: \(.key)
   Description: \(.value.description)
   Modules: \(.value.default_modules | join(", "))
"' "$CONFIG_FILE"
}

list_oca_modules() {
    echo_info "📦 Modules OCA disponibles :"
    jq -r '.oca_repositories | to_entries[] | "  \(.key) - \(.value.description)"' "$CONFIG_FILE"
}

create_template() {
    echo_info "➕ Création d'un nouveau template"
    echo
    
    read -p "Nom du template (ex: mon_template): " template_name
    if [[ ! "$template_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo_error "Le nom doit contenir uniquement des lettres, chiffres, tirets et underscores"
        return 1
    fi
    
    # Vérifier si le template existe déjà
    if jq -e ".client_templates.$template_name" "$CONFIG_FILE" >/dev/null 2>&1; then
        echo_error "Le template '$template_name' existe déjà"
        return 1
    fi
    
    read -p "Description du template: " template_desc
    
    echo
    echo_info "Modules OCA disponibles :"
    jq -r '.oca_repositories | to_entries[] | "  \(.key)"' "$CONFIG_FILE"
    echo
    echo_info "Entrez les modules souhaités (séparés par des espaces):"
    read -p "Modules: " modules_input
    
    # Convertir la liste de modules en tableau JSON
    modules_array=$(echo "$modules_input" | tr ' ' '\n' | jq -R -s 'split("\n") | map(select(length > 0))')
    
    # Ajouter le nouveau template
    jq ".client_templates.$template_name = {
        \"description\": \"$template_desc\",
        \"default_modules\": $modules_array
    }" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    
    echo_success "Template '$template_name' créé avec succès"
}

modify_template() {
    echo_info "✏️  Modification d'un template existant"
    echo
    
    echo_info "Templates disponibles :"
    jq -r '.client_templates | keys[]' "$CONFIG_FILE" | sed 's/^/  /'
    echo
    
    read -p "Nom du template à modifier: " template_name
    
    if ! jq -e ".client_templates.$template_name" "$CONFIG_FILE" >/dev/null 2>&1; then
        echo_error "Template '$template_name' non trouvé"
        return 1
    fi
    
    echo_info "Configuration actuelle :"
    jq ".client_templates.$template_name" "$CONFIG_FILE"
    echo
    
    current_desc=$(jq -r ".client_templates.$template_name.description" "$CONFIG_FILE")
    current_modules=$(jq -r ".client_templates.$template_name.default_modules | join(\" \")" "$CONFIG_FILE")
    
    read -p "Nouvelle description [$current_desc]: " new_desc
    new_desc=${new_desc:-$current_desc}
    
    echo
    echo_info "Modules actuels: $current_modules"
    echo_info "Modules OCA disponibles :"
    jq -r '.oca_repositories | to_entries[] | "  \(.key)"' "$CONFIG_FILE"
    echo
    read -p "Nouveaux modules [$current_modules]: " new_modules
    new_modules=${new_modules:-$current_modules}
    
    # Convertir en tableau JSON
    modules_array=$(echo "$new_modules" | tr ' ' '\n' | jq -R -s 'split("\n") | map(select(length > 0))')
    
    # Mettre à jour le template
    jq ".client_templates.$template_name = {
        \"description\": \"$new_desc\",
        \"default_modules\": $modules_array
    }" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    
    echo_success "Template '$template_name' modifié avec succès"
}

add_oca_module() {
    echo_info "➕ Ajout d'un nouveau module OCA"
    echo
    
    read -p "Clé du module (ex: my_module): " module_key
    if [[ ! "$module_key" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo_error "La clé doit contenir uniquement des lettres, chiffres, tirets et underscores"
        return 1
    fi
    
    # Vérifier si le module existe déjà
    if jq -e ".oca_repositories.$module_key" "$CONFIG_FILE" >/dev/null 2>&1; then
        echo_error "Le module '$module_key' existe déjà"
        return 1
    fi
    
    read -p "URL du dépôt GitHub (ex: https://github.com/OCA/my-module.git): " module_url
    read -p "Description du module: " module_desc
    
    # Ajouter le nouveau module
    jq ".oca_repositories.$module_key = {
        \"url\": \"$module_url\",
        \"description\": \"$module_desc\"
    }" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    
    echo_success "Module OCA '$module_key' ajouté avec succès"
}

delete_template() {
    echo_info "🗑️  Suppression d'un template"
    echo
    
    echo_info "Templates disponibles :"
    jq -r '.client_templates | keys[]' "$CONFIG_FILE" | sed 's/^/  /'
    echo
    
    read -p "Nom du template à supprimer: " template_name
    
    if ! jq -e ".client_templates.$template_name" "$CONFIG_FILE" >/dev/null 2>&1; then
        echo_error "Template '$template_name' non trouvé"
        return 1
    fi
    
    echo_warning "Configuration actuelle :"
    jq ".client_templates.$template_name" "$CONFIG_FILE"
    echo
    
    read -p "Êtes-vous sûr de vouloir supprimer ce template ? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo_warning "Suppression annulée"
        return 0
    fi
    
    # Supprimer le template
    jq "del(.client_templates.$template_name)" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    
    echo_success "Template '$template_name' supprimé avec succès"
}

validate_config() {
    echo_info "✅ Validation de la configuration JSON"
    
    if jq empty "$CONFIG_FILE" 2>/dev/null; then
        echo_success "Configuration JSON valide"
        
        # Vérifications supplémentaires
        echo_info "Vérifications supplémentaires :"
        
        # Vérifier que tous les modules des templates existent
        templates_valid=true
        while IFS= read -r template_name; do
            while IFS= read -r module; do
                if ! jq -e ".oca_repositories.$module" "$CONFIG_FILE" >/dev/null 2>&1; then
                    echo_error "  Template '$template_name' référence un module inexistant: '$module'"
                    templates_valid=false
                fi
            done < <(jq -r ".client_templates.$template_name.default_modules[]" "$CONFIG_FILE")
        done < <(jq -r '.client_templates | keys[]' "$CONFIG_FILE")
        
        if [ "$templates_valid" = true ]; then
            echo_success "  Toutes les références de modules sont valides"
        fi
        
        # Compter les éléments
        template_count=$(jq '.client_templates | length' "$CONFIG_FILE")
        module_count=$(jq '.oca_repositories | length' "$CONFIG_FILE")
        version_count=$(jq '.odoo_versions | length' "$CONFIG_FILE")
        
        echo_info "  📊 Statistiques :"
        echo_info "    - $version_count versions Odoo configurées"
        echo_info "    - $module_count modules OCA disponibles"
        echo_info "    - $template_count templates clients"
        
    else
        echo_error "Configuration JSON invalide !"
        echo_info "Erreurs détectées :"
        jq empty "$CONFIG_FILE"
    fi
}

# Boucle principale
while true; do
    echo
    show_menu
    read -p "Choisissez une option (1-8): " choice
    echo
    
    case $choice in
        1) list_templates ;;
        2) list_oca_modules ;;
        3) create_template ;;
        4) modify_template ;;
        5) add_oca_module ;;
        6) delete_template ;;
        7) validate_config ;;
        8) echo_info "Au revoir !"; exit 0 ;;
        *) echo_error "Option invalide" ;;
    esac
    
    echo
    read -p "Appuyez sur Entrée pour continuer..."
done

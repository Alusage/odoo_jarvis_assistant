#!/bin/bash

# Script de diagnostic pour le générateur de clients Odoo
# Usage: ./diagnostics.sh [client_name]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
CLIENTS_DIR="$SCRIPT_DIR/clients"

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

# Function to check system dependencies
check_dependencies() {
    echo_info "Vérification des dépendances système..."
    
    local missing_deps=()
    
    # Check required commands
    for cmd in git jq docker docker-compose; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
            echo_error "$cmd n'est pas installé"
        else
            echo_success "$cmd est disponible"
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo_error "Dépendances manquantes : ${missing_deps[*]}"
        echo_info "Installez les dépendances manquantes avec :"
        echo "  sudo apt update"
        for dep in "${missing_deps[@]}"; do
            case "$dep" in
                "jq")
                    echo "  sudo apt install jq"
                    ;;
                "docker")
                    echo "  curl -fsSL https://get.docker.com | sh"
                    ;;
                "docker-compose")
                    echo "  sudo apt install docker-compose"
                    ;;
                *)
                    echo "  sudo apt install $dep"
                    ;;
            esac
        done
        return 1
    else
        echo_success "Toutes les dépendances sont installées"
        return 0
    fi
}

# Function to check configuration files
check_configuration() {
    echo_info "Vérification de la configuration..."
    
    # Check if config directory exists
    if [[ ! -d "$CONFIG_DIR" ]]; then
        echo_error "Dossier de configuration manquant : $CONFIG_DIR"
        return 1
    fi
    
    # Check if templates.json exists
    if [[ ! -f "$CONFIG_DIR/templates.json" ]]; then
        echo_error "Fichier de configuration manquant : $CONFIG_DIR/templates.json"
        return 1
    fi
    
    # Validate JSON syntax
    if ! jq '.' "$CONFIG_DIR/templates.json" >/dev/null 2>&1; then
        echo_error "Format JSON invalide dans templates.json"
        return 1
    fi
    
    echo_success "Configuration valide"
    
    # Show configuration summary
    echo_info "Résumé de la configuration :"
    local versions=$(jq -r '.odoo_versions[].version' "$CONFIG_DIR/templates.json" | tr '\n' ' ')
    echo "  Versions Odoo : $versions"
    
    local templates=$(jq -r '.client_templates | keys[]' "$CONFIG_DIR/templates.json" | tr '\n' ' ')
    echo "  Templates : $templates"
    
    local oca_repos=$(jq -r '.oca_repositories | keys | length' "$CONFIG_DIR/templates.json")
    echo "  Dépôts OCA : $oca_repos"
    
    return 0
}

# Function to check scripts
check_scripts() {
    echo_info "Vérification des scripts..."
    
    local scripts=(
        "create_client.sh"
        "scripts/generate_client_repo.sh"
        "scripts/repository_optimizer.sh"
        "manage_templates.sh"
        "install_deps.sh"
    )
    
    local issues=0
    for script in "${scripts[@]}"; do
        local script_path="$SCRIPT_DIR/$script"
        if [[ ! -f "$script_path" ]]; then
            echo_error "Script manquant : $script"
            ((issues++))
        elif [[ ! -x "$script_path" ]]; then
            echo_warning "Script non exécutable : $script"
            echo_info "Correction : chmod +x $script_path"
        else
            echo_success "Script OK : $script"
        fi
    done
    
    if [[ $issues -eq 0 ]]; then
        echo_success "Tous les scripts sont présents"
        return 0
    else
        echo_error "$issues script(s) manquant(s)"
        return 1
    fi
}

# Function to check client repository
check_client() {
    local client_name="$1"
    
    if [[ -z "$client_name" ]]; then
        echo_error "Nom du client requis"
        return 1
    fi
    
    local client_dir="$CLIENTS_DIR/$client_name"
    
    if [[ ! -d "$client_dir" ]]; then
        echo_error "Client '$client_name' non trouvé dans $CLIENTS_DIR"
        return 1
    fi
    
    echo_info "Vérification du client '$client_name'..."
    
    cd "$client_dir"
    
    # Check if it's a git repository
    if [[ ! -d ".git" ]]; then
        echo_error "Le dossier client n'est pas un dépôt Git"
        return 1
    fi
    
    # Check submodules
    if [[ -f ".gitmodules" ]]; then
        local submodules_count=$(git submodule status | wc -l)
        echo_info "Submodules trouvés : $submodules_count"
        
        # Check submodule status
        local uninitialized=0
        local modified=0
        local clean=0
        
        while IFS= read -r line; do
            if [[ $line =~ ^- ]]; then
                ((uninitialized++))
            elif [[ $line =~ ^\+ ]]; then
                ((modified++))
            else
                ((clean++))
            fi
        done < <(git submodule status)
        
        echo "  - Propres : $clean"
        if [[ $modified -gt 0 ]]; then
            echo_warning "  - Modifiés : $modified"
        fi
        if [[ $uninitialized -gt 0 ]]; then
            echo_warning "  - Non initialisés : $uninitialized"
            echo_info "    Exécutez : git submodule update --init --recursive"
        fi
    else
        echo_info "Aucun submodule configuré"
    fi
    
    # Check required files
    local required_files=(
        "README.md"
        "docker-compose.yml"
        "config/odoo.conf"
        "requirements.txt"
    )
    
    local missing_files=()
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            missing_files+=("$file")
        fi
    done
    
    if [[ ${#missing_files[@]} -eq 0 ]]; then
        echo_success "Tous les fichiers requis sont présents"
    else
        echo_warning "Fichiers manquants : ${missing_files[*]}"
    fi
    
    # Check Docker configuration
    if [[ -f "docker-compose.yml" ]]; then
        if docker-compose config >/dev/null 2>&1; then
            echo_success "Configuration Docker valide"
        else
            echo_error "Configuration Docker invalide"
        fi
    fi
    
    return 0
}

# Function to run full system check
run_full_check() {
    echo_info "=== Diagnostic complet du système ==="
    echo ""
    
    local all_good=true
    
    if ! check_dependencies; then
        all_good=false
    fi
    echo ""
    
    if ! check_configuration; then
        all_good=false
    fi
    echo ""
    
    if ! check_scripts; then
        all_good=false
    fi
    echo ""
    
    # Check repository optimizer cache
    source "$SCRIPT_DIR/scripts/repository_optimizer.sh"
    show_cache_status
    echo ""
    
    # List existing clients
    if [[ -d "$CLIENTS_DIR" ]]; then
        local clients=($(ls -1 "$CLIENTS_DIR" 2>/dev/null || true))
        if [[ ${#clients[@]} -gt 0 ]]; then
            echo_info "Clients existants :"
            for client in "${clients[@]}"; do
                echo "  - $client"
            done
        else
            echo_info "Aucun client créé"
        fi
    else
        echo_info "Dossier clients non créé"
    fi
    echo ""
    
    if $all_good; then
        echo_success "=== Système prêt à utiliser ==="
    else
        echo_error "=== Problèmes détectés - voir les messages ci-dessus ==="
    fi
}

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS] [CLIENT_NAME]"
    echo ""
    echo "Options:"
    echo "  -f, --full           Diagnostic complet du système"
    echo "  -d, --deps           Vérifier les dépendances uniquement"
    echo "  -c, --config         Vérifier la configuration uniquement"
    echo "  -s, --scripts        Vérifier les scripts uniquement"
    echo "  -h, --help           Afficher cette aide"
    echo ""
    echo "Arguments:"
    echo "  CLIENT_NAME          Nom du client à vérifier"
    echo ""
    echo "Exemples:"
    echo "  $0 --full                    # Diagnostic complet"
    echo "  $0 mon_client               # Vérifier un client spécifique"
    echo "  $0 --deps                   # Vérifier seulement les dépendances"
}

# Main function
main() {
    case "${1:-}" in
        "-f"|"--full")
            run_full_check
            ;;
        "-d"|"--deps")
            check_dependencies
            ;;
        "-c"|"--config")
            check_configuration
            ;;
        "-s"|"--scripts")
            check_scripts
            ;;
        "-h"|"--help"|"help")
            show_help
            ;;
        "")
            run_full_check
            ;;
        *)
            check_client "$1"
            ;;
    esac
}

# Execute main function
main "$@"

#!/bin/bash

# Script d'installation des dépendances pour le générateur de clients Odoo
# Usage: ./install_deps.sh

set -e

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

echo_info "📦 Installation des dépendances pour le générateur de clients Odoo"
echo_info "================================================================="
echo

# Vérifier le système d'exploitation
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if command -v apt-get >/dev/null 2>&1; then
        OS="debian"
    elif command -v yum >/dev/null 2>&1; then
        OS="redhat"
    elif command -v pacman >/dev/null 2>&1; then
        OS="arch"
    else
        OS="unknown"
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
else
    OS="unknown"
fi

echo_info "Système détecté : $OS"

# Fonction d'installation selon l'OS
install_debian() {
    echo_info "Installation pour Debian/Ubuntu..."
    sudo apt-get update
    sudo apt-get install -y git jq make tree curl
}

install_redhat() {
    echo_info "Installation pour RedHat/CentOS/Fedora..."
    sudo yum install -y git jq make tree curl
}

install_arch() {
    echo_info "Installation pour Arch Linux..."
    sudo pacman -S git jq make tree curl
}

install_macos() {
    echo_info "Installation pour macOS..."
    if ! command -v brew >/dev/null 2>&1; then
        echo_warning "Homebrew non détecté. Installation de Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    brew install git jq make tree curl
}

# Vérifier les dépendances existantes
check_dependency() {
    local cmd="$1"
    local name="$2"
    
    if command -v "$cmd" >/dev/null 2>&1; then
        echo_success "$name déjà installé ($(which $cmd))"
        return 0
    else
        echo_warning "$name non trouvé"
        return 1
    fi
}

echo_info "Vérification des dépendances actuelles..."
echo

check_dependency "git" "Git"
check_dependency "jq" "jq"
check_dependency "make" "Make"
check_dependency "tree" "Tree"
check_dependency "curl" "Curl"
check_dependency "docker" "Docker"
check_dependency "docker-compose" "Docker Compose"

echo

# Installer les dépendances manquantes
case $OS in
    "debian")
        install_debian
        ;;
    "redhat")
        install_redhat
        ;;
    "arch")
        install_arch
        ;;
    "macos")
        install_macos
        ;;
    *)
        echo_error "Système d'exploitation non supporté automatiquement"
        echo_info "Veuillez installer manuellement : git, jq, make, tree, curl"
        echo_info "Et Docker + Docker Compose selon votre distribution"
        exit 1
        ;;
esac

echo
echo_info "Vérification post-installation..."

# Vérifier à nouveau les dépendances
all_good=true
for cmd in git jq make tree curl; do
    if ! check_dependency "$cmd" "$cmd"; then
        all_good=false
    fi
done

# Vérification spéciale pour Docker
echo
echo_info "Vérification de Docker..."
if command -v docker >/dev/null 2>&1; then
    if docker --version >/dev/null 2>&1; then
        echo_success "Docker installé : $(docker --version)"
    else
        echo_warning "Docker trouvé mais ne fonctionne pas (permissions ?)"
        echo_info "Essayez : sudo usermod -aG docker \$USER && newgrp docker"
        all_good=false
    fi
else
    echo_warning "Docker non trouvé - installation manuelle requise"
    echo_info "Suivez : https://docs.docker.com/engine/install/"
    all_good=false
fi

if command -v docker-compose >/dev/null 2>&1; then
    echo_success "Docker Compose installé : $(docker-compose --version)"
elif docker compose version >/dev/null 2>&1; then
    echo_success "Docker Compose (v2) installé : $(docker compose version)"
else
    echo_warning "Docker Compose non trouvé - installation manuelle requise"
    echo_info "Suivez : https://docs.docker.com/compose/install/"
    all_good=false
fi

echo
if [ "$all_good" = true ]; then
    echo_success "🎉 Toutes les dépendances sont installées et fonctionnelles !"
    echo_info "Vous pouvez maintenant utiliser : ./create_client.sh"
    echo_info "Ou tester avec : ./demo.sh"
else
    echo_warning "⚠️  Certaines dépendances nécessitent une attention manuelle"
    echo_info "Consultez les messages ci-dessus pour les instructions"
fi

echo
echo_info "Dépendances requises :"
echo "  ✓ git - Gestion des dépôts et submodules"
echo "  ✓ jq - Traitement des fichiers JSON"
echo "  ✓ make - Commandes simplifiées (optionnel)"
echo "  ✓ tree - Affichage arborescent (optionnel)"
echo "  ✓ curl - Téléchargements (optionnel)"
echo "  ⚠ docker - Exécution des environnements Odoo"
echo "  ⚠ docker-compose - Orchestration des services"

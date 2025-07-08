#!/bin/bash

# Script de tests pour le générateur de clients Odoo
# Usage: ./test.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
echo_success() { echo -e "${GREEN}✅ $1${NC}"; }
echo_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
echo_error() { echo -e "${RED}❌ $1${NC}"; }

# Compteurs
tests_total=0
tests_passed=0
tests_failed=0

# Fonction de test
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    tests_total=$((tests_total + 1))
    echo_info "Test #$tests_total: $test_name"
    
    if eval "$test_command"; then
        echo_success "  ✓ Passé"
        tests_passed=$((tests_passed + 1))
    else
        echo_error "  ✗ Échoué"
        tests_failed=$((tests_failed + 1))
    fi
    echo
}

# Nettoyage avant tests
cleanup() {
    rm -rf clients/test_* 2>/dev/null || true
}

echo_info "🧪 Tests du générateur de clients Odoo"
echo_info "====================================="
echo

# Tests des prérequis
echo_info "Phase 1: Vérification des prérequis"
echo "----------------------------------------"

run_test "Git disponible" "command -v git >/dev/null 2>&1"
run_test "jq disponible" "command -v jq >/dev/null 2>&1"
run_test "Configuration JSON valide" "jq empty config/templates.json"

# Tests de structure
echo_info "Phase 2: Vérification de la structure"
echo "--------------------------------------"

run_test "Script principal exécutable" "test -x create_client.sh"
run_test "Générateur de dépôt exécutable" "test -x scripts/generate_client_repo.sh"
run_test "Configuration templates présente" "test -f config/templates.json"
run_test "Makefile présent" "test -f Makefile"

# Tests fonctionnels
echo_info "Phase 3: Tests fonctionnels"
echo "----------------------------"

cleanup

# Test de création d'un client basic
run_test "Création client template basic" "
    ./scripts/generate_client_repo.sh 'test_basic' '18.0' 'basic' 'false' >/dev/null 2>&1 &&
    test -d clients/test_basic &&
    test -f clients/test_basic/README.md &&
    test -f clients/test_basic/docker-compose.yml
"

# Test de création d'un client ecommerce
run_test "Création client template ecommerce" "
    ./scripts/generate_client_repo.sh 'test_ecommerce' '17.0' 'ecommerce' 'true' >/dev/null 2>&1 &&
    test -d clients/test_ecommerce &&
    test -d clients/test_ecommerce/addons/enterprise
"

# Test de liste des modules
run_test "Liste modules disponibles" "
    ./scripts/list_available_modules.sh test_basic >/dev/null 2>&1
"

# Test d'ajout de module
run_test "Ajout module OCA" "
    cd clients/test_basic &&
    ../../scripts/add_oca_module.sh test_basic project >/dev/null 2>&1 &&
    test -d addons/oca_project
"

# Test de mise à jour
run_test "Mise à jour submodules" "
    ./scripts/update_client_submodules.sh test_basic >/dev/null 2>&1
"

# Tests de validation
echo_info "Phase 4: Tests de validation"
echo "-----------------------------"

run_test "Configuration Odoo valide" "
    test -f clients/test_basic/config/odoo.conf &&
    grep -q 'addons_path' clients/test_basic/config/odoo.conf
"

run_test "Docker Compose valide" "
    cd clients/test_basic &&
    docker-compose config >/dev/null 2>&1
"

run_test "Scripts client exécutables" "
    test -x clients/test_basic/scripts/start.sh &&
    test -x clients/test_basic/scripts/update_submodules.sh &&
    test -x clients/test_basic/scripts/link_modules.sh
"

run_test "Git repository initialisé" "
    cd clients/test_basic &&
    git status >/dev/null 2>&1
"

# Tests des commandes make
echo_info "Phase 5: Tests des commandes Make"
echo "----------------------------------"

run_test "make list-clients" "make list-clients >/dev/null 2>&1"
run_test "make status" "make status >/dev/null 2>&1"

# Tests de régression
echo_info "Phase 6: Tests de régression"
echo "-----------------------------"

run_test "Template JSON contient basic" "
    jq -e '.client_templates.basic' config/templates.json >/dev/null 2>&1
"

run_test "Modules OCA configurés" "
    test \$(jq '.oca_repositories | length' config/templates.json) -gt 5
"

run_test "Versions Odoo configurées" "
    jq -e '.odoo_versions.\"16.0\"' config/templates.json >/dev/null 2>&1 &&
    jq -e '.odoo_versions.\"17.0\"' config/templates.json >/dev/null 2>&1 &&
    jq -e '.odoo_versions.\"18.0\"' config/templates.json >/dev/null 2>&1
"

# Nettoyage après tests
cleanup

# Résultats
echo_info "Résultats des tests"
echo "==================="
echo
echo_info "Total: $tests_total tests"
echo_success "Passés: $tests_passed"
if [ $tests_failed -gt 0 ]; then
    echo_error "Échoués: $tests_failed"
    echo
    echo_error "❌ Certains tests ont échoué"
    echo_warning "Vérifiez les dépendances avec: ./install_deps.sh"
    exit 1
else
    echo_error "Échoués: $tests_failed"
    echo
    echo_success "🎉 Tous les tests sont passés !"
    echo_info "Le générateur de clients est prêt à être utilisé"
    echo
    echo_info "Commandes disponibles :"
    echo "  ./create_client.sh       - Créer un nouveau client"
    echo "  ./demo.sh               - Démonstration complète"
    echo "  make help               - Afficher toutes les commandes"
    echo "  ./manage_templates.sh   - Gérer les templates"
fi

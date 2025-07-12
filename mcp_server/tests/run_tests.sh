#!/bin/bash

# Script pour lancer les tests du serveur MCP
# Usage: ./tests/run_tests.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCP_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$MCP_DIR")"

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

echo_info "Lancement des tests du serveur MCP..."
echo_info "Répertoire racine: $ROOT_DIR"
echo

# Vérifier que Python 3 est disponible
if ! command -v python3 >/dev/null 2>&1; then
    echo_error "Python 3 requis mais non trouvé"
    exit 1
fi

# Vérifier que la bibliothèque MCP est installée
if ! python3 -c "import mcp" >/dev/null 2>&1; then
    echo_warning "Bibliothèque MCP non trouvée"
    echo_info "Installation automatique..."
    pip install mcp || {
        echo_error "Impossible d'installer la bibliothèque MCP"
        echo_info "Installez manuellement avec: pip install mcp"
        exit 1
    }
fi

# Vérifier que le serveur MCP existe
if [ ! -f "$MCP_DIR/mcp_server.py" ]; then
    echo_error "Serveur MCP non trouvé: $MCP_DIR/mcp_server.py"
    exit 1
fi

# Lancer les tests
echo_info "Exécution des tests..."
cd "$ROOT_DIR"

if python3 "$SCRIPT_DIR/test_mcp_server.py"; then
    echo
    echo_success "Tous les tests sont passés avec succès!"
    echo_info "Le serveur MCP est prêt à être utilisé"
    exit 0
else
    echo
    echo_error "Certains tests ont échoué"
    echo_warning "Vérifiez les erreurs ci-dessus avant de déployer"
    exit 1
fi
#!/bin/bash

# Script de développement pour le serveur MCP
# Usage: ./dev_mcp.sh [command]

set -e

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

COMMAND="${1:-help}"

case "$COMMAND" in
    "test"|"t")
        echo_info "Lancement des tests MCP..."
        ./tests/run_tests.sh
        ;;
    
    "test-watch"|"tw")
        echo_info "Mode surveillance des tests MCP..."
        echo_warning "Appuyez sur Ctrl+C pour arrêter"
        
        # Fonction pour lancer les tests
        run_tests() {
            echo
            echo_info "🔄 Relancement des tests..."
            ./tests/run_tests.sh 2>/dev/null || echo_error "Tests échoués"
            echo_info "Surveillance active... (modifiez mcp_server.py)"
        }
        
        # Tests initiaux
        run_tests
        
        # Surveillance des fichiers
        if command -v inotifywait >/dev/null 2>&1; then
            while inotifywait -e modify mcp_server.py tests/test_mcp_server.py 2>/dev/null; do
                run_tests
            done
        else
            echo_warning "inotifywait non installé, surveillez manuellement"
            echo_info "Installez avec: sudo apt-get install inotify-tools"
        fi
        ;;
    
    "syntax"|"s")
        echo_info "Vérification de la syntaxe..."
        if python3 -m py_compile mcp_server.py; then
            echo_success "Syntaxe correcte"
        else
            echo_error "Erreur de syntaxe"
            exit 1
        fi
        ;;
    
    "debug"|"d")
        echo_info "Démarrage en mode debug..."
        echo_warning "Le serveur va se lancer et attendre des connexions"
        echo_info "Connectez Claude Desktop ou appuyez sur Ctrl+C"
        python3 mcp_server.py ../
        ;;
    
    "restart-claude"|"rc")
        echo_info "Instructions pour redémarrer Claude Desktop..."
        echo "1. Fermez complètement Claude Desktop"
        echo "2. Attendez 5-10 secondes"
        echo "3. Relancez Claude Desktop"
        echo "4. Vérifiez la connexion MCP"
        ;;
    
    "config"|"c")
        echo_info "Configuration Claude Desktop actuelle:"
        cat ~/.config/Claude/claude_desktop_config.json | jq . || {
            echo_error "Fichier de configuration non trouvé ou invalide"
            echo_info "Chemin: ~/.config/Claude/claude_desktop_config.json"
        }
        ;;
    
    "status"|"st")
        echo_info "Statut du serveur MCP..."
        
        # Vérifier les processus
        if pgrep -f "mcp_server.py" >/dev/null; then
            echo_success "Serveur MCP en cours d'exécution"
            ps aux | grep mcp_server.py | grep -v grep
        else
            echo_warning "Aucun serveur MCP en cours"
        fi
        
        # Vérifier la configuration
        if [ -f ~/.config/Claude/claude_desktop_config.json ]; then
            echo_success "Configuration Claude Desktop trouvée"
        else
            echo_error "Configuration Claude Desktop manquante"
        fi
        
        # Tests rapides
        echo_info "Test rapide de la syntaxe..."
        if python3 -m py_compile mcp_server.py; then
            echo_success "Syntaxe MCP correcte"
        else
            echo_error "Erreur de syntaxe MCP"
        fi
        ;;
    
    "clean"|"cl")
        echo_info "Nettoyage des processus MCP..."
        pkill -f "mcp_server.py" 2>/dev/null && echo_success "Processus MCP arrêtés" || echo_info "Aucun processus MCP à arrêter"
        ;;
    
    "full-test"|"ft")
        echo_info "Tests complets du serveur MCP..."
        
        # 1. Syntaxe
        echo_info "1. Vérification syntaxe..."
        python3 -m py_compile mcp_server.py
        
        # 2. Tests unitaires
        echo_info "2. Tests unitaires..."
        ./tests/run_tests.sh
        
        # 3. Test de démarrage
        echo_info "3. Test de démarrage..."
        timeout 3 python3 mcp_server.py ../ >/dev/null 2>&1 && echo_success "Démarrage OK" || echo_warning "Timeout de démarrage (normal)"
        
        echo_success "Tests complets terminés !"
        ;;
    
    "help"|"h"|*)
        echo "🛠️  Script de développement serveur MCP"
        echo
        echo "Usage: $0 [command]"
        echo
        echo "Commandes disponibles:"
        echo "  test, t           - Lancer les tests MCP"
        echo "  test-watch, tw    - Mode surveillance des tests"
        echo "  syntax, s         - Vérifier la syntaxe"
        echo "  debug, d          - Démarrer en mode debug"
        echo "  restart-claude, rc - Instructions redémarrage Claude"
        echo "  config, c         - Afficher la configuration"
        echo "  status, st        - Statut du serveur"
        echo "  clean, cl         - Nettoyer les processus"
        echo "  full-test, ft     - Tests complets"
        echo "  help, h           - Cette aide"
        echo
        echo "Exemples:"
        echo "  $0 test           # Lancer les tests"
        echo "  $0 tw             # Mode surveillance"
        echo "  $0 ft             # Tests complets"
        ;;
esac
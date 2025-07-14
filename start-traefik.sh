#!/bin/bash

# Script pour démarrer Traefik et la stack d'infrastructure
# Usage: ./start-traefik.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
echo_success() { echo -e "${GREEN}✅ $1${NC}"; }
echo_error() { echo -e "${RED}❌ $1${NC}"; }

cd "$SCRIPT_DIR"

echo_info "Démarrage de l'infrastructure Traefik..."

# Nettoyer le réseau existant si nécessaire (créé manuellement)
if docker network ls | grep -q "traefik-local"; then
    echo_info "Suppression de l'ancien réseau traefik-local..."
    docker network rm traefik-local 2>/dev/null || true
fi

# Démarrer Traefik
echo_info "Démarrage de Traefik..."
docker compose up -d

# Attendre que Traefik soit prêt
echo_info "Attente du démarrage de Traefik..."
sleep 5

# Vérifier que Traefik fonctionne
if curl -s http://localhost:8080/api/overview >/dev/null; then
    echo_success "Traefik est opérationnel !"
    echo_info "Dashboard Traefik: http://localhost:8080"
    echo_info "Traefik HTTP: http://localhost:8090"
else
    echo_error "Traefik ne répond pas. Vérifiez les logs avec 'docker compose logs traefik'"
    exit 1
fi

echo_info "Pour démarrer un client Odoo :"
echo_info "  cd clients/[nom_client]"
echo_info "  docker compose up -d"
echo_info "  Accès via: http://localhost:8090 avec Host header 'dev.[nom_client].localhost'"
echo_info "  Ou configurez dev.[nom_client].localhost dans /etc/hosts"
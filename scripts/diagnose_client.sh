#!/bin/bash

# Script de diagnostic simplifié pour les clients Odoo
# Usage: diagnose_client_simple.sh <client_name> [--format json|text] [--verbose]

set -e

# Variables globales
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CLIENTS_DIR="$ROOT_DIR/clients"

# Couleurs pour la sortie
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Variables de configuration
CLIENT_NAME="$1"
OUTPUT_FORMAT="${2:-text}"
VERBOSE="${3:-false}"
TRAEFIK_PORT=8090

echo_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
echo_success() { echo -e "${GREEN}✅ $1${NC}"; }
echo_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
echo_error() { echo -e "${RED}❌ $1${NC}"; }

# Vérification des paramètres
if [ -z "$CLIENT_NAME" ]; then
    echo_error "Usage: $0 <client_name> [json|text] [verbose]"
    exit 1
fi

client_dir="$CLIENTS_DIR/$CLIENT_NAME"

echo_info "🔍 Diagnostic du client '$CLIENT_NAME'..."
echo

# 1. Vérifier l'existence du client
echo_info "📁 Vérification de l'existence du client..."
if [ ! -d "$client_dir" ]; then
    echo_error "Client '$CLIENT_NAME' non trouvé dans $client_dir"
    exit 3
fi

if [ ! -f "$client_dir/docker-compose.yml" ]; then
    echo_error "Configuration Docker manquante ($client_dir/docker-compose.yml)"
    exit 2
fi

echo_success "Client trouvé dans $client_dir"

# 2. Vérifier Docker
echo_info "🐳 Vérification des conteneurs Docker..."
cd "$client_dir"

if ! command -v docker >/dev/null 2>&1; then
    echo_error "Docker non installé"
    exit 3
fi

# Lister les conteneurs
containers=$(docker compose ps 2>/dev/null || echo "")

if [ -z "$containers" ]; then
    echo_error "Aucun conteneur trouvé - le projet n'est pas démarré"
    echo_info "💡 Pour démarrer: cd $client_dir && docker compose up -d"
    exit 2
fi

# Compter les conteneurs
container_count=$(echo "$containers" | grep -c "$CLIENT_NAME" 2>/dev/null | tr -d '\n' || echo "0")
running_containers=$(docker compose ps 2>/dev/null | grep -c "Up" 2>/dev/null | tr -d '\n' || echo "0")

echo_success "Conteneurs: $container_count trouvés, $running_containers en cours d'exécution"

# 3. Vérifier PostgreSQL
echo_info "🗄️ Vérification de PostgreSQL..."
pg_container="postgresql-$CLIENT_NAME"

if docker inspect "$pg_container" >/dev/null 2>&1; then
    pg_status=$(docker inspect "$pg_container" --format='{{.State.Status}}')
    if [ "$pg_status" = "running" ]; then
        # Test de connectivité
        pg_ready=$(docker compose exec -T "$pg_container" pg_isready -U odoo 2>/dev/null || echo "failed")
        if [[ "$pg_ready" == *"accepting connections"* ]]; then
            echo_success "PostgreSQL fonctionne et accepte les connexions"
        else
            echo_warning "PostgreSQL en cours d'exécution mais n'accepte pas les connexions"
        fi
    else
        echo_error "PostgreSQL n'est pas en cours d'exécution (état: $pg_status)"
    fi
else
    echo_error "Conteneur PostgreSQL '$pg_container' non trouvé"
fi

# 4. Vérifier Odoo
echo_info "🌐 Vérification d'Odoo..."
odoo_container="odoo-$CLIENT_NAME"

if docker inspect "$odoo_container" >/dev/null 2>&1; then
    odoo_status=$(docker inspect "$odoo_container" --format='{{.State.Status}}')
    if [ "$odoo_status" = "running" ]; then
        # Test de santé
        health_check=$(docker compose exec -T odoo curl -sf http://localhost:8069/web/health 2>/dev/null || echo "failed")
        if [[ "$health_check" == *'"status": "pass"'* ]]; then
            echo_success "Odoo fonctionne et répond au health check"
        else
            echo_warning "Odoo en cours d'exécution mais ne répond pas au health check"
        fi
    else
        echo_error "Odoo n'est pas en cours d'exécution (état: $odoo_status)"
    fi
else
    echo_error "Conteneur Odoo '$odoo_container' non trouvé"
fi

# 5. Vérifier Traefik
echo_info "🔀 Vérification de Traefik..."
traefik_running=$(docker ps --filter "name=traefik" --format "{{.Names}}" | head -1)

if [ -n "$traefik_running" ]; then
    # Test de routage
    client_host="dev.$CLIENT_NAME.localhost"
    routing_test=$(curl -H "Host: $client_host" -sf http://localhost:$TRAEFIK_PORT/web/health 2>/dev/null || echo "failed")
    
    if [[ "$routing_test" == *'"status": "pass"'* ]]; then
        echo_success "Traefik fonctionne et route correctement vers $client_host"
    else
        echo_warning "Traefik fonctionne mais problème de routage vers $client_host"
    fi
else
    echo_error "Traefik non trouvé ou non en cours d'exécution"
fi

# 6. Vérifier l'espace disque
echo_info "💾 Vérification de l'espace disque..."
disk_usage=$(df "$client_dir" | awk 'NR==2 {print $5}' | sed 's/%//')
disk_available=$(df -h "$client_dir" | awk 'NR==2 {print $4}')

if [ "$disk_usage" -gt 90 ]; then
    echo_error "Espace disque critique: ${disk_usage}% utilisé, $disk_available disponible"
elif [ "$disk_usage" -gt 80 ]; then
    echo_warning "Espace disque faible: ${disk_usage}% utilisé, $disk_available disponible"
else
    echo_success "Espace disque suffisant: ${disk_usage}% utilisé, $disk_available disponible"
fi

# 7. Test de connectivité final
echo_info "🌍 Test de connectivité final..."
final_test=$(curl -H "Host: dev.$CLIENT_NAME.localhost" -sf http://localhost:$TRAEFIK_PORT/ 2>/dev/null || echo "failed")

if [ "$final_test" != "failed" ]; then
    echo_success "✅ Client '$CLIENT_NAME' accessible via http://dev.$CLIENT_NAME.localhost"
else
    echo_error "❌ Client '$CLIENT_NAME' non accessible via Traefik"
fi

echo
echo "📊 Résumé du diagnostic"
echo "=========================="
echo "• Client: $CLIENT_NAME"
echo "• Conteneurs: $container_count ($running_containers actifs)"
echo "• Espace disque: ${disk_usage}% utilisé"
echo "• URL: http://dev.$CLIENT_NAME.localhost"

# Recommandations en cas de problème
if [ "$running_containers" -eq 0 ]; then
    echo
    echo "🛠️ Actions recommandées:"
    echo "• Démarrer les services: cd $client_dir && docker compose up -d"
elif [ "$final_test" = "failed" ]; then
    echo
    echo "🛠️ Actions recommandées:"
    echo "• Vérifier les logs: cd $client_dir && docker compose logs"
    echo "• Redémarrer les services: docker compose restart"
fi
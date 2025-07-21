#!/bin/bash

# Script de démarrage d'un service Docker pour une branche spécifique
# Usage: ./start_client_branch.sh CLIENT BRANCH [options]

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

# Variables
CLIENT=""
BRANCH=""
DETACH=true
BUILD=false

# Détection automatique du répertoire de base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$SCRIPT_DIR" == */clients/*/scripts ]]; then
    # Exécuté depuis un répertoire client
    BASE_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
    CLIENT_NAME="$(basename "$(dirname "$SCRIPT_DIR")")"
    echo_info "🏠 Détecté: exécution depuis le répertoire client '$CLIENT_NAME'"
elif [[ "$SCRIPT_DIR" == */scripts ]]; then
    # Exécuté depuis le répertoire principal
    BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    CLIENT_NAME=""
    echo_info "🏠 Détecté: exécution depuis le répertoire principal"
else
    BASE_DIR="$(pwd)"
    CLIENT_NAME=""
fi

# Aide
show_help() {
    if [[ -n "$CLIENT_NAME" ]]; then
        echo "Usage: $0 [BRANCH] [options]  (client détecté: $CLIENT_NAME)"
        echo ""
        echo "Arguments:"
        echo "  BRANCH     Nom de la branche (défaut: branche actuelle)"
    else
        echo "Usage: $0 CLIENT BRANCH [options]"
        echo ""
        echo "Arguments:"
        echo "  CLIENT     Nom du client (ex: testclient)"
        echo "  BRANCH     Nom de la branche (ex: dev-test-001)"
    fi
    echo ""
    echo "Options:"
    echo "  --build    Builder l'image avant de démarrer"
    echo "  --attach   Démarrer en mode attaché (voir les logs)"
    echo "  --help     Afficher cette aide"
    echo ""
    echo "Exemples:"
    if [[ -n "$CLIENT_NAME" ]]; then
        echo "  $0 dev-test-001              # Démarrer branche spécifique"
        echo "  $0                           # Démarrer branche actuelle"
        echo "  $0 main --build              # Builder puis démarrer"
    else
        echo "  $0 testclient dev-test-001"
        echo "  $0 testclient main --build"
    fi
}

# Parsing des arguments selon le contexte
if [[ -n "$CLIENT_NAME" ]]; then
    CLIENT="$CLIENT_NAME"
    if [[ $# -ge 1 && "$1" != --* ]]; then
        BRANCH="$1"
        shift 1
    else
        # Utiliser la branche actuelle
        if [[ -d "$BASE_DIR/clients/$CLIENT/.git" ]]; then
            cd "$BASE_DIR/clients/$CLIENT"
            BRANCH=$(git branch --show-current)
            cd - >/dev/null
        else
            echo_error "Impossible de déterminer la branche actuelle"
            exit 1
        fi
    fi
else
    if [[ $# -lt 2 ]]; then
        echo_error "Arguments manquants"
        show_help
        exit 1
    fi
    CLIENT="$1"
    BRANCH="$2"
    shift 2
fi

# Gestion des options
while [[ $# -gt 0 ]]; do
    case $1 in
        --build)
            BUILD=true
            shift
            ;;
        --attach)
            DETACH=false
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo_error "Option inconnue: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validation
CLIENT_DIR="$BASE_DIR/clients/$CLIENT"
if [[ ! -d "$CLIENT_DIR" ]]; then
    echo_error "Client '$CLIENT' n'existe pas dans $CLIENT_DIR"
    exit 1
fi

# Variables dérivées
IMAGE_NAME="odoo-alusage-$CLIENT"
IMAGE_TAG="$BRANCH"
FULL_IMAGE="$IMAGE_NAME:$IMAGE_TAG"
SERVICE_NAME="odoo-alusage-$BRANCH-$CLIENT"
POSTGRES_SERVICE="postgres-$CLIENT"
NETWORK_NAME="traefik-local"

echo_info "🚀 Démarrage du service Docker par branche"
echo_info "📋 Configuration:"
echo "   - Client: $CLIENT"
echo "   - Branche: $BRANCH"
echo "   - Image: $FULL_IMAGE"
echo "   - Service: $SERVICE_NAME"
echo "   - PostgreSQL: $POSTGRES_SERVICE"
echo "   - URL: https://$BRANCH.$CLIENT.localhost"

# Build si demandé
if [[ $BUILD = true ]]; then
    echo_info "🔨 Build de l'image..."
    "$SCRIPT_DIR/build_client_branch_docker.sh" "$CLIENT" "$BRANCH"
fi

# Vérifier que l'image existe
if ! docker image inspect "$FULL_IMAGE" >/dev/null 2>&1; then
    echo_error "L'image $FULL_IMAGE n'existe pas"
    echo_info "💡 Utilisez --build pour la créer automatiquement"
    echo_info "💡 Ou executez: ./scripts/build_client_branch_docker.sh $CLIENT $BRANCH"
    exit 1
fi

# Créer le réseau Traefik s'il n'existe pas
if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    echo_info "🌐 Création du réseau $NETWORK_NAME..."
    docker network create "$NETWORK_NAME"
fi

# Démarrer PostgreSQL pour ce client (partagé entre toutes les branches)
if ! docker container inspect "$POSTGRES_SERVICE" >/dev/null 2>&1; then
    echo_info "🐘 Démarrage de PostgreSQL pour le client $CLIENT..."
    docker run -d \
        --name "$POSTGRES_SERVICE" \
        --network "$NETWORK_NAME" \
        --restart unless-stopped \
        -e POSTGRES_DB=postgres \
        -e POSTGRES_USER=odoo \
        -e POSTGRES_PASSWORD=odoo \
        -e PGDATA=/var/lib/postgresql/data/pgdata \
        -e POSTGRES_HOST_AUTH_METHOD=trust \
        -v "$CLIENT_DIR/data/postgresql:/var/lib/postgresql/data" \
        postgres:15
    
    echo_info "⏳ Attente du démarrage de PostgreSQL..."
    sleep 5
elif [[ "$(docker container inspect -f '{{.State.Status}}' "$POSTGRES_SERVICE")" != "running" ]]; then
    echo_info "▶️  Redémarrage de PostgreSQL pour le client $CLIENT..."
    docker start "$POSTGRES_SERVICE"
    sleep 3
else
    echo_info "✅ PostgreSQL déjà en cours d'exécution"
fi

# Arrêter le service s'il existe déjà
if docker container inspect "$SERVICE_NAME" >/dev/null 2>&1; then
    echo_info "🛑 Arrêt du service existant $SERVICE_NAME..."
    docker stop "$SERVICE_NAME"
    docker rm "$SERVICE_NAME"
fi

# Créer les volumes pour cette branche
VOLUME_PREFIX="odoo-$CLIENT-$BRANCH"
DATA_VOLUME="$VOLUME_PREFIX-data"
FILESTORE_VOLUME="$VOLUME_PREFIX-filestore"
SESSIONS_VOLUME="$VOLUME_PREFIX-sessions"

echo_info "💾 Création des volumes pour la branche $BRANCH..."
docker volume create "$DATA_VOLUME" >/dev/null || true
docker volume create "$FILESTORE_VOLUME" >/dev/null || true
docker volume create "$SESSIONS_VOLUME" >/dev/null || true

# Lancer le service Odoo
echo_info "🚀 Démarrage du service $SERVICE_NAME..."

DOCKER_ARGS=(
    "--name" "$SERVICE_NAME"
    "--network" "$NETWORK_NAME"
    "--restart" "unless-stopped"
)

# Labels Traefik
DOCKER_ARGS+=(
    "--label" "traefik.enable=true"
    # Odoo HTTP
    "--label" "traefik.http.routers.$SERVICE_NAME.entrypoints=web"
    "--label" "traefik.http.routers.$SERVICE_NAME.rule=Host(\`$BRANCH.$CLIENT.localhost\`)"
    "--label" "traefik.http.services.$SERVICE_NAME.loadbalancer.server.port=8069"
    "--label" "traefik.http.routers.$SERVICE_NAME.service=$SERVICE_NAME@docker"
    # Odoo WebSocket
    "--label" "traefik.http.routers.$SERVICE_NAME-ws.entrypoints=web"
    "--label" "traefik.http.routers.$SERVICE_NAME-ws.rule=Path(\`/websocket\`) && Host(\`$BRANCH.$CLIENT.localhost\`)"
    "--label" "traefik.http.services.$SERVICE_NAME-ws.loadbalancer.server.port=8072"
    "--label" "traefik.http.routers.$SERVICE_NAME-ws.service=$SERVICE_NAME-ws@docker"
)

# Variables d'environnement
DOCKER_ARGS+=(
    "-e" "HOST=$POSTGRES_SERVICE"
    "-e" "USER=odoo"
    "-e" "PASSWORD=odoo"
    "-e" "CLIENT_NAME=$CLIENT"
    "-e" "BRANCH_NAME=$BRANCH"
)

# Volumes - monter addons et extra-addons au même niveau pour les liens symboliques
DOCKER_ARGS+=(
    "-v" "/etc/localtime:/etc/localtime:ro"
    "-v" "$CLIENT_DIR/config:/mnt/client/config:ro"
    "-v" "$CLIENT_DIR/extra-addons:/mnt/client/extra-addons:ro"
    "-v" "$CLIENT_DIR/addons:/mnt/client/addons:ro"
    "-v" "$CLIENT_DIR/requirements.txt:/mnt/client/requirements.txt:ro"
    "-v" "$DATA_VOLUME:/data"
    "-v" "$FILESTORE_VOLUME:/data/filestore"
    "-v" "$SESSIONS_VOLUME:/data/sessions"
)

# Mode détaché ou attaché
if [[ $DETACH = true ]]; then
    DOCKER_ARGS+=("-d")
fi

# Lancer le conteneur
if docker run "${DOCKER_ARGS[@]}" "$FULL_IMAGE"; then
    echo_success "🎉 Service démarré avec succès !"
    echo_info "🌐 URL: https://$BRANCH.$CLIENT.localhost"
    echo_info "📋 Service: $SERVICE_NAME"
    echo_info "🐘 PostgreSQL: $POSTGRES_SERVICE"
    
    if [[ $DETACH = true ]]; then
        echo_info "💡 Pour voir les logs:"
        echo "   docker logs -f $SERVICE_NAME"
        echo_info "💡 Pour arrêter:"
        echo "   ./scripts/stop_client_branch.sh $CLIENT $BRANCH"
    fi
else
    echo_error "❌ Échec du démarrage du service"
    exit 1
fi
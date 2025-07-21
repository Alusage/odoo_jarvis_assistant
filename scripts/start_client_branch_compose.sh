#!/bin/bash

# Script de démarrage d'un service Docker pour une branche spécifique
# Utilise docker-compose avec des fichiers temporaires par branche
# Usage: ./start_client_branch_compose.sh CLIENT BRANCH [options]

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
BUILD=false
RECREATE=false

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
    echo "  --build      Builder l'image avant de démarrer"
    echo "  --recreate   Recréer les conteneurs même s'ils existent"
    echo "  --help       Afficher cette aide"
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
        --recreate)
            RECREATE=true
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
# Nettoyer le nom de branche pour les services (remplacer . par -)
BRANCH_CLEAN="${BRANCH//\./-}"
SERVICE_NAME="odoo-alusage-$BRANCH_CLEAN-$CLIENT"
POSTGRES_SERVICE="postgresql-$CLIENT"
COMPOSE_FILE="$CLIENT_DIR/docker-compose-branch-$BRANCH.yml"
TEMPLATE_FILE="$BASE_DIR/templates/docker-compose-branch.yml.template"

echo_info "🚀 Démarrage du service Docker par branche avec Compose"
echo_info "📋 Configuration:"
echo "   - Client: $CLIENT"
echo "   - Branche: $BRANCH (service: $BRANCH_CLEAN)"
echo "   - Image: $IMAGE_NAME:$BRANCH"
echo "   - Service: $SERVICE_NAME"
echo "   - PostgreSQL: $POSTGRES_SERVICE"
echo "   - URL: $PROTOCOL://$BRANCH_CLEAN.$CLIENT.$DOMAIN"
echo "   - Compose file: $COMPOSE_FILE"

# Obtenir la version Odoo
ODOO_VERSION="18.0"
if [[ -f "$CLIENT_DIR/.odoo_version" ]]; then
    ODOO_VERSION=$(cat "$CLIENT_DIR/.odoo_version")
fi

# Obtenir la configuration Traefik
TRAEFIK_CONFIG="$BASE_DIR/config/traefik_config.json"
DOMAIN="local"
PROTOCOL="http"
if [[ -f "$TRAEFIK_CONFIG" ]]; then
    DOMAIN=$(jq -r '.domain // "local"' "$TRAEFIK_CONFIG")
    PROTOCOL=$(jq -r '.protocol // "http"' "$TRAEFIK_CONFIG")
fi

# Variables pour les volumes (utiliser la branche nettoyée)
VOLUME_PREFIX="odoo-$CLIENT-$BRANCH_CLEAN"
DATA_VOLUME="$VOLUME_PREFIX-data"
FILESTORE_VOLUME="$VOLUME_PREFIX-filestore"
SESSIONS_VOLUME="$VOLUME_PREFIX-sessions"

# Build si demandé
if [[ $BUILD = true ]]; then
    echo_info "🔨 Build de l'image..."
    "$BASE_DIR/scripts/build_client_branch_docker.sh" "$CLIENT" "$BRANCH" --force
fi

# Vérifier que l'image existe
if ! docker image inspect "$IMAGE_NAME:$BRANCH" >/dev/null 2>&1; then
    echo_error "L'image $IMAGE_NAME:$BRANCH n'existe pas"
    echo_info "💡 Utilisez --build pour la créer automatiquement"
    exit 1
fi

# Créer les volumes s'ils n'existent pas
echo_info "💾 Création des volumes pour la branche $BRANCH..."
docker volume create "$DATA_VOLUME" >/dev/null 2>&1 || true
docker volume create "$FILESTORE_VOLUME" >/dev/null 2>&1 || true
docker volume create "$SESSIONS_VOLUME" >/dev/null 2>&1 || true

# Initialiser le dossier PostgreSQL si nécessaire
if [[ ! -d "$CLIENT_DIR/data/postgresql-data" ]]; then
    echo_info "🔧 Initialisation du dossier PostgreSQL avec les bonnes permissions..."
    cd "$CLIENT_DIR"
    docker compose --profile init up postgres-init
    echo_info "✅ Dossier PostgreSQL initialisé"
fi

# S'assurer que PostgreSQL tourne (en utilisant le docker-compose principal)
if ! docker container inspect "$POSTGRES_SERVICE" >/dev/null 2>&1; then
    echo_info "🐘 Démarrage de PostgreSQL via docker-compose principal..."
    cd "$CLIENT_DIR"
    docker compose up -d "$POSTGRES_SERVICE"
    echo_info "⏳ Attente du démarrage de PostgreSQL..."
    sleep 5
elif [[ "$(docker container inspect -f '{{.State.Status}}' "$POSTGRES_SERVICE")" != "running" ]]; then
    echo_info "▶️  Redémarrage de PostgreSQL..."
    cd "$CLIENT_DIR"
    docker compose start "$POSTGRES_SERVICE"
    sleep 3
else
    echo_info "✅ PostgreSQL déjà en cours d'exécution"
fi

# Générer le fichier docker-compose temporaire
echo_info "📝 Génération du fichier docker-compose pour la branche..."
if [[ ! -f "$TEMPLATE_FILE" ]]; then
    echo_error "Template non trouvé: $TEMPLATE_FILE"
    exit 1
fi

# Remplacer les variables dans le template
sed -e "s|{{CLIENT}}|$CLIENT|g" \
    -e "s|{{BRANCH}}|$BRANCH_CLEAN|g" \
    -e "s|{{BRANCH_ORIGINAL}}|$BRANCH|g" \
    -e "s|{{SERVICE_NAME}}|$SERVICE_NAME|g" \
    -e "s|{{IMAGE_NAME}}|$IMAGE_NAME|g" \
    -e "s|{{POSTGRES_SERVICE}}|$POSTGRES_SERVICE|g" \
    -e "s|{{CLIENT_DIR}}|$CLIENT_DIR|g" \
    -e "s|{{DATA_VOLUME}}|$DATA_VOLUME|g" \
    -e "s|{{FILESTORE_VOLUME}}|$FILESTORE_VOLUME|g" \
    -e "s|{{SESSIONS_VOLUME}}|$SESSIONS_VOLUME|g" \
    -e "s|{{ODOO_VERSION}}|$ODOO_VERSION|g" \
    -e "s|{{DOMAIN}}|$DOMAIN|g" \
    "$TEMPLATE_FILE" > "$COMPOSE_FILE"

echo_success "Fichier docker-compose généré: $COMPOSE_FILE"

# Démarrer le service avec docker-compose
cd "$CLIENT_DIR"
echo_info "🚀 Démarrage du service $SERVICE_NAME..."

COMPOSE_ARGS=("up" "-d")
if [[ $RECREATE = true ]]; then
    COMPOSE_ARGS+=("--force-recreate")
fi

if docker compose -f "$COMPOSE_FILE" "${COMPOSE_ARGS[@]}" "$SERVICE_NAME"; then
    echo_success "🎉 Service démarré avec succès !"
    echo_info "🌐 URL: $PROTOCOL://$BRANCH_CLEAN.$CLIENT.$DOMAIN"
    echo_info "📋 Service: $SERVICE_NAME"
    echo_info "🐘 PostgreSQL: $POSTGRES_SERVICE"
    
    echo_info "💡 Pour voir les logs:"
    echo "   docker compose -f $COMPOSE_FILE logs -f $SERVICE_NAME"
    echo_info "💡 Pour arrêter:"
    echo "   $BASE_DIR/scripts/stop_client_branch_compose.sh $CLIENT $BRANCH"
else
    echo_error "❌ Échec du démarrage du service"
    exit 1
fi
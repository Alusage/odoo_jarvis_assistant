#!/bin/bash

# Script d'arrêt d'un service Docker pour une branche spécifique
# Utilise docker-compose avec des fichiers temporaires par branche
# Usage: ./stop_client_branch_compose.sh CLIENT BRANCH [options]

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
CLEAN_VOLUMES=false
REMOVE_COMPOSE_FILE=false

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
    echo "  --clean          Supprimer aussi les volumes de données de cette branche"
    echo "  --remove-compose Supprimer le fichier docker-compose temporaire"
    echo "  --help           Afficher cette aide"
    echo ""
    echo "Exemples:"
    if [[ -n "$CLIENT_NAME" ]]; then
        echo "  $0 dev-test-001              # Arrêter branche spécifique"
        echo "  $0                           # Arrêter branche actuelle"
        echo "  $0 old-branch --clean        # Arrêter et nettoyer"
    else
        echo "  $0 testclient dev-test-001"
        echo "  $0 testclient old-branch --clean"
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
        --clean)
            CLEAN_VOLUMES=true
            shift
            ;;
        --remove-compose)
            REMOVE_COMPOSE_FILE=true
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
# Nettoyer le nom de branche pour les services (remplacer . par -)
BRANCH_CLEAN="${BRANCH//\./-}"
SERVICE_NAME="odoo-alusage-$BRANCH_CLEAN-$CLIENT"
COMPOSE_FILE="$CLIENT_DIR/docker-compose-branch-$BRANCH.yml"
VOLUME_PREFIX="odoo-$CLIENT-$BRANCH_CLEAN"

echo_info "🛑 Arrêt du service Docker par branche avec Compose"
echo_info "📋 Configuration:"
echo "   - Client: $CLIENT"
echo "   - Branche: $BRANCH (service: $BRANCH_CLEAN)"
echo "   - Service: $SERVICE_NAME"
echo "   - Compose file: $COMPOSE_FILE"
echo "   - Nettoyage volumes: $([ $CLEAN_VOLUMES = true ] && echo "Oui" || echo "Non")"

# Vérifier que le fichier compose existe
if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo_warning "Fichier docker-compose non trouvé: $COMPOSE_FILE"
    echo_warning "Le service n'était peut-être pas démarré via cette méthode"
    
    # Tentative d'arrêt direct du conteneur
    if docker container inspect "$SERVICE_NAME" >/dev/null 2>&1; then
        echo_info "🛑 Arrêt direct du conteneur $SERVICE_NAME..."
        docker stop "$SERVICE_NAME" >/dev/null 2>&1 || true
        docker rm "$SERVICE_NAME" >/dev/null 2>&1 || true
        echo_success "Conteneur arrêté directement"
    fi
else
    # Arrêter via docker-compose
    cd "$CLIENT_DIR"
    echo_info "🛑 Arrêt du service $SERVICE_NAME via docker-compose..."
    
    if docker compose -f "$COMPOSE_FILE" stop "$SERVICE_NAME" 2>/dev/null; then
        docker compose -f "$COMPOSE_FILE" rm -f "$SERVICE_NAME" 2>/dev/null || true
        echo_success "Service arrêté via docker-compose"
    else
        echo_warning "Échec de l'arrêt via docker-compose, tentative directe..."
        docker stop "$SERVICE_NAME" >/dev/null 2>&1 || true
        docker rm "$SERVICE_NAME" >/dev/null 2>&1 || true
    fi
fi

# Nettoyage des volumes si demandé
if [[ $CLEAN_VOLUMES = true ]]; then
    echo_info "🧹 Nettoyage des volumes pour la branche $BRANCH..."
    
    DATA_VOLUME="$VOLUME_PREFIX-data"
    FILESTORE_VOLUME="$VOLUME_PREFIX-filestore"
    SESSIONS_VOLUME="$VOLUME_PREFIX-sessions"
    
    for volume in "$DATA_VOLUME" "$FILESTORE_VOLUME" "$SESSIONS_VOLUME"; do
        if docker volume inspect "$volume" >/dev/null 2>&1; then
            echo_info "🗑️  Suppression du volume $volume..."
            docker volume rm "$volume" >/dev/null 2>&1 || echo_warning "Impossible de supprimer $volume"
        fi
    done
    echo_success "Volumes nettoyés"
fi

# Suppression du fichier compose temporaire si demandé
if [[ $REMOVE_COMPOSE_FILE = true && -f "$COMPOSE_FILE" ]]; then
    echo_info "🗑️  Suppression du fichier docker-compose temporaire..."
    rm "$COMPOSE_FILE"
    echo_success "Fichier docker-compose supprimé"
fi

# Suppression de l'image si plus utilisée et si clean
if [[ $CLEAN_VOLUMES = true ]]; then
    IMAGE_NAME="odoo-alusage-$CLIENT"
    IMAGE_TAG="$BRANCH"
    FULL_IMAGE="$IMAGE_NAME:$IMAGE_TAG"
    
    # Vérifier si l'image est utilisée par d'autres conteneurs
    USING_CONTAINERS=$(docker ps -a --filter "ancestor=$FULL_IMAGE" --format "{{.Names}}" | grep -v "^$SERVICE_NAME$" || true)
    
    if [[ -z "$USING_CONTAINERS" ]]; then
        if docker image inspect "$FULL_IMAGE" >/dev/null 2>&1; then
            echo_info "🗑️  Suppression de l'image $FULL_IMAGE..."
            docker rmi "$FULL_IMAGE" >/dev/null 2>&1 || echo_warning "Impossible de supprimer l'image (peut-être utilisée ailleurs)"
        fi
    fi
fi

echo_success "🎉 Arrêt terminé avec succès !"

if [[ $CLEAN_VOLUMES = true ]]; then
    echo_info "💡 La branche $BRANCH a été complètement nettoyée"
fi

echo_info "💡 Pour redémarrer:"
echo "   $BASE_DIR/scripts/start_client_branch_compose.sh $CLIENT $BRANCH"
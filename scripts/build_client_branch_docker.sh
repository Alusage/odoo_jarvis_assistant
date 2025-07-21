#!/bin/bash

# Script de build Docker pour une branche spécifique d'un client
# Usage: ./build_client_branch_docker.sh CLIENT BRANCH [options]

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
FORCE=false
NO_CACHE=false
PUSH=false

# Détection automatique du répertoire de base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$SCRIPT_DIR" == */clients/*/scripts ]]; then
    # Exécuté depuis un répertoire client (clients/testclient/scripts/)
    BASE_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
    CLIENT_NAME="$(basename "$(dirname "$SCRIPT_DIR")")"
    echo_info "🏠 Détecté: exécution depuis le répertoire client '$CLIENT_NAME'"
elif [[ "$SCRIPT_DIR" == */scripts ]]; then
    # Exécuté depuis le répertoire principal (odoo-jarvis-assistant/scripts/)
    BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    CLIENT_NAME=""
    echo_info "🏠 Détecté: exécution depuis le répertoire principal"
else
    # Fallback
    BASE_DIR="$(pwd)"
    CLIENT_NAME=""
fi

# Aide
show_help() {
    if [[ -n "$CLIENT_NAME" ]]; then
        echo "Usage: $0 [BRANCH] [options]  (client détecté: $CLIENT_NAME)"
        echo ""
        echo "Arguments:"
        echo "  BRANCH     Nom de la branche (ex: dev-test-001, défaut: branche actuelle)"
    else
        echo "Usage: $0 CLIENT BRANCH [options]"
        echo ""
        echo "Arguments:"
        echo "  CLIENT     Nom du client (ex: testclient)"
        echo "  BRANCH     Nom de la branche (ex: dev-test-001)"
    fi
    echo ""
    echo "Options:"
    echo "  --force    Forcer le rebuild même si l'image existe"
    echo "  --no-cache Build sans utiliser le cache Docker"
    echo "  --push     Push l'image vers le registry après build"
    echo "  --help     Afficher cette aide"
    echo ""
    echo "Exemples:"
    if [[ -n "$CLIENT_NAME" ]]; then
        echo "  $0 dev-test-001              # Build branche spécifique"
        echo "  $0                           # Build branche actuelle"
        echo "  $0 main --force --no-cache   # Build branche main avec options"
    else
        echo "  $0 testclient dev-test-001"
        echo "  $0 testclient main --force --no-cache"
    fi
}

# Parsing des arguments selon le contexte
if [[ -n "$CLIENT_NAME" ]]; then
    # Exécuté depuis un répertoire client - CLIENT est déjà connu
    CLIENT="$CLIENT_NAME"
    if [[ $# -ge 1 && "$1" != --* ]]; then
        BRANCH="$1"
        shift 1
    else
        # Utiliser la branche actuelle si pas spécifiée
        if [[ -d "$BASE_DIR/clients/$CLIENT/.git" ]]; then
            cd "$BASE_DIR/clients/$CLIENT"
            BRANCH=$(git branch --show-current)
            cd - >/dev/null
        else
            echo_error "Impossible de déterminer la branche actuelle"
            show_help
            exit 1
        fi
    fi
else
    # Exécuté depuis le répertoire principal - CLIENT et BRANCH requis
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
        --force)
            FORCE=true
            shift
            ;;
        --no-cache)
            NO_CACHE=true
            shift
            ;;
        --push)
            PUSH=true
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

# Générer des tags additionnels avec versioning
TIMESTAMP=$(date +%Y%m%d-%H%M)
cd "$CLIENT_DIR"
GIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
cd - >/dev/null

# Tags additionnels pour versioning
IMAGE_TAG_TIMESTAMP="${BRANCH}-${TIMESTAMP}"
IMAGE_TAG_HASH="${BRANCH}-${GIT_HASH}"
IMAGE_TAG_LATEST="${BRANCH}-latest"

VERSIONED_IMAGES=(
    "$IMAGE_NAME:$IMAGE_TAG"           # Tag principal: dev-feature-test
    "$IMAGE_NAME:$IMAGE_TAG_TIMESTAMP" # Tag avec timestamp: dev-feature-test-20250720-1635
    "$IMAGE_NAME:$IMAGE_TAG_HASH"      # Tag avec hash Git: dev-feature-test-0a194be
    "$IMAGE_NAME:$IMAGE_TAG_LATEST"    # Tag latest: dev-feature-test-latest
)

echo_info "🐳 Build de l'image Docker par branche"
echo_info "📋 Configuration:"
echo "   - Client: $CLIENT"
echo "   - Branche: $BRANCH" 
echo "   - Image: $FULL_IMAGE"
echo "   - Force: $([ $FORCE = true ] && echo "Oui" || echo "Non")"
echo "   - No Cache: $([ $NO_CACHE = true ] && echo "Oui" || echo "Non")"
echo "   - Push: $([ $PUSH = true ] && echo "Oui" || echo "Non")"

# Vérifier si l'image existe déjà
if docker image inspect "$FULL_IMAGE" >/dev/null 2>&1; then
    if [[ $FORCE != true ]]; then
        echo_warning "L'image $FULL_IMAGE existe déjà. Utilisez --force pour la rebuilder."
        exit 0
    fi
    echo_info "L'image existe, mais rebuild forcé"
fi

# Se positionner dans le répertoire client
cd "$CLIENT_DIR"

# Vérifier que la branche existe
if ! git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    echo_error "La branche '$BRANCH' n'existe pas dans le client '$CLIENT'"
    exit 1
fi

# Sauvegarder la branche actuelle
CURRENT_BRANCH=$(git branch --show-current)
echo_info "Branche actuelle: $CURRENT_BRANCH"

# Changer vers la branche cible (avec gestion des submodules)
echo_info "🔄 Basculement vers la branche '$BRANCH'..."
if ! git checkout --recurse-submodules "$BRANCH"; then
    echo_error "Impossible de basculer vers la branche '$BRANCH'"
    exit 1
fi

# Vérifier la présence du Dockerfile
DOCKER_DIR="$CLIENT_DIR/docker"
if [[ ! -f "$DOCKER_DIR/Dockerfile" ]]; then
    echo_error "Dockerfile introuvable dans $DOCKER_DIR"
    git checkout --recurse-submodules "$CURRENT_BRANCH" 2>/dev/null || true
    exit 1
fi

# Vérifier la présence de odoo.conf
CONFIG_FILE="$CLIENT_DIR/config/odoo.conf"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo_warning "Fichier config/odoo.conf introuvable, création d'un fichier par défaut"
    mkdir -p "$CLIENT_DIR/config"
    cat > "$CONFIG_FILE" << EOF
[options]
addons_path = /mnt/addons,/mnt/extra-addons
data_dir = /data
log_level = info
db_host = postgresql-$CLIENT
db_port = 5432
db_user = odoo
db_password = odoo
admin_passwd = admin
xmlrpc_port = 8069
longpolling_port = 8072
EOF
fi

# Obtenir la version Odoo de cette branche
ODOO_VERSION="18.0"
if [[ -f "$CLIENT_DIR/.odoo_version" ]]; then
    ODOO_VERSION=$(cat "$CLIENT_DIR/.odoo_version")
fi

# Construction des arguments Docker avec tous les tags
BUILD_ARGS=(
    "--build-arg" "ODOO_VERSION=$ODOO_VERSION"
    "--build-arg" "CLIENT_NAME=$CLIENT"
    "--build-arg" "BRANCH_NAME=$BRANCH"
    "--file" "$DOCKER_DIR/Dockerfile"
)

# Ajouter tous les tags versionnés
for image_tag in "${VERSIONED_IMAGES[@]}"; do
    BUILD_ARGS+=("--tag" "$image_tag")
done

if [[ $NO_CACHE = true ]]; then
    BUILD_ARGS+=("--no-cache")
fi

# Build de l'image
echo_info "🔨 Construction de l'image Docker..."
echo_info "📂 Contexte de build: $CLIENT_DIR"
echo_info "🐳 Dockerfile: $DOCKER_DIR/Dockerfile"

if docker build "${BUILD_ARGS[@]}" "$CLIENT_DIR"; then
    echo_success "Image construite avec succès: $FULL_IMAGE"
    
    # Afficher toutes les versions créées
    echo_info "📦 Images Docker créées avec versioning:"
    for image_tag in "${VERSIONED_IMAGES[@]}"; do
        echo "   ✓ $image_tag"
    done
    
    # Afficher des informations sur l'image
    echo_info "📋 Détails de l'image:"
    echo "   - Hash Git: $GIT_HASH"
    echo "   - Timestamp: $TIMESTAMP" 
    echo "   - Taille: $(docker images --format "{{.Size}}" "$FULL_IMAGE" | head -1)"
else
    echo_error "Échec de la construction de l'image"
    git checkout --recurse-submodules "$CURRENT_BRANCH" 2>/dev/null || true
    exit 1
fi

# Push optionnel
if [[ $PUSH = true ]]; then
    echo_info "📤 Push de l'image vers le registry..."
    if docker push "$FULL_IMAGE"; then
        echo_success "Image pushée avec succès"
    else
        echo_error "Échec du push de l'image"
        git checkout --recurse-submodules "$CURRENT_BRANCH" 2>/dev/null || true
        exit 1
    fi
fi

# Retour à la branche d'origine
echo_info "🔄 Retour à la branche '$CURRENT_BRANCH'..."
git checkout "$CURRENT_BRANCH"

echo_success "🎉 Build terminé avec succès !"
echo_info "💡 Image créée: $FULL_IMAGE"
echo_info "💡 Pour démarrer le service:"
echo "   ./scripts/start_client_branch.sh $CLIENT $BRANCH"
echo ""
echo_info "💡 Service Docker qui sera créé: odoo-alusage-$BRANCH-$CLIENT"
echo_info "💡 URL Traefik: https://$BRANCH.$CLIENT.localhost"
#!/bin/bash

# Script pour générer un dépôt client
# Usage: generate_client_repo.sh <client_name> <odoo_version> <template> <has_enterprise>

set -e

# Gestion des options d'aide
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $0 <client_name> <odoo_version> <template> <has_enterprise>"
    echo ""
    echo "Paramètres:"
    echo "  client_name      - Nom du client"
    echo "  odoo_version     - Version d'Odoo (ex: 18.0)"
    echo "  template         - Template à utiliser"
    echo "  has_enterprise   - true/false pour Odoo Enterprise"
    echo ""
    echo "Exemple: $0 mon_client 18.0 basic false"
    exit 0
fi

CLIENT_NAME="$1"
ODOO_VERSION="$2"
TEMPLATE="$3"
HAS_ENTERPRISE="$4"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$ROOT_DIR/config"
TEMPLATES_DIR="$ROOT_DIR/templates"
CLIENTS_DIR="$ROOT_DIR/clients"
CLIENT_DIR="$CLIENTS_DIR/$CLIENT_NAME"

# Source the repository optimizer
source "$SCRIPT_DIR/repository_optimizer.sh"

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

# Validation des paramètres
validate_parameters() {
    if [[ -z "$CLIENT_NAME" || -z "$ODOO_VERSION" || -z "$TEMPLATE" || -z "$HAS_ENTERPRISE" ]]; then
        echo_error "Usage: $0 <client_name> <odoo_version> <template> <has_enterprise>"
        echo_error "Exemple: $0 mon_client 18.0 basic false"
        exit 1
    fi
    
    # Vérifier que le template existe
    if ! jq -e ".client_templates.\"$TEMPLATE\"" "$CONFIG_DIR/client_templates.json" >/dev/null 2>&1; then
        echo_error "Template '$TEMPLATE' non trouvé dans la configuration"
        echo_info "Templates disponibles :"
        jq -r '.client_templates | keys[]' "$CONFIG_DIR/client_templates.json"
        exit 1
    fi
    
    # Vérifier que la version Odoo est supportée
    if ! jq -e ".odoo_versions.\"$ODOO_VERSION\"" "$CONFIG_DIR/odoo_versions.json" >/dev/null 2>&1; then
        echo_error "Version Odoo '$ODOO_VERSION' non supportée"
        echo_info "Versions disponibles :"
        jq -r '.odoo_versions | keys[]' "$CONFIG_DIR/odoo_versions.json"
        exit 1
    fi
}

# Créer la structure du dépôt client
create_client_structure() {
    echo_info "Création de la structure pour $CLIENT_NAME..."
    
    mkdir -p "$CLIENT_DIR"
    cd "$CLIENT_DIR"
    
    # Initialiser le dépôt Git avec la branche nommée selon la version Odoo
    git init --initial-branch="$ODOO_VERSION"
    
    # Créer les dossiers principaux
    mkdir -p addons extra-addons config scripts data logs
    
    # Créer les sous-dossiers nécessaires pour Odoo dans data
    mkdir -p data/filestore data/sessions
    
    # Définir les permissions appropriées pour les dossiers de données
    # L'utilisateur odoo dans le conteneur a l'UID 101
    if command -v chown >/dev/null 2>&1; then
        # Essayer de définir les permissions pour l'utilisateur odoo (UID 101)
        chown -R 101:101 data logs 2>/dev/null || true
        chmod -R 755 data logs 2>/dev/null || true
    fi
    
    # Créer le .gitignore
    cat > .gitignore << 'EOF'
# Byte-compiled / optimized / DLL files
__pycache__/
*.py[cod]
*$py.class

# Odoo
*.pyc
filestore/
sessions/
.odoorc

# Dossiers de données Odoo
data/
logs/

# IDE
.vscode/
.idea/
*.swp
*.swo

# Logs
*.log

# OS
.DS_Store
Thumbs.db

# Temporary files
tmp/
temp/
EOF

    # Créer le .gitmodules (sera rempli par add_submodules)
    touch .gitmodules
}

# Ajouter les submodules OCA selon le template
add_submodules() {
    echo_info "Ajout des submodules OCA..."
    
    local modules_list
    if [ "$TEMPLATE" = "custom" ]; then
        # Pour custom, on demande à l'utilisateur
        echo_info "Modules OCA disponibles :"
        jq -r '.oca_repositories | to_entries[] | "\(.key) - \(.value.description)"' "$CONFIG_DIR/repositories.json"
        echo
        read -p "Entrez les modules souhaités (séparés par des espaces): " modules_list
        modules_array=($modules_list)
    else
        # Récupérer les modules du template avec la nouvelle structure
        process_template_modules "$TEMPLATE"
    fi
    
    # Valider les modules avec l'optimisateur
    echo_info "Validation des modules OCA..."
    local valid_modules
    valid_modules=$(validate_oca_modules "$CLIENT_DIR" "$ODOO_VERSION" "${modules_array[@]}")
    if [[ $? -ne 0 ]]; then
        echo_error "Validation des modules échouée"
        return 1
    fi
    
    # Convertir la chaîne en tableau
    read -ra validated_modules <<< "$valid_modules"
    
    cd "$CLIENT_DIR"
    
    for module in "${validated_modules[@]}"; do
        if [[ -n "$module" ]]; then
            local url=$(jq -r ".oca_repositories[\"$module\"].url" "$CONFIG_DIR/repositories.json")
            if [ "$url" != "null" ]; then
                echo_info "Ajout du submodule: $module"
                
                # Essayer d'abord le clonage optimisé
                if clone_repository_optimized "$module" "$ODOO_VERSION" "addons/$module"; then
                    # Convertir en submodule git
                    git submodule add -b "$ODOO_VERSION" "$url" "addons/$module" 2>/dev/null || {
                        echo_warning "Ajout direct du dépôt cloné comme submodule"
                        git add "addons/$module"
                    }
                else
                    # Fallback vers la méthode standard
                    echo_warning "Fallback vers le submodule standard pour $module"
                    git submodule add -b "$ODOO_VERSION" "$url" "addons/$module" || {
                        echo_error "Échec de l'ajout du submodule $module"
                        continue
                    }
                fi
            else
                echo_error "Module '$module' non trouvé dans la configuration"
            fi
        fi
    done
}

# Traiter les modules du template avec la nouvelle structure
process_template_modules() {
    local template="$1"
    local temp_file="/tmp/module_linking_${CLIENT_NAME}.txt"
    
    # Nettoyer le fichier temporaire
    rm -f "$temp_file"
    
    # Extraire les repositories et créer le fichier de linking
    modules_array=()
    while IFS= read -r module_config; do
        local repository=$(echo "$module_config" | jq -r '.repository')
        local modules=$(echo "$module_config" | jq -r '.modules')
        
        # Ajouter le repository à la liste des modules à installer
        modules_array+=("$repository")
        
        # Stocker les informations de linking pour plus tard
        if [ "$modules" = "all" ]; then
            echo "$repository:all" >> "$temp_file"
        else
            local module_list=$(echo "$module_config" | jq -r '.modules | join(",")')
            echo "$repository:$module_list" >> "$temp_file"
        fi
    done < <(jq -c ".client_templates.\"$template\".default_modules[]" "$CONFIG_DIR/client_templates.json")
}

# Appliquer le linking automatique selon la configuration du template
apply_automatic_linking() {
    local temp_file="/tmp/module_linking_${CLIENT_NAME}.txt"
    
    if [ ! -f "$temp_file" ]; then
        return 0
    fi
    
    if [ ! -d "extra-addons" ]; then
        mkdir -p extra-addons
        echo_info "Création du répertoire extra-addons"
    fi
    
    echo_info "Application du linking automatique selon le template..."
    
    while IFS=':' read -r repository module_spec; do
        local submodule_path="addons/$repository"
        
        if [ ! -d "$submodule_path" ]; then
            echo_warning "Dépôt $repository non trouvé, linking ignoré"
            continue
        fi
        
        if [ "$module_spec" = "all" ]; then
            echo_info "Linking de tous les modules de $repository..."
            for dir in "$submodule_path"/*; do
                if [ -d "$dir" ] && [ -f "$dir/__manifest__.py" ]; then
                    local module_name=$(basename "$dir")
                    ln -sf "../$submodule_path/$module_name" "extra-addons/$module_name"
                    echo_success "Module '$module_name' lié dans extra-addons"
                fi
            done
        else
            echo_info "Linking des modules spécifiés de $repository: $module_spec"
            IFS=',' read -ra modules <<< "$module_spec"
            for module in "${modules[@]}"; do
                if [ -d "$submodule_path/$module" ] && [ -f "$submodule_path/$module/__manifest__.py" ]; then
                    ln -sf "../$submodule_path/$module" "extra-addons/$module"
                    echo_success "Module '$module' lié dans extra-addons"
                else
                    echo_warning "Module '$module' non trouvé dans $repository"
                fi
            done
        fi
    done < "$temp_file"
    
    # Nettoyer le fichier temporaire
    rm -f "$temp_file"
}

# Ajouter Odoo Enterprise si demandé
add_enterprise() {
    if [ "$HAS_ENTERPRISE" = "true" ]; then
        echo_info "Ajout d'Odoo Enterprise comme submodule..."
        cd "$CLIENT_DIR"
        
        # URL du dépôt Enterprise (peut être personnalisé)
        ENTERPRISE_URL="https://github.com/odoo/enterprise.git"
        
        # Supprimer le dossier s'il existe déjà (au cas où il y aurait un placeholder)
        if [ -d "addons/enterprise" ]; then
            echo_info "Suppression du placeholder Enterprise existant..."
            rm -rf addons/enterprise
        fi
        
        # Ajouter le submodule Enterprise
        echo_info "Clonage du dépôt Enterprise (branche $ODOO_VERSION)..."
        if git submodule add -b "$ODOO_VERSION" "$ENTERPRISE_URL" "addons/enterprise"; then
            echo_success "Submodule Enterprise ajouté avec succès"
        else
            echo_warning "Échec de l'ajout du submodule Enterprise"
            echo_warning "Cela peut être dû à des problèmes d'accès au dépôt privé"
            echo_info "Création d'un placeholder avec instructions..."
            
            # Créer un placeholder si le submodule échoue
            mkdir -p addons/enterprise
            cat > addons/enterprise/README.md << EOF
# Odoo Enterprise

Ce dossier doit contenir les modules Odoo Enterprise.

ERREUR: Le clonage automatique du dépôt Enterprise a échoué.
Cela peut être dû à :
- Problèmes d'authentification (pas de token GitHub ou clé SSH)
- Pas d'accès au dépôt privé odoo/enterprise
- Problèmes de réseau

## Solution manuelle

Pour ajouter manuellement le submodule Enterprise :

1. **Avec accès GitHub** :
   \`\`\`bash
   rm -rf addons/enterprise
   git submodule add -b $ODOO_VERSION https://github.com/odoo/enterprise.git addons/enterprise
   \`\`\`

2. **Avec token GitHub** :
   \`\`\`bash
   rm -rf addons/enterprise
   git submodule add -b $ODOO_VERSION https://YOUR_TOKEN@github.com/odoo/enterprise.git addons/enterprise
   \`\`\`

3. **Avec SSH** :
   \`\`\`bash
   rm -rf addons/enterprise
   git submodule add -b $ODOO_VERSION git@github.com:odoo/enterprise.git addons/enterprise
   \`\`\`

Note: Vous devez avoir accès au dépôt Odoo Enterprise.
EOF
            git add addons/enterprise/README.md
            echo_info "Placeholder créé dans addons/enterprise/"
        fi
    fi
}

# Créer les fichiers de configuration
create_config_files() {
    echo_info "Création des fichiers de configuration..."
    
    # odoo.conf
    cat > "$CLIENT_DIR/config/odoo.conf" << EOF
[options]
addons_path = extra-addons,addons/odoo/addons$([ "$HAS_ENTERPRISE" = "true" ] && echo ",addons/enterprise")
data_dir = data
db_host = postgresql-$CLIENT_NAME
db_port = 5432
db_user = odoo
db_password = odoo
dbfilter = ^${CLIENT_NAME}_.*$
logfile = logs/odoo.log
log_level = info
workers = 2
max_cron_threads = 1
EOF

    # docker-compose.yml - Version complète avec build intégré
    cat > "$CLIENT_DIR/docker-compose.yml" << EOF
# Docker Compose pour le client $CLIENT_NAME
# Version avec support Traefik

services:
  odoo:
    # Option 1: Utiliser l'image construite localement (recommandé)
    build: 
      context: ./docker
      args:
        ODOO_VERSION: $ODOO_VERSION
    image: odoo-alusage-$CLIENT_NAME:$ODOO_VERSION
    
    # Option 2: Utiliser l'image générique (décommentez si nécessaire)
    # image: odoo:$ODOO_VERSION
    
    container_name: odoo-$CLIENT_NAME
    restart: unless-stopped
    
    # Ports exposés uniquement pour accès direct (optionnel avec Traefik)
    # ports:
    #   - "8069:8069"
    #   - "8072:8072"
    
    labels:
      - traefik.enable=true
      # Odoo
      - traefik.http.routers.odoo-$CLIENT_NAME.entrypoints=web
      - traefik.http.routers.odoo-$CLIENT_NAME.rule=Host(\`dev.$CLIENT_NAME.\${TRAEFIK_DOMAIN:-localhost}\`)
      - traefik.http.services.odoo-$CLIENT_NAME.loadbalancer.server.port=8069
      - traefik.http.routers.odoo-$CLIENT_NAME.service=odoo-$CLIENT_NAME@docker
      - traefik.http.routers.odoo-$CLIENT_NAME.middlewares=odoo-forward@docker,odoo-compress@docker
      # Odoo Websocket
      - traefik.http.routers.odoo-$CLIENT_NAME-ws.entrypoints=web
      - traefik.http.routers.odoo-$CLIENT_NAME-ws.rule=Path(\`/websocket\`) && Host(\`dev.$CLIENT_NAME.\${TRAEFIK_DOMAIN:-localhost}\`)
      - traefik.http.services.odoo-$CLIENT_NAME-ws.loadbalancer.server.port=8072
      - traefik.http.routers.odoo-$CLIENT_NAME-ws.service=odoo-$CLIENT_NAME-ws@docker
      - traefik.http.routers.odoo-$CLIENT_NAME-ws.middlewares=odoo-headers@docker,odoo-forward@docker,odoo-compress@docker
    
    volumes:
      # Container localtime
      - /etc/localtime:/etc/localtime:ro
      # Configuration
      - ./config:/mnt/config:ro
      
      # Modules personnalisés et OCA
      - ./extra-addons:/mnt/extra-addons:ro
      - ./addons:/mnt/addons:ro
      
      # Dépendances Python
      - ./requirements.txt:/mnt/requirements.txt:ro
      
      # Données persistantes
      - ./data:/data
    
    environment:
      # Configuration de base
      - HOST=postgresql-$CLIENT_NAME
      - USER=odoo
      - PASSWORD=odoo
      
      # Configuration spécifique au client
      - CLIENT_NAME=$CLIENT_NAME
      - ODOO_VERSION=$ODOO_VERSION
      - TEMPLATE=$TEMPLATE
      - HAS_ENTERPRISE=$HAS_ENTERPRISE
      
      # Mode debug (décommentez si nécessaire)
      # - DEBUG_MODE=true
    
    depends_on:
      - postgresql-$CLIENT_NAME
    
    networks:
      - traefik-local
    
    # Healthcheck pour vérifier que le service fonctionne
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8069/web/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

  postgres-init:
    image: alpine:3.18
    container_name: postgres-init-$CLIENT_NAME
    command: |
      sh -c "
        mkdir -p /data/postgresql-data &&
        chown 999:999 /data/postgresql-data &&
        chmod 755 /data/postgresql-data &&
        echo 'PostgreSQL data directory created with correct permissions'
      "
    volumes:
      - ./data:/data
    profiles:
      - init

  postgresql-$CLIENT_NAME:
    image: postgres:15
    container_name: postgresql-$CLIENT_NAME
    restart: unless-stopped
    
    environment:
      - POSTGRES_DB=postgres
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=odoo
      - PGDATA=/var/lib/postgresql/data/pgdata
      - POSTGRES_HOST_AUTH_METHOD=trust
    
    volumes:
      - ./data/postgresql-data:/var/lib/postgresql/data
    
    # Healthcheck pour PostgreSQL
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U odoo"]
      interval: 10s
      timeout: 5s
      retries: 5
    
    networks:
      - traefik-local

# Réseaux
networks:
  traefik-local:
    external: true

# Note: PostgreSQL utilise maintenant un bind mount vers ./data/postgresql-data
# Ce dossier sera créé automatiquement et ignoré par Git
EOF

    # requirements.txt
    cat > "$CLIENT_DIR/requirements.txt" << EOF
# Requirements pour Odoo $ODOO_VERSION
wheel
setuptools
EOF
    
    # project_config.json - Configuration pour la gestion des branches et modules
    cat > "$CLIENT_DIR/project_config.json" << EOF
{
  "version": "1.0",
  "project_name": "$CLIENT_NAME",
  "odoo_version": "$ODOO_VERSION",
  "linked_modules": {},
  "branch_configs": {},
  "settings": {
    "auto_restore_modules": true,
    "backup_before_switch": true
  },
  "metadata": {
    "created": "$(date -Iseconds)",
    "last_updated": "$(date -Iseconds)",
    "updated_by": "generate_client_repo"
  }
}
EOF

    # Créer les fichiers .gitkeep pour les dossiers vides
    touch "$CLIENT_DIR/logs/.gitkeep"
    touch "$CLIENT_DIR/data/.gitkeep"
    
    # Créer le dossier docker avec les fichiers nécessaires pour le build
    create_docker_files
}

# Créer les fichiers Docker nécessaires pour le build
create_docker_files() {
    echo_info "Création des fichiers Docker pour le build..."
    
    local docker_dir="$CLIENT_DIR/docker"
    mkdir -p "$docker_dir"
    
    # Créer le Dockerfile adapté au client
    create_client_dockerfile "$docker_dir"
    
    # Copier et adapter l'entrypoint
    create_client_entrypoint "$docker_dir"
    
    # Copier le script d'installation des requirements
    create_client_install_requirements "$docker_dir"
    
    # Créer un script de build pour faciliter l'usage
    create_client_build_script "$docker_dir"
    
    echo_success "Fichiers Docker créés dans docker/"
}

# Créer les scripts utilitaires
create_scripts() {
    echo_info "Création des scripts utilitaires..."
    
    # Script de mise à jour des submodules
    cat > "$CLIENT_DIR/scripts/update_submodules.sh" << 'EOF'
#!/bin/bash

# Script pour mettre à jour tous les submodules
echo "🔄 Mise à jour des submodules..."

git submodule update --init --recursive
git submodule foreach git pull origin HEAD

echo "✅ Mise à jour terminée"

# Mettre à jour automatiquement les requirements.txt
if [ -x "./scripts/update_requirements.sh" ]; then
    echo "🔄 Mise à jour des requirements.txt..."
    ./scripts/update_requirements.sh --clean
fi
EOF

    # Script de mise à jour des requirements Python
    cat > "$CLIENT_DIR/scripts/update_requirements.sh" << 'EOF'
#!/bin/bash

# Script pour mettre à jour requirements.txt avec les dépendances des submodules OCA
# Généré automatiquement - ne pas modifier manuellement
# Usage: update_requirements.sh [--clean]

set -e

# Parser les arguments
CLEAN_BACKUPS=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            CLEAN_BACKUPS=true
            shift
            ;;
        *)
            echo "Argument inconnu: $1"
            echo "Usage: $0 [--clean]"
            exit 1
            ;;
    esac
done

# Couleurs pour la sortie
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo_info() { echo -e "${BLUE}-  $1${NC}"; }
echo_success() { echo -e "${GREEN}✅ $1${NC}"; }
echo_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
echo_error() { echo -e "${RED}❌ $1${NC}"; }

echo_info "🔄 Mise à jour des requirements.txt avec les dépendances des submodules..."

# Fichier de requirements final
REQUIREMENTS_FILE="requirements.txt"
TEMP_REQUIREMENTS="/tmp/client_requirements_$(basename $(pwd)).txt"

# En-tête du fichier requirements
cat > "$TEMP_REQUIREMENTS" << EOFR
# Requirements pour le client $(basename $(pwd))
# Généré automatiquement le $(date '+%Y-%m-%d %H:%M:%S')

# Base Odoo requirements
wheel
setuptools
psycopg2-binary
EOFR

# Variables pour les statistiques
total_submodules=0
submodules_with_requirements=0
total_dependencies=0

# Créer un fichier temporaire pour collecter toutes les dépendances
ALL_DEPS_FILE="/tmp/all_deps_$(basename $(pwd)).txt"
> "$ALL_DEPS_FILE"

echo_info "🔍 Recherche des requirements.txt dans les submodules..."

# Parcourir tous les submodules (dossiers dans addons/)
if [ -d "addons" ]; then
    for submodule_dir in addons/*/; do
        if [ -d "$submodule_dir" ]; then
            submodule_name=$(basename "$submodule_dir")
            total_submodules=$((total_submodules + 1))
            
            # Chercher le fichier requirements.txt dans le submodule
            req_file="$submodule_dir/requirements.txt"
            
            if [ -f "$req_file" ]; then
                echo_info "📦 Traitement de $submodule_name..."
                submodules_with_requirements=$((submodules_with_requirements + 1))
                
                # Lire le fichier requirements et filtrer les lignes valides
                while IFS= read -r line; do
                    # Ignorer les lignes vides et les commentaires
                    if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
                        # Nettoyer la ligne (supprimer espaces de début/fin)
                        clean_line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                        
                        if [[ -n "$clean_line" ]]; then
                            echo "$clean_line" >> "$ALL_DEPS_FILE"
                            total_dependencies=$((total_dependencies + 1))
                        fi
                    fi
                done < "$req_file"
            else
                echo_info "   - $submodule_name : pas de requirements.txt"
            fi
        fi
    done
else
    echo_warning "Dossier 'addons' non trouvé"
fi

# Compter les dépendances uniques
unique_dependencies=0
if [ -f "$ALL_DEPS_FILE" ]; then
    unique_dependencies=$(sort "$ALL_DEPS_FILE" | uniq | wc -l)
fi

# Ajouter les dépendances dédupliquées directement
if [ -f "$ALL_DEPS_FILE" ] && [ -s "$ALL_DEPS_FILE" ]; then
    echo "" >> "$TEMP_REQUIREMENTS"
    echo "# Dépendances des modules OCA (dédoublonnées)" >> "$TEMP_REQUIREMENTS"
    
    # Trier et dédupliquer les dépendances
    sort "$ALL_DEPS_FILE" | uniq >> "$TEMP_REQUIREMENTS"
fi

# Sauvegarder l'ancien fichier s'il existe
if [ -f "$REQUIREMENTS_FILE" ]; then
    backup_file="${REQUIREMENTS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$REQUIREMENTS_FILE" "$backup_file"
    echo_info "💾 Sauvegarde créée : $backup_file"
fi

# Remplacer le fichier requirements
mv "$TEMP_REQUIREMENTS" "$REQUIREMENTS_FILE"

# Nettoyer les fichiers temporaires
rm -f "$ALL_DEPS_FILE"

# Afficher les statistiques
echo_success "🎯 Requirements.txt mis à jour avec succès !"
echo_info "📊 Statistiques :"
echo_info "   - Submodules analysés : $total_submodules"
echo_info "   - Submodules avec requirements : $submodules_with_requirements"
echo_info "   - Total dépendances : $total_dependencies"
echo_info "   - Dépendances uniques : $unique_dependencies"

# Nettoyage des fichiers de sauvegarde si demandé
if [ "$CLEAN_BACKUPS" = true ]; then
    echo_info "🧹 Nettoyage des fichiers de sauvegarde..."
    backup_count=$(ls -1 requirements.txt.backup.* 2>/dev/null | wc -l || echo "0")
    
    if [ "$backup_count" -gt 0 ]; then
        rm -f requirements.txt.backup.*
        echo_success "✅ $backup_count fichier(s) de sauvegarde supprimé(s)"
    else
        echo_info "   - Aucun fichier de sauvegarde à supprimer"
    fi
fi

echo_info "💡 Pour installer les dépendances :"
echo_info "   pip install -r requirements.txt"
echo_info "🐳 Ou pour Docker :"
echo_info "   docker compose exec odoo pip install -r requirements.txt"
EOF

    # Script pour créer des liens symboliques
    cat > "$CLIENT_DIR/scripts/link_modules.sh" << 'EOF'
#!/bin/bash

# Script pour créer des liens symboliques vers les modules
# Usage: ./link_modules.sh <submodule_path> <module_name>

SUBMODULE_PATH="$1"
MODULE_NAME="$2"

if [ -z "$SUBMODULE_PATH" ] || [ -z "$MODULE_NAME" ]; then
    echo "Usage: $0 <submodule_path> <module_name>"
    echo "Exemple: $0 addons/partner-contact partner_firstname"
    exit 1
fi

if [ ! -d "$SUBMODULE_PATH/$MODULE_NAME" ]; then
    echo "❌ Module $MODULE_NAME non trouvé dans $SUBMODULE_PATH"
    exit 1
fi

ln -sf "../$SUBMODULE_PATH/$MODULE_NAME" "extra-addons/$MODULE_NAME"
echo "✅ Lien créé: extra-addons/$MODULE_NAME -> $SUBMODULE_PATH/$MODULE_NAME"
EOF

    # Script de démarrage Docker
    cat > "$CLIENT_DIR/scripts/start.sh" << 'EOF'
#!/bin/bash

# Script pour démarrer l'environnement
echo "🚀 Démarrage de l'environnement Odoo..."

# Mettre à jour les submodules
./scripts/update_submodules.sh

# Démarrer Docker Compose
docker compose up -d

echo "✅ Environnement démarré"
echo "🌐 Odoo accessible sur: http://localhost:8069"
EOF

    # Script merge_pr.sh pour gérer les PRs des submodules
    cat > "$CLIENT_DIR/scripts/merge_pr.sh" << 'EOF'
#!/bin/bash

SUBMODULE_PATH=$1
PR_NUMBER=$2
BASE_BRANCH=${3:-16.0}

if [ -z "$SUBMODULE_PATH" ] || [ -z "$PR_NUMBER" ]; then
  echo "❌ Usage : bash merge_pr.sh <submodule_path> <pr_number> [base_branch]"
  echo "Exemple : bash merge_pr.sh addons/oca_partner_contact 1234 16.0"
  exit 1
fi

# Résoudre le chemin absolu du submodule
REPO_PATH=$(realpath "$SUBMODULE_PATH")

# Aller dans le dossier
cd "$REPO_PATH" || { echo "❌ Répertoire $REPO_PATH introuvable."; exit 1; }

# Récupérer l'URL du dépôt d'origine
REPO_URL=$(git config --get remote.origin.url)
REPO_NAME=$(basename -s .git "$REPO_URL")

echo "📦 Dépôt : $REPO_NAME"
echo "🌱 Branche de base : $BASE_BRANCH"
echo "🔢 PR à merger : #$PR_NUMBER"

echo "🔄 Récupération de la PR depuis GitHub..."
git fetch origin pull/$PR_NUMBER/head:pr-$PR_NUMBER

echo "🧪 Merge de la PR dans $BASE_BRANCH..."
git checkout "$BASE_BRANCH"
git pull origin "$BASE_BRANCH"
git merge --no-ff pr-$PR_NUMBER -m "Merge PR #$PR_NUMBER from $REPO_NAME"

if [ $? -eq 0 ]; then
  echo "✅ PR #$PR_NUMBER mergée avec succès dans $BASE_BRANCH."
else
  echo "⚠️ Conflits détectés. Veuillez les résoudre manuellement dans $REPO_PATH."
fi
EOF

    # Script de configuration des permissions
    cat > "$CLIENT_DIR/scripts/setup_permissions.sh" << 'EOF'
#!/bin/bash

# Script pour configurer les permissions des dossiers Odoo
# Généré automatiquement - ne pas modifier manuellement

set -e

echo "🔧 Configuration des permissions des dossiers Odoo..."

# Créer les dossiers nécessaires s'ils n'existent pas
mkdir -p data/filestore data/sessions logs

# Vérifier si nous sommes en mode développement (avec sudo)
if [ "$EUID" -eq 0 ] || command -v sudo >/dev/null 2>&1; then
    echo "📁 Configuration des permissions avec les privilèges administrateur..."
    
    # L'utilisateur odoo dans le conteneur a l'UID 101 et GID 101
    ODOO_UID=101
    ODOO_GID=101
    
    # Créer le groupe et l'utilisateur s'ils n'existent pas
    if ! getent group odoo-container >/dev/null 2>&1; then
        groupadd -g $ODOO_GID odoo-container 2>/dev/null || true
    fi
    
    if ! getent passwd odoo-container >/dev/null 2>&1; then
        useradd -u $ODOO_UID -g $ODOO_GID -s /bin/false odoo-container 2>/dev/null || true
    fi
    
    # Configurer les permissions
    if command -v sudo >/dev/null 2>&1 && [ "$EUID" -ne 0 ]; then
        sudo chown -R $ODOO_UID:$ODOO_GID data logs
        sudo chmod -R 755 data logs
    else
        chown -R $ODOO_UID:$ODOO_GID data logs
        chmod -R 755 data logs
    fi
    
    echo "✅ Permissions configurées pour l'utilisateur odoo-container (UID: $ODOO_UID, GID: $ODOO_GID)"
else
    echo "📁 Configuration des permissions en mode utilisateur..."
    
    # En mode utilisateur, essayer de configurer les permissions de base
    chmod -R 755 data logs 2>/dev/null || true
    
    echo "✅ Permissions de base configurées"
    echo "💡 Pour des permissions optimales, exécutez: sudo ./scripts/setup_permissions.sh"
fi

echo "📂 Structure des dossiers de données:"
ls -la data/ logs/ 2>/dev/null || true
EOF

    # Script de build Docker par branche
    cat > "$CLIENT_DIR/scripts/build_client_branch_docker.sh" << 'EOF'
#!/bin/bash

# Script pour construire une image Docker spécifique à une branche
# Utilise la même logique que le script principal mais adapté au contexte client

set -e

# Détection automatique du répertoire de base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT_DIR="$(dirname "$SCRIPT_DIR")"
BASE_DIR="$(cd "$CLIENT_DIR/../.." && pwd)"

# Extraire le nom du client depuis le répertoire
CLIENT_NAME="$(basename "$CLIENT_DIR")"

echo "🔨 Building Docker image for client: $CLIENT_NAME"
echo "📁 Client directory: $CLIENT_DIR"
echo "🏠 Base directory: $BASE_DIR"

# Appeler le script principal depuis le répertoire de base
cd "$BASE_DIR"
exec ./scripts/build_client_branch_docker.sh "$CLIENT_NAME" "$@"
EOF

    # Script de démarrage par branche avec Compose
    cat > "$CLIENT_DIR/scripts/start_client_branch.sh" << 'EOF'
#!/bin/bash

# Script pour démarrer un service Docker spécifique à une branche
# Utilise la même logique que le script principal mais adapté au contexte client

set -e

# Détection automatique du répertoire de base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT_DIR="$(dirname "$SCRIPT_DIR")"
BASE_DIR="$(cd "$CLIENT_DIR/../.." && pwd)"

# Extraire le nom du client depuis le répertoire
CLIENT_NAME="$(basename "$CLIENT_DIR")"

echo "🚀 Starting branch service for client: $CLIENT_NAME"
echo "📁 Client directory: $CLIENT_DIR"
echo "🏠 Base directory: $BASE_DIR"

# Appeler le script principal depuis le répertoire de base
cd "$BASE_DIR"
exec ./scripts/start_client_branch_compose.sh "$CLIENT_NAME" "$@"
EOF

    # Script d'arrêt par branche avec Compose
    cat > "$CLIENT_DIR/scripts/stop_client_branch.sh" << 'EOF'
#!/bin/bash

# Script pour arrêter un service Docker spécifique à une branche
# Utilise la même logique que le script principal mais adapté au contexte client

set -e

# Détection automatique du répertoire de base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT_DIR="$(dirname "$SCRIPT_DIR")"
BASE_DIR="$(cd "$CLIENT_DIR/../.." && pwd)"

# Extraire le nom du client depuis le répertoire
CLIENT_NAME="$(basename "$CLIENT_DIR")"

echo "🛑 Stopping branch service for client: $CLIENT_NAME"
echo "📁 Client directory: $CLIENT_DIR"
echo "🏠 Base directory: $BASE_DIR"

# Appeler le script principal depuis le répertoire de base
cd "$BASE_DIR"
exec ./scripts/stop_client_branch_compose.sh "$CLIENT_NAME" "$@"
EOF

    # Rendre les scripts exécutables
    chmod +x "$CLIENT_DIR/scripts"/*.sh
}

# Créer le README du client
create_readme() {
    echo_info "Création du README..."
    
    cat > "$CLIENT_DIR/README.md" << EOF
# Projet Odoo - $CLIENT_NAME

Configuration Odoo pour le client **$CLIENT_NAME**.

## Configuration
- **Version Odoo**: $ODOO_VERSION
- **Template**: $TEMPLATE
- **Enterprise**: $([ "$HAS_ENTERPRISE" = "true" ] && echo "Oui" || echo "Non")

## Structure du projet

\`\`\`
$CLIENT_NAME/
├── addons/                 # Submodules OCA et autres dépôts
├── extra-addons/           # Liens symboliques vers les modules activés
├── config/                 # Fichiers de configuration
│   └── odoo.conf
├── scripts/                # Scripts utilitaires
├── logs/                   # Logs Odoo
├── docker-compose.yml      # Configuration Docker
└── requirements.txt        # Dépendances Python
\`\`\`

## Installation

1. **Cloner le dépôt avec les submodules** :
   \`\`\`bash
   git clone --recursive <url_du_depot>
   cd $CLIENT_NAME
   \`\`\`

2. **Initialiser les submodules** (si pas fait au clone) :
   \`\`\`bash
   ./scripts/update_submodules.sh
   \`\`\`

$([ "$HAS_ENTERPRISE" = "true" ] && echo "3. **Ajouter Odoo Enterprise** :
   \`\`\`bash
   rm -rf addons/enterprise
   git submodule add -b $ODOO_VERSION https://github.com/odoo/enterprise.git addons/enterprise
   \`\`\`" || echo "")

## Utilisation

### Démarrer l'environnement
\`\`\`bash
./scripts/start.sh
\`\`\`

### Activer des modules
Pour activer un module, créez un lien symbolique :
\`\`\`bash
./scripts/link_modules.sh addons/partner-contact partner_firstname
\`\`\`

### Accéder à Odoo
- URL: http://localhost:8069
- Base de données: ${CLIENT_NAME}_prod (ou autre nom commençant par ${CLIENT_NAME}_)

### Merger une Pull Request d'un submodule
\`\`\`bash
./scripts/merge_pr.sh addons/partner-contact 1234 16.0
\`\`\`

### Mise à jour des submodules
\`\`\`bash
./scripts/update_submodules.sh
\`\`\`

### Mise à jour des requirements Python
\`\`\`bash
./scripts/update_requirements.sh
\`\`\`

## Scripts disponibles

- \`scripts/update_submodules.sh\` - Met à jour tous les submodules
- \`scripts/update_requirements.sh\` - Met à jour requirements.txt avec les dépendances OCA
- \`scripts/link_modules.sh\` - Crée des liens symboliques vers les modules
- \`scripts/start.sh\` - Démarre l'environnement Docker
- \`scripts/merge_pr.sh\` - Merge une Pull Request dans un submodule

## Modules OCA installés

EOF

    # Ajouter la liste des modules installés
    if [ "$TEMPLATE" != "custom" ]; then
        jq -c ".client_templates.\"$TEMPLATE\".default_modules[]" "$CONFIG_DIR/client_templates.json" | while read -r module_config; do
            local repository=$(echo "$module_config" | jq -r '.repository')
            local modules=$(echo "$module_config" | jq -r '.modules')
            local desc=$(jq -r ".oca_repositories[\"$repository\"].description" "$CONFIG_DIR/repositories.json")
            
            if [ "$modules" = "all" ]; then
                echo "- **$repository**: $desc (tous les modules)" >> "$CLIENT_DIR/README.md"
            else
                local module_list=$(echo "$module_config" | jq -r '.modules | join(", ")')
                echo "- **$repository**: $desc (modules: $module_list)" >> "$CLIENT_DIR/README.md"
            fi
        done
    fi

    cat >> "$CLIENT_DIR/README.md" << EOF

    cat >> "$CLIENT_DIR/README.md" << EOF

## Utilisation avec Docker

Ce projet inclut deux options pour utiliser Docker :

### Option 1 : Image Docker dédiée (Recommandée)

Le sous-dossier \`docker/\` contient tous les fichiers nécessaires pour construire une image Docker spécifique au client.

1. **Construire l'image** :
   \`\`\`bash
   cd docker/
   ./build.sh
   \`\`\`

2. **Lancer les services** :
   \`\`\`bash
   docker-compose up -d
   \`\`\`

3. **Accéder à Odoo** :
   - URL: http://localhost:8069

**Avantages** :
- Image optimisée pour le client
- Dépendances Python pré-installées
- Configuration spécifique intégrée
- Autonomie complète du projet

### Option 2 : Image générique (À la racine)

Utiliser le \`docker-compose.yml\` à la racine avec l'image Odoo générique.

\`\`\`bash
docker-compose up -d
\`\`\`

### Fichiers Docker inclus

\`\`\`
docker/
├── Dockerfile              # Image Docker dédiée odoo-alusage-$CLIENT_NAME
├── docker-compose.yml      # Services complets (Odoo + PostgreSQL)
├── entrypoint.sh          # Script d'entrée personnalisé
├── install_requirements.sh # Installation des dépendances Python
└── build.sh               # Script de construction simplifié
\`\`\`

### Commandes Docker utiles

- **Voir les logs** : \`docker-compose logs -f odoo\`
- **Shell dans le conteneur** : \`docker-compose exec odoo bash\`
- **Mode debug** : Décommentez \`DEBUG_MODE=true\` dans docker-compose.yml
- **Rebuild l'image** : \`cd docker && ./build.sh --no-cache\`

## Configuration Docker

Le fichier \`docker-compose.yml\` configure :
- Service Odoo sur le port 8069
- Base de données PostgreSQL
- Volumes persistants pour les données
- Healthchecks pour les services
- Réseau dédié

## Notes importantes

- Les modules sont dans \`addons/\` comme submodules Git
- Seuls les modules liés dans \`extra-addons/\` sont chargés par Odoo
- La configuration de base filtre les bases de données par le préfixe \`${CLIENT_NAME}_\`
- Les logs sont stockés dans le dossier \`logs/\`

EOF
}

# Créer les liens symboliques pour les modules Enterprise
create_enterprise_links() {
    if [ "$HAS_ENTERPRISE" = "true" ] && [ -d "$CLIENT_DIR/addons/enterprise" ]; then
        echo_info "Création des liens symboliques pour les modules Enterprise..."
        cd "$CLIENT_DIR"
        
        # Compter le nombre de modules
        local module_count=0
        local linked_count=0
        
        # Parcourir tous les dossiers dans addons/enterprise
        for module_dir in addons/enterprise/*/; do
            if [ -d "$module_dir" ]; then
                module_count=$((module_count + 1))
                module_name=$(basename "$module_dir")
                
                # Ignorer certains dossiers techniques
                case "$module_name" in
                    ".git"|".tx"|"setup")
                        continue
                        ;;
                esac
                
                # Vérifier que c'est bien un module Odoo (contient __manifest__.py)
                if [ -f "$module_dir/__manifest__.py" ] || [ -f "$module_dir/__openerp__.py" ]; then
                    # Créer le lien symbolique dans extra-addons
                    if ln -sf "../$module_dir" "extra-addons/$module_name" 2>/dev/null; then
                        linked_count=$((linked_count + 1))
                    else
                        echo_warning "Échec de création du lien pour $module_name"
                    fi
                fi
            fi
        done
        
        echo_success "Liens symboliques Enterprise créés : $linked_count modules liés"
        echo_info "   - Modules Enterprise trouvés : $module_count"
        echo_info "   - Modules liés dans extra-addons : $linked_count"
    fi
}

# Commit initial
create_initial_commit() {
    echo_info "Création du commit initial..."
    
    cd "$CLIENT_DIR"
    git add .
    git commit -m "Initial commit for client $CLIENT_NAME

- Odoo version: $ODOO_VERSION
- Template: $TEMPLATE
- Enterprise: $([ "$HAS_ENTERPRISE" = "true" ] && echo "Yes" || echo "No")
- OCA modules configured"
}

# Mise à jour automatique des requirements.txt
update_requirements_automatically() {
    echo_info "Génération automatique des requirements.txt basés sur les modules installés..."
    
    cd "$CLIENT_DIR"
    
    # Vérifier que le script existe et est exécutable
    if [ -f "scripts/update_requirements.sh" ] && [ -x "scripts/update_requirements.sh" ]; then
        echo_info "Exécution du script update_requirements.sh..."
        ./scripts/update_requirements.sh --clean
        
        if [ $? -eq 0 ]; then
            echo_success "Requirements.txt mis à jour automatiquement"
        else
            echo_warning "Échec de la mise à jour automatique des requirements"
            echo_info "Vous pouvez lancer manuellement: ./scripts/update_requirements.sh"
        fi
    else
        echo_warning "Script update_requirements.sh non trouvé ou non exécutable"
    fi
}

# Créer le Dockerfile spécifique au client
create_client_dockerfile() {
    local docker_dir="$1"
    local dockerfile="$docker_dir/Dockerfile"
    
    echo_info "Génération du Dockerfile pour odoo-alusage-$CLIENT_NAME..."
    
    cat > "$dockerfile" << EOF
# Dockerfile pour le client $CLIENT_NAME
# Image Odoo personnalisée avec modules spécifiques
# Généré automatiquement - ne pas modifier manuellement

# Étape 1 : Utiliser l'image officielle Odoo comme base
ARG ODOO_VERSION=$ODOO_VERSION
FROM odoo:\${ODOO_VERSION}

# Métadonnées de l'image
LABEL maintainer="Odoo Alusage"
LABEL description="Image Odoo personnalisée pour le client $CLIENT_NAME"
LABEL version="1.0"
LABEL odoo.version="$ODOO_VERSION"
LABEL client.name="$CLIENT_NAME"
LABEL client.template="$TEMPLATE"
LABEL client.enterprise="$HAS_ENTERPRISE"

# Étape 2 : Installer les outils nécessaires et les polices
USER root
RUN apt-get update && apt-get install -y \\
    python3-pip \\
    fonts-liberation \\
    fonts-dejavu-core \\
    fontconfig \\
    gosu \\
    && fc-cache -f -v \\
    && rm -rf /var/lib/apt/lists/*

# Étape 3 : Définir les variables d'environnement
ENV ODOO_CONF_DIR=/etc/odoo
ENV CUSTOM_CONF_DIR=/mnt/config
ENV REQUIREMENTS_FILE=/mnt/requirements.txt
ENV EXTRA_ADDONS_DIR=/mnt/extra-addons
ENV ADDONS_DIR=/mnt/addons
ENV DEBUG_MODE=false
ENV CLIENT_NAME=$CLIENT_NAME

# Étape 4 : Créer les répertoires nécessaires avec les bonnes permissions
RUN mkdir -p \${CUSTOM_CONF_DIR} \${EXTRA_ADDONS_DIR} \${ADDONS_DIR} /data /var/lib/odoo && \\
    chown -R odoo:odoo \${CUSTOM_CONF_DIR} \${EXTRA_ADDONS_DIR} \${ADDONS_DIR} /data /var/lib/odoo && \\
    chmod -R 755 /data /var/lib/odoo

# Étape 5 : Copier les scripts personnalisés
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/install_requirements.sh /usr/local/bin/install_requirements.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/install_requirements.sh

# Étape 6 : Configurer le PATH pour l'utilisateur odoo
ENV PATH="/var/lib/odoo/.local/bin:\$PATH"

# Étape 7 : Remplacer le point d'entrée par le script personnalisé
# L'entrypoint s'exécute en tant que root pour configurer les permissions
# puis bascule vers l'utilisateur odoo
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Étape 8 : Commande par défaut
CMD ["odoo"]

# Instructions de build :
# docker build -t odoo-alusage-$CLIENT_NAME .
# 
# Instructions d'usage :
# docker run -d \\
#   --name odoo-$CLIENT_NAME \\
#   -p 8069:8069 \\
#   -v \$(pwd)/../config:/mnt/config \\
#   -v \$(pwd)/../extra-addons:/mnt/extra-addons \\
#   -v \$(pwd)/../addons:/mnt/addons \\
#   -v \$(pwd)/../requirements.txt:/mnt/requirements.txt \\
#   -v \$(pwd)/../data:/data \\
#   odoo-alusage-$CLIENT_NAME
EOF
}

# Créer l'entrypoint spécifique au client
create_client_entrypoint() {
    local docker_dir="$1"
    local entrypoint="$docker_dir/entrypoint.sh"
    
    echo_info "Création de l'entrypoint pour le client..."
    
    # Copier l'entrypoint principal et l'adapter
    cp "$ROOT_DIR/docker/entrypoint.sh" "$entrypoint"
    
    # Ajouter une section spécifique au client au début
    sed -i '1a\\n# Entrypoint personnalisé pour le client '$CLIENT_NAME'\n# Version Odoo: '$ODOO_VERSION'\n# Template: '$TEMPLATE'\n# Enterprise: '$HAS_ENTERPRISE'\n' "$entrypoint"
    
    chmod +x "$entrypoint"
}

# Créer le script d'installation des requirements
create_client_install_requirements() {
    local docker_dir="$1"
    local install_script="$docker_dir/install_requirements.sh"
    
    echo_info "Création du script d'installation des requirements..."
    
    # Copier le script principal
    cp "$ROOT_DIR/docker/install_requirements.sh" "$install_script"
    chmod +x "$install_script"
}

# Créer un script de build pour faciliter l'usage
create_client_build_script() {
    local docker_dir="$1"
    local build_script="$docker_dir/build.sh"
    
    echo_info "Création du script de build..."
    
    cat > "$build_script" << EOF
#!/bin/bash

# Script de build pour l'image Docker du client $CLIENT_NAME
# Usage: ./build.sh [options]

set -e

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo_info() { echo -e "\${BLUE}-  \$1\${NC}"; }
echo_success() { echo -e "\${GREEN}✅ \$1\${NC}"; }
echo_warning() { echo -e "\${YELLOW}⚠️  \$1\${NC}"; }
echo_error() { echo -e "\${RED}❌ \$1\${NC}"; }

# Variables
CLIENT_NAME="$CLIENT_NAME"
ODOO_VERSION="$ODOO_VERSION"
IMAGE_NAME="odoo-alusage-\$CLIENT_NAME"
IMAGE_TAG="$ODOO_VERSION"

# Options
PUSH=false
NO_CACHE=false

# Gestion des arguments
while [[ \$# -gt 0 ]]; do
    case \$1 in
        --push)
            PUSH=true
            shift
            ;;
        --no-cache)
            NO_CACHE=true
            shift
            ;;
        --tag)
            IMAGE_TAG="\$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: \$0 [options]"
            echo ""
            echo "Options:"
            echo "  --push      Push l'image vers le registry après build"
            echo "  --no-cache  Build sans utiliser le cache"
            echo "  --tag TAG   Tag à utiliser (défaut: $ODOO_VERSION)"
            echo "  --help      Afficher cette aide"
            exit 0
            ;;
        *)
            echo_error "Option inconnue: \$1"
            exit 1
            ;;
    esac
done

echo_info "🐳 Build de l'image Docker pour le client \$CLIENT_NAME"
echo_info "📋 Configuration:"
echo "   - Client: \$CLIENT_NAME"
echo "   - Version Odoo: \$ODOO_VERSION"
echo "   - Image: \$IMAGE_NAME:\$IMAGE_TAG"
echo "   - Push: \$([ \$PUSH = true ] && echo "Oui" || echo "Non")"
echo "   - No Cache: \$([ \$NO_CACHE = true ] && echo "Oui" || echo "Non")"

# Construction de l'image
echo_info "🔨 Construction de l'image..."

BUILD_ARGS="--build-arg ODOO_VERSION=\$ODOO_VERSION"
BUILD_ARGS="\$BUILD_ARGS --tag \$IMAGE_NAME:\$IMAGE_TAG"

if [ \$NO_CACHE = true ]; then
    BUILD_ARGS="\$BUILD_ARGS --no-cache"
fi

if docker build \$BUILD_ARGS .; then
    echo_success "✅ Image construite avec succès: \$IMAGE_NAME:\$IMAGE_TAG"
else
    echo_error "❌ Échec de la construction de l'image"
    exit 1
fi

# Push optionnel
if [ \$PUSH = true ]; then
    echo_info "📤 Push de l'image vers le registry..."
    if docker push "\$IMAGE_NAME:\$IMAGE_TAG"; then
        echo_success "✅ Image pushée avec succès"
    else
        echo_error "❌ Échec du push de l'image"
        exit 1
    fi
fi

echo_success "🎉 Build terminé avec succès !"
echo_info "💡 Pour lancer le conteneur:"
echo "   docker-compose up -d"
echo ""
echo_info "💡 Pour lancer manuellement:"
echo "   docker run -d \\\\"
echo "     --name odoo-\$CLIENT_NAME \\\\"
echo "     -p 8069:8069 \\\\"
echo "     -v \\\$(pwd)/../config:/mnt/config \\\\"
echo "     -v \\\$(pwd)/../extra-addons:/mnt/extra-addons \\\\"
echo "     -v \\\$(pwd)/../addons:/mnt/addons \\\\"
echo "     -v \\\$(pwd)/../requirements.txt:/mnt/requirements.txt \\\\"
echo "     -v \\\$(pwd)/../data:/data \\\\"
echo "     \$IMAGE_NAME:\$IMAGE_TAG"

EOF

    chmod +x "$build_script"
}

# Fonction principale
main() {
    validate_parameters
    create_client_structure
    add_submodules
    apply_automatic_linking
    add_enterprise
    create_enterprise_links
    create_config_files
    create_scripts
    create_readme
    update_requirements_automatically
    create_initial_commit
    
    echo_success "Dépôt client '$CLIENT_NAME' créé avec succès !"
    echo_info "💡 Structure créée:"
    echo "   📁 clients/$CLIENT_NAME/"
    echo "   ├── ⚙️  config/          (Configuration Odoo)"
    echo "   ├── 📦 extra-addons/     (Modules OCA et externes)"
    echo "   ├── 🏢 addons/           (Modules Enterprise)"
    echo "   ├── 🛠️  scripts/         (Scripts de gestion)"
    echo "   ├── 🐳 docker/           (Fichiers Docker pour le build)"
    echo "   ├── 📄 requirements.txt  (Dépendances Python)"
    echo "   ├── 🐙 docker-compose.yml (Configuration complète)"
    echo "   └── 🐙 .git/            (Dépôt Git)"
    echo ""
    echo_info "🚀 Pour démarrer:"
    echo "   cd clients/$CLIENT_NAME"
    echo "   docker-compose up -d      # Lancer les services"
}

# Exécuter
main

#!/bin/bash

# Script pour générer un dépôt client
# Usage: generate_client_repo.sh <client_name> <odoo_version> <template> <has_enterprise>

set -e

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

echo_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
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
    if ! jq -e ".client_templates.\"$TEMPLATE\"" "$CONFIG_DIR/templates.json" >/dev/null 2>&1; then
        echo_error "Template '$TEMPLATE' non trouvé dans la configuration"
        echo_info "Templates disponibles :"
        jq -r '.client_templates | keys[]' "$CONFIG_DIR/templates.json"
        exit 1
    fi
    
    # Vérifier que la version Odoo est supportée
    if ! jq -e ".odoo_versions[] | select(.version == \"$ODOO_VERSION\")" "$CONFIG_DIR/templates.json" >/dev/null 2>&1; then
        echo_error "Version Odoo '$ODOO_VERSION' non supportée"
        echo_info "Versions disponibles :"
        jq -r '.odoo_versions[].version' "$CONFIG_DIR/templates.json"
        exit 1
    fi
}

# Créer la structure du dépôt client
create_client_structure() {
    echo_info "Création de la structure pour $CLIENT_NAME..."
    
    mkdir -p "$CLIENT_DIR"
    cd "$CLIENT_DIR"
    
    # Initialiser le dépôt Git
    git init
    
    # Créer les dossiers principaux
    mkdir -p addons extra-addons config scripts
    
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
        jq -r '.oca_repositories | to_entries[] | "\(.key) - \(.value.description)"' "$CONFIG_DIR/templates.json"
        echo
        read -p "Entrez les modules souhaités (séparés par des espaces): " modules_list
        modules_array=($modules_list)
    else
        # Récupérer les modules du template
        readarray -t modules_array < <(jq -r ".client_templates.\"$TEMPLATE\".default_modules[]" "$CONFIG_DIR/templates.json")
    fi
    
    # Valider les modules avec l'optimisateur
    echo_info "Validation des modules OCA..."
    local valid_modules
    valid_modules=$(validate_oca_modules "$CLIENT_DIR" "$ODOO_VERSION" "${modules_array[@]}")
    if [[ $? -ne 0 ]]; then
        echo_error "Validation des modules échouée"
        return 1
    fi
    
    readarray -t validated_modules <<< "$valid_modules"
    
    cd "$CLIENT_DIR"
    
    for module in "${validated_modules[@]}"; do
        if [[ -n "$module" ]]; then
            local url=$(jq -r ".oca_repositories.\"$module\".url" "$CONFIG_DIR/templates.json")
            if [ "$url" != "null" ]; then
                echo_info "Ajout du submodule: $module"
                
                # Essayer d'abord le clonage optimisé
                if clone_repository_optimized "$module" "$ODOO_VERSION" "addons/oca_$module"; then
                    # Convertir en submodule git
                    git submodule add -b "$ODOO_VERSION" "$url" "addons/oca_$module" 2>/dev/null || {
                        echo_warning "Ajout direct du dépôt cloné comme submodule"
                        git add "addons/oca_$module"
                    }
                else
                    # Fallback vers la méthode standard
                    echo_warning "Fallback vers le submodule standard pour $module"
                    git submodule add -b "$ODOO_VERSION" "$url" "addons/oca_$module" || {
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

# Ajouter Odoo Enterprise si demandé
add_enterprise() {
    if [ "$HAS_ENTERPRISE" = "true" ]; then
        echo_info "Préparation pour Odoo Enterprise..."
        cd "$CLIENT_DIR"
        
        # Créer un placeholder pour enterprise
        mkdir -p addons/enterprise
        cat > addons/enterprise/README.md << EOF
# Odoo Enterprise

Ce dossier doit contenir les modules Odoo Enterprise.

Pour l'ajouter comme submodule :
\`\`\`bash
rm -rf addons/enterprise
git submodule add -b $ODOO_VERSION https://github.com/odoo/enterprise.git addons/enterprise
\`\`\`

Note: Vous devez avoir accès au dépôt Odoo Enterprise.
EOF
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
db_host = localhost
db_port = 5432
db_user = odoo
db_password = odoo
dbfilter = ^${CLIENT_NAME}_.*$
logfile = logs/odoo.log
log_level = info
workers = 2
max_cron_threads = 1
EOF

    # docker-compose.yml
    cat > "$CLIENT_DIR/docker-compose.yml" << EOF
version: '3.8'

services:
  odoo:
    image: odoo:$ODOO_VERSION
    depends_on:
      - db
    ports:
      - "8069:8069"
    volumes:
      - ./config/odoo.conf:/etc/odoo/odoo.conf
      - ./extra-addons:/mnt/extra-addons
      - ./addons:/mnt/addons
      - odoo-data:/var/lib/odoo
      - ./logs:/var/log/odoo
    environment:
      - HOST=db
      - USER=odoo
      - PASSWORD=odoo
    restart: unless-stopped

  db:
    image: postgres:13
    environment:
      - POSTGRES_DB=postgres
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=odoo
    volumes:
      - postgres-data:/var/lib/postgresql/data
    restart: unless-stopped

volumes:
  odoo-data:
  postgres-data:
EOF

    # requirements.txt
    cat > "$CLIENT_DIR/requirements.txt" << EOF
# Requirements pour Odoo $ODOO_VERSION
wheel
setuptools
EOF

    # Créer le dossier logs
    mkdir -p "$CLIENT_DIR/logs"
    touch "$CLIENT_DIR/logs/.gitkeep"
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
    echo "Exemple: $0 addons/oca_partner partner_firstname"
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
docker-compose up -d

echo "✅ Environnement démarré"
echo "🌐 Odoo accessible sur: http://localhost:8069"
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
./scripts/link_modules.sh addons/oca_partner partner_firstname
\`\`\`

### Accéder à Odoo
- URL: http://localhost:8069
- Base de données: ${CLIENT_NAME}_prod (ou autre nom commençant par ${CLIENT_NAME}_)

### Mise à jour des submodules
\`\`\`bash
./scripts/update_submodules.sh
\`\`\`

## Scripts disponibles

- \`scripts/update_submodules.sh\` - Met à jour tous les submodules
- \`scripts/link_modules.sh\` - Crée des liens symboliques vers les modules
- \`scripts/start.sh\` - Démarre l'environnement Docker

## Modules OCA installés

EOF

    # Ajouter la liste des modules installés
    if [ "$TEMPLATE" != "custom" ]; then
        jq -r ".client_templates.\"$TEMPLATE\".default_modules[]" "$CONFIG_DIR/templates.json" | while read module; do
            local desc=$(jq -r ".oca_repositories.\"$module\".description" "$CONFIG_DIR/templates.json")
            echo "- **$module**: $desc" >> "$CLIENT_DIR/README.md"
        done
    fi

    cat >> "$CLIENT_DIR/README.md" << EOF

## Configuration Docker

Le fichier \`docker-compose.yml\` configure :
- Service Odoo sur le port 8069
- Base de données PostgreSQL
- Volumes persistants pour les données

## Notes importantes

- Les modules sont dans \`addons/\` comme submodules Git
- Seuls les modules liés dans \`extra-addons/\` sont chargés par Odoo
- La configuration de base filtre les bases de données par le préfixe \`${CLIENT_NAME}_\`
- Les logs sont stockés dans le dossier \`logs/\`

EOF
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

# Fonction principale
main() {
    validate_parameters
    create_client_structure
    add_submodules
    add_enterprise
    create_config_files
    create_scripts
    create_readme
    create_initial_commit
    
    echo_success "Dépôt client '$CLIENT_NAME' créé avec succès !"
}

# Exécuter
main

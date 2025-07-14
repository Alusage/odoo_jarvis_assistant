#!/bin/bash
# Opérations GitHub pour la gestion des dépôts clients

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
GITHUB_CONFIG="$REPO_ROOT/config/github_config.json"

# Source des fonctions de configuration
source "$SCRIPT_DIR/setup_github.sh"

check_repository_exists() {
    local client_name="$1"
    local organization="$2"
    local token="$3"
    
    if [ -z "$client_name" ] || [ -z "$organization" ] || [ -z "$token" ]; then
        echo "❌ Paramètres manquants pour check_repository_exists"
        return 2
    fi
    
    local repo_url="https://api.github.com/repos/$organization/$client_name"
    
    echo "🔍 Vérification de l'existence du dépôt: $organization/$client_name"
    
    response=$(curl -s -H "Authorization: token $token" "$repo_url")
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token $token" "$repo_url")
    
    case "$http_code" in
        200)
            echo "✅ Dépôt existe: $organization/$client_name"
            return 0
            ;;
        404)
            echo "📝 Dépôt n'existe pas: $organization/$client_name"
            return 1
            ;;
        *)
            echo "❌ Erreur lors de la vérification (HTTP $http_code)"
            echo "Réponse: $response"
            return 2
            ;;
    esac
}

create_github_repository() {
    local client_name="$1"
    local organization="$2"
    local token="$3"
    local description="$4"
    
    if [ -z "$client_name" ] || [ -z "$organization" ] || [ -z "$token" ]; then
        echo "❌ Paramètres manquants pour create_github_repository"
        return 1
    fi
    
    [ -z "$description" ] && description="Odoo client repository for $client_name"
    
    echo "🚀 Création du dépôt GitHub: $organization/$client_name"
    
    # Créer le dépôt dans l'organisation
    local api_url="https://api.github.com/orgs/$organization/repos"
    local payload=$(jq -n \
        --arg name "$client_name" \
        --arg description "$description" \
        '{
            name: $name,
            description: $description,
            private: true,
            has_issues: true,
            has_projects: false,
            has_wiki: false,
            auto_init: false
        }')
    
    response=$(curl -s -X POST \
        -H "Authorization: token $token" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$api_url")
    
    if echo "$response" | jq -e '.clone_url' >/dev/null 2>&1; then
        clone_url=$(echo "$response" | jq -r '.clone_url')
        ssh_url=$(echo "$response" | jq -r '.ssh_url')
        echo "✅ Dépôt créé avec succès"
        echo "   HTTPS: $clone_url"
        echo "   SSH: $ssh_url"
        return 0
    else
        echo "❌ Erreur lors de la création du dépôt"
        echo "Réponse: $response"
        return 1
    fi
}

clone_repository_with_submodules() {
    local client_name="$1"
    local organization="$2"
    local version="$3"
    local target_dir="$4"
    
    if [ -z "$client_name" ] || [ -z "$organization" ] || [ -z "$version" ] || [ -z "$target_dir" ]; then
        echo "❌ Paramètres manquants pour clone_repository_with_submodules"
        return 1
    fi
    
    local ssh_url="git@github.com:$organization/$client_name.git"
    
    echo "📥 Clonage du dépôt: $ssh_url"
    echo "   Branche: $version"
    echo "   Destination: $target_dir"
    
    # Vérifier si le répertoire existe déjà
    if [ -d "$target_dir" ]; then
        echo "❌ Le répertoire $target_dir existe déjà"
        return 1
    fi
    
    # Cloner avec la branche spécifique et les submodules
    if git clone --recurse-submodules -b "$version" "$ssh_url" "$target_dir" 2>/dev/null; then
        echo "✅ Clonage réussi avec submodules"
        
        # Vérifier les submodules
        cd "$target_dir"
        submodule_count=$(git submodule status | wc -l)
        if [ "$submodule_count" -gt 0 ]; then
            echo "📦 $submodule_count submodule(s) détecté(s)"
            git submodule status
        fi
        
        return 0
    else
        echo "⚠️ Clonage avec branche $version a échoué, tentative sur branche par défaut..."
        
        # Tentative de clone sans branche spécifique
        if git clone --recurse-submodules "$ssh_url" "$target_dir" 2>/dev/null; then
            cd "$target_dir"
            
            # Vérifier si la branche existe
            if git ls-remote --heads origin "$version" | grep -q "$version"; then
                echo "🔄 Basculement vers la branche $version"
                git checkout -b "$version" "origin/$version"
                git submodule update --init --recursive
            else
                echo "🆕 Création de la branche $version"
                git checkout -b "$version"
            fi
            
            echo "✅ Clonage réussi"
            return 0
        else
            echo "❌ Échec du clonage du dépôt"
            return 1
        fi
    fi
}

initialize_git_repository() {
    local client_dir="$1"
    local client_name="$2"
    local version="$3"
    local organization="$4"
    
    if [ -z "$client_dir" ] || [ -z "$client_name" ] || [ -z "$version" ] || [ -z "$organization" ]; then
        echo "❌ Paramètres manquants pour initialize_git_repository"
        return 1
    fi
    
    echo "🎯 Initialisation du dépôt Git pour $client_name"
    
    cd "$client_dir" || {
        echo "❌ Impossible d'accéder au répertoire $client_dir"
        return 1
    }
    
    # Initialiser le dépôt Git
    git init
    
    # Configurer l'utilisateur si disponible
    if verify_github_config; then
        git_user=$(get_git_user)
        git_email=$(get_git_email)
        
        if [ -n "$git_user" ] && [ -n "$git_email" ]; then
            git config user.name "$git_user"
            git config user.email "$git_email"
            echo "👤 Configuration Git: $git_user <$git_email>"
        fi
    fi
    
    # Créer la branche version
    git checkout -b "$version"
    
    # Ajouter le remote GitHub
    local ssh_url="git@github.com:$organization/$client_name.git"
    git remote add origin "$ssh_url"
    echo "🔗 Remote ajouté: $ssh_url"
    
    # Créer .gitignore approprié
    cat > .gitignore << 'EOF'
# Odoo specific
*.pyc
__pycache__/
.pytest_cache/
*.egg-info/

# Data directories
data/
logs/
*.log

# IDE
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Environment
.env
.env.local

# Backups
*.backup
*.bak
requirements.txt.backup.*
EOF
    
    # Premier commit
    git add .
    git commit -m "feat: initialize Odoo client $client_name

- Odoo version: $version
- Generated with Odoo Client Generator
- Includes OCA modules as submodules
- Ready for development and deployment"
    
    echo "✅ Dépôt Git initialisé avec premier commit"
    echo "📤 Pour pousser: git push -u origin $version"
    
    return 0
}

# Fonction principale pour gérer un client avec GitHub
manage_client_with_github() {
    local client_name="$1"
    local version="$2"
    local template="$3"
    local clients_dir="$4"
    
    echo "🐙 Gestion GitHub pour le client: $client_name"
    
    # Vérifier la configuration
    if ! verify_github_config; then
        echo "❌ Configuration GitHub manquante"
        echo "Exécutez: ./scripts/setup_github.sh"
        return 1
    fi
    
    local token=$(get_github_token)
    local organization=$(get_github_org)
    local client_dir="$clients_dir/$client_name"
    
    # Vérifier si le dépôt existe
    if check_repository_exists "$client_name" "$organization" "$token"; then
        echo "📥 Clonage du dépôt existant..."
        
        if clone_repository_with_submodules "$client_name" "$organization" "$version" "$client_dir"; then
            echo "✅ Client cloné depuis GitHub"
            return 0
        else
            echo "❌ Échec du clonage"
            return 1
        fi
    else
        echo "🆕 Dépôt n'existe pas, sera créé après génération du client"
        
        # Le client sera créé normalement, puis on initialisera Git
        return 2  # Code spécial pour "créer normalement puis initialiser Git"
    fi
}

post_create_github_setup() {
    local client_name="$1"
    local version="$2"
    local client_dir="$3"
    
    echo "🐙 Configuration GitHub post-création pour: $client_name"
    
    if ! verify_github_config; then
        echo "❌ Configuration GitHub manquante"
        return 1
    fi
    
    local token=$(get_github_token)
    local organization=$(get_github_org)
    
    # Créer le dépôt sur GitHub
    if create_github_repository "$client_name" "$organization" "$token" "Odoo $version client: $client_name"; then
        # Initialiser le dépôt Git local
        if initialize_git_repository "$client_dir" "$client_name" "$version" "$organization"; then
            echo "✅ Client configuré avec GitHub"
            echo "📤 Pour pousser sur GitHub: cd $client_dir && git push -u origin $version"
            return 0
        else
            echo "❌ Échec de l'initialisation Git"
            return 1
        fi
    else
        echo "❌ Échec de la création du dépôt GitHub"
        return 1
    fi
}
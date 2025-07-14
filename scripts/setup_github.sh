#!/bin/bash
# Configuration GitHub pour Odoo Client Generator

GITHUB_CONFIG="config/github_config.json"

setup_github_config() {
    echo "🔧 Configuration GitHub pour Odoo Client Generator"
    echo "================================================="
    
    if [ ! -f "$GITHUB_CONFIG" ]; then
        echo "❌ Fichier de configuration non trouvé: $GITHUB_CONFIG"
        exit 1
    fi
    
    # Lire la configuration actuelle
    current_token=$(jq -r '.github_token // ""' "$GITHUB_CONFIG")
    current_org=$(jq -r '.github_organization // "Alusage"' "$GITHUB_CONFIG")
    current_user=$(jq -r '.git_user_name // ""' "$GITHUB_CONFIG")
    current_email=$(jq -r '.git_user_email // ""' "$GITHUB_CONFIG")
    
    echo
    echo "Configuration actuelle :"
    echo "- Organisation: $current_org"
    echo "- Token GitHub: $([ -n "$current_token" ] && echo "configuré" || echo "non configuré")"
    echo "- Utilisateur Git: $current_user"
    echo "- Email Git: $current_email"
    echo
    
    # Demander le token GitHub si pas configuré
    if [ -z "$current_token" ]; then
        echo "🔑 Configuration du token GitHub"
        echo "Créez un Personal Access Token sur GitHub avec les permissions :"
        echo "- repo (full control of private repositories)"
        echo "- admin:org (read/write access to organization)"
        echo
        echo "URL: https://github.com/settings/tokens/new"
        echo
        read -p "Entrez votre token GitHub: " github_token
        
        if [ -z "$github_token" ]; then
            echo "❌ Token requis pour continuer"
            exit 1
        fi
    else
        github_token="$current_token"
        read -p "Voulez-vous changer le token GitHub ? (y/N): " change_token
        if [[ "$change_token" =~ ^[Yy]$ ]]; then
            read -p "Nouveau token GitHub: " github_token
        fi
    fi
    
    # Demander les infos Git si pas configurées
    if [ -z "$current_user" ]; then
        read -p "Nom d'utilisateur Git (pour les commits): " git_user
    else
        git_user="$current_user"
        read -p "Nom d'utilisateur Git [$current_user]: " new_git_user
        [ -n "$new_git_user" ] && git_user="$new_git_user"
    fi
    
    if [ -z "$current_email" ]; then
        read -p "Email Git (pour les commits): " git_email
    else
        git_email="$current_email"
        read -p "Email Git [$current_email]: " new_git_email
        [ -n "$new_git_email" ] && git_email="$new_git_email"
    fi
    
    # Organisation
    organization="$current_org"
    read -p "Organisation GitHub [$current_org]: " new_org
    [ -n "$new_org" ] && organization="$new_org"
    
    # Tester le token
    echo
    echo "🧪 Test du token GitHub..."
    response=$(curl -s -H "Authorization: token $github_token" https://api.github.com/user)
    if echo "$response" | jq -e '.login' >/dev/null 2>&1; then
        username=$(echo "$response" | jq -r '.login')
        echo "✅ Token valide pour l'utilisateur: $username"
    else
        echo "❌ Token invalide ou erreur de connexion"
        echo "Réponse: $response"
        exit 1
    fi
    
    # Sauvegarder la configuration
    jq --arg token "$github_token" \
       --arg org "$organization" \
       --arg user "$git_user" \
       --arg email "$git_email" \
       '.github_token = $token | .github_organization = $org | .git_user_name = $user | .git_user_email = $email' \
       "$GITHUB_CONFIG" > "${GITHUB_CONFIG}.tmp" && mv "${GITHUB_CONFIG}.tmp" "$GITHUB_CONFIG"
    
    echo
    echo "✅ Configuration GitHub sauvegardée dans $GITHUB_CONFIG"
    echo "🔐 Attention: Ce fichier contient des informations sensibles"
}

verify_github_config() {
    if [ ! -f "$GITHUB_CONFIG" ]; then
        echo "❌ Configuration GitHub non trouvée"
        return 1
    fi
    
    token=$(jq -r '.github_token // ""' "$GITHUB_CONFIG")
    if [ -z "$token" ]; then
        echo "❌ Token GitHub non configuré"
        return 1
    fi
    
    return 0
}

get_github_token() {
    jq -r '.github_token // ""' "$GITHUB_CONFIG"
}

get_github_org() {
    jq -r '.github_organization // "Alusage"' "$GITHUB_CONFIG"
}

get_git_user() {
    jq -r '.git_user_name // ""' "$GITHUB_CONFIG"
}

get_git_email() {
    jq -r '.git_user_email // ""' "$GITHUB_CONFIG"
}

# Si le script est appelé directement
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    setup_github_config
fi
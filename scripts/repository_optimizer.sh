#!/bin/bash

# Optimization and robustness improvements for OCA repository management

CONFIG_DIR="$(dirname "$0")/../config"
CACHE_DIR="$HOME/.cache/odoo_client_generator"

# Create cache directory if it doesn't exist
mkdir -p "$CACHE_DIR"

# Function to check if a repository exists for a given version
check_repository_exists() {
    local repo_name="$1"
    local version="$2"
    local repo_url="https://github.com/OCA/$repo_name.git"
    
    echo "🔍 Vérification de l'existence du dépôt $repo_name pour la version $version..." >&2
    
    # Check if the repository exists at all
    if ! git ls-remote --heads "$repo_url" >/dev/null 2>&1; then
        echo "❌ Le dépôt $repo_name n'existe pas sur GitHub OCA" >&2
        return 1
    fi
    
    # Check if the version branch exists
    if ! git ls-remote --heads "$repo_url" "$version" >/dev/null 2>&1; then
        echo "⚠️  La branche $version n'existe pas pour le dépôt $repo_name" >&2
        return 1
    fi
    
    echo "✅ Le dépôt $repo_name existe pour la version $version" >&2
    return 0
}

# Function to create a shallow clone for faster downloads
clone_repository_optimized() {
    local repo_name="$1"
    local version="$2"
    local target_dir="$3"
    local repo_url="https://github.com/OCA/$repo_name.git"
    
    echo "📥 Clonage optimisé de $repo_name (version $version)..."
    
    # Use shallow clone with specific branch for faster download
    if git clone --depth 1 --branch "$version" --single-branch "$repo_url" "$target_dir" 2>/dev/null; then
        echo "✅ Clonage optimisé réussi pour $repo_name"
        return 0
    else
        echo "⚠️  Clonage optimisé échoué, tentative de clonage standard..."
        # Fallback to standard clone
        if git clone --branch "$version" "$repo_url" "$target_dir" 2>/dev/null; then
            echo "✅ Clonage standard réussi pour $repo_name"
            return 0
        else
            echo "❌ Échec du clonage pour $repo_name"
            return 1
        fi
    fi
}

# Function to cache repository information
cache_repository_info() {
    local repo_name="$1"
    local version="$2"
    local status="$3"  # "exists" or "missing"
    
    local cache_file="$CACHE_DIR/repo_${repo_name}_${version}.cache"
    echo "$status" > "$cache_file"
    echo "$(date +%s)" >> "$cache_file"
}

# Function to check cached repository information
check_cached_repository_info() {
    local repo_name="$1"
    local version="$2"
    local cache_file="$CACHE_DIR/repo_${repo_name}_${version}.cache"
    local cache_duration=3600  # 1 hour cache
    
    if [[ -f "$cache_file" ]]; then
        local status=$(head -n 1 "$cache_file")
        local timestamp=$(tail -n 1 "$cache_file")
        local current_time=$(date +%s)
        
        if (( current_time - timestamp < cache_duration )); then
            echo "$status"
            return 0
        fi
    fi
    
    return 1
}

# Function to validate OCA modules before adding them
validate_oca_modules() {
    local client_dir="$1"
    local version="$2"
    shift 2
    local modules=("$@")
    
    echo "🔍 Validation des modules OCA pour la version $version..." >&2
    
    local valid_modules=()
    local invalid_modules=()
    
    for module in "${modules[@]}"; do
        # Check cache first
        cached_status=$(check_cached_repository_info "$module" "$version")
        if [[ $? -eq 0 ]]; then
            if [[ "$cached_status" == "exists" ]]; then
                valid_modules+=("$module")
                echo "✅ $module (depuis le cache)" >&2
            else
                invalid_modules+=("$module")
                echo "❌ $module (depuis le cache)" >&2
            fi
        else
            # Check repository existence
            if check_repository_exists "$module" "$version"; then
                valid_modules+=("$module")
                cache_repository_info "$module" "$version" "exists"
            else
                invalid_modules+=("$module")
                cache_repository_info "$module" "$version" "missing"
            fi
        fi
    done
    
    if [[ ${#invalid_modules[@]} -gt 0 ]]; then
        echo "" >&2
        echo "⚠️  Les modules suivants ne sont pas disponibles pour la version $version :" >&2
        for module in "${invalid_modules[@]}"; do
            echo "   - $module" >&2
        done
        echo "" >&2
        echo "🤔 Voulez-vous continuer avec seulement les modules valides ? (y/N)" >&2
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "❌ Annulation de la création du dépôt client" >&2
            return 1
        fi
    fi
    
    # Export valid modules for use by the main script
    echo "${valid_modules[@]}"
    return 0
}

# Function to clean up cache
clean_cache() {
    echo "🧹 Nettoyage du cache..."
    rm -rf "$CACHE_DIR"
    echo "✅ Cache nettoyé"
}

# Function to show cache status
show_cache_status() {
    echo "📊 Statut du cache :"
    if [[ -d "$CACHE_DIR" ]]; then
        local cache_files=$(find "$CACHE_DIR" -name "*.cache" | wc -l)
        echo "   Fichiers en cache : $cache_files"
        echo "   Dossier cache : $CACHE_DIR"
        
        if [[ $cache_files -gt 0 ]]; then
            echo "   Derniers éléments mis en cache :"
            find "$CACHE_DIR" -name "*.cache" -printf '%T@ %p\n' | sort -n | tail -5 | while read timestamp file; do
                local module_info=$(basename "$file" .cache)
                echo "     - $module_info"
            done
        fi
    else
        echo "   Aucun cache trouvé"
    fi
}

# Main function for script usage
main() {
    case "${1:-}" in
        "validate")
            shift
            validate_oca_modules "$@"
            ;;
        "check")
            check_repository_exists "$2" "$3"
            ;;
        "clone")
            clone_repository_optimized "$2" "$3" "$4"
            ;;
        "clean-cache")
            clean_cache
            ;;
        "cache-status")
            show_cache_status
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 {validate|check|clone|clean-cache|cache-status|help}"
            echo ""
            echo "Commands:"
            echo "  validate CLIENT_DIR VERSION MODULE1 MODULE2...  - Valider les modules OCA"
            echo "  check REPO VERSION                              - Vérifier l'existence d'un dépôt"
            echo "  clone REPO VERSION TARGET_DIR                   - Cloner un dépôt de manière optimisée"
            echo "  clean-cache                                     - Nettoyer le cache"
            echo "  cache-status                                    - Afficher le statut du cache"
            echo "  help                                            - Afficher cette aide"
            ;;
        *)
            echo "❌ Commande inconnue. Utilisez '$0 help' pour voir les options disponibles."
            exit 1
            ;;
    esac
}

# If script is run directly, execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

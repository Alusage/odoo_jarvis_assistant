#!/bin/bash

# Script pour mettre à jour automatiquement la liste des dépôts OCA dans templates.json
# Ce script récupère tous les dépôts de l'organisation OCA sur GitHub
# Usage: update_oca_repositories.sh [--clean]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$ROOT_DIR/config"
TEMPLATES_FILE="$CONFIG_DIR/templates.json"
DESCRIPTIONS_FILE="$CONFIG_DIR/oca_descriptions.json"
TEMP_FILE="/tmp/oca_repos.json"

# Options
CLEAN_BACKUPS=false
LANGUAGE="fr"
VERIFY_ADDONS=true
FILTER_EXISTING=false

# Parser les arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            CLEAN_BACKUPS=true
            shift
            ;;
        --lang)
            LANGUAGE="$2"
            if [[ ! "$LANGUAGE" =~ ^(fr|en)$ ]]; then
                echo_error "Langue non supportée: $LANGUAGE (fr/en uniquement)"
                exit 1
            fi
            shift 2
            ;;
        --no-verify)
            VERIFY_ADDONS=false
            shift
            ;;
        --filter-existing)
            FILTER_EXISTING=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--clean] [--lang fr|en] [--no-verify] [--filter-existing]"
            echo "Options:"
            echo "  --clean            Supprimer les fichiers de sauvegarde après succès"
            echo "  --lang fr|en       Langue pour les descriptions (défaut: fr)"
            echo "  --no-verify        Désactiver la vérification des addons Odoo (plus rapide)"
            echo "  --filter-existing  Filtrer le fichier existant sans appels API"
            echo "  -h, --help         Afficher cette aide"
            exit 0
            ;;
        *)
            echo "Option inconnue: $1"
            echo "Utilisez --help pour voir les options disponibles"
            exit 1
            ;;
    esac
done

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

# Vérifier les dépendances
check_dependencies() {
    local missing_deps=()
    
    if ! command -v curl >/dev/null 2>&1; then
        missing_deps+=("curl")
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        missing_deps+=("jq")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo_error "Dépendances manquantes: ${missing_deps[*]}"
        echo_info "Installez-les avec: sudo apt-get install ${missing_deps[*]}"
        exit 1
    fi
}

# Fonction pour récupérer tous les dépôts OCA
fetch_oca_repositories() {
    echo_info "Récupération de la liste des dépôts OCA depuis GitHub..."
    
    local page=1
    local all_repos="[]"
    
    while true; do
        echo_info "Récupération de la page $page..."
        
        # Récupérer une page de dépôts (100 par page maximum)
        local response=$(curl -s "https://api.github.com/orgs/OCA/repos?page=$page&per_page=100" 2>/dev/null)
        
        # Vérifier si la réponse est valide
        if [ -z "$response" ] || [ "$response" = "[]" ]; then
            break
        fi
        
        # Vérifier si on a atteint la limite de taux
        if echo "$response" | jq -e '.message' >/dev/null 2>&1; then
            local message=$(echo "$response" | jq -r '.message')
            if [[ "$message" == *"rate limit"* ]]; then
                echo_error "Limite de taux API GitHub atteinte. Réessayez plus tard."
                exit 1
            fi
        fi
        
        # Fusionner avec les dépôts déjà récupérés
        all_repos=$(echo "$all_repos" "$response" | jq -s '.[0] + .[1]')
        
        # Si on a moins de 100 repos sur cette page, c'est la dernière
        local repo_count=$(echo "$response" | jq length)
        if [ "$repo_count" -lt 100 ]; then
            break
        fi
        
        page=$((page + 1))
        
        # Pause pour éviter de surcharger l'API
        sleep 0.5
    done
    
    echo "$all_repos" > "$TEMP_FILE"
    local total_repos=$(echo "$all_repos" | jq length)
    echo_success "Récupéré $total_repos dépôts OCA"
}

# Fonction pour filtrer les dépôts pertinents pour Odoo
filter_odoo_repositories() {
    echo_info "Filtrage des dépôts pertinents pour Odoo..."
    
    # Filtrer les dépôts qui semblent être des modules Odoo
    # Exclure les dépôts d'infrastructure, de documentation, etc.
    jq '[
        .[] | 
        select(
            .archived == false and
            .name != "odoo-sphinx-autodoc" and
            .name != "pylint-odoo" and
            .name != "odoo-test-helper" and
            .name != "openupgradelib" and
            .name != "openupgrade-addons" and
            .name != "maintainer-tools" and
            .name != "maintainer-quality-tools" and
            .name != "oca-addons-repo-template" and
            .name != "odoo-addon-template" and
            .name != "oca-port" and
            .name != "oca-github-bot" and
            .name != "odoo-pre-commit-hooks" and
            .name != "setuptools-odoo" and
            .name != "oca-custom" and
            .name != ".github" and
            .name != "repo-maintainer" and
            .name != "repo-maintainer-conf" and
            .name != "oca-ci" and
            .name != "oca-weblate-deployment" and
            .name != "mirrors-flake8" and
            (.name | test("^(odoo|addons|modules)") | not) and
            (.name | test("(tools?|helper|template|bot|sphinx|pylint|test|upgrade|setup|hook|custom|maintainer|mirror|\\.github)$") | not)
        ) |
        {
            name: .name,
            url: .clone_url,
            description: (if .description then .description else "Module OCA" end),
            stars: .stargazers_count,
            updated: .updated_at,
            topics: .topics
        }
    ] | sort_by(.name)' "$TEMP_FILE" > "${TEMP_FILE}.filtered"
    
    local filtered_count=$(jq length "${TEMP_FILE}.filtered")
    echo_success "Filtré vers $filtered_count dépôts pertinents"
}

# Fonction pour vérifier que les dépôts contiennent des addons Odoo
verify_odoo_addons() {
    echo_info "Vérification de la présence d'addons Odoo dans les dépôts..."
    echo_info "🔍 Recherche de fichiers __manifest__.py dans chaque dépôt..."
    
    local verified_repos="[]"
    local total_repos=$(jq length "${TEMP_FILE}.filtered")
    local verified_count=0
    local rejected_count=0
    
    echo_info "Vérification de $total_repos dépôts..."
    
    local repo_index=0
    while IFS= read -r repo_data; do
        repo_index=$((repo_index + 1))
        local repo_name=$(echo "$repo_data" | jq -r '.name')
        
        echo_info "[$repo_index/$total_repos] Vérification de $repo_name..."
        
        # Construire l'URL de l'API GitHub pour lister le contenu
        local api_url="https://api.github.com/repos/OCA/$repo_name/contents"
        
        # Récupérer la liste des fichiers/dossiers de premier niveau
        local contents=$(curl -s "$api_url" 2>/dev/null)
        
        # Vérifier si on a une réponse valide
        if [ -z "$contents" ] || echo "$contents" | jq -e '.message' >/dev/null 2>&1; then
            local error_msg=$(echo "$contents" | jq -r '.message' 2>/dev/null || "erreur de connexion")
            echo_warning "  ⚠️  Impossible de vérifier $repo_name ($error_msg), exclusion"
            rejected_count=$((rejected_count + 1))
            continue
        fi
        
        # Vérifier s'il y a des dossiers et si l'un d'eux contient un __manifest__.py
        local has_addon=false
        local manifest_found=""
        local directories=$(echo "$contents" | jq -r '.[] | select(.type == "dir") | .name' 2>/dev/null || echo "")
        
        if [ -n "$directories" ]; then
            # Vérifier chaque dossier pour trouver des __manifest__.py
            local dir_count=0
            while IFS= read -r dir_name && [ $dir_count -lt 5 ]; do  # Limiter à 5 dossiers par dépôt
                if [ -n "$dir_name" ]; then
                    local manifest_url="https://api.github.com/repos/OCA/$repo_name/contents/$dir_name/__manifest__.py"
                    local manifest_check=$(curl -s "$manifest_url" 2>/dev/null)
                    
                    if echo "$manifest_check" | jq -e '.name' >/dev/null 2>&1; then
                        has_addon=true
                        manifest_found="$dir_name"
                        break
                    fi
                    
                    dir_count=$((dir_count + 1))
                fi
            done <<< "$directories"
        fi
        
        if [ "$has_addon" = true ]; then
            verified_repos=$(echo "$verified_repos" | jq ". + [$repo_data]")
            verified_count=$((verified_count + 1))
            echo "     ✅ Module Odoo trouvé dans $manifest_found/"
        else
            rejected_count=$((rejected_count + 1))
            echo "     ❌ Aucun module Odoo détecté (pas de __manifest__.py)"
        fi
        
        # Pause pour éviter de surcharger l'API GitHub
        if [ $((repo_index % 10)) -eq 0 ]; then
            echo_info "  ⏸️  Pause API (traité $repo_index/$total_repos)..."
            sleep 2
        else
            sleep 0.3
        fi
    done < <(jq -c '.[]' "${TEMP_FILE}.filtered")
    
    # Sauvegarder les dépôts vérifiés
    echo "$verified_repos" > "${TEMP_FILE}.verified"
    
    echo
    echo_success "🎯 Vérification terminée:"
    echo "   - ✅ Dépôts avec modules Odoo: $verified_count"
    echo "   - ❌ Dépôts rejetés (pas de modules): $rejected_count"
    echo "   - 📊 Taux de validation: $((verified_count * 100 / total_repos))%"
    
    # Remplacer le fichier filtré par le fichier vérifié pour la suite du traitement
    cp "${TEMP_FILE}.verified" "${TEMP_FILE}.filtered"
}

# Fonction pour gérer les descriptions multilingues
manage_descriptions() {
    echo_info "Gestion des descriptions multilingues ($LANGUAGE)..."
    
    # Vérifier si le fichier de descriptions existe
    if [ ! -f "$DESCRIPTIONS_FILE" ]; then
        echo_warning "Fichier de descriptions manquant, création d'un fichier vide"
        echo '{}' > "$DESCRIPTIONS_FILE"
    fi
    
    # Créer une sauvegarde du fichier de descriptions
    local timestamp=$(date +%Y%m%d_%H%M%S)
    cp "$DESCRIPTIONS_FILE" "${DESCRIPTIONS_FILE}.backup.$timestamp"
    
    # Lire la liste des dépôts filtrés
    local repos_list=$(jq -r '.[].name' "${TEMP_FILE}.filtered")
    local new_descriptions=0
    local missing_descriptions=()
    
    # Charger les descriptions existantes
    local descriptions=$(cat "$DESCRIPTIONS_FILE")
    
    echo_info "Vérification des descriptions pour $(echo "$repos_list" | wc -l) dépôts..."
    
    # Ajouter les descriptions pour chaque dépôt
    while IFS= read -r repo_name; do
        # Vérifier si une description existe pour ce dépôt
        local has_entry=$(echo "$descriptions" | jq --arg repo "$repo_name" 'has($repo)')
        local has_lang=$(echo "$descriptions" | jq --arg repo "$repo_name" --arg lang "$LANGUAGE" 'if has($repo) then .[$repo] | has($lang) else false end')
        
        if [ "$has_entry" = "false" ]; then
            # Ajouter une nouvelle entrée vide
            descriptions=$(echo "$descriptions" | jq --arg repo "$repo_name" '. + {($repo): {"fr": "", "en": ""}}')
            new_descriptions=$((new_descriptions + 1))
            missing_descriptions+=("$repo_name")
        elif [ "$has_lang" = "false" ]; then
            # Ajouter la langue manquante
            descriptions=$(echo "$descriptions" | jq --arg repo "$repo_name" --arg lang "$LANGUAGE" '.[$repo] += {($lang): ""}')
            missing_descriptions+=("$repo_name")
        fi
    done <<< "$repos_list"
    
    # Sauvegarder les descriptions mises à jour
    echo "$descriptions" | jq '.' > "$DESCRIPTIONS_FILE"
    
    # Compter les descriptions manquantes pour la langue actuelle
    local missing_count=$(echo "$descriptions" | jq --arg lang "$LANGUAGE" '[to_entries[] | select(.value[$lang] == "")] | length')
    
    if [ $new_descriptions -gt 0 ]; then
        echo_success "Ajouté $new_descriptions nouvelles entrées de description"
    fi
    
    if [ $missing_count -gt 0 ]; then
        echo_warning "$missing_count descriptions manquantes pour la langue '$LANGUAGE'"
        echo_info "💡 Utilisez 'make edit-descriptions' pour compléter les descriptions manquantes"
        
        # Afficher les 5 premières descriptions manquantes
        local sample_missing=$(echo "$descriptions" | jq -r --arg lang "$LANGUAGE" '[to_entries[] | select(.value[$lang] == "") | .key] | .[0:5] | .[]')
        if [ -n "$sample_missing" ]; then
            echo_info "Exemples de descriptions manquantes :"
            echo "$sample_missing" | while read -r repo; do
                echo "   - $repo"
            done
            if [ $missing_count -gt 5 ]; then
                echo "   ... et $((missing_count - 5)) autres"
            fi
        fi
    fi
    
    # Générer le mapping final pour templates.json
    local final_descriptions=$(echo "$descriptions" | jq --arg lang "$LANGUAGE" '
        to_entries | map({
            key: .key,
            value: (.value[$lang] // .value.en // .value.fr // "Description à compléter")
        }) | from_entries
    ')
    
    echo "$final_descriptions" > "${TEMP_FILE}.descriptions"
    echo_success "Descriptions préparées pour la langue '$LANGUAGE'"
}
# Fonction pour mettre à jour le fichier templates.json
update_templates_file() {
    echo_info "Mise à jour du fichier templates.json..."
    
    # Lire la configuration actuelle
    local current_config=$(cat "$TEMPLATES_FILE")
    
    # Extraire les sections non-OCA
    local odoo_versions=$(echo "$current_config" | jq '.odoo_versions')
    local client_templates=$(echo "$current_config" | jq '.client_templates')
    
    # Charger les descriptions préparées
    local descriptions=$(cat "${TEMP_FILE}.descriptions")
    
    # Créer la nouvelle section oca_repositories en une seule fois
    local new_oca_repos=$(jq --argjson descriptions "$descriptions" '
        reduce .[] as $repo ({}; 
            . + {
                ($repo.name): {
                    "url": $repo.url,
                    "description": ($descriptions[$repo.name] // "Module OCA"),
                    "stars": $repo.stars,
                    "last_updated": $repo.updated
                }
            }
        )
    ' "${TEMP_FILE}.filtered")
    
    # Assembler la nouvelle configuration
    local new_config=$(jq -n --argjson versions "$odoo_versions" --argjson templates "$client_templates" --argjson oca "$new_oca_repos" '
        {
            "odoo_versions": $versions,
            "client_templates": $templates,
            "oca_repositories": $oca
        }
    ')
    
    # Écrire le nouveau fichier
    echo "$new_config" | jq '.' > "$TEMPLATES_FILE"
    
    local repo_count=$(echo "$new_oca_repos" | jq 'keys | length')
    echo_success "templates.json mis à jour avec $repo_count dépôts OCA"
}

# Fonction pour sauvegarder la configuration actuelle
backup_current_config() {
    if [ -f "$TEMPLATES_FILE" ]; then
        local backup_file="${TEMPLATES_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$TEMPLATES_FILE" "$backup_file"
        echo_info "Sauvegarde de la configuration actuelle: $backup_file"
    fi
}

# Fonction pour afficher les statistiques
show_statistics() {
    echo_info "📊 Statistiques des dépôts OCA:"
    
    local total_repos=$(jq 'length' "${TEMP_FILE}.filtered")
    echo "   Total des dépôts: $total_repos"
    
    echo "   Top 10 des dépôts les plus populaires:"
    jq -r '.[] | "\(.stars)⭐ \(.name) - Description OCA"' "${TEMP_FILE}.filtered" | sort -nr | head -10 | while read line; do
        echo "     $line"
    done
    
    echo
    echo_info "🔧 Nouveaux dépôts détectés (non présents dans la configuration précédente):"
    
    # Vérifier s'il existe des fichiers de sauvegarde
    local backup_files=(${TEMPLATES_FILE}.backup.*)
    if [ -f "${backup_files[0]}" ]; then
        local latest_backup=$(ls -t "${TEMPLATES_FILE}.backup."* 2>/dev/null | head -1)
        local old_repos=$(jq -r '.oca_repositories | keys[]' "$latest_backup" 2>/dev/null || echo "")
        local new_repos=$(jq -r '.oca_repositories | keys[]' "$TEMPLATES_FILE")
        
        local new_count=0
        echo "$new_repos" | while read repo; do
            if ! echo "$old_repos" | grep -q "^$repo$"; then
                local desc=$(jq -r ".oca_repositories[\"$repo\"].description" "$TEMPLATES_FILE")
                echo "     ✨ $repo - $desc"
                new_count=$((new_count + 1))
            fi
        done
        
        if [ $new_count -eq 0 ]; then
            echo "     Aucun nouveau dépôt détecté"
        fi
    else
        echo "     Première exécution - tous les dépôts sont nouveaux"
    fi
}

# Fonction pour nettoyer les fichiers de sauvegarde
clean_backup_files() {
    if [ "$CLEAN_BACKUPS" = true ]; then
        echo_info "🧹 Nettoyage des fichiers de sauvegarde..."
        
        local total_count=0
        
        # Nettoyer les sauvegardes de templates.json
        local templates_backup_files=(${TEMPLATES_FILE}.backup.*)
        if [ -f "${templates_backup_files[0]}" ]; then
            local count=0
            for backup_file in "${templates_backup_files[@]}"; do
                if [ -f "$backup_file" ]; then
                    rm -f "$backup_file"
                    count=$((count + 1))
                    total_count=$((total_count + 1))
                fi
            done
            echo_info "Supprimé $count sauvegarde(s) de templates.json"
        fi
        
        # Nettoyer les sauvegardes de oca_descriptions.json
        local descriptions_backup_files=(${DESCRIPTIONS_FILE}.backup.*)
        if [ -f "${descriptions_backup_files[0]}" ]; then
            local count=0
            for backup_file in "${descriptions_backup_files[@]}"; do
                if [ -f "$backup_file" ]; then
                    rm -f "$backup_file"
                    count=$((count + 1))
                    total_count=$((total_count + 1))
                fi
            done
            echo_info "Supprimé $count sauvegarde(s) de descriptions"
        fi
        
        if [ $total_count -gt 0 ]; then
            echo_success "Total supprimé: $total_count fichier(s) de sauvegarde"
        else
            echo_info "Aucun fichier de sauvegarde à supprimer"
        fi
    fi
}

# Fonction pour nettoyer les fichiers temporaires
cleanup() {
    rm -f "$TEMP_FILE" "${TEMP_FILE}.filtered" "${TEMP_FILE}.descriptions" "${TEMP_FILE}.verified"
}

# Fonction principale
main() {
    echo_info "🚀 Mise à jour automatique des dépôts OCA"
    echo_info "========================================"
    
    check_dependencies
    backup_current_config
    
    if [ "$FILTER_EXISTING" = true ]; then
        echo_info "🔄 Filtrage du fichier existant templates.json..."
        # Charger les dépôts existants depuis templates.json
        local existing_repos=$(jq -r '.oca_repositories | to_entries[] | {name: .key, url: .value.url, description: .value.description, stars: .value.stars, updated: .value.last_updated}' "$TEMPLATES_FILE")
        
        # Sauvegarder les dépôts existants dans un fichier temporaire
        echo "$existing_repos" > "$TEMP_FILE"
        
        # Passer à l'étape de filtrage
        filter_odoo_repositories
        
        # Vérification optionnelle des addons Odoo
        if [ "$VERIFY_ADDONS" = true ]; then
            verify_odoo_addons
        else
            echo_info "⏭️  Vérification des addons désactivée (--no-verify)"
        fi
        
        manage_descriptions
        update_templates_file
        show_statistics
    else
        fetch_oca_repositories
        filter_odoo_repositories
        
        # Vérification optionnelle des addons Odoo
        if [ "$VERIFY_ADDONS" = true ]; then
            verify_odoo_addons
        else
            echo_info "⏭️  Vérification des addons désactivée (--no-verify)"
        fi
        
        manage_descriptions
        update_templates_file
        show_statistics
    fi
    
    cleanup
    clean_backup_files
    
    echo_success "✨ Mise à jour terminée avec succès !"
    echo_info "📝 Le fichier templates.json a été mis à jour avec tous les dépôts OCA disponibles (langue: $LANGUAGE)."
    echo_info "🔄 Vous pouvez maintenant utiliser ces nouveaux dépôts dans vos projets clients."
    if [ "$CLEAN_BACKUPS" = true ]; then
        echo_info "🧹 Les fichiers de sauvegarde ont été supprimés (option --clean)"
    fi
}

# Gestion des signaux pour nettoyer en cas d'interruption
trap cleanup EXIT

# Exécuter le script principal
main "$@"

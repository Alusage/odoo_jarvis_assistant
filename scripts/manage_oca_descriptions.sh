#!/bin/bash

# Script pour gérer les descriptions multilingues des modules OCA
# Usage: manage_oca_descriptions.sh [COMMANDE] [OPTIONS]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$ROOT_DIR/config"
DESCRIPTIONS_FILE="$CONFIG_DIR/oca_descriptions.json"

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

# Fonction d'aide
show_help() {
    cat << EOF
Usage: $0 [COMMANDE] [OPTIONS]

COMMANDES:
  list                    Lister toutes les descriptions
  missing [fr|en]         Lister les descriptions manquantes pour une langue
  edit [REPO] [LANG]      Éditer une description spécifique
  auto-complete [LANG]    Compléter automatiquement les descriptions manquantes via traduction dynamique
  test-translate [REPO] [LANG]  Tester la traduction d'un dépôt spécifique
  validate               Valider le format du fichier de descriptions
  stats                  Afficher les statistiques des descriptions

OPTIONS:
  -h, --help             Afficher cette aide

EXEMPLES:
  $0 list                              # Lister toutes les descriptions
  $0 missing fr                        # Lister les descriptions françaises manquantes
  $0 edit account-analytic fr          # Éditer la description française de account-analytic
  $0 auto-complete en                  # Compléter automatiquement les descriptions anglaises
  $0 test-translate server-tools fr    # Tester la traduction de server-tools en français
  $0 validate                          # Valider le fichier de descriptions

EOF
}

# Vérifier les dépendances
check_dependencies() {
    local missing_deps=()
    
    if ! command -v jq >/dev/null 2>&1; then
        missing_deps+=("jq")
    fi
    
    if ! command -v python3 >/dev/null 2>&1; then
        missing_deps+=("python3")
    fi
    
    # Vérifier que le script de traduction existe
    if [ ! -f "$SCRIPT_DIR/translate_description.py" ]; then
        echo_error "Script de traduction manquant: $SCRIPT_DIR/translate_description.py"
        missing_deps+=("translate_description.py")
    fi
    
    # Vérifier que le module requests Python est installé
    if ! python3 -c "import requests" >/dev/null 2>&1; then
        echo_error "Module Python 'requests' manquant"
        missing_deps+=("python3-requests")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo_error "Dépendances manquantes: ${missing_deps[*]}"
        echo_info "Installez-les avec:"
        echo_info "  sudo apt-get install jq python3-requests"
        echo_info "  ou: pip3 install requests"
        exit 1
    fi
}

# Vérifier que le fichier de descriptions existe
check_descriptions_file() {
    if [ ! -f "$DESCRIPTIONS_FILE" ]; then
        echo_error "Fichier de descriptions introuvable: $DESCRIPTIONS_FILE"
        echo_info "Exécutez d'abord: make update-oca-repos"
        exit 1
    fi
}

# Lister toutes les descriptions
list_descriptions() {
    echo_info "📋 Liste de toutes les descriptions OCA:"
    echo
    
    jq -r 'to_entries[] | "\(.key): fr=\"\(.value.fr // "")\" en=\"\(.value.en // "")\""' "$DESCRIPTIONS_FILE" | sort
}

# Lister les descriptions manquantes pour une langue
list_missing() {
    local lang="${1:-fr}"
    
    if [[ ! "$lang" =~ ^(fr|en)$ ]]; then
        echo_error "Langue non supportée: $lang (fr/en uniquement)"
        exit 1
    fi
    
    echo_info "📋 Descriptions manquantes pour la langue '$lang':"
    echo
    
    local missing_repos=$(jq -r --arg lang "$lang" 'to_entries[] | select(.value[$lang] == "" or (.value[$lang] | not)) | .key' "$DESCRIPTIONS_FILE")
    
    if [ -z "$missing_repos" ]; then
        echo_success "Aucune description manquante pour la langue '$lang' !"
        return
    fi
    
    local count=0
    while IFS= read -r repo; do
        if [ -n "$repo" ]; then
            local other_lang=$([ "$lang" = "fr" ] && echo "en" || echo "fr")
            local other_desc=$(jq -r --arg repo "$repo" --arg lang "$other_lang" '.[$repo][$lang] // ""' "$DESCRIPTIONS_FILE")
            if [ -n "$other_desc" ]; then
                echo "  $repo (traduction de: \"$other_desc\")"
            else
                echo "  $repo (aucune description disponible)"
            fi
            count=$((count + 1))
        fi
    done <<< "$missing_repos"
    
    echo
    echo_info "Total: $count descriptions manquantes"
}

# Éditer une description spécifique
edit_description() {
    local repo="$1"
    local lang="$2"
    
    if [ -z "$repo" ] || [ -z "$lang" ]; then
        echo_error "Usage: $0 edit [REPO] [LANG]"
        exit 1
    fi
    
    if [[ ! "$lang" =~ ^(fr|en)$ ]]; then
        echo_error "Langue non supportée: $lang (fr/en uniquement)"
        exit 1
    fi
    
    # Vérifier que le dépôt existe
    local exists=$(jq --arg repo "$repo" 'has($repo)' "$DESCRIPTIONS_FILE")
    if [ "$exists" = "false" ]; then
        echo_error "Dépôt '$repo' introuvable dans les descriptions"
        echo_info "💡 Exécutez 'make update-oca-repos' pour mettre à jour la liste"
        exit 1
    fi
    
    # Obtenir la description actuelle
    local current_desc=$(jq -r --arg repo "$repo" --arg lang "$lang" '.[$repo][$lang] // ""' "$DESCRIPTIONS_FILE")
    local other_lang=$([ "$lang" = "fr" ] && echo "en" || echo "fr")
    local other_desc=$(jq -r --arg repo "$repo" --arg lang "$other_lang" '.[$repo][$lang] // ""' "$DESCRIPTIONS_FILE")
    
    echo_info "✏️  Édition de la description pour '$repo' (langue: $lang)"
    echo
    if [ -n "$other_desc" ]; then
        echo "Description $other_lang existante: \"$other_desc\""
        echo
    fi
    
    echo -n "Description actuelle ($lang): "
    if [ -n "$current_desc" ]; then
        echo "\"$current_desc\""
    else
        echo "(vide)"
    fi
    echo
    
    echo -n "Nouvelle description ($lang): "
    read -r new_desc
    
    if [ -z "$new_desc" ]; then
        echo_warning "Description vide, annulation."
        exit 0
    fi
    
    # Créer une sauvegarde
    local backup_file="${DESCRIPTIONS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$DESCRIPTIONS_FILE" "$backup_file"
    echo_info "Sauvegarde créée: $backup_file"
    
    # Mettre à jour la description
    local updated_descriptions=$(jq --arg repo "$repo" --arg lang "$lang" --arg desc "$new_desc" '.[$repo][$lang] = $desc' "$DESCRIPTIONS_FILE")
    echo "$updated_descriptions" | jq '.' > "$DESCRIPTIONS_FILE"
    
    echo_success "Description mise à jour pour '$repo' ($lang): \"$new_desc\""
}

# Note: La génération de descriptions intelligentes a été remplacée par la traduction dynamique
# via le script translate_description.py qui récupère les descriptions GitHub et les traduit.

# Tester la traduction d'un dépôt spécifique
test_translate() {
    local repo="$1"
    local lang="${2:-fr}"
    
    if [ -z "$repo" ]; then
        echo_error "Usage: $0 test-translate [REPO] [LANG]"
        echo_info "Exemple: $0 test-translate server-tools fr"
        exit 1
    fi
    
    if [[ ! "$lang" =~ ^(fr|en)$ ]]; then
        echo_error "Langue non supportée: $lang (fr/en uniquement)"
        exit 1
    fi
    
    echo_info "🧪 Test de traduction pour le dépôt '$repo' (langue: $lang)"
    echo
    
    # Vérifier si le dépôt existe dans le fichier de descriptions
    if [ -f "$DESCRIPTIONS_FILE" ]; then
        local exists=$(jq --arg repo "$repo" 'has($repo)' "$DESCRIPTIONS_FILE" 2>/dev/null)
        if [ "$exists" = "true" ]; then
            local current_desc=$(jq -r --arg repo "$repo" --arg lang "$lang" '.[$repo][$lang] // ""' "$DESCRIPTIONS_FILE")
            if [ -n "$current_desc" ]; then
                echo_info "Description actuelle ($lang): \"$current_desc\""
                echo
            fi
        fi
    fi
    
    echo_info "🌐 Récupération et traduction depuis GitHub..."
    
    # Appeler le script Python pour obtenir la description traduite
    python3 "$SCRIPT_DIR/translate_description.py" "$repo" "$lang"
    local exit_code=$?
    
    echo
    if [ $exit_code -eq 0 ]; then
        echo_success "✅ Traduction réussie !"
    else
        echo_error "❌ Échec de la traduction"
        echo_info "💡 Vérifiez votre connexion internet et l'existence du dépôt"
    fi
}

# Complétion automatique des descriptions via traduction dynamique
auto_complete() {
    local lang="${1:-fr}"
    
    if [[ ! "$lang" =~ ^(fr|en)$ ]]; then
        echo_error "Langue non supportée: $lang (fr/en uniquement)"
        exit 1
    fi
    
    echo_info "🤖 Complétion automatique des descriptions via traduction dynamique pour la langue '$lang'..."
    echo_info "🌐 Récupération des descriptions GitHub et traduction en temps réel..."
    echo
    
    # Créer une sauvegarde
    local backup_file="${DESCRIPTIONS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$DESCRIPTIONS_FILE" "$backup_file"
    echo_info "Sauvegarde créée: $backup_file"
    
    local updated_count=0
    local failed_count=0
    local skipped_count=0
    local descriptions=$(cat "$DESCRIPTIONS_FILE")
    
    # Parcourir tous les dépôts avec des descriptions manquantes
    local missing_repos=$(echo "$descriptions" | jq -r --arg lang "$lang" 'to_entries[] | select(.value[$lang] == "" or (.value[$lang] | not)) | .key')
    local total_missing=$(echo "$missing_repos" | wc -l)
    
    echo_info "🔍 $total_missing dépôts à traiter..."
    echo
    
    local current=0
    while IFS= read -r repo; do
        if [ -n "$repo" ]; then
            current=$((current + 1))
            echo_info "[$current/$total_missing] Traitement de '$repo'..."
            
            # Appeler le script Python pour obtenir la description traduite
            local translated_desc=$(python3 "$SCRIPT_DIR/translate_description.py" "$repo" "$lang" 2>/dev/null)
            local exit_code=$?
            
            if [ $exit_code -eq 0 ] && [ -n "$translated_desc" ] && [ "$translated_desc" != "null" ]; then
                # Mettre à jour le JSON avec la description traduite
                descriptions=$(echo "$descriptions" | jq --arg repo "$repo" --arg lang "$lang" --arg desc "$translated_desc" '.[$repo][$lang] = $desc')
                echo "  ✅ $repo: \"$translated_desc\""
                updated_count=$((updated_count + 1))
            else
                # En cas d'échec, essayer une description de fallback basique
                local fallback_desc=""
                case "$repo" in
                    connector-*|connector_*)
                        if [ "$lang" = "fr" ]; then 
                            fallback_desc="Connecteur pour intégrations externes"
                        else 
                            fallback_desc="Connector for external integrations"
                        fi ;;
                    *account*)
                        if [ "$lang" = "fr" ]; then 
                            fallback_desc="Modules comptables"
                        else 
                            fallback_desc="Accounting modules"
                        fi ;;
                    *l10n*)
                        if [ "$lang" = "fr" ]; then 
                            fallback_desc="Localisation"
                        else 
                            fallback_desc="Localization"
                        fi ;;
                    *stock*)
                        if [ "$lang" = "fr" ]; then 
                            fallback_desc="Gestion de stock"
                        else 
                            fallback_desc="Stock management"
                        fi ;;
                    *)
                        if [ "$lang" = "fr" ]; then 
                            fallback_desc="Module OCA"
                        else 
                            fallback_desc="OCA module"
                        fi ;;
                esac
                
                if [ -n "$fallback_desc" ] && [ "$fallback_desc" != "Module OCA" ] && [ "$fallback_desc" != "OCA module" ]; then
                    descriptions=$(echo "$descriptions" | jq --arg repo "$repo" --arg lang "$lang" --arg desc "$fallback_desc" '.[$repo][$lang] = $desc')
                    echo "  ⚠️  $repo: \"$fallback_desc\" (fallback)"
                    skipped_count=$((skipped_count + 1))
                else
                    echo "  ❌ $repo: Échec de la traduction"
                    failed_count=$((failed_count + 1))
                fi
            fi
            
            # Pause courte pour éviter de surcharger les APIs
            sleep 0.5
        fi
    done <<< "$missing_repos"
    
    # Sauvegarder les modifications
    echo "$descriptions" | jq '.' > "$DESCRIPTIONS_FILE"
    
    echo
    echo_success "Complétion automatique terminée !"
    echo "📊 Résultats:"
    echo "  - ✅ Descriptions traduites: $updated_count"
    echo "  - ⚠️  Descriptions de fallback: $skipped_count"
    echo "  - ❌ Échecs: $failed_count"
    echo "  - 📈 Total traité: $((updated_count + skipped_count + failed_count))"
    echo
    echo_info "💡 Utilisez '$0 missing $lang' pour voir les descriptions encore manquantes"
    echo_info "💡 Les descriptions traduites sont mises en cache pour éviter les requêtes répétées"
}

# Valider le format du fichier
validate() {
    echo_info "🔍 Validation du fichier de descriptions..."
    
    # Vérifier que c'est un JSON valide
    if ! jq empty "$DESCRIPTIONS_FILE" 2>/dev/null; then
        echo_error "Le fichier n'est pas un JSON valide"
        exit 1
    fi
    
    # Vérifier la structure
    local invalid_entries=$(jq -r 'to_entries[] | select((.value | type) != "object" or (.value | has("fr") | not) or (.value | has("en") | not)) | .key' "$DESCRIPTIONS_FILE")
    
    if [ -n "$invalid_entries" ]; then
        echo_error "Entrées avec une structure invalide détectées:"
        echo "$invalid_entries" | while read -r entry; do
            echo "  - $entry"
        done
        exit 1
    fi
    
    # Statistiques
    local total_repos=$(jq 'keys | length' "$DESCRIPTIONS_FILE")
    local fr_complete=$(jq '[to_entries[] | select(.value.fr != "")] | length' "$DESCRIPTIONS_FILE")
    local en_complete=$(jq '[to_entries[] | select(.value.en != "")] | length' "$DESCRIPTIONS_FILE")
    local both_complete=$(jq '[to_entries[] | select(.value.fr != "" and .value.en != "")] | length' "$DESCRIPTIONS_FILE")
    
    echo_success "Fichier de descriptions valide !"
    echo
    echo "📊 Statistiques:"
    echo "  - Total des dépôts: $total_repos"
    echo "  - Descriptions FR complètes: $fr_complete/$total_repos"
    echo "  - Descriptions EN complètes: $en_complete/$total_repos"
    echo "  - Descriptions complètes (FR+EN): $both_complete/$total_repos"
}

# Afficher les statistiques
show_stats() {
    echo_info "📊 Statistiques des descriptions OCA:"
    echo
    
    local total_repos=$(jq 'keys | length' "$DESCRIPTIONS_FILE")
    local fr_complete=$(jq '[to_entries[] | select(.value.fr != "")] | length' "$DESCRIPTIONS_FILE")
    local en_complete=$(jq '[to_entries[] | select(.value.en != "")] | length' "$DESCRIPTIONS_FILE")
    local fr_missing=$(jq '[to_entries[] | select(.value.fr == "")] | length' "$DESCRIPTIONS_FILE")
    local en_missing=$(jq '[to_entries[] | select(.value.en == "")] | length' "$DESCRIPTIONS_FILE")
    local both_complete=$(jq '[to_entries[] | select(.value.fr != "" and .value.en != "")] | length' "$DESCRIPTIONS_FILE")
    local neither_complete=$(jq '[to_entries[] | select(.value.fr == "" and .value.en == "")] | length' "$DESCRIPTIONS_FILE")
    
    echo "Total des dépôts OCA: $total_repos"
    echo
    echo "🇫🇷 Descriptions françaises:"
    echo "  - Complètes: $fr_complete"
    echo "  - Manquantes: $fr_missing"
    echo "  - Taux de complétion: $(( fr_complete * 100 / total_repos ))%"
    echo
    echo "🇬🇧 Descriptions anglaises:"
    echo "  - Complètes: $en_complete"
    echo "  - Manquantes: $en_missing"
    echo "  - Taux de complétion: $(( en_complete * 100 / total_repos ))%"
    echo
    echo "🌍 Global:"
    echo "  - Descriptions bilingues complètes: $both_complete"
    echo "  - Descriptions totalement manquantes: $neither_complete"
    echo "  - Taux de complétion bilingue: $(( both_complete * 100 / total_repos ))%"
}

# Fonction principale
main() {
    local command="${1:-help}"
    
    case "$command" in
        "list")
            check_dependencies
            check_descriptions_file
            list_descriptions
            ;;
        "missing")
            check_dependencies
            check_descriptions_file
            list_missing "$2"
            ;;
        "edit")
            check_dependencies
            check_descriptions_file
            edit_description "$2" "$3"
            ;;
        "auto-complete")
            check_dependencies
            check_descriptions_file
            auto_complete "$2"
            ;;
        "test-translate")
            check_dependencies
            test_translate "$2" "$3"
            ;;
        "validate")
            check_dependencies
            check_descriptions_file
            validate
            ;;
        "stats")
            check_dependencies
            check_descriptions_file
            show_stats
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            echo_error "Commande inconnue: $command"
            echo
            show_help
            exit 1
            ;;
    esac
}

# Exécuter le script principal
main "$@"

#!/bin/bash

# Script pour mettre à jour automatiquement la liste des dépôts OCA dans templates.json
# Ce script récupère tous les dépôts de l'organisation OCA sur GitHub
# Usage: update_oca_repositories.sh [--clean]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$ROOT_DIR/config"
TEMPLATES_FILE="$CONFIG_DIR/templates.json"
TEMP_FILE="/tmp/oca_repos.json"

# Options
CLEAN_BACKUPS=false

# Parser les arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            CLEAN_BACKUPS=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--clean]"
            echo "Options:"
            echo "  --clean    Supprimer les fichiers de sauvegarde après succès"
            echo "  -h, --help Afficher cette aide"
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
            (.name | test("^(odoo|addons|modules)") | not) and
            (.name | test("(tools?|helper|template|bot|sphinx|pylint|test|upgrade|setup|hook|custom|\\.github)$") | not)
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

# Fonction pour générer des descriptions en français
generate_french_descriptions() {
    echo_info "Génération des descriptions en français..."
    
    # Mapping des noms de dépôts vers des descriptions en français
    local descriptions=$(cat << 'EOF'
{
  "account-analytic": "Comptabilité analytique",
  "account-budgeting": "Budgets et contrôle budgétaire", 
  "account-closing": "Clôtures comptables",
  "account-consolidation": "Consolidation comptable",
  "account-financial-reporting": "Rapports financiers",
  "account-financial-tools": "Outils financiers et comptables",
  "account-invoicing": "Facturation",
  "account-payment": "Paiements et encaissements",
  "account-reconcile": "Rapprochements bancaires",
  "bank-payment": "Paiements bancaires",
  "bank-statement-import": "Import relevés bancaires",
  "brand": "Gestion de marques",
  "commission": "Commissions",
  "connector": "Connecteurs génériques",
  "connector-ecommerce": "Connecteurs e-commerce",
  "connector-interfaces": "Interfaces de connecteurs",
  "connector-lengow": "Connecteur Lengow",
  "connector-magento": "Connecteur Magento",
  "connector-prestashop": "Connecteur PrestaShop",
  "connector-woocommerce": "Connecteur WooCommerce",
  "crm": "Gestion de la relation client (CRM)",
  "currency": "Devises et changes",
  "data-protection": "Protection des données (RGPD)",
  "ddmrp": "Demand Driven MRP",
  "delivery-carrier": "Transporteurs",
  "dms": "Gestion documentaire (DMS)",
  "donation": "Dons et fundraising",
  "e-commerce": "Commerce électronique",
  "edi": "Échange de données informatisé (EDI)",
  "event": "Gestion d'événements",
  "field-service": "Service après-vente",
  "geospatial": "Géolocalisation et GIS",
  "helpdesk": "Service d'assistance",
  "hr": "Ressources humaines",
  "hr-attendance": "Pointage et présences",
  "hr-expense": "Notes de frais",
  "hr-holidays": "Congés et absences", 
  "intrastat": "Déclarations Intrastat",
  "iot": "Internet des objets (IoT)",
  "knowledge": "Gestion des connaissances",
  "l10n-argentina": "Localisation Argentine",
  "l10n-brazil": "Localisation Brésil",
  "l10n-chile": "Localisation Chili",
  "l10n-colombia": "Localisation Colombie",
  "l10n-france": "Localisation France",
  "l10n-germany": "Localisation Allemagne",
  "l10n-italy": "Localisation Italie",
  "l10n-spain": "Localisation Espagne",
  "l10n-switzerland": "Localisation Suisse",
  "manufacture": "Manufacturing/MRP",
  "margin-analysis": "Analyse de marge",
  "mis-builder": "Générateur de rapports MIS",
  "multi-company": "Multi-sociétés",
  "operating-unit": "Unités opérationnelles",
  "partner-contact": "Gestion des partenaires et contacts",
  "pos": "Point de vente (POS)",
  "product-attribute": "Attributs produits",
  "product-configurator": "Configurateur de produits",
  "product-pack": "Packs de produits",
  "product-variant": "Variantes de produits",
  "project": "Gestion de projet",
  "project-agile": "Gestion de projet agile",
  "purchase-workflow": "Workflow d'achat",
  "queue": "Files d'attente",
  "report-print-send": "Impression et envoi de rapports",
  "reporting-engine": "Moteur de rapports",
  "rest-framework": "Framework REST API",
  "sale-workflow": "Workflow de vente",
  "server-auth": "Authentification serveur",
  "server-backend": "Backend serveur",
  "server-brand": "Marque serveur",
  "server-env": "Environnement serveur",
  "server-tools": "Outils serveur",
  "server-ux": "UX serveur",
  "social": "Réseaux sociaux",
  "stock-logistics-barcode": "Codes-barres logistique",
  "stock-logistics-reporting": "Rapports logistique",
  "stock-logistics-tracking": "Traçabilité logistique",
  "stock-logistics-transport": "Transport logistique",
  "stock-logistics-warehouse": "Entrepôt logistique",
  "stock-logistics-workflow": "Workflow logistique",
  "timesheet": "Feuilles de temps",
  "vertical-agriculture": "Agriculture verticale",
  "vertical-association": "Associations",
  "vertical-education": "Éducation",
  "vertical-hotel": "Hôtellerie",
  "vertical-isp": "Fournisseurs d'accès Internet",
  "vertical-medical": "Médical",
  "vertical-ngo": "ONG",
  "vertical-realestate": "Immobilier",
  "vertical-travel": "Voyage et tourisme",
  "web": "Interface web",
  "website": "Site web",
  "website-cms": "CMS pour site web"
}
EOF
    )
    
    # Appliquer les descriptions françaises
    jq --argjson desc "$descriptions" '
        map(
            .description = ($desc[.name] // .description // "Module OCA")
        )
    ' "${TEMP_FILE}.filtered" > "${TEMP_FILE}.final"
}

# Fonction pour sauvegarder la configuration actuelle
backup_current_config() {
    if [ -f "$TEMPLATES_FILE" ]; then
        local backup_file="${TEMPLATES_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$TEMPLATES_FILE" "$backup_file"
        echo_info "Sauvegarde de la configuration actuelle: $backup_file"
    fi
}

# Fonction pour mettre à jour le fichier templates.json
update_templates_file() {
    echo_info "Mise à jour du fichier templates.json..."
    
    # Lire la configuration actuelle
    local current_config=$(cat "$TEMPLATES_FILE")
    
    # Extraire les sections non-OCA
    local odoo_versions=$(echo "$current_config" | jq '.odoo_versions')
    local client_templates=$(echo "$current_config" | jq '.client_templates')
    
    # Créer la nouvelle section oca_repositories
    local new_oca_repos="{}"
    while IFS= read -r repo; do
        local name=$(echo "$repo" | jq -r '.name')
        local url=$(echo "$repo" | jq -r '.url')
        local description=$(echo "$repo" | jq -r '.description')
        
        new_oca_repos=$(echo "$new_oca_repos" | jq --arg name "$name" --arg url "$url" --arg desc "$description" '
            .[$name] = {
                "url": $url,
                "description": $desc
            }
        ')
    done < <(jq -c '.[]' "${TEMP_FILE}.final")
    
    # Reconstituer le fichier complet
    local new_config=$(jq -n \
        --argjson odoo_versions "$odoo_versions" \
        --argjson oca_repositories "$new_oca_repos" \
        --argjson client_templates "$client_templates" \
        '{
            "odoo_versions": $odoo_versions,
            "oca_repositories": $oca_repositories,
            "client_templates": $client_templates
        }')
    
    # Écrire le nouveau fichier
    echo "$new_config" | jq '.' > "$TEMPLATES_FILE"
    
    local repo_count=$(echo "$new_oca_repos" | jq 'keys | length')
    echo_success "Mis à jour $repo_count dépôts OCA dans templates.json"
}

# Fonction pour afficher les statistiques
show_statistics() {
    echo_info "📊 Statistiques des dépôts OCA:"
    
    local total_repos=$(jq 'length' "${TEMP_FILE}.final")
    echo "   Total des dépôts: $total_repos"
    
    echo "   Top 10 des dépôts les plus populaires:"
    jq -r '.[] | "\(.stars)⭐ \(.name) - \(.description)"' "${TEMP_FILE}.final" | sort -nr | head -10 | while read line; do
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
        
        local backup_files=(${TEMPLATES_FILE}.backup.*)
        if [ -f "${backup_files[0]}" ]; then
            local count=0
            for backup_file in "${backup_files[@]}"; do
                if [ -f "$backup_file" ]; then
                    rm -f "$backup_file"
                    count=$((count + 1))
                fi
            done
            echo_success "Supprimé $count fichier(s) de sauvegarde"
        else
            echo_info "Aucun fichier de sauvegarde à supprimer"
        fi
    fi
}

# Fonction pour nettoyer les fichiers temporaires
cleanup() {
    rm -f "$TEMP_FILE" "${TEMP_FILE}.filtered" "${TEMP_FILE}.final"
}

# Fonction principale
main() {
    echo_info "🚀 Mise à jour automatique des dépôts OCA"
    echo_info "========================================"
    
    check_dependencies
    backup_current_config
    fetch_oca_repositories
    filter_odoo_repositories
    generate_french_descriptions
    update_templates_file
    show_statistics
    cleanup
    clean_backup_files
    
    echo_success "✨ Mise à jour terminée avec succès !"
    echo_info "📝 Le fichier templates.json a été mis à jour avec tous les dépôts OCA disponibles."
    echo_info "🔄 Vous pouvez maintenant utiliser ces nouveaux dépôts dans vos projets clients."
    if [ "$CLEAN_BACKUPS" = true ]; then
        echo_info "🧹 Les fichiers de sauvegarde ont été supprimés (option --clean)"
    fi
}

# Gestion des signaux pour nettoyer en cas d'interruption
trap cleanup EXIT

# Exécuter le script principal
main "$@"

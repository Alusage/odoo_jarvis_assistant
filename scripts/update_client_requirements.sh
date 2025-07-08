#!/bin/bash

# Script pour mettre à jour le requirements.txt d'un client avec les dépendances des submodules OCA
# Usage: update_client_requirements.sh <client_name> [--clean]

set -e

CLIENT_NAME=""
CLEAN_BACKUPS=false

# Parser les arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            CLEAN_BACKUPS=true
            shift
            ;;
        *)
            if [ -z "$CLIENT_NAME" ]; then
                CLIENT_NAME="$1"
            else
                echo "Argument inconnu: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CLIENTS_DIR="$ROOT_DIR/clients"
CLIENT_DIR="$CLIENTS_DIR/$CLIENT_NAME"

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
if [ -z "$CLIENT_NAME" ]; then
    echo_error "Usage: $0 <client_name> [--clean]"
    echo_info "Options:"
    echo_info "  --clean  Supprimer les fichiers de sauvegarde après la mise à jour"
    exit 1
fi

if [ ! -d "$CLIENT_DIR" ]; then
    echo_error "Client '$CLIENT_NAME' non trouvé dans $CLIENTS_DIR"
    exit 1
fi

echo_info "🔄 Mise à jour des requirements.txt pour le client '$CLIENT_NAME'..."

cd "$CLIENT_DIR"

# Fichier de requirements final
REQUIREMENTS_FILE="requirements.txt"
TEMP_REQUIREMENTS="/tmp/client_requirements_${CLIENT_NAME}.txt"

# En-tête du fichier requirements
cat > "$TEMP_REQUIREMENTS" << EOF
# Requirements pour le client $CLIENT_NAME
# Généré automatiquement le $(date '+%Y-%m-%d %H:%M:%S')

# Base Odoo requirements
wheel
setuptools
psycopg2-binary
EOF

# Variables pour les statistiques
total_submodules=0
submodules_with_requirements=0
total_dependencies=0
unique_dependencies=0

# Créer un fichier temporaire pour collecter toutes les dépendances
ALL_DEPS_FILE="/tmp/all_deps_${CLIENT_NAME}.txt"
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
    echo_warning "Dossier 'addons' non trouvé dans le client"
fi

# Compter les dépendances uniques
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

echo_info "📝 Fichier généré : $CLIENT_DIR/$REQUIREMENTS_FILE"

# Suggestions d'installation
echo ""
echo_info "💡 Pour installer les dépendances :"
echo_info "   cd $CLIENT_DIR"
echo_info "   pip install -r requirements.txt"
echo ""
echo_info "🐳 Ou pour Docker :"
echo_info "   docker-compose exec odoo pip install -r requirements.txt"

# Optionnel : valider les dépendances (en mode non-interactif pour l'automatisation)
if [[ "${VALIDATE_DEPS:-no}" =~ ^[Yy]|^yes$ ]]; then
    echo_info "🔍 Validation des dépendances..."
    
    # Créer un environnement virtuel temporaire pour tester
    temp_venv="/tmp/validate_requirements_${CLIENT_NAME}"
    
    if command -v python3 >/dev/null 2>&1; then
        if python3 -m venv "$temp_venv" 2>/dev/null; then
            echo_info "Environnement virtuel de test créé"
            
            # Activer et installer
            if [ -f "$temp_venv/bin/activate" ]; then
                source "$temp_venv/bin/activate"
                
                echo_info "Installation des dépendances dans l'environnement de test..."
                pip install --quiet --upgrade pip setuptools wheel 2>/dev/null
                
                if pip install -r "$REQUIREMENTS_FILE" --dry-run 2>/dev/null; then
                    echo_success "✅ Toutes les dépendances sont valides"
                else
                    echo_warning "⚠️  Certaines dépendances pourraient avoir des conflits"
                    echo_info "💡 Vérifiez manuellement avec : pip install -r requirements.txt"
                fi
                
                deactivate
            else
                echo_warning "Impossible d'activer l'environnement virtuel"
            fi
            
            rm -rf "$temp_venv"
        else
            echo_warning "Impossible de créer l'environnement virtuel de test (venv non disponible)"
        fi
    else
        echo_warning "Python3 non trouvé, validation ignorée"
    fi
fi

# Nettoyage des fichiers de sauvegarde si demandé
if [ "$CLEAN_BACKUPS" = true ]; then
    echo_info "🧹 Nettoyage des fichiers de sauvegarde..."
    backup_count=$(ls -1 "$CLIENT_DIR"/requirements.txt.backup.* 2>/dev/null | wc -l || echo "0")
    
    if [ "$backup_count" -gt 0 ]; then
        rm -f "$CLIENT_DIR"/requirements.txt.backup.*
        echo_success "✅ $backup_count fichier(s) de sauvegarde supprimé(s)"
    else
        echo_info "   - Aucun fichier de sauvegarde à supprimer"
    fi
fi

echo_success "🏁 Mise à jour des requirements terminée !"

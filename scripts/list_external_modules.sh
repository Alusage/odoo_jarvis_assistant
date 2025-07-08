#!/bin/bash
# Script pour lister tous les dépôts de modules Odoo (OCA et externes) d'un client
# Usage : ./scripts/list_external_modules.sh <client_name>

set -e

CLIENT_NAME="$1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CLIENTS_DIR="$ROOT_DIR/clients"
CLIENT_DIR="$CLIENTS_DIR/$CLIENT_NAME"
ADDONS_DIR="$CLIENT_DIR/addons"

BLUE='\033[0;34m'
NC='\033[0m'

echo_info() { echo -e "${BLUE}-  $1${NC}"; }

if [ -z "$CLIENT_NAME" ]; then
  echo "Usage : $0 <client_name>"
  exit 1
fi

if [ ! -d "$ADDONS_DIR" ]; then
  echo_info "Le dossier addons/ n'existe pas pour le client '$CLIENT_NAME'."
  exit 0
fi

cd "$ADDONS_DIR"
for d in */ ; do
  if [ -d "$d/.git" ]; then
    echo_info "Dépôt git : ${d%/}"
  else
    echo_info "Dossier : ${d%/}"
  fi
done

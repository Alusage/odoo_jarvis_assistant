#!/bin/bash
set -e

# Script d'entrée personnalisé pour Cloudron Odoo
# Client: {{CLIENT_NAME}}

echo "🚀 Démarrage de l'instance Odoo {{CLIENT_NAME}} pour Cloudron..."

# Configuration des variables d'environnement Cloudron
export PGHOST="${CLOUDRON_POSTGRESQL_HOST:-localhost}"
export PGPORT="${CLOUDRON_POSTGRESQL_PORT:-5432}"  
export PGUSER="${CLOUDRON_POSTGRESQL_USERNAME:-odoo}"
export PGPASSWORD="${CLOUDRON_POSTGRESQL_PASSWORD:-odoo}"
export PGDATABASE="${CLOUDRON_POSTGRESQL_DATABASE:-odoo}"

# Créer le fichier de configuration Odoo dynamique
cat > /etc/odoo/odoo.conf << EOF
[options]
# Configuration générée automatiquement pour Cloudron
addons_path = /mnt/extra-addons,/usr/lib/python3/dist-packages/odoo/addons
data_dir = ${ODOO_DATA_DIR:-/app/data}
admin_passwd = \$pbkdf2-sha512\$600000\$PZw1Bh4Cae4bpe1K9EKOVg\$kgP.jKOHoPuSKMdp2Yl3bAr7g41qoTRsR8jRKgPQ.8O.ZvCT7fGIKjHUlBzFrHGvYrJE4qO8Kno5v8sMjJ1kqQ

# Configuration base de données
db_host = ${PGHOST}
db_port = ${PGPORT}
db_user = ${PGUSER}
db_password = ${PGPASSWORD}
db_name = ${PGDATABASE}

# Configuration serveur
http_port = 8069
workers = 2
max_cron_threads = 1

# Configuration logs
log_level = info
logfile = False
log_db = False

# Configuration sécurité
list_db = False

# Configuration proxy (Cloudron utilise un reverse proxy)
proxy_mode = True
EOF

echo "✅ Configuration Odoo générée pour Cloudron"

# Attendre que PostgreSQL soit disponible
echo "🔍 Vérification de la connexion PostgreSQL..."
until PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -c '\q' 2>/dev/null; do
  echo "⏳ PostgreSQL n'est pas encore disponible. Attente..."
  sleep 2
done

echo "✅ PostgreSQL connecté avec succès"

# Créer la base de données si elle n'existe pas
PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -tc "SELECT 1 FROM pg_database WHERE datname = '$PGDATABASE'" | grep -q 1 || \
PGPASSWORD="$PGPASSWORD" createdb -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" "$PGDATABASE"

echo "✅ Base de données $PGDATABASE prête"

# Permissions sur les répertoires
mkdir -p "${ODOO_DATA_DIR}"
chown -R odoo:odoo "${ODOO_DATA_DIR}" 2>/dev/null || true

echo "🎉 Démarrage d'Odoo {{CLIENT_NAME}}..."

# Démarrer Odoo
exec "$@"
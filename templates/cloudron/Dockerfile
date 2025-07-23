# Dockerfile pour déploiement Cloudron Odoo
# Client: {{CLIENT_NAME}}
# Version: {{ODOO_VERSION}}

FROM odoo:{{ODOO_VERSION}}

LABEL cloudron.version={{CLOUDRON_VERSION}} \
      cloudron.displayName="{{CLIENT_DISPLAY_NAME}}" \
      cloudron.description="Instance Odoo pour {{CLIENT_DISPLAY_NAME}}" \
      cloudron.addons="postgresql"

# Installation des dépendances système si nécessaires
USER root

# Copier les dépendances Python personnalisées
COPY requirements.txt /tmp/requirements.txt
RUN if [ -s /tmp/requirements.txt ]; then \
        pip3 install --no-cache-dir --break-system-packages -r /tmp/requirements.txt; \
    fi

# Copier les modules personnalisés et OCA
COPY extra-addons /mnt/extra-addons
COPY addons /mnt/addons

# Copier la configuration Odoo
COPY config/odoo.conf /etc/odoo/odoo.conf

# Créer le répertoire de données
RUN mkdir -p /var/lib/odoo && chown odoo:odoo /var/lib/odoo

# Variables d'environnement pour Cloudron
ENV ODOO_RC=/etc/odoo/odoo.conf \
    ODOO_DATA_DIR=/app/data \
    CLOUDRON=true

# Script de démarrage personnalisé pour Cloudron
COPY cloudron-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/cloudron-entrypoint.sh

# Utiliser l'utilisateur odoo
USER odoo

# Exposer le port standard Odoo
EXPOSE 8069

# Point d'entrée
ENTRYPOINT ["/usr/local/bin/cloudron-entrypoint.sh"]
CMD ["odoo"]
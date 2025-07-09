# Dockerfile basé sur l'image officielle Odoo
# Source : https://github.com/odoo/docker

# Étape 1 : Utiliser l'image officielle Odoo comme base
ARG ODOO_VERSION=18.0
FROM odoo:${ODOO_VERSION}

# Étape 2 : Installer les outils nécessaires et les polices
USER root
RUN apt-get update && apt-get install -y \
    python3-pip \
    fonts-liberation \
    fonts-dejavu-core \
    fontconfig \
    gosu \
    && fc-cache -f -v \
    && rm -rf /var/lib/apt/lists/*

# Étape 3 : Définir les variables d'environnement
ENV ODOO_CONF_DIR=/etc/odoo
ENV CUSTOM_CONF_DIR=/mnt/config
ENV REQUIREMENTS_FILE=/mnt/requirements.txt
ENV EXTRA_ADDONS_DIR=/mnt/extra-addons
ENV ADDONS_DIR=/mnt/addons
ENV DEBUG_MODE=false

# Étape 4 : Créer les répertoires nécessaires avec les bonnes permissions
RUN mkdir -p ${CUSTOM_CONF_DIR} ${EXTRA_ADDONS_DIR} ${ADDONS_DIR} /data /var/lib/odoo && \
    chown -R odoo:odoo ${CUSTOM_CONF_DIR} ${EXTRA_ADDONS_DIR} ${ADDONS_DIR} /data /var/lib/odoo && \
    chmod -R 755 /data /var/lib/odoo

# Étape 5 : Copier les scripts personnalisés
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY install_requirements.sh /usr/local/bin/install_requirements.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/install_requirements.sh

# Étape 6 : Configurer le PATH pour l'utilisateur odoo
ENV PATH="/var/lib/odoo/.local/bin:$PATH"

# Étape 7 : Remplacer le point d'entrée par le script personnalisé
# L'entrypoint s'exécute en tant que root pour configurer les permissions
# puis bascule vers l'utilisateur odoo
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Étape 8 : Commande par défaut
CMD ["odoo"]

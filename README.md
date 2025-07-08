# Générateur de Dépôts Client Odoo

Ce dépôt est un **générateur automatisé** pour créer des dépôts clients Odoo standardisés avec :

- Gestion multi-versions Odoo (16.0, 17.0, 18.0)
- Intégration automatique des modules OCA
- Support Odoo Enterprise optionnel
- Configuration Docker Compose prête à l'emploi
- Scripts de gestion automatisés

## 🚀 Démarrage rapide

```bash
# Créer un nouveau client interactivement
./create_client.sh

# Ou utiliser make
make create-client
```

## 📁 Structure du projet

```
odoo_alusage_18.0/
├── clients/                    # Dépôts générés pour chaque client
│   ├── client_abc/            # Exemple de client généré
│   └── client_xyz/
├── config/                    # Configuration des templates
│   └── templates.json         # Définition des modules OCA et templates
├── scripts/                   # Scripts utilitaires
│   ├── generate_client_repo.sh
│   ├── update_client_submodules.sh
│   ├── add_oca_module.sh
│   └── list_available_modules.sh
├── templates/                 # Templates de fichiers
├── create_client.sh          # Script principal de création
├── Makefile                  # Commandes make pour la gestion
└── README.md                 # Ce fichier
```

## 🛠️ Utilisation

### Créer un nouveau client

**Méthode 1 : Interactive**

```bash
./create_client.sh
```

**Méthode 2 : Avec make**

```bash
make create-client
```

Le script vous demandera :

- **Nom du client** (ex: `client_abc`)
- **Version Odoo** (16.0, 17.0, 18.0)
- **Template** (basic, ecommerce, manufacturing, services, custom)
- **Odoo Enterprise** (Oui/Non)

### Templates disponibles

- **basic** : Configuration de base (partner, accounting, server-tools)
- **ecommerce** : E-commerce complet (partner, website, sale, stock, accounting)
- **manufacturing** : Entreprise manufacturière (partner, sale, purchase, stock, manufacturing, accounting)
- **services** : Entreprise de services (partner, project, hr, accounting)
- **custom** : Sélection personnalisée des modules

### Gestion des clients existants

```bash
# Lister tous les clients
make list-clients

# Mettre à jour les submodules d'un client
make update-client CLIENT=client_abc

# Ajouter un module OCA à un client
make add-module CLIENT=client_abc MODULE=website

# Lister les modules disponibles pour un client
make list-modules CLIENT=client_abc

# Lister tous les modules OCA disponibles
make list-oca-modules

# Filtrer les modules OCA par nom
make list-oca-modules PATTERN=account

# Mettre à jour la liste des modules OCA depuis GitHub
make update-oca-repos

# Voir le statut de tous les clients
make status
```

## 📦 Structure d'un client généré

Chaque client généré contient :

```
client_abc/
├── addons/                    # Submodules OCA et autres dépôts
│   ├── partner-contact/      # Modules partenaires (nom exact du dépôt OCA)
│   ├── account-financial-tools/ # Modules comptables (nom exact du dépôt OCA)
│   └── enterprise/           # Odoo Enterprise (si activé)
├── extra-addons/             # Liens symboliques vers modules activés
├── config/
│   └── odoo.conf            # Configuration Odoo
├── scripts/                  # Scripts utilitaires du client
│   ├── update_submodules.sh
│   ├── link_modules.sh
│   └── start.sh
├── logs/                     # Logs Odoo
├── docker-compose.yml        # Configuration Docker
├── requirements.txt          # Dépendances Python
└── README.md                # Documentation du client
```

## 🐳 Utilisation avec Docker

Chaque client généré inclut une configuration Docker Compose :

```bash
cd clients/client_abc
./scripts/start.sh              # Démarre l'environnement
# Ou manuellement :
docker-compose up -d
```

Accès : http://localhost:8069

## 🔧 Scripts disponibles

### Scripts globaux (racine)

- `./create_client.sh` - Créer un nouveau client
- `./scripts/update_client_submodules.sh` - Mettre à jour un client
- `./scripts/add_oca_module.sh` - Ajouter un module à un client
- `./scripts/list_available_modules.sh` - Lister les modules d'un client

### Scripts par client (dans chaque dépôt client)

- `./scripts/update_submodules.sh` - Mettre à jour les submodules
- `./scripts/link_modules.sh` - Créer des liens symboliques
- `./scripts/start.sh` - Démarrer l'environnement Docker

## 🆕 Nouvelles fonctionnalités - Gestion automatique des modules OCA

### Mise à jour automatique des dépôts OCA

Le système maintient automatiquement une liste complète de tous les dépôts OCA disponibles sur GitHub :

```bash
# Mettre à jour la liste depuis GitHub (récupère ~226 dépôts)
make update-oca-repos                    # Nettoie automatiquement les sauvegardes

# Mise à jour manuelle avec options
./scripts/update_oca_repositories.sh     # Garde les sauvegardes
./scripts/update_oca_repositories.sh --clean  # Supprime les sauvegardes

# Voir tous les modules disponibles
make list-oca-modules

# Filtrer par catégorie
make list-oca-modules PATTERN=account    # Modules comptables
make list-oca-modules PATTERN=stock      # Modules stock/logistique
make list-oca-modules PATTERN=l10n       # Localisations
```

### Nomenclature des dossiers

Les modules OCA utilisent maintenant les **noms exacts** des dépôts GitHub :

```
addons/
├── partner-contact/              # ✅ Nom exact du dépôt OCA
├── account-financial-tools/      # ✅ Nom exact du dépôt OCA
├── stock-logistics-workflow/     # ✅ Nom exact du dépôt OCA
└── server-tools/                 # ✅ Nom exact du dépôt OCA
```

### Avantages

- **Synchronisation automatique** : La liste des modules se met à jour automatiquement
- **Nomenclature cohérente** : Les noms correspondent exactement aux dépôts GitHub
- **Descriptions françaises** : Chaque module a une description claire en français
- **Popularité visible** : Les modules sont classés par nombre d'étoiles GitHub

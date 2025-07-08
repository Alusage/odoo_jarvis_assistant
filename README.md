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

# Voir le statut de tous les clients
make status
```

## 📦 Structure d'un client généré

Chaque client généré contient :

```
client_abc/
├── addons/                    # Submodules OCA et autres dépôts
│   ├── oca_partner/          # Modules partenaires
│   ├── oca_accounting/       # Modules comptables
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

## ⚙️ Configuration

### Ajouter de nouveaux modules OCA

Éditez `config/templates.json` pour ajouter de nouveaux dépôts OCA :

```json
{
  "oca_repositories": {
    "nouveau_module": {
      "url": "https://github.com/OCA/nouveau-module.git",
      "description": "Description du module"
    }
  }
}
```

### Créer de nouveaux templates

Ajoutez des templates dans `config/templates.json` :

```json
{
  "client_templates": {
    "mon_template": {
      "description": "Mon template personnalisé",
      "default_modules": ["partner", "accounting", "nouveau_module"]
    }
  }
}
```

## 📋 Commandes Make

```bash
make help                                    # Afficher l'aide
make create-client                          # Créer un nouveau client
make list-clients                           # Lister les clients
make update-client CLIENT=nom               # Mettre à jour un client
make add-module CLIENT=nom MODULE=module    # Ajouter un module
make list-modules CLIENT=nom                # Lister les modules d'un client
make status                                 # Statut de tous les clients
make backup-client CLIENT=nom               # Sauvegarder un client
make clean                                  # Nettoyer les fichiers temporaires
make install-deps                          # Installer les dépendances
```

## 🛡️ Prérequis

- **Git** (gestion des dépôts et submodules)
- **jq** (traitement JSON)
- **Docker & Docker Compose** (pour l'exécution)
- **Make** (optionnel, pour les commandes simplifiées)

Installation sur Ubuntu/Debian :

```bash
sudo apt-get update
sudo apt-get install git jq make
# + Docker selon la documentation officielle
```

## 🔄 Workflow recommandé

1. **Créer un client** : `./create_client.sh`
2. **Tester l'environnement** : `cd clients/mon_client && ./scripts/start.sh`
3. **Activer des modules** : `./scripts/link_modules.sh addons/oca_partner partner_firstname`
4. **Développer** : Ajouter vos modules personnalisés dans `addons/`
5. **Maintenir** : `make update-client CLIENT=mon_client`
6. **Déployer** : Pousser le dépôt client vers votre Git distant

## 💡 Conseils

- Chaque client est un dépôt Git indépendant avec ses submodules
- Les modules OCA sont en submodules, vos développements peuvent être en submodules aussi
- Utilisez `extra-addons/` uniquement pour les liens symboliques
- La configuration Docker filtre les bases par préfixe client
- Gardez `config/templates.json` à jour avec vos modules préférés

## 🆘 Dépannage

**Problème de submodules :**

```bash
cd clients/mon_client
git submodule update --init --recursive
```

**Conflit de versions :**

```bash
# Vérifier les branches des submodules
git submodule foreach git branch -a
```

**Modules non trouvés :**

```bash
# Lister les modules disponibles
make list-modules CLIENT=mon_client
```

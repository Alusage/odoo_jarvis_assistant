# Image Docker Odoo Personnalisée

Cette image Docker est basée sur l'image officielle Odoo et ajoute des fonctionnalités pour l'intégration avec l'arborescence des dépôts clients.

## Fonctionnalités

- **Configuration automatique** : Copie le fichier `odoo.conf` depuis l'image officielle si absent
- **Installation des dépendances** : Installe automatiquement les packages Python depuis `requirements.txt`
- **Gestion des addons** : Ajoute automatiquement les dossiers `extra-addons/` et `addons/*/` au chemin des modules
- **Volumes montés** : Supporte les volumes pour configuration, modules et logs

## Structure attendue

L'image s'attend à trouver cette structure dans le dépôt client :

```
client_repo/
├── config/
│   └── odoo.conf           # Configuration Odoo (créé automatiquement si absent)
├── requirements.txt        # Dépendances Python (optionnel)
├── extra-addons/          # Modules activés (liens symboliques)
├── addons/                # Submodules OCA
│   ├── partner-contact/
│   ├── server-tools/
│   └── ...
└── logs/                  # Logs Odoo
```

## Utilisation

### 1. Construire l'image

```bash
cd docker/
docker build -t odoo-alusage:18.0 .
```

### 2. Utiliser dans un dépôt client

Copiez le `docker-compose.yml` dans votre dépôt client et adaptez-le :

```yaml
version: "3.8"

services:
  odoo:
    image: odoo-alusage:18.0 # Utilisez votre image construite
    volumes:
      - ./config:/mnt/config
      - ./requirements.txt:/mnt/requirements.txt:ro
      - ./extra-addons:/mnt/extra-addons:ro
      - ./addons:/mnt/addons:ro
      - odoo-data:/var/lib/odoo
      - ./logs:/var/log/odoo
    ports:
      - "8069:8069"
    environment:
      - HOST=db
      - USER=odoo
      - PASSWORD=odoo
    depends_on:
      - db

  db:
    image: postgres:13
    environment:
      - POSTGRES_DB=postgres
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=odoo
    volumes:
      - postgres-data:/var/lib/postgresql/data

volumes:
  odoo-data:
  postgres-data:
```

### 3. Démarrer l'environnement

```bash
cd client_repo/
docker compose up -d
```

## Variables d'environnement

- `ODOO_VERSION` : Version d'Odoo à utiliser (défaut: 18.0)

## Volumes

- `/mnt/config` : Dossier de configuration (odoo.conf)
- `/mnt/requirements.txt` : Fichier des dépendances Python
- `/mnt/extra-addons` : Modules activés (liens symboliques)
- `/mnt/addons` : Dossiers des submodules OCA
- `/var/lib/odoo` : Données Odoo (persistent)
- `/var/log/odoo` : Logs Odoo

## Processus de démarrage

1. **Vérification de odoo.conf** : Si absent, copie depuis l'image officielle
2. **Installation des dépendances** : Installe les packages depuis requirements.txt
3. **Construction du chemin des addons** : Ajoute extra-addons/ et tous les dossiers addons/\*/
4. **Démarrage d'Odoo** : Lance Odoo avec la configuration et les chemins personnalisés

## Logs

Les logs de l'initialisation utilisent des couleurs pour faciliter le debug :

- 🔵 Informations
- ✅ Succès
- ⚠️ Avertissements
- ❌ Erreurs

## Versions supportées

Cette image supporte toutes les versions d'Odoo disponibles dans l'image officielle. Modifiez l'argument `ODOO_VERSION` lors de la construction :

```bash
docker build --build-arg ODOO_VERSION=17.0 -t odoo-alusage:17.0 .
```

## Dépôts de modules Odoo externes (non-OCA)

En plus des submodules OCA, vous pouvez ajouter des dépôts de modules Odoo externes (par exemple depuis GitHub ou d'autres forges) via leur URL (https ou ssh). Ces dépôts seront gérés exactement comme les submodules OCA, dans le dossier `addons/`.

### Ajouter un dépôt externe

Utilisez le script adapté (ex : `add_external_module.sh` ou via l'option correspondante dans `add_oca_module.sh`) pour ajouter un dépôt externe :

```bash
./scripts/add_external_module.sh https://github.com/monorg/mon_module_odoo.git
# ou
./scripts/add_external_module.sh git@github.com:monorg/mon_module_odoo.git
```

Le dépôt sera cloné comme un submodule dans `addons/mon_module_odoo/`.

### Lister les dépôts externes

Pour lister tous les dépôts de modules (OCA et externes) présents dans `addons/` :

```bash
./scripts/list_external_modules.sh
```

### Gestion automatique

- Les dépôts externes sont mis à jour et intégrés dans la génération des requirements et la gestion des submodules.
- Vous pouvez utiliser des URLs https ou ssh.
- La logique de gestion (update, requirements, etc.) est identique à celle des submodules OCA.

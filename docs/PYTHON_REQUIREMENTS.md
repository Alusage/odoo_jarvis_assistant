# Gestion Automatique des Requirements Python

## Vue d'ensemble

Cette fonctionnalité permet de gérer automatiquement les dépendances Python des modules OCA dans les projets clients. Elle agrège tous les `requirements.txt` des submodules OCA pour créer un fichier de requirements unifié pour le client.

## Problème résolu

Chaque module OCA peut avoir ses propres dépendances Python définies dans son fichier `requirements.txt`. Sans cette fonctionnalité, il faudrait :

1. Identifier manuellement tous les modules OCA utilisés
2. Vérifier individuellement leurs dépendances
3. Installer manuellement chaque dépendance
4. Gérer les conflits de versions

## Solution automatisée

### Pour les nouveaux clients

Les nouveaux clients générés avec `generate_client_repo.sh` incluent automatiquement :

- Script `scripts/update_requirements.sh` dans le dépôt client
- Mise à jour automatique lors de `scripts/update_submodules.sh`
- Fichier `requirements.txt` initial avec les dépendances de base

### Pour les clients existants

```bash
# Mise à jour des requirements depuis le dépôt principal
make update-requirements CLIENT=nom_client

# Avec nettoyage automatique des sauvegardes
make update-requirements CLIENT=nom_client CLEAN=true

# Ou depuis le dépôt client
cd clients/nom_client
./scripts/update_requirements.sh  # (si le script existe)

# Avec nettoyage des sauvegardes
./scripts/update_requirements.sh --clean
```

## Fonctionnalités

### 1. Agrégation automatique

- Analyse tous les submodules dans `addons/`
- Lit chaque `requirements.txt` trouvé
- Filtre les commentaires et lignes vides
- Génère un fichier consolidé

### 2. Organisation du fichier généré

```
# Requirements pour le client nom_client
# Généré automatiquement le 2025-01-08 15:30:00

# Base Odoo requirements
wheel
setuptools
psycopg2-binary

# Dépendances du module partner-contact
python-stdnum
phonenumbers

# Dépendances du module account-payment
...

# === DÉPENDANCES UNIQUES CONSOLIDÉES ===
# (dédoublonnées automatiquement)
```

### 3. Statistiques et validation

- Compte des modules analysés
- Nombre de dépendances trouvées
- Dédoublonnage automatique
- Validation optionnelle avec environnement virtuel temporaire

### 4. Sauvegarde automatique et nettoyage

- Sauvegarde de l'ancien `requirements.txt`
- Horodatage des sauvegardes
- Option `--clean` pour supprimer automatiquement les sauvegardes
- Récupération possible en cas de problème

## Usage

### Commande Make (recommandée)

```bash
# Mettre à jour les requirements d'un client
make update-requirements CLIENT=mon_client

# Avec nettoyage automatique des sauvegardes
make update-requirements CLIENT=mon_client CLEAN=true
```

### Script direct

```bash
# Depuis le dépôt principal
./scripts/update_client_requirements.sh mon_client

# Avec nettoyage des sauvegardes
./scripts/update_client_requirements.sh mon_client --clean

# Depuis le dépôt client
cd clients/mon_client
./scripts/update_requirements.sh

# Avec nettoyage des sauvegardes
./scripts/update_requirements.sh --clean
```

### Installation des dépendances

```bash
# Installation classique
pip install -r requirements.txt

# Avec Docker
docker-compose exec odoo pip install -r requirements.txt

# Avec environnement virtuel
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

## Intégration dans les workflows

### Workflow de mise à jour recommandé

```bash
# 1. Mettre à jour les submodules
make update-client CLIENT=mon_client

# 2. Mettre à jour les requirements
make update-requirements CLIENT=mon_client

# 3. Redémarrer l'environnement
cd clients/mon_client
docker-compose down
docker-compose up -d
```

### Automatisation dans les scripts clients

Le script `update_submodules.sh` des nouveaux clients appelle automatiquement `update_requirements.sh`.

## Avantages

1. **Automatisation complète** : Plus de gestion manuelle des dépendances
2. **Toujours à jour** : Mise à jour automatique avec les submodules
3. **Pas de conflits** : Dédoublonnage et consolidation intelligente
4. **Traçabilité** : Commentaires indiquant l'origine de chaque dépendance
5. **Sécurité** : Sauvegarde automatique des fichiers existants
6. **Validation** : Vérification optionnelle des dépendances

## Limitations

- Nécessite que les modules OCA aient des `requirements.txt` bien formatés
- Les conflits de versions entre modules doivent être résolus manuellement
- Ne gère pas les dépendances système (apt, yum, etc.)

## Troubleshooting

### Dépendances conflictuelles

```bash
# Identifier les conflits
pip check

# Analyser les versions
pip list | grep problematic_package
```

### Modules sans requirements.txt

Les modules sans fichier `requirements.txt` sont ignorés automatiquement.

### Validation des dépendances

Le script propose une validation optionnelle qui crée un environnement virtuel temporaire pour tester l'installation.

Cette fonctionnalité simplifie considérablement la gestion des dépendances Python dans les projets clients Odoo avec modules OCA.

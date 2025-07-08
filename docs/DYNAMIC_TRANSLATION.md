# Système de Traduction Dynamique des Descriptions OCA

## Aperçu

Ce système remplace les descriptions statiques par un système de **traduction dynamique** qui :

1. **Récupère automatiquement** les descriptions GitHub des dépôts OCA
2. **Traduit en temps réel** via plusieurs services de traduction en ligne
3. **Met à jour** les résultats dans le fichier JSON local
4. **Supporte plusieurs services** de traduction avec fallback automatique

## Fichiers Modifiés/Créés

### 🆕 Nouveau : `scripts/translate_description.py`

Script Python qui :

- Récupère la description GitHub d'un dépôt OCA
- Traduit le texte via Google Translate, LibreTranslate, ou MyMemory
- Gère les erreurs et les fallbacks automatiquement
- Support multilingue (fr, en, es, de, it, pt)
- Cache en mémoire pendant la session (pas de persistance)

### 🔄 Modifié : `scripts/manage_oca_descriptions.sh`

Améliorations :

- Intégration de la traduction dynamique
- Nouvelle commande `test-translate` pour tester un dépôt
- Vérification des dépendances Python
- Suppression des descriptions statiques obsolètes
- Amélioration des messages et statistiques

### 🧪 Test : `scripts/test_auto_complete.sh`

Script de test pour valider le système sur un sous-ensemble de dépôts.

## Utilisation

### 1. Tester la traduction d'un dépôt spécifique

```bash
./scripts/manage_oca_descriptions.sh test-translate server-tools fr
./scripts/manage_oca_descriptions.sh test-translate account-analytic en
```

### 2. Compléter automatiquement toutes les descriptions manquantes

```bash
# Pour le français
./scripts/manage_oca_descriptions.sh complete-missing fr

# Pour l'anglais avec limitation
./scripts/manage_oca_descriptions.sh complete-missing en --limit 10

# Avec délai personnalisé pour éviter le rate limit
./scripts/manage_oca_descriptions.sh complete-missing fr --limit 5 --delay 3
```

### 3. Voir les statistiques et descriptions manquantes

```bash
./scripts/manage_oca_descriptions.sh stats
./scripts/manage_oca_descriptions.sh missing fr
```

### 4. Éditer manuellement une description

```bash
./scripts/manage_oca_descriptions.sh edit account-analytic fr
```

## Services de Traduction Utilisés

Le système essaie les services dans cet ordre :

1. **Google Translate** (API gratuite non officielle)
2. **LibreTranslate** (Service libre et open source)
3. **MyMemory** (Service gratuit)

En cas d'échec de tous les services, des descriptions de fallback contextuelles sont utilisées.

## Dépendances

### Système

```bash
sudo apt-get install jq python3-requests
```

### Python

```bash
pip3 install requests
```

### 🆕 Gestion du Rate Limit

**Nouveau dans `update_oca_repositories.sh`** :

```bash
# Mise à jour des dépôts avec traductions (attention au rate limit)
./scripts/update_oca_repositories.sh --update-translations --lang fr

# Mise à jour sans traductions (recommandé)
./scripts/update_oca_repositories.sh --lang fr
```

**Options pour éviter le rate limit** :

```bash
# Traduction limitée et avec délais
./scripts/manage_oca_descriptions.sh complete-missing fr --limit 5 --delay 3

# Vérifier le rate limit GitHub
curl -s https://api.github.com/rate_limit | jq '.rate'
```

### ✅ Avantages

- **Dynamique** : Utilise toujours les descriptions GitHub les plus récentes
- **Précis** : Traductions de qualité professionnelle
- **Robuste** : Plusieurs services de fallback
- **Intelligent** : Cache les résultats pour éviter les requêtes répétées
- **Multilingue** : Support facile de nouvelles langues
- **Maintenable** : Plus besoin de maintenir des listes statiques

### 🔄 Comparaison avec l'ancien système

- **Avant** : Descriptions statiques codées en dur dans le script
- **Après** : Descriptions récupérées dynamiquement depuis GitHub et traduites

## Exemple d'Utilisation Complète

```bash
# 1. Voir l'état actuel
./scripts/manage_oca_descriptions.sh stats

# 2. Voir ce qui manque en français
./scripts/manage_oca_descriptions.sh missing fr

# 3. Tester la traduction d'un dépôt spécifique
./scripts/manage_oca_descriptions.sh test-translate connector-jira fr

# 4. Compléter automatiquement toutes les descriptions françaises manquantes
./scripts/manage_oca_descriptions.sh auto-complete fr

# 5. Vérifier les résultats
./scripts/manage_oca_descriptions.sh stats
```

## Configuration et Personnalisation

### Ajouter un nouveau service de traduction

Modifier `translate_description.py` et ajouter une nouvelle classe héritant de `TranslationService`.

### Modifier les langues supportées

Ajouter les codes de langue dans la fonction `normalize_language_code()`.

### Ajuster les descriptions de fallback

Modifier les patterns dans la fonction `auto_complete()` du script bash.

## Résolution de Problèmes

### Erreur "Module requests manquant"

```bash
pip3 install requests
# ou
sudo apt-get install python3-requests
```

### Erreur de traduction

- Vérifier la connexion internet
- Tester avec un dépôt connu : `./scripts/manage_oca_descriptions.sh test-translate server-tools fr`
- Les services de traduction peuvent avoir des limites de taux

### Dépôt non trouvé

- Vérifier que le dépôt existe sur GitHub : https://github.com/OCA/[nom-depot]
- Mettre à jour la liste : `make update-oca-repos`

## Performance

- **Cache automatique** : Les traductions sont mises en cache dans le fichier JSON
- **Pause entre requêtes** : 0.5s pour respecter les limites des APIs
- **Traitement en lot** : Toutes les descriptions manquantes d'un coup
- **Progression visible** : Compteur et statut pour chaque dépôt

## Sécurité

- **Pas de clés API** : Utilise uniquement des services gratuits
- **Pas de données sensibles** : Seules les descriptions publiques sont traitées
- **Sauvegarde automatique** : Backup avant chaque modification

Ce système offre une solution moderne, robuste et maintenable pour la gestion multilingue des descriptions OCA.

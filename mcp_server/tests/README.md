# Tests du serveur MCP

Ce répertoire contient les tests unitaires pour le serveur MCP Odoo Client Generator.

## Structure

- `test_mcp_server.py` - Tests unitaires complets du serveur MCP
- `run_tests.sh` - Script pour lancer les tests facilement
- `README.md` - Cette documentation

## Lancement des tests

### Méthode 1 : Script automatisé (recommandé)

```bash
./tests/run_tests.sh
```

### Méthode 2 : Python direct

```bash
python3 tests/test_mcp_server.py
```

### Méthode 3 : Depuis la racine du projet

```bash
make test-mcp  # Si ajouté au Makefile
```

## Tests inclus

### Tests de base
- ✅ **Server Creation** - Création du serveur MCP
- ✅ **Invalid Repo Path** - Gestion des chemins invalides
- ✅ **Command Execution** - Exécution de commandes système
- ✅ **Error Handling** - Gestion des erreurs

### Tests des outils
- ✅ **Tools List** - Liste des 13 outils MCP
- ✅ **Create Client Schema** - Schéma de l'outil create_client
- ✅ **Create Client Parameters** - Paramètres par défaut et personnalisés
- ✅ **Tool Calls Mapping** - Vérification des mappings de tous les outils
- ✅ **Delete Client Workflow** - Tests complets du workflow de suppression avec confirmation
- ✅ **List Clients Mock** - Fonctionnalité list_clients

## Outils testés

Le serveur MCP expose **13 outils** (version complète) :

1. `create_client` - Créer un nouveau client
2. `list_clients` - Lister les clients existants
3. `update_client` - Mettre à jour les submodules d'un client
4. `add_module` - Ajouter un module OCA à un client
5. `list_modules` - Lister les modules disponibles pour un client
6. `list_oca_modules` - Lister tous les modules OCA
7. `client_status` - Statut de tous les clients
8. `check_client` - Diagnostics d'un client spécifique
9. `update_requirements` - Mettre à jour les requirements Python
10. `update_oca_repos` - Mettre à jour les repos OCA depuis GitHub
11. `build_docker_image` - Construire l'image Docker personnalisée
12. `backup_client` - Créer une sauvegarde d'un client
13. `delete_client` - Supprimer un client (avec confirmation obligatoire)

## Prérequis

- Python 3.6+
- Bibliothèque `mcp` : `pip install mcp`
- Serveur MCP fonctionnel dans `mcp_server/mcp_server.py`

## Résultats

Les tests affichent :
- ✅ Tests réussis avec détails
- ❌ Tests échoués avec raisons
- 📊 Résumé final avec statistiques

## Utilisation en développement

Lancez les tests **à chaque modification** du serveur MCP :

```bash
# Après modification du serveur
./tests/run_tests.sh

# Si tous les tests passent, le serveur est prêt
# Redémarrez Claude Desktop pour utiliser les changements
```

### Tests de régression

Ces tests garantissent que :
- ✅ **Version complète** : 13 outils fonctionnels testés (16/16 tests ✅)
- ✅ **Pas de régression** : Chaque modification est vérifiée
- ✅ **Compatibilité Claude Desktop** : Structure MCP respectée
- ✅ **Signatures correctes** : Paramètres et types validés
- ✅ **Workflow de suppression** : Tests de sécurité et confirmation

### Ajout de nouvelles fonctionnalités

Quand vous ajoutez un nouvel outil MCP :

1. **Ajoutez l'outil** dans `mcp_server.py`
2. **Lancez les tests** : `make test-mcp`
3. **Si échec** : Mettez à jour les tests dans `tests/test_mcp_server.py`
4. **Testez Claude Desktop** : Redémarrez et vérifiez la connectivité

## Intégration continue

Ces tests peuvent être intégrés dans un pipeline CI/CD :

```bash
# Dans votre CI
./tests/run_tests.sh || exit 1
```

## Dépannage

### Erreur "MCP library not found"
```bash
pip install mcp
```

### Erreur "Server creation failed"
Vérifiez que :
- Le fichier `mcp_server/mcp_server.py` existe
- Le répertoire contient un `Makefile` valide
- Les permissions sont correctes

### Tests qui échouent
1. Vérifiez les logs détaillés dans la sortie
2. Testez le serveur MCP manuellement
3. Vérifiez les dépendances et la configuration
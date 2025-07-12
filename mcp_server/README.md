# Serveur MCP pour Odoo Client Generator

Ce répertoire contient le serveur MCP qui expose toutes les fonctionnalités du générateur de clients Odoo via le protocole MCP, permettant une interaction naturelle avec Claude Desktop.

## 📁 Structure

```
mcp_server/
├── mcp_server.py          # Serveur MCP principal
├── dev_mcp.sh            # Outils de développement
├── tests/                # Tests unitaires
│   ├── test_mcp_server.py
│   ├── run_tests.sh
│   └── README.md
├── requirements.txt      # Dépendances Python
└── README.md            # Cette documentation
```

## ⚡ Installation rapide

1. **Installer les dépendances** :
```bash
pip install -r mcp_server/requirements.txt
```

2. **Configurer Claude Desktop** :
Ajouter dans `~/.config/Claude/claude_desktop_config.json` :
```json
{
  "mcpServers": {
    "odoo-client-generator": {
      "command": "python3",
      "args": [
        "/home/user/odoo_alusage_18.0/mcp_server/mcp_server.py",
        "/home/user/odoo_alusage_18.0"
      ]
    }
  }
}
```

3. **Redémarrer Claude Desktop**

## 🚀 Utilisation

Dans Claude Desktop, utilisez des commandes naturelles :
- *"Créer un nouveau client avec le template ecommerce pour Odoo 18.0"*
- *"Lister tous les clients existants"*
- *"Ajouter le module sale_management au client mon_client"*
- *"Mettre à jour les repositories OCA"*
- *"Construire l'image Docker pour la version 17.0"*

## 🛠️ Développement

### Tests
```bash
# Depuis la racine du projet
make test-mcp

# Depuis mcp_server/
./tests/run_tests.sh
./dev_mcp.sh test
```

### Outils de développement
```bash
# Tests + surveillance des fichiers
./dev_mcp.sh test-watch

# Vérification syntaxe
./dev_mcp.sh syntax

# Statut complet
./dev_mcp.sh status

# Tests complets
./dev_mcp.sh full-test
```

### Script dev_mcp.sh utilité

Le script `dev_mcp.sh` est un outil de développement qui :
- **Automatise les tests** : lance les tests unitaires à chaque modification
- **Surveille les fichiers** : relance automatiquement les tests quand vous modifiez le code
- **Vérifie la syntaxe** : détecte les erreurs de code rapidement
- **Debug le serveur** : lance le serveur en mode debug pour diagnostics
- **Affiche le statut** : vérifie que tout fonctionne (processus, config, syntaxe)

C'est très utile quand vous développez/modifiez le serveur MCP !

## 🔧 Outils MCP exposés

Le serveur expose **12 outils** :

| Outil | Description |
|-------|-------------|
| `create_client` | Créer un nouveau client Odoo |
| `list_clients` | Lister tous les clients existants |
| `update_client` | Mettre à jour les submodules d'un client |
| `add_module` | Ajouter un module OCA à un client |
| `list_modules` | Lister les modules disponibles pour un client |
| `list_oca_modules` | Lister tous les modules OCA |
| `client_status` | Afficher le statut de tous les clients |
| `check_client` | Exécuter des diagnostics sur un client |
| `update_requirements` | Mettre à jour les requirements Python |
| `update_oca_repos` | Mettre à jour les repos OCA depuis GitHub |
| `build_docker_image` | Construire une image Docker personnalisée |
| `backup_client` | Créer une sauvegarde d'un client |

## 🧪 Tests unitaires

Les tests garantissent :
- ✅ **12/12 tests qui passent** avec la version stable
- ✅ **Pas de régression** lors des modifications
- ✅ **Performance** : création < 2s, appels < 100ms
- ✅ **Compatibilité Claude Desktop** : structure MCP respectée

Voir [tests/README.md](tests/README.md) pour plus de détails.

## 🐛 Dépannage

### Serveur déconnecté
1. Vérifiez que le serveur démarre : `./dev_mcp.sh debug`
2. Vérifiez la configuration : `./dev_mcp.sh config`
3. Redémarrez Claude Desktop : `./dev_mcp.sh restart-claude`

### Tests qui échouent
1. Vérifiez la syntaxe : `./dev_mcp.sh syntax`
2. Lancez les tests : `./dev_mcp.sh test`
3. Vérifiez le statut : `./dev_mcp.sh status`

### Processus bloqués
```bash
./dev_mcp.sh clean  # Nettoie les processus MCP
```
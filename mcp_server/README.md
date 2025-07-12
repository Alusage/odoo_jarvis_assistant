# Odoo Client MCP Server

Un serveur MCP (Model Context Protocol) pour interagir avec le générateur de dépôts clients Odoo à travers Claude Desktop.

## Installation

```bash
cd mcp_server
pip install -r requirements.txt
```

## Configuration Claude Desktop

Ajouter dans `~/.config/Claude/claude_desktop_config.json` :

```json
{
  "mcpServers": {
    "odoo-client-generator": {
      "command": "python3",
      "args": [
        "/chemin/vers/votre/depot/mcp_server/mcp_server.py",
        "/chemin/vers/votre/depot"
      ]
    }
  }
}
```

## Outils disponibles (12)

### Gestion des clients
- `create_client` - Créer un nouveau client Odoo
- `list_clients` - Lister tous les clients existants  
- `update_client` - Mettre à jour les submodules d'un client
- `check_client` - Diagnostics sur un client spécifique
- `client_status` - Statut de tous les clients
- `backup_client` - Sauvegarder un client

### Gestion des modules
- `add_module` - Ajouter un module OCA à un client
- `list_modules` - Lister les modules disponibles pour un client
- `list_oca_modules` - Lister tous les modules OCA avec filtrage optionnel
- `update_requirements` - Mettre à jour les requirements Python d'un client

### Maintenance
- `update_oca_repos` - Mettre à jour la liste des dépôts OCA depuis GitHub
- `build_docker_image` - Construire une image Docker Odoo personnalisée

## Utilisation avec Claude Desktop

Une fois configuré, vous pouvez utiliser Claude Desktop pour interagir avec votre générateur :

**Exemples de commandes :**
- "Crée un nouveau client appelé 'mon-client' avec le template ecommerce pour Odoo 18.0"
- "Liste tous mes clients existants"
- "Ajoute le module 'partner-contact' au client 'mon-client'"
- "Mets à jour les requirements du client 'mon-client'"
- "Montre-moi le statut de tous mes clients"

## Test

```bash
# Tester le serveur
python3 mcp_server.py /chemin/vers/depot

# Vérifier la configuration
python3 -c "import mcp; print('MCP library OK')"
```

## Prérequis

- Python 3.8+
- Générateur Odoo Client (git, jq, etc.)
- Claude Desktop

---

*Ce projet a été développé avec l'assistance de l'IA Claude d'Anthropic.*
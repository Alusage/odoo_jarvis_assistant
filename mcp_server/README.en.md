# Dual-Mode MCP Server for Odoo Client Repository Generator

This MCP (Model Context Protocol) server exposes all Odoo client management tools through both:
- **MCP protocol over stdio** (for Claude Desktop integration)
- **HTTP REST API** (for web dashboards and external integrations)

## Features

- **Client Management**: Create, list, update, and delete Odoo client repositories
- **Module Management**: Add OCA modules, link modules, and manage dependencies
- **Repository Management**: Handle Git submodules and external repositories
- **Diagnostics**: Comprehensive client health checks and issue detection
- **Requirements Management**: Automatic Python requirements generation
- **OCA Integration**: Browse and manage OCA module repositories
- **Dual Interface**: Both MCP stdio and HTTP API support
- **Docker Support**: Containerized HTTP server with Traefik integration
- **HTTPS Support**: SSL/TLS termination via Traefik

## Installation

1. Install dependencies:
```bash
pip install -r requirements.txt
```

## Usage Modes

### 1. stdio Mode (Claude Desktop)

Configure Claude Desktop by adding to `~/.config/Claude/claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "odoo-client-generator": {
      "command": "python3",
      "args": ["/path/to/mcp_server/mcp_server.py", "/path/to/odoo_alusage_18.0", "--mode", "stdio"],
      "env": {}
    }
  }
}
```

### 2. HTTP Mode (Web Dashboard)

#### Local Development
```bash
python3 mcp_server.py . --mode http --host 0.0.0.0 --port 8000
```

#### Docker with Traefik
```bash
cd mcp_server
./start-http.sh
```

This will:
- Build and start the MCP server in a Docker container
- Configure Traefik routing for HTTP/HTTPS
- Make the API available at:
  - `http://mcp.odoo-alusage.localhost`
  - `https://mcp.odoo-alusage.localhost` (with automatic SSL)

#### Stop HTTP Server
```bash
cd mcp_server
./stop-http.sh
```

### 3. Both Modes (Hybrid)
```bash
python3 mcp_server.py . --mode both --host 0.0.0.0 --port 8000
```

## HTTP API Endpoints

### Server Info
- `GET /` - Server information and status
- `GET /tools` - List available MCP tools

### Tool Execution
- `POST /tools/call` - Execute any MCP tool
  ```json
  {
    "name": "list_clients",
    "arguments": {}
  }
  ```

### Client Management
- `GET /clients` - List all clients
- `GET /clients/{client_name}/status` - Get client status
- `GET /status` - Get status of all clients

### Examples

```bash
# List clients
curl http://mcp.odoo-alusage.localhost/clients

# Check client status
curl http://mcp.odoo-alusage.localhost/clients/my-client/status

# Create a client via tool call
curl -X POST http://mcp.odoo-alusage.localhost/tools/call \
  -H "Content-Type: application/json" \
  -d '{
    "name": "create_client",
    "arguments": {
      "name": "new-client",
      "template": "ecommerce",
      "version": "18.0"
    }
  }'
```

## Available Tools

- `create_client` - Create a new Odoo client repository
- `list_clients` - List all existing client repositories
- `update_client` - Update submodules for a specific client
- `add_module` - Add an OCA module to a client
- `link_modules` - Link modules from a repository to a client
- `list_modules` - List available modules for a client
- `list_oca_modules` - Browse OCA modules with optional filtering
- `client_status` - Show status of all clients
- `check_client` - Run diagnostics on a specific client
- `diagnose_client` - Run comprehensive diagnostics with detailed output
- `update_requirements` - Update Python requirements for a client
- `update_oca_repos` - Update OCA repository information
- `backup_client` - Create a backup of a client repository
- `delete_client` - Delete a client repository (with confirmation)

## Docker Configuration

### Dockerfile
The server runs in a Python 3.11 slim container with:
- Git and Make for repository operations
- Volume mounting for repository access
- Health checks for reliability

### Traefik Integration
- Automatic HTTP to HTTPS redirect
- SSL certificate management via Let's Encrypt
- CORS headers for API access
- Load balancing ready

### Environment Variables
- `PYTHONUNBUFFERED=1` - Real-time logging
- Custom host/port configuration available

## Development

### Local Development
```bash
# stdio mode (for Claude testing)
python3 mcp_server.py . --mode stdio

# HTTP mode (for web testing)
python3 mcp_server.py . --mode http --port 8000

# Both modes
python3 mcp_server.py . --mode both --port 8000
```

### Run Tests
```bash
./tests/run_tests.sh
```

### Development Tools
```bash
./dev_mcp.sh help
```

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Claude        │    │   Web           │    │   External      │
│   Desktop       │    │   Dashboard     │    │   API Clients   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │ stdio/MCP             │ HTTP/REST             │ HTTP/REST
         │                       │                       │
┌─────────────────────────────────────────────────────────────────┐
│                    MCP Server (Dual Mode)                      │
│  ┌─────────────────┐              ┌─────────────────────────┐  │
│  │   stdio Handler │              │     FastAPI HTTP       │  │
│  │                 │              │                         │  │
│  │  - MCP Protocol │              │  - REST Endpoints      │  │
│  │  - Tool Calls   │              │  - CORS Support        │  │
│  │  - Text Responses              │  - JSON Responses      │  │
│  └─────────────────┘              └─────────────────────────┘  │
│                    │                        │                  │
│                    └────────────────────────┘                  │
│                           │                                     │
│              ┌─────────────────────────────┐                   │
│              │     Shared Tool Handlers    │                   │
│              │                             │                   │
│              │  - Client Management        │                   │
│              │  - Module Operations        │                   │
│              │  - Diagnostics              │                   │
│              │  - Repository Management    │                   │
│              └─────────────────────────────┘                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────────────────┐
                    │   Odoo Repository   │
                    │                     │
                    │  - Makefile         │
                    │  - Scripts          │
                    │  - Client Configs   │
                    └─────────────────────┘
```

## Troubleshooting

### stdio Mode
1. **Permission Issues**: Ensure the script has execute permissions
2. **Path Issues**: Use absolute paths in Claude Desktop configuration
3. **Dependencies**: Make sure all required packages are installed

### HTTP Mode
1. **Port Conflicts**: Change port with `--port` option
2. **Network Issues**: Ensure Traefik network exists
3. **SSL Issues**: Check Traefik certificate configuration
4. **CORS Issues**: Verify middleware configuration

### Docker
1. **Build Issues**: Check Dockerfile and dependencies
2. **Volume Mounting**: Ensure repository path is accessible
3. **Network**: Verify traefik-public network exists

## Contributing

1. Add new tools in the `_setup_handlers()` method
2. Implement corresponding methods following the naming pattern `_tool_name()`
3. Update both stdio and HTTP response handling
4. Add comprehensive tests in the `tests/` directory
5. Update this documentation
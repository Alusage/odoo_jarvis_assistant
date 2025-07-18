# 🚀 Setup Instructions

## Quick Start

1. **Configure environment** (auto-detects Docker group and user IDs):
   ```bash
   ./setup-env.sh
   ```

2. **Start services**:
   ```bash
   docker compose up -d
   ```

3. **Access services**:
   - **Dashboard**: http://dashboard.localhost
   - **MCP Server**: http://mcp.localhost
   - **Traefik Dashboard**: http://traefik.localhost:8080

## Configuration

The `setup-env.sh` script automatically detects:
- Docker group ID (usually 997 or 999)
- Current user ID (usually 1000)
- Creates `.env` file with these values

This ensures Docker socket permissions work correctly across different machines.

## Environment Variables

The following variables are auto-configured in `.env`:

```bash
# Docker group ID (auto-detected)
DOCKER_GID=997

# User ID (auto-detected)  
USER_ID=1000

# Service ports
MCP_SERVER_PORT=8000
DASHBOARD_PORT=3000
TRAEFIK_PORT=8080
```

## Troubleshooting

### Docker Permission Issues

If you see permission errors like:
```
permission denied while trying to connect to the Docker daemon socket
```

1. Run the setup script again:
   ```bash
   ./setup-env.sh
   ```

2. Rebuild and restart the MCP server:
   ```bash
   docker compose build mcp-server
   docker compose up -d mcp-server
   ```

### User Not in Docker Group

If the setup script warns about Docker group membership:
```bash
sudo usermod -aG docker $USER
```
Then logout and login again.

### Different Machine Setup

The system automatically adapts to different machines by:
- Detecting local Docker group ID
- Detecting local user ID
- Creating appropriate build args for containers

No manual configuration needed!
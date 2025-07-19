# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an **Odoo Client Repository Generator** - an automated system for creating standardized Odoo client repositories. It supports multi-version Odoo (16.0, 17.0, 18.0), automatic OCA module integration, optional Odoo Enterprise support, and pre-configured Docker Compose environments.

## Common Commands

### Creating and Managing Clients
```bash
# Create a new client interactively
./create_client.sh
make create-client

# List all existing clients
make list-clients

# Check status of all clients
make status

# Run diagnostics on a specific client
make check-client CLIENT=client_name

# Update a client's submodules
make update-client CLIENT=client_name

# Update client's Python requirements automatically
make update-requirements CLIENT=client_name
make update-requirements CLIENT=client_name CLEAN=true
```

### Managing OCA Modules
```bash
# Add an OCA module to a client
make add-module CLIENT=client_name MODULE=module_key

# List available modules for a client
make list-modules CLIENT=client_name

# List all available OCA modules (with optional filtering)
make list-oca-modules
make list-oca-modules PATTERN=account

# Update OCA repository list from GitHub
make update-oca-repos                    # French descriptions
make update-oca-repos-en                 # English descriptions
make update-oca-repos-fast               # Fast update without verification
```

### OCA Descriptions Management
```bash
# List all OCA descriptions
make descriptions-list

# Show missing descriptions
make descriptions-missing LANG=fr
make descriptions-missing LANG=en

# Auto-complete descriptions
make descriptions-auto LANG=fr

# View description statistics
make descriptions-stats

# Validate description file format
make descriptions-validate

# Edit descriptions file
make edit-descriptions
```

### Version and Branch Management
```bash
# Configure branch-version mappings for a client
make configure-branch-version CLIENT=client_name BRANCH=master VERSION=18.0
make configure-branch-version CLIENT=client_name BRANCH=production VERSION=17.0

# List branch-version mappings for a client
make list-branch-mappings CLIENT=client_name
./scripts/configure_branch_version.sh client_name --list

# Get Odoo version for a branch
make get-branch-version CLIENT=client_name BRANCH=master
make get-branch-version CLIENT=client_name  # Current branch

# Switch branches (with version info)
make switch-branch CLIENT=client_name BRANCH=staging
./scripts/switch_client_branch.sh client_name staging --create

# Check module compatibility across versions
make check-compatibility CLIENT=client_name VERSION=17.0
make check-compatibility CLIENT=client_name FORMAT=json
```

### Multi-Branch Deployment Management

Le système supporte deux architectures pour les déploiements multi-branches :

#### **V1 - Dynamic Docker Compose with Traefik**
- **Principe** : Docker Compose dynamique avec volumes montés
- **Avantages** : Configuration Traefik automatique, URLs dynamiques
- **Inconvénients** : Partage du même dépôt Git local
```bash
# Deploy a specific branch (creates Docker containers with Traefik URLs)
make deploy-branch CLIENT=client_name BRANCH=master
make deploy-branch CLIENT=client_name BRANCH=dev-feature
make deploy-branch CLIENT=client_name BRANCH=staging

# Manage deployments
make stop-deployment CLIENT=client_name BRANCH=master
make restart-deployment CLIENT=client_name BRANCH=dev-feature
make deployment-logs CLIENT=client_name BRANCH=staging
make deployment-shell CLIENT=client_name BRANCH=master

# Global deployment management
make list-deployments              # List all active deployments
make deployment-status             # Show status of all deployments
make deployment-urls               # Show all deployment URLs
make stop-all-deployments          # Stop all deployments
make clean-deployments             # Clean up stopped containers

# Direct script usage for more control
./scripts/deploy_branch.sh client_name master up -d
./scripts/deploy_branch.sh client_name dev-feature logs
./scripts/deploy_branch.sh client_name staging shell
./scripts/manage_deployments.sh status
```

#### **V2 - Git Clone in Docker (Recommended)**
- **Principe** : Git clone de la branche dans l'image Docker lors du build
- **Avantages** : Isolation complète des branches, version spécifique embarquée
- **Workflow** : `git clone /mnt/client` → `git checkout branch` → Image Docker dédiée
```bash
# Build Docker image for a specific branch (embeds Git repository)
make build-branch-image CLIENT=client_name BRANCH=master
make build-branch-image CLIENT=client_name BRANCH=dev-feature FORCE=true

# Deploy a branch with embedded Git repository
make deploy-branch-v2 CLIENT=client_name BRANCH=master
make deploy-branch-v2 CLIENT=client_name BRANCH=dev-feature
make deploy-branch-v2 CLIENT=client_name BRANCH=staging

# Manage V2 deployments
make stop-deployment-v2 CLIENT=client_name BRANCH=master
make restart-deployment-v2 CLIENT=client_name BRANCH=dev-feature
make deployment-logs-v2 CLIENT=client_name BRANCH=staging
make deployment-shell-v2 CLIENT=client_name BRANCH=master
make deployment-status-v2 CLIENT=client_name BRANCH=production

# Direct script usage for more control
./scripts/build_branch_image.sh client_name master --force
./scripts/deploy_branch_v2.sh client_name dev-feature up
./scripts/deploy_branch_v2.sh client_name staging logs
./scripts/deploy_branch_v2.sh client_name production shell
```

### Docker Operations
```bash
# Build custom Odoo Docker image
make build
make build VERSION=18.0 TAG=custom-tag

# Build client-specific Docker image (within client directory)
cd clients/client_name/docker
./build.sh
./build.sh --no-cache --tag 1.0
```

### Testing and Demo
```bash
# Run comprehensive tests
make test
./test.sh

# Run MCP server tests (unit tests for MCP functionality)
make test-mcp
./mcp_server/tests/run_tests.sh

# Run demo with example client creation
make demo
./demo.sh

# Install system dependencies
make install-deps
./install_deps.sh
```

### Template Management
```bash
# Manage client templates interactively
make manage-templates
./manage_templates.sh
```

### Maintenance
```bash
# Clean temporary files
make clean

# Cache management
make cache-status
make clean-cache

# Backup a client
make backup-client CLIENT=client_name
```

## Architecture and Structure

### Core Components

**Configuration System**: Uses separate JSON files in `config/` for modular configuration:
- `client_templates.json` - Client template definitions (basic, ecommerce, manufacturing, services, custom)
- `oca_descriptions.json` - Multilingual descriptions for OCA modules  
- `repositories.json` - External repository configurations
- `odoo_versions.json` - Supported Odoo version configurations

**Client Generation Pipeline**:
1. `create_client.sh` - Interactive client creation entry point
2. `scripts/generate_client_repo.sh` - Core client repository generator
3. Template system creates complete client structure with Docker configurations

**Version and Branch Management**:
1. `scripts/configure_branch_version.sh` - Configure Odoo version mappings for client branches
2. `scripts/get_branch_version.sh` - Get Odoo version for specific branches
3. `scripts/switch_client_branch.sh` - Enhanced branch switching with version info
4. `scripts/check_version_compatibility.sh` - Check module compatibility across versions

**Multi-Branch Deployment**:
1. `scripts/deploy_branch.sh` - V1 deployment with Traefik and dynamic compose
2. `scripts/manage_deployments.sh` - Global deployment management
3. `scripts/build_branch_image.sh` - V2 branch-specific Docker image builder
4. `scripts/deploy_branch_v2.sh` - V2 deployment with embedded Git repository

**Generated Client Structure**:
```
clients/client_name/
├── addons/                 # OCA submodules (exact GitHub repo names)
├── extra-addons/          # Symbolic links to activated modules
├── config/odoo.conf       # Odoo configuration
├── docker/                # Client-specific Docker setup
├── scripts/               # Client management scripts
├── data/                  # Client data directory
├── requirements.txt       # Auto-generated Python dependencies
├── .odoo_branch_config    # Branch-to-Odoo-version mappings
└── .odoo_version          # Legacy version tracking (deprecated)
```

### Key Scripts

**Client Management**:
- `scripts/generate_client_repo.sh` - Main client generation logic
- `scripts/update_client_submodules.sh` - Update client Git submodules
- `scripts/update_client_requirements.sh` - Auto-generate Python requirements from OCA modules

**OCA Module Management**:
- `scripts/add_oca_module.sh` - Add OCA modules to existing clients
- `scripts/list_oca_modules.sh` - List available OCA modules with descriptions
- `scripts/update_oca_repositories.sh` - Sync OCA repository list from GitHub
- `scripts/manage_oca_descriptions.sh` - Manage multilingual module descriptions

**Repository Management**:
- `scripts/repository_optimizer.sh` - Git repository caching and optimization
- `scripts/add_external_module.sh` - Add non-OCA external repositories

### Docker Integration

Each generated client includes **two Docker deployment options**:

1. **Client-specific Docker image** (Recommended): Located in `clients/client_name/docker/`
   - Custom image tagged as `odoo-alusage-client_name:version`
   - Pre-installed Python dependencies
   - Optimized for production deployment

2. **Generic Docker setup**: Uses standard Odoo image with volume mounts

### Module Naming Convention

OCA modules use **exact GitHub repository names** for consistency:
- `partner-contact/` (not `partner_contact/`)
- `account-financial-tools/` (not `account_financial_tools/`)
- `stock-logistics-workflow/` (not `stock_logistics_workflow/`)

### Multi-language Support

The system supports French and English descriptions for OCA modules via `config/oca_descriptions.json`, allowing for internationalization of module documentation.

### MCP Server Integration

The project includes an **MCP (Model Context Protocol) server** that exposes all functionality to Claude Desktop:
- **Location**: `mcp_server/` (serveur, tests, outils de développement)
- **Configuration**: `~/.config/Claude/claude_desktop_config.json`
- **Tools exposed**: 19+ outils stables pour gestion clients, modules OCA, Docker, déploiements multi-branches
- **Testing**: `make test-mcp` pour tests unitaires complets
- **Development**: `make dev-mcp ARGS="help"` pour outils de développement

**Multi-Branch Tools** (nouvellement ajoutés):
- `start_client_branch` - Démarrer un déploiement de branche
- `stop_client_branch` - Arrêter un déploiement de branche  
- `restart_client_branch` - Redémarrer un déploiement de branche
- `get_branch_logs` - Récupérer les logs d'une branche
- `open_branch_shell` - Ouvrir un shell dans le conteneur d'une branche
- `get_branch_status` - Obtenir le statut d'un déploiement de branche
- `list_deployments` - Lister tous les déploiements actifs

## Important Notes

- Always check that clients exist before running operations with `make list-clients`
- OCA repository updates can take time - use `--fast` option for quick updates
- Python requirements are auto-generated from OCA module dependencies
- Git hooks are versioned in the `hooks/` directory - configure with `git config core.hooksPath hooks`
- Client repositories are independent Git repositories with their own submodules
- The system maintains a cache of OCA repositories for performance optimization

### Multi-Branch Deployment Notes

**V1 vs V2 Architecture**:
- **V1** : Volumes montés, partage du même dépôt Git local entre branches
- **V2** : Git clone dans Docker, isolation complète des branches, version embarquée

**V2 Workflow**:
1. `make build-branch-image CLIENT=client BRANCH=branch` - Clone la branche dans l'image
2. `make deploy-branch-v2 CLIENT=client BRANCH=branch` - Déploie l'image avec la branche
3. Chaque rebuild récupère automatiquement le dernier commit de la branche

**V2 Advantages**:
- Isolation complète des branches (code, données, configuration)
- Version spécifique embarquée dans l'image Docker
- Pas de conflit entre branches simultanées
- Rebuild automatique des derniers commits

## Testing

The project includes comprehensive testing via `./test.sh` which verifies:
- System prerequisites (git, jq)
- Configuration file validity
- Client creation with different templates
- Module addition and management
- Docker configuration validation
- Make command functionality
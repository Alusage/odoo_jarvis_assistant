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

**Generated Client Structure**:
```
clients/client_name/
├── addons/                 # OCA submodules (exact GitHub repo names)
├── extra-addons/          # Symbolic links to activated modules
├── config/odoo.conf       # Odoo configuration
├── docker/                # Client-specific Docker setup
├── scripts/               # Client management scripts
├── data/                  # Client data directory
└── requirements.txt       # Auto-generated Python dependencies
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

## Important Notes

- Always check that clients exist before running operations with `make list-clients`
- OCA repository updates can take time - use `--fast` option for quick updates
- Python requirements are auto-generated from OCA module dependencies
- Git hooks are versioned in the `hooks/` directory - configure with `git config core.hooksPath hooks`
- Client repositories are independent Git repositories with their own submodules
- The system maintains a cache of OCA repositories for performance optimization

## Testing

The project includes comprehensive testing via `./test.sh` which verifies:
- System prerequisites (git, jq)
- Configuration file validity
- Client creation with different templates
- Module addition and management
- Docker configuration validation
- Make command functionality
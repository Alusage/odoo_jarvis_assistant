#!/bin/bash
"""
Script to stop MCP Server HTTP mode
"""

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🛑 Stopping Odoo MCP Server...${NC}"

# Stop the services
docker-compose down

echo -e "${GREEN}✅ MCP Server stopped${NC}"

# Option to remove images
read -p "Remove Docker images? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}🗑️  Removing Docker images...${NC}"
    docker-compose down --rmi all
    echo -e "${GREEN}✅ Images removed${NC}"
fi
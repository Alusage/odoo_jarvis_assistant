#!/bin/bash
"""
Script to start MCP Server in HTTP mode with Docker and Traefik
"""

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting Odoo MCP Server in HTTP mode${NC}"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ Docker is not running. Please start Docker first.${NC}"
    exit 1
fi

# Check if Traefik network exists
if ! docker network ls | grep -q traefik-public; then
    echo -e "${YELLOW}⚠️  Traefik network not found. Creating traefik-public network...${NC}"
    docker network create traefik-public
fi

# Build and start the services
echo -e "${BLUE}🔨 Building MCP Server Docker image...${NC}"
docker-compose build

echo -e "${BLUE}🚀 Starting MCP Server...${NC}"
docker-compose up -d

# Wait for the service to be ready
echo -e "${BLUE}⏳ Waiting for MCP Server to be ready...${NC}"
sleep 5

# Check if service is running
if docker-compose ps | grep -q "Up"; then
    echo -e "${GREEN}✅ MCP Server is running!${NC}"
    echo -e "${GREEN}🌐 HTTP API available at: http://mcp.odoo-alusage.localhost${NC}"
    echo -e "${GREEN}🔒 HTTPS API available at: https://mcp.odoo-alusage.localhost${NC}"
    echo ""
    echo -e "${BLUE}📋 Available endpoints:${NC}"
    echo -e "  • GET  /                     - Server info"
    echo -e "  • GET  /tools                - List available tools"
    echo -e "  • POST /tools/call           - Call a tool"
    echo -e "  • GET  /clients              - List clients"
    echo -e "  • GET  /clients/{name}/status - Check client status"
    echo -e "  • GET  /status               - Get all clients status"
    echo ""
    echo -e "${BLUE}📊 View logs:${NC} docker-compose logs -f"
    echo -e "${BLUE}🛑 Stop server:${NC} docker-compose down"
else
    echo -e "${RED}❌ Failed to start MCP Server${NC}"
    echo -e "${YELLOW}📋 Check logs:${NC} docker-compose logs"
    exit 1
fi
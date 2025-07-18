#!/usr/bin/env python3
"""
MCP Server for Odoo Client Repository Generator

This server exposes all Odoo client management tools via both:
- MCP protocol over stdio (for Claude Desktop)
- HTTP API (for web dashboard)
"""

import asyncio
import subprocess
import os
import sys
import logging
import json
import argparse
from pathlib import Path
from typing import Any, Dict, List, Optional
from contextlib import asynccontextmanager

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    stream=sys.stderr
)
logger = logging.getLogger(__name__)

try:
    from mcp.server.stdio import stdio_server
    from mcp.types import TextContent, Tool, JSONRPCRequest, JSONRPCNotification
    from mcp.server import Server
    import mcp.types as types
except ImportError:
    logger.error("MCP library not found. Install with: pip install mcp")
    sys.exit(1)

# HTTP server dependencies
try:
    from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
    from fastapi.middleware.cors import CORSMiddleware
    from pydantic import BaseModel
    import uvicorn
    import asyncio
    import pty
    import select
    import termios
    import struct
    import fcntl
except ImportError:
    logger.warning("FastAPI not found. HTTP mode will not be available. Install with: pip install fastapi uvicorn")
    FastAPI = None

# HTTP API Models
if FastAPI:
    class ToolCallRequest(BaseModel):
        name: str
        arguments: Dict[str, Any] = {}
    
    class ToolCallResponse(BaseModel):
        success: bool
        result: Any
        error: Optional[str] = None

class OdooClientMCPServer:
    """MCP Server for Odoo Client Repository Generator"""
    
    def __init__(self, repo_path: str):
        self.repo_path = Path(repo_path).resolve()
        self.server = Server("odoo-client-generator")
        self.http_app = None
        
        if not self.repo_path.exists():
            raise ValueError(f"Repository path '{repo_path}' does not exist")
        
        if not (self.repo_path / "Makefile").exists():
            raise ValueError(f"Makefile not found in '{repo_path}'. Not a valid repository.")
        
        self._setup_handlers()
        if FastAPI:
            self._setup_http_app()
    
    def _run_command(self, command: List[str], cwd: Optional[Path] = None) -> Dict[str, Any]:
        """Execute a shell command and return the result"""
        try:
            result = subprocess.run(
                command,
                cwd=cwd or self.repo_path,
                capture_output=True,
                text=True,
                timeout=300  # 5 minute timeout
            )
            return {
                "success": result.returncode == 0,
                "stdout": result.stdout,
                "stderr": result.stderr,
                "return_code": result.returncode
            }
        except subprocess.TimeoutExpired:
            return {
                "success": False,
                "stdout": "",
                "stderr": "Command timed out after 5 minutes",
                "return_code": -1
            }
        except Exception as e:
            return {
                "success": False,
                "stdout": "",
                "stderr": str(e),
                "return_code": -1
            }
    
    def _setup_handlers(self):
        """Setup MCP handlers"""
        
        @self.server.list_tools()
        async def handle_list_tools():
            """Return list of available tools"""
            return [
                types.Tool(
                    name="create_client",
                    description="Create a new Odoo client repository",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "name": {
                                "type": "string",
                                "description": "Client name (will be used as directory name)"
                            },
                            "template": {
                                "type": "string",
                                "description": "Template type",
                                "enum": ["basic", "ecommerce", "manufacturing", "services", "custom"],
                                "default": "basic"
                            },
                            "version": {
                                "type": "string",
                                "description": "Odoo version",
                                "enum": ["16.0", "17.0", "18.0"],
                                "default": "18.0"
                            },
                            "has_enterprise": {
                                "type": "boolean",
                                "description": "Include Odoo Enterprise modules and repositories",
                                "default": False
                            }
                        },
                        "required": ["name"]
                    }
                ),
                types.Tool(
                    name="create_client_github",
                    description="Create a new Odoo client repository with GitHub integration",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "name": {
                                "type": "string",
                                "description": "Client name (will be used as directory and repository name)"
                            },
                            "template": {
                                "type": "string",
                                "description": "Template type",
                                "enum": ["basic", "ecommerce", "manufacturing", "services", "custom"],
                                "default": "basic"
                            },
                            "version": {
                                "type": "string",
                                "description": "Odoo version",
                                "enum": ["16.0", "17.0", "18.0"],
                                "default": "18.0"
                            },
                            "has_enterprise": {
                                "type": "boolean",
                                "description": "Include Odoo Enterprise modules and repositories",
                                "default": False
                            },
                            "github_token": {
                                "type": "string",
                                "description": "GitHub personal access token"
                            },
                            "github_org": {
                                "type": "string",
                                "description": "GitHub organization name",
                                "default": "Alusage"
                            },
                            "git_user_name": {
                                "type": "string",
                                "description": "Git user name for commits"
                            },
                            "git_user_email": {
                                "type": "string",
                                "description": "Git user email for commits"
                            }
                        },
                        "required": ["name", "github_token", "git_user_name", "git_user_email"]
                    }
                ),
                types.Tool(
                    name="list_clients",
                    description="List all existing client repositories",
                    inputSchema={
                        "type": "object",
                        "properties": {},
                        "required": []
                    }
                ),
                types.Tool(
                    name="update_client",
                    description="Update submodules for a specific client",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client to update"
                            }
                        },
                        "required": ["client"]
                    }
                ),
                types.Tool(
                    name="add_module",
                    description="Add an OCA module to a client",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "module": {
                                "type": "string", 
                                "description": "Module key/name to add"
                            },
                            "link_all": {
                                "type": "boolean",
                                "description": "Link all modules from the repository to extra-addons",
                                "default": False
                            },
                            "link_modules": {
                                "type": "string",
                                "description": "Comma-separated list of specific modules to link to extra-addons (e.g. 'module1,module2')"
                            }
                        },
                        "required": ["client", "module"]
                    }
                ),
                types.Tool(
                    name="link_modules",
                    description="Link existing repository modules to extra-addons for a client",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "repository": {
                                "type": "string",
                                "description": "Repository name (e.g. 'sale-workflow', 'account-analytic')"
                            },
                            "link_all": {
                                "type": "boolean",
                                "description": "Link all modules from the repository",
                                "default": False
                            },
                            "modules": {
                                "type": "string",
                                "description": "Comma-separated list of specific modules to link (e.g. 'module1,module2')"
                            }
                        },
                        "required": ["client", "repository"]
                    }
                ),
                types.Tool(
                    name="list_modules",
                    description="List available modules for a specific client",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            }
                        },
                        "required": ["client"]
                    }
                ),
                types.Tool(
                    name="list_oca_modules",
                    description="List all available OCA modules with optional filtering",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "pattern": {
                                "type": "string",
                                "description": "Optional pattern to filter modules",
                                "default": ""
                            }
                        },
                        "required": []
                    }
                ),
                types.Tool(
                    name="client_status",
                    description="Show status of all clients",
                    inputSchema={
                        "type": "object",
                        "properties": {},
                        "required": []
                    }
                ),
                types.Tool(
                    name="check_client",
                    description="Run diagnostics on a specific client",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client to check"
                            }
                        },
                        "required": ["client"]
                    }
                ),
                types.Tool(
                    name="update_requirements",
                    description="Update Python requirements for a client based on OCA module dependencies",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "clean": {
                                "type": "boolean",
                                "description": "Whether to clean backup files after update",
                                "default": False
                            }
                        },
                        "required": ["client"]
                    }
                ),
                types.Tool(
                    name="update_oca_repos",
                    description="Update OCA repository list from GitHub",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "language": {
                                "type": "string",
                                "description": "Language for descriptions",
                                "enum": ["fr", "en"],
                                "default": "fr"
                            },
                            "fast": {
                                "type": "boolean",
                                "description": "Use fast update without verification",
                                "default": False
                            }
                        },
                        "required": []
                    }
                ),
                types.Tool(
                    name="build_docker_image",
                    description="Build custom Odoo Docker image",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "version": {
                                "type": "string",
                                "description": "Odoo version to build",
                                "default": "18.0"
                            },
                            "tag": {
                                "type": "string",
                                "description": "Custom tag for the image",
                                "default": ""
                            }
                        },
                        "required": []
                    }
                ),
                types.Tool(
                    name="backup_client",
                    description="Create a backup of a client",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client to backup"
                            }
                        },
                        "required": ["client"]
                    }
                ),
                types.Tool(
                    name="diagnose_client",
                    description="Run comprehensive diagnostics on a client to identify issues",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client to diagnose"
                            },
                            "format": {
                                "type": "string",
                                "description": "Output format",
                                "enum": ["text", "json"],
                                "default": "text"
                            },
                            "verbose": {
                                "type": "boolean",
                                "description": "Enable verbose output with detailed information",
                                "default": False
                            }
                        },
                        "required": ["client"]
                    }
                ),
                types.Tool(
                    name="delete_client",
                    description="Delete a client repository (REQUIRES USER CONFIRMATION)",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client to delete"
                            },
                            "confirmed": {
                                "type": "boolean",
                                "description": "User confirmation for deletion (must be true to proceed)",
                                "default": False
                            }
                        },
                        "required": ["client"]
                    }
                ),
                types.Tool(
                    name="start_client",
                    description="Start a client's Docker containers",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client to start"
                            }
                        },
                        "required": ["client"]
                    }
                ),
                types.Tool(
                    name="stop_client",
                    description="Stop a client's Docker containers",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client to stop"
                            }
                        },
                        "required": ["client"]
                    }
                ),
                types.Tool(
                    name="rebuild_client",
                    description="Rebuild a client's Docker image with updated requirements",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client to rebuild"
                            },
                            "no_cache": {
                                "type": "boolean",
                                "description": "Build without using cache",
                                "default": False
                            }
                        },
                        "required": ["client"]
                    }
                ),
                types.Tool(
                    name="get_client_status",
                    description="Get the running status of a client's Docker containers",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client to check"
                            }
                        },
                        "required": ["client"]
                    }
                ),
                types.Tool(
                    name="get_client_logs",
                    description="Get Docker logs for a client's containers",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "container": {
                                "type": "string",
                                "description": "Container type (odoo or postgresql)",
                                "default": "odoo"
                            },
                            "lines": {
                                "type": "integer",
                                "description": "Number of log lines to return",
                                "default": 100
                            }
                        },
                        "required": ["client"]
                    }
                ),
                types.Tool(
                    name="execute_shell_command",
                    description="Execute a shell command in a client's container",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "command": {
                                "type": "string",
                                "description": "Shell command to execute"
                            },
                            "container": {
                                "type": "string",
                                "description": "Container type (odoo or postgresql)",
                                "default": "odoo"
                            }
                        },
                        "required": ["client", "command"]
                    }
                ),
                types.Tool(
                    name="get_github_config",
                    description="Get current GitHub configuration",
                    inputSchema={
                        "type": "object",
                        "properties": {},
                        "required": []
                    }
                ),
                types.Tool(
                    name="save_github_config",
                    description="Save GitHub configuration for repository management",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "token": {
                                "type": "string",
                                "description": "GitHub Personal Access Token"
                            },
                            "organization": {
                                "type": "string",
                                "description": "GitHub Organization name",
                                "default": "Alusage"
                            },
                            "gitUserName": {
                                "type": "string",
                                "description": "Git user name for commits"
                            },
                            "gitUserEmail": {
                                "type": "string",
                                "description": "Git user email for commits"
                            }
                        },
                        "required": ["token", "organization", "gitUserName", "gitUserEmail"]
                    }
                ),
                types.Tool(
                    name="test_github_connection",
                    description="Test GitHub connection with provided credentials",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "token": {
                                "type": "string",
                                "description": "GitHub Personal Access Token"
                            },
                            "organization": {
                                "type": "string",
                                "description": "GitHub Organization name",
                                "default": "Alusage"
                            }
                        },
                        "required": ["token", "organization"]
                    }
                ),
                types.Tool(
                    name="get_client_git_log",
                    description="Get Git commit history for a client repository",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "limit": {
                                "type": "integer",
                                "description": "Maximum number of commits to return",
                                "default": 20
                            },
                            "format": {
                                "type": "string",
                                "description": "Output format",
                                "enum": ["json", "text"],
                                "default": "json"
                            }
                        },
                        "required": ["client"]
                    }
                ),
                types.Tool(
                    name="get_commit_details",
                    description="Get detailed information about a specific commit including diff",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "commit": {
                                "type": "string",
                                "description": "Commit hash"
                            },
                            "format": {
                                "type": "string",
                                "description": "Output format",
                                "enum": ["json", "text"],
                                "default": "json"
                            }
                        },
                        "required": ["client", "commit"]
                    }
                )
            ]
        
        @self.server.call_tool()
        async def handle_call_tool(name: str, arguments: dict):
            """Handle tool calls"""
            
            if name == "create_client":
                return await self._create_client(
                    arguments.get("name"),
                    arguments.get("template", "basic"),
                    arguments.get("version", "18.0"),
                    arguments.get("has_enterprise", False)
                )
            elif name == "create_client_github":
                return await self._create_client_github(
                    arguments.get("name"),
                    arguments.get("template", "basic"),
                    arguments.get("version", "18.0"),
                    arguments.get("has_enterprise", False),
                    arguments.get("github_token"),
                    arguments.get("github_org", "Alusage"),
                    arguments.get("git_user_name"),
                    arguments.get("git_user_email")
                )
            elif name == "list_clients":
                return await self._list_clients()
            elif name == "update_client":
                return await self._update_client(arguments.get("client"))
            elif name == "add_module":
                return await self._add_module(
                    arguments.get("client"), 
                    arguments.get("module"),
                    arguments.get("link_all", False),
                    arguments.get("link_modules", "")
                )
            elif name == "link_modules":
                return await self._link_modules(
                    arguments.get("client"),
                    arguments.get("repository"),
                    arguments.get("link_all", False),
                    arguments.get("modules", "")
                )
            elif name == "list_modules":
                return await self._list_modules(arguments.get("client"))
            elif name == "list_oca_modules":
                return await self._list_oca_modules(arguments.get("pattern", ""))
            elif name == "client_status":
                return await self._client_status()
            elif name == "check_client":
                return await self._check_client(arguments.get("client"))
            elif name == "diagnose_client":
                return await self._diagnose_client(
                    arguments.get("client"),
                    arguments.get("format", "text"),
                    arguments.get("verbose", False)
                )
            elif name == "update_requirements":
                return await self._update_requirements(
                    arguments.get("client"),
                    arguments.get("clean", False)
                )
            elif name == "update_oca_repos":
                return await self._update_oca_repos(
                    arguments.get("language", "fr"),
                    arguments.get("fast", False)
                )
            elif name == "build_docker_image":
                return await self._build_docker_image(
                    arguments.get("version", "18.0"),
                    arguments.get("tag", "")
                )
            elif name == "backup_client":
                return await self._backup_client(arguments.get("client"))
            elif name == "delete_client":
                return await self._delete_client(
                    arguments.get("client"),
                    arguments.get("confirmed", False)
                )
            elif name == "start_client":
                return await self._start_client(arguments.get("client"))
            elif name == "stop_client":
                return await self._stop_client(arguments.get("client"))
            elif name == "rebuild_client":
                return await self._rebuild_client(
                    arguments.get("client"),
                    arguments.get("no_cache", False)
                )
            elif name == "get_client_status":
                return await self._get_client_status(arguments.get("client"))
            elif name == "get_client_logs":
                return await self._get_client_logs(
                    arguments.get("client"),
                    arguments.get("container", "odoo"),
                    arguments.get("lines", 100)
                )
            elif name == "execute_shell_command":
                return await self._execute_shell_command(
                    arguments.get("client"),
                    arguments.get("command"),
                    arguments.get("container", "odoo")
                )
            elif name == "get_github_config":
                return await self._get_github_config()
            elif name == "save_github_config":
                return await self._save_github_config(
                    arguments.get("token"),
                    arguments.get("organization"),
                    arguments.get("gitUserName"),
                    arguments.get("gitUserEmail")
                )
            elif name == "test_github_connection":
                return await self._test_github_connection(
                    arguments.get("token"),
                    arguments.get("organization")
                )
            elif name == "get_client_git_log":
                return await self._get_client_git_log(
                    arguments.get("client"),
                    arguments.get("limit", 20),
                    arguments.get("format", "json")
                )
            elif name == "get_commit_details":
                return await self._get_commit_details(
                    arguments.get("client"),
                    arguments.get("commit"),
                    arguments.get("format", "json")
                )
            else:
                raise ValueError(f"Unknown tool: {name}")
        
        logger.info("✅ MCP handlers configured")
    
    async def _handle_tool_call(self, name: str, arguments: dict):
        """Handle tool calls for HTTP API"""
        if name == "create_client":
            return await self._create_client(
                arguments.get("name"),
                arguments.get("template", "basic"),
                arguments.get("version", "18.0"),
                arguments.get("has_enterprise", False)
            )
        elif name == "create_client_github":
            return await self._create_client_github(
                arguments.get("name"),
                arguments.get("template", "basic"),
                arguments.get("version", "18.0"),
                arguments.get("has_enterprise", False),
                arguments.get("github_url", "")
            )
        elif name == "list_clients":
            return await self._list_clients()
        elif name == "update_client":
            return await self._update_client(arguments.get("client"))
        elif name == "add_module":
            return await self._add_module(
                arguments.get("client"), 
                arguments.get("module"),
                arguments.get("link_all", False),
                arguments.get("link_modules", "")
            )
        elif name == "link_modules":
            return await self._link_modules(
                arguments.get("client"),
                arguments.get("repository"),
                arguments.get("link_all", False),
                arguments.get("modules", "")
            )
        elif name == "list_modules":
            return await self._list_modules(arguments.get("client"))
        elif name == "list_oca_modules":
            return await self._list_oca_modules(arguments.get("pattern", ""))
        elif name == "client_status":
            return await self._client_status()
        elif name == "check_client":
            return await self._check_client(arguments.get("client"))
        elif name == "diagnose_client":
            return await self._diagnose_client(
                arguments.get("client"),
                arguments.get("format", "text"),
                arguments.get("verbose", False)
            )
        elif name == "update_requirements":
            return await self._update_requirements(
                arguments.get("client"),
                arguments.get("clean", False)
            )
        elif name == "update_oca_repos":
            return await self._update_oca_repos(
                arguments.get("language", "fr"),
                arguments.get("fast", False)
            )
        elif name == "build_docker_image":
            return await self._build_docker_image(
                arguments.get("version", "18.0"),
                arguments.get("tag", "")
            )
        elif name == "backup_client":
            return await self._backup_client(arguments.get("client"))
        elif name == "delete_client":
            return await self._delete_client(
                arguments.get("client"),
                arguments.get("confirmed", False)
            )
        elif name == "start_client":
            return await self._start_client(arguments.get("client"))
        elif name == "stop_client":
            return await self._stop_client(arguments.get("client"))
        elif name == "rebuild_client":
            return await self._rebuild_client(
                arguments.get("client"),
                arguments.get("no_cache", False)
            )
        elif name == "get_client_status":
            return await self._get_client_status(arguments.get("client"))
        elif name == "get_client_logs":
            return await self._get_client_logs(
                arguments.get("client"),
                arguments.get("container", "odoo"),
                arguments.get("lines", 100)
            )
        elif name == "execute_shell_command":
            return await self._execute_shell_command(
                arguments.get("client"),
                arguments.get("command"),
                arguments.get("container", "odoo")
            )
        elif name == "get_github_config":
            return await self._get_github_config()
        elif name == "save_github_config":
            return await self._save_github_config(
                arguments.get("token"),
                arguments.get("organization"),
                arguments.get("gitUserName"),
                arguments.get("gitUserEmail")
            )
        elif name == "test_github_connection":
            return await self._test_github_connection(
                arguments.get("token"),
                arguments.get("organization")
            )
        elif name == "get_client_git_log":
            return await self._get_client_git_log(
                arguments.get("client"),
                arguments.get("limit", 20),
                arguments.get("format", "json")
            )
        elif name == "get_commit_details":
            return await self._get_commit_details(
                arguments.get("client"),
                arguments.get("commit"),
                arguments.get("format", "json")
            )
        else:
            raise ValueError(f"Unknown tool: {name}")
    
    # Tool implementation methods
    
    async def _create_client(self, name: str, template: str = "basic", version: str = "18.0", has_enterprise: bool = False):
        """Create a new Odoo client repository"""
        script_path = self.repo_path / "scripts" / "generate_client_repo.sh"
        
        result = self._run_command([
            str(script_path),
            name,                              # client_name
            version,                           # odoo_version  
            template,                          # template
            "true" if has_enterprise else "false"  # has_enterprise
        ])
        
        if result["success"]:
            enterprise_msg = " (with Enterprise)" if has_enterprise else ""
            return [types.TextContent(
                type="text",
                text=f"✅ Client '{name}' created successfully with template '{template}' for Odoo {version}{enterprise_msg}\n\n{result['stdout']}"
            )]
        else:
            return [types.TextContent(
                type="text", 
                text=f"❌ Failed to create client '{name}'\n\nError: {result['stderr']}\n\nOutput: {result['stdout']}"
            )]
    
    async def _create_client_github(self, name: str, template: str = "basic", version: str = "18.0", has_enterprise: bool = False, github_url: str = ""):
        """Create a new Odoo client repository with GitHub integration"""
        # Check if GitHub is configured
        github_config_path = self.repo_path / "config" / "github_config.json"
        github_configured = False
        
        if github_config_path.exists():
            try:
                with open(github_config_path, 'r') as f:
                    config = json.load(f)
                    github_configured = bool(config.get('github_token') and config.get('github_organization'))
            except Exception:
                github_configured = False
        
        if github_configured:
            # Use the interactive create_client.sh script with GitHub integration
            script_path = self.repo_path / "create_client.sh"
            
            # Prepare the input for the interactive script
            inputs = [
                name,                                    # Client name
                "1" if version == "16.0" else "2" if version == "17.0" else "3",  # Version choice
                "1" if template == "basic" else "2" if template == "ecommerce" else "3" if template == "manufacturing" else "4" if template == "services" else "5",  # Template choice
                "y" if has_enterprise else "n",         # Enterprise
                "y",                                     # GitHub integration
                "y"                                      # Confirm
            ]
            
            # Create input string
            input_string = "\n".join(inputs) + "\n"
            
            try:
                # Run the interactive script with pre-configured inputs
                result = subprocess.run(
                    [str(script_path)],
                    cwd=self.repo_path,
                    input=input_string,
                    capture_output=True,
                    text=True,
                    timeout=600  # 10 minute timeout for GitHub operations
                )
                
                if result.returncode == 0:
                    enterprise_msg = " (with Enterprise)" if has_enterprise else ""
                    return [types.TextContent(
                        type="text",
                        text=f"✅ Client '{name}' created successfully with template '{template}' for Odoo {version}{enterprise_msg} with GitHub integration\n\n{result.stdout}"
                    )]
                else:
                    return [types.TextContent(
                        type="text", 
                        text=f"❌ Failed to create client '{name}' with GitHub integration\n\nError: {result.stderr}\n\nOutput: {result.stdout}"
                    )]
                    
            except subprocess.TimeoutExpired:
                return [types.TextContent(
                    type="text",
                    text=f"❌ Timeout creating client '{name}' with GitHub integration (operation took too long)"
                )]
            except Exception as e:
                return [types.TextContent(
                    type="text",
                    text=f"❌ Error creating client '{name}' with GitHub integration: {str(e)}"
                )]
        else:
            # GitHub not configured, fall back to normal client creation
            return await self._create_client(name, template, version, has_enterprise)
    
    async def _list_clients(self):
        """List all existing client repositories"""
        result = self._run_command(["make", "list-clients"])
        
        return [types.TextContent(
            type="text",
            text=result["stdout"] if result["success"] else f"Error: {result['stderr']}"
        )]
    
    async def _update_client(self, client: str):
        """Update submodules for a specific client"""
        result = self._run_command(["make", "update-client", f"CLIENT={client}"])
        
        if result["success"]:
            return [types.TextContent(
                type="text",
                text=f"✅ Client '{client}' updated successfully\n\n{result['stdout']}"
            )]
        else:
            return [types.TextContent(
                type="text",
                text=f"❌ Failed to update client '{client}'\n\nError: {result['stderr']}"
            )]
    
    async def _add_module(self, client: str, module: str, link_all: bool = False, link_modules: str = ""):
        """Add an OCA module to a client"""
        # Build command with linking options
        cmd = [str(self.repo_path / "scripts" / "add_oca_module.sh"), client, module]
        
        if link_all:
            cmd.append("--all")
        elif link_modules:
            cmd.extend(["--link", link_modules])
            
        result = self._run_command(cmd)
        
        if result["success"]:
            # Verify the module was properly cloned and has content
            module_path = self.repo_path / "clients" / client / "addons" / module
            if module_path.exists():
                # Check if the directory has content (more than just .git)
                try:
                    contents = list(module_path.iterdir())
                    non_git_contents = [f for f in contents if f.name != '.git']
                    
                    if len(non_git_contents) == 0:
                        return [types.TextContent(
                            type="text",
                            text=f"⚠️ Module '{module}' was added but appears to be empty\n\nThe repository may need to be reinitialized. Try updating the client submodules with:\n`update_client(client='{client}')`"
                        )]
                except Exception:
                    pass  # If we can't check, just continue with success message
                    
            return [types.TextContent(
                type="text",
                text=f"✅ Module '{module}' added to client '{client}'\n\n{result['stdout']}"
            )]
        else:
            # Check if the module already exists (can be in stdout or stderr)
            combined_output = result["stdout"] + " " + result["stderr"]
            if "Le submodule existe déjà" in combined_output or "submodule exists" in combined_output.lower():
                # Also check if the existing module is empty and offer to fix it
                module_path = self.repo_path / "clients" / client / "addons" / module
                if module_path.exists():
                    try:
                        contents = list(module_path.iterdir())
                        non_git_contents = [f for f in contents if f.name != '.git']
                        
                        if len(non_git_contents) == 0:
                            return [types.TextContent(
                                type="text",
                                text=f"⚠️ Module '{module}' exists but appears to be empty\n\nThe repository may be corrupted. To fix this, you can:\n1. Update submodules: `update_client(client='{client}')`\n2. Or manually remove and re-add the module"
                            )]
                    except Exception:
                        pass
                        
                return [types.TextContent(
                    type="text",
                    text=f"ℹ️ Module '{module}' is already present in client '{client}'\n\nThe module is already installed and available for use."
                )]
            else:
                return [types.TextContent(
                    type="text",
                    text=f"❌ Failed to add module '{module}' to client '{client}'\n\nError: {result['stderr']}\n\nOutput: {result['stdout']}"
                )]
    
    async def _link_modules(self, client: str, repository: str, link_all: bool = False, modules: str = ""):
        """Link existing repository modules to extra-addons for a client"""
        client_path = self.repo_path / "clients" / client
        repo_path = client_path / "addons" / repository
        extra_addons_path = client_path / "extra-addons"
        
        # Check if client and repository exist
        if not client_path.exists():
            return [types.TextContent(
                type="text",
                text=f"❌ Client '{client}' not found"
            )]
            
        if not repo_path.exists():
            return [types.TextContent(
                type="text",
                text=f"❌ Repository '{repository}' not found in client '{client}'\n\nAvailable repositories can be listed with `list_modules(client='{client}')`"
            )]
        
        # Create extra-addons directory if it doesn't exist
        if not extra_addons_path.exists():
            extra_addons_path.mkdir(exist_ok=True)
        
        # Get list of modules to link
        modules_to_link = []
        if link_all:
            # Find all directories with __manifest__.py files
            for item in repo_path.iterdir():
                if item.is_dir() and (item / "__manifest__.py").exists():
                    modules_to_link.append(item.name)
        elif modules:
            modules_to_link = [m.strip() for m in modules.split(",")]
        else:
            return [types.TextContent(
                type="text",
                text=f"❌ You must specify either link_all=True or provide a list of modules to link\n\nExample: link_modules(client='{client}', repository='{repository}', link_all=True)"
            )]
        
        if not modules_to_link:
            return [types.TextContent(
                type="text",
                text=f"❌ No valid modules found in repository '{repository}'"
            )]
        
        # Link modules
        linked_modules = []
        failed_modules = []
        
        for module in modules_to_link:
            module_source = repo_path / module
            module_link = extra_addons_path / module
            
            if not module_source.exists() or not (module_source / "__manifest__.py").exists():
                failed_modules.append(f"{module} (not found or invalid)")
                continue
            
            try:
                # Remove existing link if it exists
                if module_link.exists() or module_link.is_symlink():
                    module_link.unlink()
                
                # Create relative symlink
                relative_path = f"../addons/{repository}/{module}"
                module_link.symlink_to(relative_path)
                linked_modules.append(module)
            except Exception as e:
                failed_modules.append(f"{module} (error: {str(e)})")
        
        # Build result message
        result_parts = []
        if linked_modules:
            result_parts.append(f"✅ Successfully linked {len(linked_modules)} modules from '{repository}':")
            for module in linked_modules:
                result_parts.append(f"  - {module}")
        
        if failed_modules:
            result_parts.append(f"❌ Failed to link {len(failed_modules)} modules:")
            for module in failed_modules:
                result_parts.append(f"  - {module}")
        
        return [types.TextContent(
            type="text",
            text="\n".join(result_parts)
        )]
    
    async def _list_modules(self, client: str):
        """List available modules for a specific client"""
        result = self._run_command(["make", "list-modules", f"CLIENT={client}"])
        
        return [types.TextContent(
            type="text",
            text=result["stdout"] if result["success"] else f"Error: {result['stderr']}"
        )]
    
    async def _list_oca_modules(self, pattern: str = ""):
        """List all available OCA modules with optional filtering"""
        cmd = ["make", "list-oca-modules"]
        if pattern:
            cmd.append(f"PATTERN={pattern}")
        
        result = self._run_command(cmd)
        
        return [types.TextContent(
            type="text",
            text=result["stdout"] if result["success"] else f"Error: {result['stderr']}"
        )]
    
    async def _client_status(self):
        """Show status of all clients"""
        result = self._run_command(["make", "status"])
        
        return [types.TextContent(
            type="text",
            text=result["stdout"] if result["success"] else f"Error: {result['stderr']}"
        )]
    
    async def _check_client(self, client: str):
        """Run diagnostics on a specific client"""
        result = self._run_command(["make", "check-client", f"CLIENT={client}"])
        
        return [types.TextContent(
            type="text",
            text=result["stdout"] if result["success"] else f"Error: {result['stderr']}"
        )]
    
    async def _update_requirements(self, client: str, clean: bool = False):
        """Update Python requirements for a client"""
        cmd = ["make", "update-requirements", f"CLIENT={client}"]
        if clean:
            cmd.append("CLEAN=true")
        
        result = self._run_command(cmd)
        
        if result["success"]:
            return [types.TextContent(
                type="text",
                text=f"✅ Requirements updated for client '{client}'\n\n{result['stdout']}"
            )]
        else:
            return [types.TextContent(
                type="text",
                text=f"❌ Failed to update requirements for client '{client}'\n\nError: {result['stderr']}"
            )]
    
    async def _update_oca_repos(self, language: str = "fr", fast: bool = False):
        """Update OCA repository list from GitHub"""
        if fast:
            cmd = ["make", "update-oca-repos-fast"]
        elif language == "en":
            cmd = ["make", "update-oca-repos-en"]
        else:
            cmd = ["make", "update-oca-repos"]
        
        result = self._run_command(cmd)
        
        if result["success"]:
            return [types.TextContent(
                type="text",
                text=f"✅ OCA repositories updated (language: {language})\n\n{result['stdout']}"
            )]
        else:
            return [types.TextContent(
                type="text",
                text=f"❌ Failed to update OCA repositories\n\nError: {result['stderr']}"
            )]
    
    async def _build_docker_image(self, version: str = "18.0", tag: str = ""):
        """Build custom Odoo Docker image"""
        cmd = ["make", "build"]
        if version:
            cmd.append(f"VERSION={version}")
        if tag:
            cmd.append(f"TAG={tag}")
        
        result = self._run_command(cmd)
        
        if result["success"]:
            return [types.TextContent(
                type="text",
                text=f"✅ Docker image built successfully\n\n{result['stdout']}"
            )]
        else:
            return [types.TextContent(
                type="text",
                text=f"❌ Failed to build Docker image\n\nError: {result['stderr']}"
            )]
    
    async def _backup_client(self, client: str):
        """Create a backup of a client"""
        result = self._run_command(["make", "backup-client", f"CLIENT={client}"])
        
        if result["success"]:
            return [types.TextContent(
                type="text",
                text=f"✅ Client '{client}' backed up successfully\n\n{result['stdout']}"
            )]
        else:
            return [types.TextContent(
                type="text",
                text=f"❌ Failed to backup client '{client}'\n\nError: {result['stderr']}"
            )]
    
    async def _delete_client(self, client: str, confirmed: bool = False):
        """Delete a client repository with confirmation"""
        
        # Vérifier que le client existe d'abord
        client_dir = self.repo_path / "clients" / client
        if not client_dir.exists():
            return [types.TextContent(
                type="text",
                text=f"❌ Client '{client}' not found.\n\nAvailable clients:\n" + 
                     "\n".join([f"  - {c.name}" for c in (self.repo_path / "clients").iterdir() if c.is_dir()])
            )]
        
        # Si pas confirmé, demander la confirmation avec les détails
        if not confirmed:
            # Affichons les infos de base sans essayer de lire les contenus qui pourraient bloquer
            module_count = "Unknown"
            try:
                if (client_dir / "extra-addons").exists():
                    # Utiliser un timeout pour éviter les blocages
                    import subprocess
                    result = subprocess.run(
                        ["find", str(client_dir / "extra-addons"), "-maxdepth", "1", "-type", "l"], 
                        capture_output=True, text=True, timeout=2
                    )
                    if result.returncode == 0:
                        module_count = len(result.stdout.strip().split('\n')) - 1 if result.stdout.strip() else 0
            except Exception:
                module_count = "Unknown (permission issues)"
            
            return [types.TextContent(
                type="text",
                text=f"⚠️ CONFIRMATION REQUIRED: Delete client '{client}'\n\n" +
                     f"📁 Client path: {client_dir}\n" +
                     f"📦 Linked modules: {module_count}\n" +
                     f"💾 All data, configurations, and Git history will be lost!\n\n" +
                     f"❗ This action cannot be undone!\n\n" +
                     f"To proceed with deletion, please confirm by calling this tool again with confirmed=true.\n\n" +
                     f"Example: delete_client(client='{client}', confirmed=True)"
            )]
        
        # Si confirmé, procéder à la suppression - utiliser directement le script bash
        # pour éviter les blocages Python avec les permissions
        result = self._run_command(["make", "delete-client", f"CLIENT={client}", "FORCE=true"])
        
        if result["success"]:
            return [types.TextContent(
                type="text",
                text=f"✅ Client '{client}' deleted successfully\n\n{result['stdout']}"
            )]
        else:
            # Analyser l'erreur pour donner des instructions spécifiques
            error_msg = result.get('stderr', '')
            
            if "Permission denied" in error_msg:
                return [types.TextContent(
                    type="text",
                    text=f"❌ Failed to delete client '{client}' due to permission issues\n\n" +
                             f"🔧 The client directory contains files owned by root (probably created by Docker).\n\n" +
                             f"📋 To fix this, run these commands in your terminal:\n\n" +
                             f"```bash\n" +
                             f"# Fix permissions first\n" +
                             f"sudo chown -R $(whoami):$(whoami) {client_dir}\n" +
                             f"sudo chmod -R u+w {client_dir}\n\n" +
                             f"# Then delete the client\n" +
                             f"rm -rf {client_dir}\n" +
                             f"```\n\n" +
                             f"💡 Or run this single command:\n" +
                             f"```bash\n" +
                             f"sudo rm -rf {client_dir}\n" +
                             f"```\n\n" +
                             f"After running these commands manually, the client will be deleted."
                )]
            else:
                return [types.TextContent(
                    type="text",
                    text=f"❌ Failed to delete client '{client}'\n\n" +
                         f"Error: {error_msg}\n\n" +
                         f"💡 Try manually: sudo rm -rf {client_dir}"
                )]

    async def _diagnose_client(self, client: str, format: str = "text", verbose: bool = False):
        """Run comprehensive diagnostics on a client"""
        if not client:
            return [types.TextContent(
                type="text",
                text="❌ Client name is required"
            )]
        
        # Build command arguments
        cmd = [str(self.repo_path / "scripts" / "diagnose_client.sh"), client]
        
        if format == "json":
            cmd.extend(["--format", "json"])
        
        if verbose:
            cmd.append("--verbose")
        
        result = self._run_command(cmd)
        
        if result['success']:
            if format == "json":
                # For JSON output, parse and format nicely
                import json
                try:
                    json_data = json.loads(result['stdout'])
                    formatted_json = json.dumps(json_data, indent=2, ensure_ascii=False)
                    return [types.TextContent(
                        type="text",
                        text=f"🔍 Diagnostic Results for Client '{client}':\n\n```json\n{formatted_json}\n```"
                    )]
                except json.JSONDecodeError:
                    # Fallback to raw output if JSON parsing fails
                    return [types.TextContent(
                        type="text",
                        text=f"🔍 Diagnostic Results for Client '{client}':\n\n{result['stdout']}"
                    )]
            else:
                # Text format
                return [types.TextContent(
                    type="text",
                    text=f"🔍 Diagnostic Results for Client '{client}':\n\n{result['stdout']}"
                )]
        else:
            error_msg = result.get('stderr', 'Unknown error occurred')
            return_code = result.get('return_code', -1)
            
            # Interpret return codes
            status_messages = {
                0: "✅ All systems operational",
                1: "⚠️ Some warnings detected",
                2: "❌ Significant errors found", 
                3: "🚨 Critical issues detected"
            }
            
            status_text = status_messages.get(return_code, f"❌ Unknown status (code: {return_code})")
            
            return [types.TextContent(
                type="text",
                text=f"🔍 Diagnostic completed with status: {status_text}\n\n" +
                     f"Client: {client}\n" +
                     f"Format: {format}\n" +
                     f"Verbose: {verbose}\n\n" +
                     f"Output:\n{result.get('stdout', 'No output')}\n\n" +
                     f"Issues:\n{error_msg}\n\n" +
                     f"💡 For more details, run the diagnostic with --verbose flag or check the client manually:\n" +
                     f"```bash\n" +
                     f"cd clients/{client}\n" +
                     f"docker compose ps\n" +
                     f"docker compose logs\n" +
                     f"```"
            )]

    def _setup_http_app(self):
        """Setup FastAPI HTTP server"""
        if not FastAPI:
            return
            
        self.http_app = FastAPI(
            title="Odoo Client MCP Server",
            description="HTTP API for Odoo Client Repository Generator",
            version="1.0.0"
        )
        
        # Add CORS middleware
        self.http_app.add_middleware(
            CORSMiddleware,
            allow_origins=["*"],  # Configure appropriately for production
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )
        
        @self.http_app.get("/")
        async def root():
            return {"message": "Odoo Client MCP Server", "version": "1.0.0", "status": "running"}
        
        @self.http_app.get("/tools")
        async def list_tools():
            """List available tools"""
            # Retourner la liste des outils disponibles
            tools = self._get_tools_list()
            return [{"name": tool.name, "description": tool.description, "inputSchema": tool.inputSchema} for tool in tools]
        
        @self.http_app.post("/tools/call")
        async def call_tool(request: ToolCallRequest):
            """Call a tool with given arguments"""
            try:
                # Call the MCP tool handler directly
                result = await self._handle_tool_call(request.name, request.arguments)
                
                # Convert MCP response to HTTP response
                return ToolCallResponse(
                    success=True,
                    result=self._mcp_to_http_response(result)
                )
                
            except Exception as e:
                logger.error(f"Error calling tool {request.name}: {e}")
                return ToolCallResponse(
                    success=False,
                    result=None,
                    error=str(e)
                )
        
        @self.http_app.get("/clients")
        async def get_clients():
            """Get list of clients"""
            try:
                result = await self._list_clients()
                clients_text = result[0].text if result else ""
                
                # Parse the make output to extract client names
                clients = []
                for line in clients_text.split('\n'):
                    line = line.strip()
                    if line and not line.startswith('make') and not line.startswith('==') and line != "Clients disponibles:":
                        if line.startswith('- '):
                            clients.append(line[2:])
                        elif line and not line.startswith('aucun') and not line.startswith('Aucun'):
                            clients.append(line)
                
                return {"clients": clients}
                
            except Exception as e:
                logger.error(f"Error listing clients: {e}")
                raise HTTPException(status_code=500, detail=str(e))
        
        @self.http_app.get("/clients/{client_name}/status")
        async def get_client_status(client_name: str):
            """Get status of a specific client"""
            try:
                result = await self._check_client(client_name)
                status_text = result[0].text if result else ""
                
                # Parse status and determine health
                status = "unknown"
                if "✅" in status_text or "healthy" in status_text.lower():
                    status = "healthy"
                elif "⚠️" in status_text or "warning" in status_text.lower():
                    status = "warning"
                elif "❌" in status_text or "error" in status_text.lower():
                    status = "error"
                
                return {
                    "client": client_name,
                    "status": status,
                    "details": status_text
                }
                
            except Exception as e:
                logger.error(f"Error checking client {client_name}: {e}")
                raise HTTPException(status_code=500, detail=str(e))
        
        @self.http_app.get("/status")
        async def get_all_status():
            """Get status of all clients"""
            try:
                result = await self._client_status()
                return {"status": result[0].text if result else "No status available"}
                
            except Exception as e:
                logger.error(f"Error getting status: {e}")
                raise HTTPException(status_code=500, detail=str(e))
        
        @self.http_app.websocket("/terminal/{client_name}")
        async def websocket_terminal(websocket: WebSocket, client_name: str):
            """WebSocket terminal connection to client container"""
            await websocket.accept()
            
            try:
                # Check if client exists
                client_dir = self.repo_path / "clients" / client_name
                if not client_dir.exists():
                    await websocket.send_text(f"❌ Client '{client_name}' not found\r\n")
                    await websocket.close()
                    return
                
                # Container name
                container_name = f"odoo-{client_name}"
                
                # Start docker exec process with pseudo-terminal
                cmd = [
                    "docker", "exec", "-it", container_name, 
                    "/bin/bash", "-l"
                ]
                
                # Create subprocess with pty for proper terminal behavior
                master, slave = pty.openpty()
                
                # Start the docker exec process
                process = await asyncio.create_subprocess_exec(
                    *cmd,
                    stdin=slave,
                    stdout=slave,
                    stderr=slave,
                    preexec_fn=os.setsid
                )
                
                # Close slave end (parent doesn't need it)
                os.close(slave)
                
                # Make master non-blocking
                fcntl.fcntl(master, fcntl.F_SETFL, os.O_NONBLOCK)
                
                async def read_output():
                    """Read output from docker exec and send to websocket"""
                    try:
                        while True:
                            # Check if process is still running
                            if process.returncode is not None:
                                break
                                
                            # Use select to check if data is available
                            ready, _, _ = select.select([master], [], [], 0.1)
                            if ready:
                                try:
                                    data = os.read(master, 1024)
                                    if data:
                                        await websocket.send_text(data.decode('utf-8', errors='ignore'))
                                except OSError:
                                    break
                            await asyncio.sleep(0.01)
                    except WebSocketDisconnect:
                        pass
                    except Exception as e:
                        logger.error(f"Error reading terminal output: {e}")
                
                # Start reading output task
                read_task = asyncio.create_task(read_output())
                
                # Handle incoming messages from websocket
                try:
                    async for message in websocket.iter_text():
                        try:
                            # Handle special terminal sequences
                            if message.startswith('\x1b['):  # ANSI escape sequences
                                os.write(master, message.encode('utf-8'))
                            else:
                                # Regular input
                                os.write(master, message.encode('utf-8'))
                        except OSError:
                            break
                except WebSocketDisconnect:
                    pass
                
                # Cleanup
                read_task.cancel()
                try:
                    process.terminate()
                    await process.wait()
                except:
                    pass
                os.close(master)
                
            except Exception as e:
                logger.error(f"Terminal websocket error: {e}")
                try:
                    await websocket.send_text(f"❌ Terminal error: {str(e)}\r\n")
                except:
                    pass


    async def _start_client(self, client: str):
        """Start a client's Docker containers"""
        if not client:
            return [types.TextContent(
                type="text",
                text="❌ Client name is required"
            )]
        
        # Vérifier que le client existe
        client_dir = self.repo_path / "clients" / client
        if not client_dir.exists():
            return [types.TextContent(
                type="text",
                text=f"❌ Client '{client}' not found.\n\nAvailable clients:\n" + 
                     "\n".join([f"  - {c.name}" for c in (self.repo_path / "clients").iterdir() if c.is_dir()])
            )]
        
        # Utiliser le script start.sh du client s'il existe, sinon docker compose up
        start_script = client_dir / "scripts" / "start.sh"
        if start_script.exists():
            cmd = ["bash", str(start_script)]
            result = self._run_command(cmd, cwd=client_dir)
        else:
            # Fallback vers docker compose up directement
            cmd = ["docker", "compose", "up", "-d"]
            result = self._run_command(cmd, cwd=client_dir)
        
        if result['success']:
            return [types.TextContent(
                type="text",
                text=f"✅ Client '{client}' started successfully\n\n{result['stdout']}"
            )]
        else:
            return [types.TextContent(
                type="text",
                text=f"❌ Failed to start client '{client}'\n\nError: {result['stderr']}\n\nOutput: {result['stdout']}"
            )]

    async def _stop_client(self, client: str):
        """Stop a client's Docker containers"""
        if not client:
            return [types.TextContent(
                type="text",
                text="❌ Client name is required"
            )]
        
        # Vérifier que le client existe
        client_dir = self.repo_path / "clients" / client
        if not client_dir.exists():
            return [types.TextContent(
                type="text",
                text=f"❌ Client '{client}' not found.\n\nAvailable clients:\n" + 
                     "\n".join([f"  - {c.name}" for c in (self.repo_path / "clients").iterdir() if c.is_dir()])
            )]
        
        # Arrêter avec docker compose down
        cmd = ["docker", "compose", "down"]
        result = self._run_command(cmd, cwd=client_dir)
        
        if result['success']:
            return [types.TextContent(
                type="text",
                text=f"✅ Client '{client}' stopped successfully\n\n{result['stdout']}"
            )]
        else:
            return [types.TextContent(
                type="text",
                text=f"❌ Failed to stop client '{client}'\n\nError: {result['stderr']}\n\nOutput: {result['stdout']}"
            )]

    async def _rebuild_client(self, client: str, no_cache: bool = False):
        """Rebuild a client's Docker image with updated requirements"""
        if not client:
            return [types.TextContent(
                type="text",
                text="❌ Client name is required"
            )]
        
        # Vérifier que le client existe
        client_dir = self.repo_path / "clients" / client
        if not client_dir.exists():
            return [types.TextContent(
                type="text",
                text=f"❌ Client '{client}' not found.\n\nAvailable clients:\n" + 
                     "\n".join([f"  - {c.name}" for c in (self.repo_path / "clients").iterdir() if c.is_dir()])
            )]
        
        # Vérifier si le client est en cours d'exécution
        status_result = await self._get_client_status(client)
        was_running = False
        if status_result and status_result[0].text:
            try:
                import json
                status_data = json.loads(status_result[0].text)
                was_running = status_data.get("status") == "running"
            except:
                pass
        
        build_log = []
        
        # Arrêter le client s'il est en cours d'exécution
        if was_running:
            build_log.append("🛑 Stopping client before rebuild...")
            stop_result = await self._stop_client(client)
            if stop_result and "successfully" in stop_result[0].text:
                build_log.append("✅ Client stopped")
            else:
                build_log.append("⚠️ Stop failed but continuing...")
        
        # Mettre à jour les requirements d'abord
        build_log.append("📦 Updating requirements...")
        logger.info(f"🔄 Updating requirements for client '{client}'...")
        requirements_cmd = ["make", "update-requirements", f"CLIENT={client}"]
        req_result = self._run_command(requirements_cmd, cwd=self.repo_path)
        
        if not req_result['success']:
            logger.warning(f"⚠️ Requirements update failed for '{client}': {req_result['stderr']}")
            build_log.append("⚠️ Requirements update had warnings")
        else:
            build_log.append("✅ Requirements updated")
        
        # Rebuild l'image Docker
        build_log.append("🐳 Rebuilding Docker image...")
        build_script = client_dir / "docker" / "build.sh"
        if build_script.exists():
            cmd = ["bash", str(build_script)]
            if no_cache:
                cmd.append("--no-cache")
            result = self._run_command(cmd, cwd=client_dir / "docker")
        else:
            # Fallback vers docker compose build directement
            cmd = ["docker", "compose", "build"]
            if no_cache:
                cmd.append("--no-cache")
            result = self._run_command(cmd, cwd=client_dir)
        
        if result['success']:
            build_log.append("✅ Docker image rebuilt")
        else:
            build_log.append("❌ Docker image rebuild failed")
        
        # Redémarrer le client s'il était en cours d'exécution
        if was_running and result['success']:
            build_log.append("🚀 Restarting client...")
            start_result = await self._start_client(client)
            if start_result and "successfully" in start_result[0].text:
                build_log.append("✅ Client restarted")
            else:
                build_log.append("⚠️ Failed to restart client")
        
        if result['success']:
            return [types.TextContent(
                type="text",
                text=f"✅ Client '{client}' rebuilt successfully\n\n" +
                     "\n".join(build_log) + "\n\n" +
                     f"Build output:\n{result['stdout']}"
            )]
        else:
            return [types.TextContent(
                type="text",
                text=f"❌ Failed to rebuild client '{client}'\n\n" +
                     "\n".join(build_log) + "\n\n" +
                     f"Error: {result['stderr']}\n\nOutput: {result['stdout']}"
            )]

    async def _get_client_status(self, client: str):
        """Get the running status of a client's Docker containers"""
        if not client:
            return [types.TextContent(
                type="text",
                text="❌ Client name is required"
            )]
        
        # Vérifier que le client existe
        client_dir = self.repo_path / "clients" / client
        if not client_dir.exists():
            return [types.TextContent(
                type="text",
                text=f"❌ Client '{client}' not found"
            )]
        
        # Vérifier l'état des conteneurs
        result = self._run_command([
            "docker", "compose", "ps", "--format", "json"
        ], cwd=client_dir)
        
        if result['success']:
            try:
                import json
                containers = []
                # Parse each line as JSON (docker compose ps output)
                for line in result['stdout'].strip().split('\n'):
                    if line.strip():
                        container_info = json.loads(line)
                        containers.append({
                            "name": container_info.get("Name", ""),
                            "status": container_info.get("State", ""),
                            "health": container_info.get("Health", "")
                        })
                
                # Déterminer l'état global
                running_count = sum(1 for c in containers if c["status"] == "running")
                total_count = len(containers)
                
                if running_count == total_count and total_count > 0:
                    status = "running"
                elif running_count > 0:
                    status = "partial"
                else:
                    status = "stopped"
                
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "status": status,
                        "containers": containers,
                        "running": running_count,
                        "total": total_count
                    })
                )]
            except Exception as e:
                return [types.TextContent(
                    type="text",
                    text=f'{{ "status": "error", "error": "{str(e)}" }}'
                )]
        else:
            return [types.TextContent(
                type="text",
                text='{ "status": "stopped", "containers": [], "running": 0, "total": 0 }'
            )]

    async def _get_client_logs(self, client: str, container: str = "odoo", lines: int = 100):
        """Get Docker logs for a client's containers"""
        if not client:
            return [types.TextContent(
                type="text",
                text="❌ Client name is required"
            )]
        
        # Vérifier que le client existe
        client_dir = self.repo_path / "clients" / client
        if not client_dir.exists():
            return [types.TextContent(
                type="text",
                text=f"❌ Client '{client}' not found"
            )]
        
        # Nom du conteneur basé sur le pattern
        container_name = f"{container}-{client}"
        
        # Récupérer les logs
        result = self._run_command([
            "docker", "logs", "--tail", str(lines), container_name
        ], cwd=client_dir)
        
        if result['success']:
            logs = result['stdout'] + result['stderr']  # Docker logs peuvent être sur stderr
            return [types.TextContent(
                type="text",
                text=logs or "No logs available"
            )]
        else:
            return [types.TextContent(
                type="text",
                text=f"❌ Failed to get logs for {container_name}: {result['stderr']}"
            )]

    async def _execute_shell_command(self, client: str, command: str, container: str = "odoo"):
        """Execute a shell command in a client's container"""
        if not client or not command:
            return [types.TextContent(
                type="text",
                text="❌ Client name and command are required"
            )]
        
        # Vérifier que le client existe
        client_dir = self.repo_path / "clients" / client
        if not client_dir.exists():
            return [types.TextContent(
                type="text",
                text=f"❌ Client '{client}' not found"
            )]
        
        # Nom du conteneur
        container_name = f"{container}-{client}"
        
        # Exécuter la commande
        result = self._run_command([
            "docker", "exec", container_name, "bash", "-c", command
        ], cwd=client_dir)
        
        if result['success']:
            return [types.TextContent(
                type="text",
                text=result['stdout'] or "(no output)"
            )]
        else:
            return [types.TextContent(
                type="text",
                text=f"❌ Command failed: {result['stderr']}"
            )]

    async def _get_github_config(self):
        """Get current GitHub configuration"""
        try:
            logger.info("Getting GitHub config...")
            config_file = self.repo_path / "config" / "github_config.json"
            logger.info(f"Config file path: {config_file}")
            
            if config_file.exists():
                logger.info("Config file exists, reading...")
                with open(config_file, 'r') as f:
                    config = json.load(f)
                    logger.info("Config loaded successfully")
                    # Remove sensitive token from response for security
                    safe_config = config.copy()
                    if 'github_token' in safe_config and safe_config['github_token']:
                        safe_config['github_token'] = '***configured***'
                    
                    return [types.TextContent(
                        type="text",
                        text=json.dumps(safe_config, indent=2)
                    )]
            else:
                logger.info("Config file does not exist, returning default")
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "github_token": "",
                        "github_organization": "Alusage",
                        "git_user_name": "",
                        "git_user_email": ""
                    }, indent=2)
                )]
        except Exception as e:
            logger.error(f"Error in _get_github_config: {e}")
            return [types.TextContent(
                type="text",
                text=f"❌ Error reading GitHub config: {str(e)}"
            )]

    async def _save_github_config(self, token: str, organization: str, git_user_name: str, git_user_email: str):
        """Save GitHub configuration"""
        try:
            config_file = self.repo_path / "config" / "github_config.json"
            
            # Create config directory if it doesn't exist
            config_file.parent.mkdir(exist_ok=True)
            
            config = {
                "github_token": token,
                "github_organization": organization,
                "github_base_url": "https://api.github.com",
                "git_user_name": git_user_name,
                "git_user_email": git_user_email
            }
            
            with open(config_file, 'w') as f:
                json.dump(config, f, indent=2)
            
            return [types.TextContent(
                type="text",
                text="✅ GitHub configuration saved successfully"
            )]
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=f"❌ Error saving GitHub config: {str(e)}"
            )]

    async def _test_github_connection(self, token: str, organization: str):
        """Test GitHub connection with provided credentials"""
        try:
            import requests
            
            # Test user authentication
            headers = {
                'Authorization': f'token {token}',
                'Accept': 'application/vnd.github.v3+json'
            }
            
            response = requests.get('https://api.github.com/user', headers=headers, timeout=10)
            
            if response.status_code == 200:
                user_data = response.json()
                username = user_data.get('login', 'unknown')
                
                # Test organization access
                org_response = requests.get(f'https://api.github.com/orgs/{organization}', headers=headers, timeout=10)
                
                if org_response.status_code == 200:
                    return [types.TextContent(
                        type="text",
                        text=json.dumps({
                            "success": True,
                            "username": username,
                            "organization": organization,
                            "message": f"✅ Connected as {username} with access to {organization}"
                        }, indent=2)
                    )]
                elif org_response.status_code == 404:
                    return [types.TextContent(
                        type="text",
                        text=json.dumps({
                            "success": False,
                            "username": username,
                            "error": f"Organization '{organization}' not found or no access"
                        }, indent=2)
                    )]
                else:
                    return [types.TextContent(
                        type="text",
                        text=json.dumps({
                            "success": False,
                            "username": username,
                            "error": f"Cannot access organization '{organization}' (HTTP {org_response.status_code})"
                        }, indent=2)
                    )]
            elif response.status_code == 401:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "success": False,
                        "error": "Invalid token or insufficient permissions"
                    }, indent=2)
                )]
            else:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "success": False,
                        "error": f"GitHub API error (HTTP {response.status_code})"
                    }, indent=2)
                )]
                
        except requests.RequestException as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": False,
                    "error": f"Network error: {str(e)}"
                }, indent=2)
            )]
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": False,
                    "error": f"Unexpected error: {str(e)}"
                }, indent=2)
            )]

    async def _get_client_git_log(self, client_name: str, limit: int = 20, format: str = "json"):
        """Get Git commit history for a client repository"""
        if not client_name:
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": "Client name is required"}, indent=2)
            )]
        
        client_path = self.repo_path / "clients" / client_name
        if not client_path.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": f"Client '{client_name}' not found"}, indent=2)
            )]
        
        try:
            # Get git log with detailed information
            git_log_cmd = [
                "git", "log", f"--max-count={limit}",
                "--pretty=format:%H|%an|%ae|%ad|%s",
                "--date=iso"
            ]
            
            result = self._run_command(git_log_cmd, cwd=client_path)
            
            if not result["success"]:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "error": f"Failed to get git log for client '{client_name}'",
                        "details": result["stderr"]
                    }, indent=2)
                )]
            
            if format == "text":
                return [types.TextContent(
                    type="text",
                    text=result["stdout"]
                )]
            
            # Parse commits into JSON format
            commits = []
            if result["stdout"].strip():
                for line in result["stdout"].strip().split('\n'):
                    try:
                        parts = line.split('|')
                        if len(parts) >= 5:
                            commit_hash = parts[0]
                            author_name = parts[1]
                            author_email = parts[2]
                            date = parts[3]
                            message = '|'.join(parts[4:])  # Handle message with | characters
                            
                            commits.append({
                                "id": commit_hash[:8],  # Short hash
                                "hash": commit_hash,
                                "author": {
                                    "name": author_name,
                                    "email": author_email,
                                    "avatar": f"https://ui-avatars.com/api/?name={author_name.replace(' ', '+')}&background=7D6CA8&color=fff"
                                },
                                "message": message,
                                "timestamp": date,
                                "branch": "current"  # We could enhance this later
                            })
                    except Exception as e:
                        logger.warning(f"Failed to parse commit line: {line}, error: {e}")
                        continue
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "client": client_name,
                    "commits": commits,
                    "total": len(commits)
                }, indent=2)
            )]
            
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "error": f"Error getting git log for client '{client_name}': {str(e)}"
                }, indent=2)
            )]

    async def _get_commit_details(self, client_name: str, commit_hash: str, format: str = "json"):
        """Get detailed information about a specific commit including diff"""
        if not client_name:
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": "Client name is required"}, indent=2)
            )]
        
        if not commit_hash:
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": "Commit hash is required"}, indent=2)
            )]
        
        client_path = self.repo_path / "clients" / client_name
        if not client_path.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": f"Client '{client_name}' not found"}, indent=2)
            )]
        
        try:
            # Get commit details with diff
            cmd = [
                "git", "show", "--format=fuller", "--stat", "--patch", commit_hash
            ]
            
            result = self._run_command(cmd, cwd=client_path)
            
            if result["return_code"] != 0:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "error": f"Git command failed: {result['stderr']}"
                    }, indent=2)
                )]
            
            # Parse the git show output
            output = result["stdout"]
            
            # Extract commit info (first part before diff)
            lines = output.split('\n')
            diff_started = False
            commit_info = []
            diff_lines = []
            
            for line in lines:
                if line.startswith('diff --git'):
                    diff_started = True
                
                if not diff_started:
                    commit_info.append(line)
                else:
                    diff_lines.append(line)
            
            # Parse commit info
            commit_data = '\n'.join(commit_info)
            
            # Parse diff into structured format
            files = []
            current_file = None
            current_hunk = None
            in_file_content = False
            
            for line in diff_lines:
                if line.startswith('diff --git'):
                    # New file
                    if current_file:
                        if current_hunk:
                            current_file["hunks"].append(current_hunk)
                        files.append(current_file)
                    
                    # Extract filename from diff --git a/file b/file
                    filename = line.split(' b/')[-1] if ' b/' in line else line.split(' ')[-1]
                    current_file = {
                        "filename": filename,
                        "additions": 0,
                        "deletions": 0,
                        "hunks": []
                    }
                    current_hunk = None
                    in_file_content = False
                
                elif line.startswith('@@'):
                    # Hunk header
                    if current_hunk:
                        current_file["hunks"].append(current_hunk)
                    
                    current_hunk = {
                        "header": line,
                        "lines": []
                    }
                    in_file_content = True
                
                elif line.startswith('index ') or line.startswith('new file mode') or line.startswith('deleted file mode') or line.startswith('--- ') or line.startswith('+++ '):
                    # File metadata - skip
                    continue
                
                elif in_file_content or current_hunk is not None:
                    # Hunk content or new file content
                    line_type = 'context'
                    if line.startswith('+'):
                        line_type = 'added'
                        current_file["additions"] += 1
                    elif line.startswith('-'):
                        line_type = 'removed'
                        current_file["deletions"] += 1
                    elif line.startswith(' '):
                        line_type = 'context'
                    
                    # Create hunk if we don't have one (for new files)
                    if current_hunk is None:
                        current_hunk = {
                            "header": "@@ -0,0 +1,{} @@".format(current_file["additions"]),
                            "lines": []
                        }
                    
                    current_hunk["lines"].append({
                        "type": line_type,
                        "content": line[1:] if line.startswith(('+', '-', ' ')) else line,
                        "lineNumber": len(current_hunk["lines"]) + 1
                    })
            
            # Add the last file
            if current_file:
                if current_hunk:
                    current_file["hunks"].append(current_hunk)
                files.append(current_file)
            
            # Calculate stats
            total_additions = sum(f["additions"] for f in files)
            total_deletions = sum(f["deletions"] for f in files)
            
            details = {
                "diff": True,
                "stats": {
                    "files": len(files),
                    "insertions": total_additions,
                    "deletions": total_deletions
                },
                "files": files,
                "raw_output": output if format == "text" else None
            }
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "client": client_name,
                    "commit": commit_hash,
                    "details": details
                }, indent=2)
            )]
            
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "error": f"Error getting commit details for '{commit_hash}': {str(e)}"
                }, indent=2)
            )]

    def _get_tools_list(self):
        """Get the list of available tools"""
        return [
            types.Tool(
                name="create_client",
                description="Create a new Odoo client repository",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "name": {
                            "type": "string",
                            "description": "Client name (will be used as directory name)"
                        },
                        "template": {
                            "type": "string",
                            "description": "Template type",
                            "enum": ["basic", "ecommerce", "manufacturing", "services", "custom"],
                            "default": "basic"
                        },
                        "version": {
                            "type": "string",
                            "description": "Odoo version",
                            "enum": ["16.0", "17.0", "18.0"],
                            "default": "18.0"
                        },
                        "has_enterprise": {
                            "type": "boolean",
                            "description": "Include Odoo Enterprise modules and repositories",
                            "default": False
                        }
                    },
                    "required": ["name"]
                }
            ),
            types.Tool(
                name="create_client_github",
                description="Create a new Odoo client repository with GitHub integration",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "name": {
                            "type": "string",
                            "description": "Client name (will be used as directory and repository name)"
                        },
                        "template": {
                            "type": "string",
                            "description": "Template type",
                            "enum": ["basic", "ecommerce", "manufacturing", "services", "custom"],
                            "default": "basic"
                        },
                        "version": {
                            "type": "string",
                            "description": "Odoo version",
                            "enum": ["16.0", "17.0", "18.0"],
                            "default": "18.0"
                        },
                        "has_enterprise": {
                            "type": "boolean",
                            "description": "Include Odoo Enterprise modules and repositories",
                            "default": False
                        }
                    },
                    "required": ["name"]
                }
            ),
            types.Tool(
                name="list_clients",
                description="List all existing client repositories",
                inputSchema={
                    "type": "object",
                    "properties": {},
                    "required": []
                }
            ),
            types.Tool(
                name="get_github_config",
                description="Get current GitHub configuration",
                inputSchema={
                    "type": "object",
                    "properties": {},
                    "required": []
                }
            ),
            types.Tool(
                name="save_github_config",
                description="Save GitHub configuration for repository management",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "token": {
                            "type": "string",
                            "description": "GitHub Personal Access Token"
                        },
                        "organization": {
                            "type": "string",
                            "description": "GitHub Organization name",
                            "default": "Alusage"
                        },
                        "gitUserName": {
                            "type": "string",
                            "description": "Git user name for commits"
                        },
                        "gitUserEmail": {
                            "type": "string",
                            "description": "Git user email for commits"
                        }
                    },
                    "required": ["token", "organization", "gitUserName", "gitUserEmail"]
                }
            ),
            types.Tool(
                name="test_github_connection",
                description="Test GitHub connection with provided credentials",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "token": {
                            "type": "string",
                            "description": "GitHub Personal Access Token"
                        },
                        "organization": {
                            "type": "string",
                            "description": "GitHub Organization name",
                            "default": "Alusage"
                        }
                    },
                    "required": ["token", "organization"]
                }
            )
        ]

    def _mcp_to_http_response(self, mcp_result):
        """Convert MCP response to HTTP-friendly format"""
        if isinstance(mcp_result, list):
            # Multiple TextContent objects
            return {
                "type": "text",
                "content": "\n".join([item.text for item in mcp_result if hasattr(item, 'text')])
            }
        elif hasattr(mcp_result, 'text'):
            # Single TextContent object
            return {
                "type": "text", 
                "content": mcp_result.text
            }
        else:
            # Raw data
            return mcp_result


async def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Dual-mode MCP Server for Odoo Client Generator")
    parser.add_argument("repo_path", nargs="?", default=os.getcwd(), 
                       help="Path to the Odoo client generator repository")
    parser.add_argument("--mode", choices=["stdio", "http", "both"], default="stdio",
                       help="Server mode: stdio (for Claude), http (for web dashboard), or both")
    parser.add_argument("--host", default="0.0.0.0", help="HTTP server host")
    parser.add_argument("--port", type=int, default=8000, help="HTTP server port")
    
    args = parser.parse_args()
    
    logger.info(f"🚀 Starting MCP server for {args.repo_path} in {args.mode} mode")
    
    try:
        server = OdooClientMCPServer(args.repo_path)
        
        if args.mode == "stdio":
            logger.info("🔌 Starting MCP server with stdio...")
            # Run the MCP server using stdio
            async with stdio_server() as (read_stream, write_stream):
                await server.server.run(
                    read_stream,
                    write_stream,
                    server.server.create_initialization_options()
                )
        
        elif args.mode == "http":
            if not FastAPI:
                logger.error("❌ FastAPI not available. Install with: pip install fastapi uvicorn")
                sys.exit(1)
            
            logger.info(f"🌐 Starting HTTP server on {args.host}:{args.port}...")
            config = uvicorn.Config(
                app=server.http_app,
                host=args.host,
                port=args.port,
                log_level="info"
            )
            http_server = uvicorn.Server(config)
            await http_server.serve()
        
        elif args.mode == "both":
            if not FastAPI:
                logger.error("❌ FastAPI not available for HTTP mode. Install with: pip install fastapi uvicorn")
                sys.exit(1)
            
            logger.info(f"🔌🌐 Starting both stdio and HTTP server on {args.host}:{args.port}...")
            
            # Start HTTP server in background
            config = uvicorn.Config(
                app=server.http_app,
                host=args.host,
                port=args.port,
                log_level="info"
            )
            http_server = uvicorn.Server(config)
            
            # Run both concurrently
            async def run_stdio():
                async with stdio_server() as (read_stream, write_stream):
                    await server.server.run(
                        read_stream,
                        write_stream,
                        server.server.create_initialization_options()
                    )
            
            # Run both servers concurrently
            await asyncio.gather(
                http_server.serve(),
                run_stdio()
            )
            
    except Exception as e:
        logger.error(f"❌ Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("👋 Shutting down...")
    except Exception as e:
        logger.error(f"❌ Fatal error: {e}")
        sys.exit(1)
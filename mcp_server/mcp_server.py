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
import re
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
    
    def _save_linked_modules(self, client_dir: Path, branch: str) -> int:
        """Save the current linked modules configuration for a branch"""
        import json
        import os
        
        project_config_path = client_dir / "project_config.json"
        extra_addons_dir = client_dir / "extra-addons"
        
        # Read or create project configuration
        if project_config_path.exists():
            with open(project_config_path, 'r') as f:
                config = json.load(f)
        else:
            config = {
                "version": "1.0",
                "project_name": client_dir.name,
                "odoo_version": "18.0",
                "linked_modules": {},
                "branch_configs": {},
                "settings": {
                    "auto_restore_modules": True,
                    "backup_before_switch": True
                },
                "metadata": {
                    "created": "",
                    "last_updated": "",
                    "updated_by": "mcp_server"
                }
            }
        
        # Scan extra-addons directory for symbolic links
        linked_modules = {}
        modules_count = 0
        
        if extra_addons_dir.exists():
            for item in extra_addons_dir.iterdir():
                if item.is_symlink():
                    try:
                        # Get the target path and extract repository name and module name
                        target = item.resolve()
                        addons_dir = client_dir / "addons"
                        
                        # Find which repository this module belongs to
                        if addons_dir.exists():
                            for repo_dir in addons_dir.iterdir():
                                if repo_dir.is_dir() and target.is_relative_to(repo_dir):
                                    repo_name = repo_dir.name
                                    module_name = target.name
                                    
                                    if repo_name not in linked_modules:
                                        linked_modules[repo_name] = []
                                    
                                    if module_name not in linked_modules[repo_name]:
                                        linked_modules[repo_name].append(module_name)
                                        modules_count += 1
                                    break
                    except (OSError, FileNotFoundError) as e:
                        # Skip broken symlinks or missing targets
                        print(f"Warning: Skipping broken symlink {item}: {e}")
                        continue
        
        # Check if configuration has actually changed
        old_branch_config = config.get("branch_configs", {}).get(branch, {}).get("linked_modules", {})
        old_global_config = config.get("linked_modules", {})
        
        config_changed = (old_branch_config != linked_modules or old_global_config != linked_modules)
        
        # Only update if there are actual changes
        if config_changed:
            # Save to branch configuration
            if branch not in config["branch_configs"]:
                config["branch_configs"][branch] = {}
            
            config["branch_configs"][branch]["linked_modules"] = linked_modules
            
            # Update global linked_modules for current state
            config["linked_modules"] = linked_modules
            
            # Update metadata only when content changes
            from datetime import datetime
            now = datetime.utcnow().isoformat() + "Z"
            if not config["metadata"]["created"]:
                config["metadata"]["created"] = now
            config["metadata"]["last_updated"] = now
            
            # Write back to file
            with open(project_config_path, 'w') as f:
                json.dump(config, f, indent=2)
        
        return modules_count
    
    def _restore_linked_modules(self, client_dir: Path, branch: str) -> int:
        """Restore linked modules configuration for a branch"""
        import json
        import os
        
        project_config_path = client_dir / "project_config.json"
        extra_addons_dir = client_dir / "extra-addons"
        
        # Ensure extra-addons directory exists
        extra_addons_dir.mkdir(exist_ok=True)
        
        # Read project configuration
        if not project_config_path.exists():
            return 0
        
        with open(project_config_path, 'r') as f:
            config = json.load(f)
        
        # Get linked modules for this branch
        branch_config = config.get("branch_configs", {}).get(branch, {})
        linked_modules = branch_config.get("linked_modules", {})
        
        modules_count = 0
        addons_dir = client_dir / "addons"
        
        # Create symbolic links for each module
        for repo_name, modules in linked_modules.items():
            repo_dir = addons_dir / repo_name
            if not repo_dir.exists():
                continue
                
            for module_name in modules:
                module_path = repo_dir / module_name
                if module_path.exists() and module_path.is_dir():
                    link_path = extra_addons_dir / module_name
                    
                    # Create symbolic link if it doesn't exist
                    if not link_path.exists():
                        try:
                            link_path.symlink_to(module_path)
                            modules_count += 1
                        except OSError as e:
                            # Link creation failed, continue with others
                            pass
        
        # Check if global linked_modules state has changed
        old_global_config = config.get("linked_modules", {})
        config_changed = (old_global_config != linked_modules)
        
        # Only update if there are actual changes
        if config_changed:
            # Update global linked_modules state
            config["linked_modules"] = linked_modules
            
            # Update metadata only when content changes
            from datetime import datetime
            config["metadata"]["last_updated"] = datetime.utcnow().isoformat() + "Z"
            
            # Write back to file
            with open(project_config_path, 'w') as f:
                json.dump(config, f, indent=2)
        
        return modules_count
    
    def _update_project_config_add_module(self, client_dir: Path, repository: str, module: str) -> bool:
        """Add a module to the project configuration for the current branch"""
        import json
        import os
        
        try:
            project_config_path = client_dir / "project_config.json"
            
            # Get current branch
            current_branch_result = self._run_command(["git", "branch", "--show-current"], cwd=client_dir)
            current_branch = current_branch_result["stdout"].strip() if current_branch_result["success"] else "unknown"
            
            # Read or create project configuration
            if project_config_path.exists():
                with open(project_config_path, 'r') as f:
                    config = json.load(f)
            else:
                config = {
                    "version": "1.0",
                    "project_name": client_dir.name,
                    "odoo_version": "18.0",
                    "linked_modules": {},
                    "branch_configs": {},
                    "settings": {
                        "auto_restore_modules": True,
                        "backup_before_switch": True
                    },
                    "metadata": {
                        "created": "",
                        "last_updated": "",
                        "updated_by": "mcp_server"
                    }
                }
            
            # Initialize branch config if needed
            if current_branch not in config["branch_configs"]:
                config["branch_configs"][current_branch] = {"linked_modules": {}}
            
            branch_config = config["branch_configs"][current_branch]
            if "linked_modules" not in branch_config:
                branch_config["linked_modules"] = {}
            
            # Add module to repository
            if repository not in branch_config["linked_modules"]:
                branch_config["linked_modules"][repository] = []
            
            # Check if module is already linked
            module_already_linked = module in branch_config["linked_modules"][repository]
            
            if not module_already_linked:
                branch_config["linked_modules"][repository].append(module)
            
            # Check if global config would change
            old_global_config = config.get("linked_modules", {})
            config_changed = (old_global_config != branch_config["linked_modules"]) or not module_already_linked
            
            # Only update if there are actual changes
            if config_changed:
                # Update global linked_modules for current state
                config["linked_modules"] = branch_config["linked_modules"]
                
                # Update metadata only when content changes
                from datetime import datetime
                now = datetime.utcnow().isoformat() + "Z"
                if not config["metadata"]["created"]:
                    config["metadata"]["created"] = now
                config["metadata"]["last_updated"] = now
                
                # Write back to file
                with open(project_config_path, 'w') as f:
                    json.dump(config, f, indent=2)
            
            return True
            
        except Exception as e:
            print(f"Error updating project config: {e}")
            return False
    
    def _update_project_config_remove_module(self, client_dir: Path, repository: str, module: str) -> bool:
        """Remove a module from the project configuration for the current branch"""
        import json
        import os
        
        try:
            project_config_path = client_dir / "project_config.json"
            
            # Return True if no config file (nothing to remove)
            if not project_config_path.exists():
                return True
            
            # Get current branch
            current_branch_result = self._run_command(["git", "branch", "--show-current"], cwd=client_dir)
            current_branch = current_branch_result["stdout"].strip() if current_branch_result["success"] else "unknown"
            
            # Read project configuration
            with open(project_config_path, 'r') as f:
                config = json.load(f)
            
            # Check if branch config exists
            if current_branch not in config["branch_configs"]:
                return True  # Nothing to remove
            
            branch_config = config["branch_configs"][current_branch]
            if "linked_modules" not in branch_config:
                return True  # Nothing to remove
            
            # Check if module exists and would be removed
            module_removed = False
            old_global_config = config.get("linked_modules", {}).copy()
            
            # Remove module from repository
            if repository in branch_config["linked_modules"]:
                if module in branch_config["linked_modules"][repository]:
                    branch_config["linked_modules"][repository].remove(module)
                    module_removed = True
                    
                    # Remove repository entry if empty
                    if not branch_config["linked_modules"][repository]:
                        del branch_config["linked_modules"][repository]
            
            # Check if global config would change
            config_changed = (old_global_config != branch_config["linked_modules"]) or module_removed
            
            # Only update if there are actual changes
            if config_changed:
                # Update global linked_modules for current state
                config["linked_modules"] = branch_config["linked_modules"]
                
                # Update metadata only when content changes
                from datetime import datetime
                config["metadata"]["last_updated"] = datetime.utcnow().isoformat() + "Z"
                
                # Write back to file
                with open(project_config_path, 'w') as f:
                    json.dump(config, f, indent=2)
            
            return True
            
        except Exception as e:
            print(f"Error updating project config: {e}")
            return False
    
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
                    name="list_submodules",
                    description="List Git submodules (addon repositories) for a client",
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
                    name="list_linked_modules",
                    description="List modules currently linked in extra-addons for a client",
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
                    name="get_build_history",
                    description="Get Docker build history and image versions for a client",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "limit": {
                                "type": "integer",
                                "description": "Maximum number of builds to return",
                                "default": 20
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
                    name="get_git_config",
                    description="Get current Git configuration for commits",
                    inputSchema={
                        "type": "object",
                        "properties": {},
                        "required": []
                    }
                ),
                types.Tool(
                    name="save_git_config",
                    description="Save Git configuration for commits when creating clients",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "user_name": {
                                "type": "string",
                                "description": "Git user name for commits"
                            },
                            "user_email": {
                                "type": "string",
                                "description": "Git user email for commits"
                            }
                        },
                        "required": ["user_name", "user_email"]
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
                ),
                types.Tool(
                    name="get_client_branches",
                    description="Get Git branches for a client repository",
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
                    name="create_client_branch",
                    description="Create a new Git branch for a client",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "branch": {
                                "type": "string",
                                "description": "Branch name (e.g., 'staging-v2', 'dev-feature')"
                            },
                            "source": {
                                "type": "string",
                                "description": "Source branch to create from",
                                "default": "18.0"
                            }
                        },
                        "required": ["client", "branch"]
                    }
                ),
                types.Tool(
                    name="switch_client_branch",
                    description="Switch to a different Git branch for a client",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "branch": {
                                "type": "string",
                                "description": "Branch name to switch to"
                            }
                        },
                        "required": ["client", "branch"]
                    }
                ),
                types.Tool(
                    name="start_client_branch",
                    description="Start Docker containers for a specific client branch",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "branch": {
                                "type": "string",
                                "description": "Branch name to start"
                            }
                        },
                        "required": ["client", "branch"]
                    }
                ),
                types.Tool(
                    name="stop_client_branch",
                    description="Stop Docker containers for a specific client branch",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "branch": {
                                "type": "string",
                                "description": "Branch name to stop"
                            }
                        },
                        "required": ["client", "branch"]
                    }
                ),
                types.Tool(
                    name="restart_client_branch",
                    description="Restart Docker containers for a specific client branch",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "branch": {
                                "type": "string",
                                "description": "Branch name to restart"
                            }
                        },
                        "required": ["client", "branch"]
                    }
                ),
                types.Tool(
                    name="get_branch_logs",
                    description="Get Docker logs for a specific client branch deployment",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "branch": {
                                "type": "string",
                                "description": "Branch name"
                            },
                            "lines": {
                                "type": "integer",
                                "description": "Number of log lines to return",
                                "default": 100
                            }
                        },
                        "required": ["client", "branch"]
                    }
                ),
                types.Tool(
                    name="open_branch_shell",
                    description="Open an interactive shell in a client branch container",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "branch": {
                                "type": "string",
                                "description": "Branch name"
                            }
                        },
                        "required": ["client", "branch"]
                    }
                ),
                types.Tool(
                    name="get_branch_status",
                    description="Get deployment status for a specific client branch",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "branch": {
                                "type": "string",
                                "description": "Branch name"
                            }
                        },
                        "required": ["client", "branch"]
                    }
                ),
                types.Tool(
                    name="list_deployments",
                    description="List all active branch deployments across all clients",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Optional: filter by specific client name"
                            }
                        }
                    }
                ),
                types.Tool(
                    name="commit_client_changes",
                    description="Commit current changes in client repository (modules linked/unlinked)",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "message": {
                                "type": "string",
                                "description": "Commit message",
                                "default": "Update module links"
                            }
                        },
                        "required": ["client"]
                    }
                ),
                types.Tool(
                    name="switch_client_branch",
                    description="Switch client repository to a specific Git branch",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "branch": {
                                "type": "string",
                                "description": "Git branch name to switch to"
                            },
                            "create": {
                                "type": "boolean",
                                "description": "Create the branch if it doesn't exist",
                                "default": False
                            }
                        },
                        "required": ["client", "branch"]
                    }
                ),
                types.Tool(
                    name="get_client_git_status",
                    description="Get Git status of client repository including sync status with remote",
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
                    name="update_client_submodules",
                    description="Update Git submodules for a client repository",
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
                    name="check_submodules_status",
                    description="Check status of submodules and detect outdated ones",
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
                    name="update_submodule",
                    description="Update a specific submodule to latest version",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "submodule_path": {
                                "type": "string",
                                "description": "Path to the submodule (e.g., 'addons/partner-contact')"
                            }
                        },
                        "required": ["client", "submodule_path"]
                    }
                ),
                types.Tool(
                    name="update_all_submodules",
                    description="Update all outdated submodules to their latest versions",
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
                    name="add_oca_module_to_client",
                    description="Add an OCA module repository to a client",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "module_key": {
                                "type": "string",
                                "description": "OCA module key (e.g., 'partner-contact', 'account-analytic')"
                            },
                            "branch": {
                                "type": "string",
                                "description": "Git branch to use (optional, defaults to client's Odoo version)"
                            }
                        },
                        "required": ["client", "module_key"]
                    }
                ),
                types.Tool(
                    name="add_external_repo_to_client",
                    description="Add an external Git repository to a client",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "repo_url": {
                                "type": "string",
                                "description": "Git repository URL"
                            },
                            "repo_name": {
                                "type": "string",
                                "description": "Name for the repository (will be used as directory name)"
                            },
                            "branch": {
                                "type": "string",
                                "description": "Git branch to use (optional, defaults to main/master)"
                            }
                        },
                        "required": ["client", "repo_url", "repo_name"]
                    }
                ),
                types.Tool(
                    name="change_submodule_branch",
                    description="Change the branch of an existing submodule",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "submodule_path": {
                                "type": "string",
                                "description": "Path to the submodule (e.g., 'addons/partner-contact')"
                            },
                            "new_branch": {
                                "type": "string",
                                "description": "New branch to switch to"
                            }
                        },
                        "required": ["client", "submodule_path", "new_branch"]
                    }
                ),
                types.Tool(
                    name="remove_submodule",
                    description="Remove a submodule from a client",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "submodule_path": {
                                "type": "string",
                                "description": "Path to the submodule (e.g., 'addons/partner-contact')"
                            }
                        },
                        "required": ["client", "submodule_path"]
                    }
                ),
                types.Tool(
                    name="list_available_oca_modules",
                    description="List all available OCA modules",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "search": {
                                "type": "string",
                                "description": "Search term to filter modules (optional)"
                            }
                        }
                    }
                ),
                types.Tool(
                    name="toggle_dev_mode",
                    description="Toggle development mode for a repository (switch between submodule and git clone)",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "repository": {
                                "type": "string",
                                "description": "Name of the repository"
                            },
                            "branch": {
                                "type": "string",
                                "description": "Target branch (optional, will auto-detect if not provided)"
                            }
                        },
                        "required": ["client", "repository"]
                    }
                ),
                types.Tool(
                    name="get_dev_status",
                    description="Get development status of repositories for a client",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "branch": {
                                "type": "string",
                                "description": "Target branch (optional, will auto-detect if not provided)"
                            }
                        },
                        "required": ["client"]
                    }
                ),
                types.Tool(
                    name="sync_dev_links",
                    description="Synchronize symbolic links for development/production modes",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "branch": {
                                "type": "string",
                                "description": "Target branch (optional, will auto-detect if not provided)"
                            }
                        },
                        "required": ["client"]
                    }
                ),
                types.Tool(
                    name="rename_dev_branch",
                    description="Rename a development branch in a repository",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "repository": {
                                "type": "string",
                                "description": "Repository name (e.g. 'project', 'account-analytic')"
                            },
                            "new_branch_name": {
                                "type": "string",
                                "description": "New name for the development branch"
                            },
                            "current_branch": {
                                "type": "string",
                                "description": "Current branch context (optional, will auto-detect if not provided)"
                            }
                        },
                        "required": ["client", "repository", "new_branch_name"]
                    }
                ),
                types.Tool(
                    name="get_client_diff",
                    description="Get diff of uncommitted changes in client repository",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "branch": {
                                "type": "string",
                                "description": "Branch name (optional)"
                            }
                        },
                        "required": ["client"]
                    }
                ),
                types.Tool(
                    name="check_branch_docker_status",
                    description="Check Docker image status for a client branch",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "branch": {
                                "type": "string",
                                "description": "Branch name (optional)"
                            }
                        },
                        "required": ["client"]
                    }
                ),
                types.Tool(
                    name="link_module_with_config",
                    description="Link a module and update project configuration",
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
                            "module": {
                                "type": "string",
                                "description": "Module name to link"
                            }
                        },
                        "required": ["client", "repository", "module"]
                    }
                ),
                types.Tool(
                    name="unlink_module_with_config",
                    description="Unlink a module and update project configuration",
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
                            "module": {
                                "type": "string",
                                "description": "Module name to unlink"
                            }
                        },
                        "required": ["client", "repository", "module"]
                    }
                ),
                types.Tool(
                    name="rename_client_branch",
                    description="Rename a Git branch for a client",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "old_branch": {
                                "type": "string",
                                "description": "Current branch name to rename"
                            },
                            "new_branch": {
                                "type": "string",
                                "description": "New branch name"
                            }
                        },
                        "required": ["client", "old_branch", "new_branch"]
                    }
                ),
                types.Tool(
                    name="build_client_branch_docker",
                    description="Build Docker image for a specific client branch",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "branch": {
                                "type": "string",
                                "description": "Name of the branch to build"
                            },
                            "force": {
                                "type": "boolean",
                                "description": "Force rebuild even if image exists",
                                "default": False
                            },
                            "no_cache": {
                                "type": "boolean",
                                "description": "Build without using Docker cache",
                                "default": False
                            }
                        },
                        "required": ["client", "branch"]
                    }
                ),
                types.Tool(
                    name="start_client_branch",
                    description="Start Docker service for a specific client branch",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "branch": {
                                "type": "string",
                                "description": "Name of the branch to start"
                            },
                            "build": {
                                "type": "boolean",
                                "description": "Build image before starting",
                                "default": False
                            }
                        },
                        "required": ["client", "branch"]
                    }
                ),
                types.Tool(
                    name="stop_client_branch",
                    description="Stop Docker service for a specific client branch",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "branch": {
                                "type": "string",
                                "description": "Name of the branch to stop"
                            },
                            "clean_volumes": {
                                "type": "boolean",
                                "description": "Remove volumes for this branch",
                                "default": False
                            },
                            "stop_postgres": {
                                "type": "boolean",
                                "description": "Stop PostgreSQL (affects all branches)",
                                "default": False
                            }
                        },
                        "required": ["client", "branch"]
                    }
                ),
                types.Tool(
                    name="get_client_branch_status",
                    description="Get status of Docker services for a client branch",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "branch": {
                                "type": "string",
                                "description": "Name of the branch"
                            }
                        },
                        "required": ["client", "branch"]
                    }
                ),
                types.Tool(
                    name="restart_client_branch",
                    description="Restart Docker service for a specific client branch",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "client": {
                                "type": "string",
                                "description": "Name of the client"
                            },
                            "branch": {
                                "type": "string",
                                "description": "Name of the branch to restart"
                            }
                        },
                        "required": ["client", "branch"]
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
            elif name == "list_submodules":
                return await self._list_submodules(arguments.get("client"))
            elif name == "list_linked_modules":
                return await self._list_linked_modules(arguments.get("client"))
            elif name == "commit_client_changes":
                return await self._commit_client_changes(
                    arguments.get("client"),
                    arguments.get("message", "Update module links")
                )
            elif name == "switch_client_branch":
                return await self._switch_client_branch(
                    arguments.get("client"),
                    arguments.get("branch"),
                    arguments.get("create", False)
                )
            elif name == "get_client_git_status":
                return await self._get_client_git_status(arguments.get("client"))
            elif name == "update_client_submodules":
                return await self._update_client_submodules(arguments.get("client"))
            elif name == "check_submodules_status":
                return await self._check_submodules_status(arguments.get("client"))
            elif name == "update_submodule":
                return await self._update_submodule(arguments.get("client"), arguments.get("submodule_path"))
            elif name == "update_all_submodules":
                return await self._update_all_submodules(arguments.get("client"))
            elif name == "add_oca_module_to_client":
                return await self._add_oca_module_to_client(
                    arguments.get("client"),
                    arguments.get("module_key"),
                    arguments.get("branch")
                )
            elif name == "add_external_repo_to_client":
                return await self._add_external_repo_to_client(
                    arguments.get("client"),
                    arguments.get("repo_url"),
                    arguments.get("repo_name"),
                    arguments.get("branch")
                )
            elif name == "change_submodule_branch":
                return await self._change_submodule_branch(
                    arguments.get("client"),
                    arguments.get("submodule_path"),
                    arguments.get("new_branch")
                )
            elif name == "remove_submodule":
                return await self._remove_submodule(
                    arguments.get("client"),
                    arguments.get("submodule_path")
                )
            elif name == "list_available_oca_modules":
                return await self._list_available_oca_modules(arguments.get("search"))
            elif name == "toggle_dev_mode":
                return await self._toggle_dev_mode(
                    arguments.get("client"),
                    arguments.get("repository"),
                    arguments.get("branch")
                )
            elif name == "get_dev_status":
                return await self._get_dev_status(
                    arguments.get("client"),
                    arguments.get("branch")
                )
            elif name == "sync_dev_links":
                return await self._sync_dev_links(
                    arguments.get("client"),
                    arguments.get("branch")
                )
            elif name == "get_client_diff":
                return await self._get_client_diff(
                    arguments.get("client"),
                    arguments.get("branch")
                )
            elif name == "check_branch_docker_status":
                return await self._check_branch_docker_status(
                    arguments.get("client"),
                    arguments.get("branch")
                )
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
            elif name == "get_git_config":
                return await self._get_git_config()
            elif name == "save_git_config":
                return await self._save_git_config(
                    arguments.get("user_name"),
                    arguments.get("user_email")
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
            elif name == "get_client_branches":
                return await self._get_client_branches(
                    arguments.get("client")
                )
            elif name == "create_client_branch":
                return await self._create_client_branch(
                    arguments.get("client"),
                    arguments.get("branch"),
                    arguments.get("source", "18.0")
                )
            elif name == "switch_client_branch":
                return await self._switch_client_branch(
                    arguments.get("client"),
                    arguments.get("branch")
                )
            elif name == "start_client_branch":
                return await self._start_client_branch(
                    arguments.get("client"),
                    arguments.get("branch")
                )
            elif name == "stop_client_branch":
                return await self._stop_client_branch(
                    arguments.get("client"),
                    arguments.get("branch")
                )
            elif name == "restart_client_branch":
                return await self._restart_client_branch(
                    arguments.get("client"),
                    arguments.get("branch")
                )
            elif name == "get_branch_logs":
                return await self._get_branch_logs(
                    arguments.get("client"),
                    arguments.get("branch"),
                    arguments.get("lines", 100)
                )
            elif name == "open_branch_shell":
                return await self._open_branch_shell(
                    arguments.get("client"),
                    arguments.get("branch")
                )
            elif name == "get_branch_status":
                return await self._get_branch_status(
                    arguments.get("client"),
                    arguments.get("branch")
                )
            elif name == "list_deployments":
                return await self._list_deployments(
                    arguments.get("client")
                )
            elif name == "get_traefik_config":
                return await self._get_traefik_config()
            elif name == "set_traefik_config":
                return await self._set_traefik_config(
                    arguments.get("domain"),
                    arguments.get("protocol", "http")
                )
            elif name == "build_cloudron_app":
                return await self._build_cloudron_app(
                    arguments.get("client"),
                    arguments.get("force", False)
                )
            elif name == "deploy_cloudron_app":
                return await self._deploy_cloudron_app(
                    arguments.get("client"),
                    arguments.get("action", "install")
                )
            elif name == "get_cloudron_config":
                return await self._get_cloudron_config(arguments.get("client"))
            elif name == "update_cloudron_config":
                return await self._update_cloudron_config(
                    arguments.get("client"),
                    arguments.get("config", {})
                )
            elif name == "get_cloudron_status":
                return await self._get_cloudron_status(arguments.get("client"))
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
        elif name == "list_submodules":
            return await self._list_submodules(arguments.get("client"))
        elif name == "list_linked_modules":
            return await self._list_linked_modules(arguments.get("client"))
        elif name == "commit_client_changes":
            return await self._commit_client_changes(
                arguments.get("client"),
                arguments.get("message", "Update module links")
            )
        elif name == "switch_client_branch":
            return await self._switch_client_branch(
                arguments.get("client"),
                arguments.get("branch"),
                arguments.get("create", False)
            )
        elif name == "switch_client_branch_with_progress":
            return await self._switch_client_branch_with_progress(
                arguments.get("client"),
                arguments.get("branch"),
                arguments.get("create", False)
            )
        elif name == "get_client_git_status":
            return await self._get_client_git_status(arguments.get("client"))
        elif name == "update_client_submodules":
            return await self._update_client_submodules(arguments.get("client"))
        elif name == "check_submodules_status":
            return await self._check_submodules_status(arguments.get("client"))
        elif name == "update_submodule":
            return await self._update_submodule(arguments.get("client"), arguments.get("submodule_path"))
        elif name == "update_all_submodules":
            return await self._update_all_submodules(arguments.get("client"))
        elif name == "add_oca_module_to_client":
            return await self._add_oca_module_to_client(
                arguments.get("client"),
                arguments.get("module_key"),
                arguments.get("branch")
            )
        elif name == "add_external_repo_to_client":
            return await self._add_external_repo_to_client(
                arguments.get("client"),
                arguments.get("repo_url"),
                arguments.get("repo_name"),
                arguments.get("branch")
            )
        elif name == "change_submodule_branch":
            return await self._change_submodule_branch(
                arguments.get("client"),
                arguments.get("submodule_path"),
                arguments.get("new_branch")
            )
        elif name == "remove_submodule":
            return await self._remove_submodule(
                arguments.get("client"),
                arguments.get("submodule_path")
            )
        elif name == "list_available_oca_modules":
            return await self._list_available_oca_modules(arguments.get("search"))
        elif name == "toggle_dev_mode":
            return await self._toggle_dev_mode(
                arguments.get("client"),
                arguments.get("repository"),
                arguments.get("branch")
            )
        elif name == "get_dev_status":
            return await self._get_dev_status(
                arguments.get("client"),
                arguments.get("branch")
            )
        elif name == "sync_dev_links":
            return await self._sync_dev_links(
                arguments.get("client"),
                arguments.get("branch")
            )
        elif name == "rename_dev_branch":
            return await self._rename_dev_branch(
                arguments.get("client"),
                arguments.get("repository"),
                arguments.get("new_branch_name"),
                arguments.get("current_branch")
            )
        elif name == "get_client_diff":
            return await self._get_client_diff(
                arguments.get("client"),
                arguments.get("branch")
            )
        elif name == "check_branch_docker_status":
            return await self._check_branch_docker_status(
                arguments.get("client"),
                arguments.get("branch")
            )
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
        elif name == "get_git_config":
            return await self._get_git_config()
        elif name == "save_git_config":
            return await self._save_git_config(
                arguments.get("user_name"),
                arguments.get("user_email")
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
        elif name == "get_client_branches":
            return await self._get_client_branches(
                arguments.get("client")
            )
        elif name == "create_client_branch":
            return await self._create_client_branch(
                arguments.get("client"),
                arguments.get("branch"),
                arguments.get("source", "18.0")
            )
        elif name == "switch_client_branch":
            return await self._switch_client_branch(
                arguments.get("client"),
                arguments.get("branch")
            )
        elif name == "start_client_branch":
            return await self._start_client_branch(
                arguments.get("client"),
                arguments.get("branch")
            )
        elif name == "stop_client_branch":
            return await self._stop_client_branch(
                arguments.get("client"),
                arguments.get("branch")
            )
        elif name == "restart_client_branch":
            return await self._restart_client_branch(
                arguments.get("client"),
                arguments.get("branch")
            )
        elif name == "get_branch_logs":
            return await self._get_branch_logs(
                arguments.get("client"),
                arguments.get("branch"),
                arguments.get("lines", 100)
            )
        elif name == "open_branch_shell":
            return await self._open_branch_shell(
                arguments.get("client"),
                arguments.get("branch")
            )
        elif name == "get_branch_status":
            return await self._get_branch_status(
                arguments.get("client"),
                arguments.get("branch")
            )
        elif name == "list_deployments":
            return await self._list_deployments(
                arguments.get("client")
            )
        elif name == "get_traefik_config":
            return await self._get_traefik_config()
        elif name == "set_traefik_config":
            return await self._set_traefik_config(
                arguments.get("domain"),
                arguments.get("protocol", "http")
            )
        elif name == "link_module_with_config":
            return await self._link_module_with_config(
                arguments.get("client"),
                arguments.get("repository"),
                arguments.get("module")
            )
        elif name == "unlink_module_with_config":
            return await self._unlink_module_with_config(
                arguments.get("client"),
                arguments.get("repository"),
                arguments.get("module")
            )
        elif name == "rename_client_branch":
            return await self._rename_client_branch(
                arguments.get("client"),
                arguments.get("old_branch"),
                arguments.get("new_branch")
            )
        elif name == "build_client_branch_docker":
            return await self._build_client_branch_docker(
                arguments.get("client"),
                arguments.get("branch"),
                arguments.get("force", False),
                arguments.get("no_cache", False)
            )
        elif name == "start_client_branch":
            return await self._start_client_branch(
                arguments.get("client"),
                arguments.get("branch"),
                arguments.get("build", False)
            )
        elif name == "stop_client_branch":
            return await self._stop_client_branch(
                arguments.get("client"),
                arguments.get("branch"),
                arguments.get("clean_volumes", False),
                arguments.get("stop_postgres", False)
            )
        elif name == "get_client_branch_status":
            return await self._get_client_branch_status(
                arguments.get("client"),
                arguments.get("branch")
            )
        elif name == "restart_client_branch":
            return await self._restart_client_branch(
                arguments.get("client"),
                arguments.get("branch")
            )
        elif name == "get_build_history":
            return await self._get_build_history(
                arguments.get("client"),
                arguments.get("limit", 20)
            )
        elif name == "build_cloudron_app":
            return await self._build_cloudron_app(
                arguments.get("client"),
                arguments.get("force", False)
            )
        elif name == "deploy_cloudron_app":
            return await self._deploy_cloudron_app(
                arguments.get("client"),
                arguments.get("action", "install")
            )
        elif name == "get_cloudron_config":
            return await self._get_cloudron_config(arguments.get("client"))
        elif name == "update_cloudron_config":
            return await self._update_cloudron_config(
                arguments.get("client"),
                arguments.get("config", {})
            )
        elif name == "get_cloudron_status":
            return await self._get_cloudron_status(arguments.get("client"))
        else:
            raise ValueError(f"Unknown tool: {name}")
    
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
                "y" if github_url else "n",         # GitHub integration
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
    
    async def _link_module_with_config(self, client: str, repository: str, module: str):
        """Link a single module and update project configuration"""
        import json
        import os
        
        if not client or not repository or not module:
            return [types.TextContent(
                type="text",
                text="❌ Client, repository, and module are required"
            )]
        
        client_path = self.repo_path / "clients" / client
        extra_addons_path = client_path / "extra-addons"
        
        # Check dev mode status to determine correct repo path
        dev_config_path = client_path / ".dev-config.json"
        is_dev_mode = False
        current_branch = "18.0"  # Default branch
        
        if dev_config_path.exists():
            try:
                with open(dev_config_path, 'r') as f:
                    dev_config = json.load(f)
                    repo_config = dev_config.get("repositories", {}).get(repository, {})
                    branch_config = repo_config.get("branches", {}).get(current_branch, {})
                    is_dev_mode = branch_config.get("mode") == "dev"
            except Exception:
                pass  # Use production mode as fallback
        
        # Set repo path based on dev mode
        if is_dev_mode:
            repo_path = client_path / ".dev-repos" / current_branch / repository
        else:
            repo_path = client_path / "addons" / repository
            
        module_path = repo_path / module
        
        # Check if client, repository, and module exist
        if not client_path.exists():
            return [types.TextContent(
                type="text",
                text=f"❌ Client '{client}' not found"
            )]
            
        if not repo_path.exists():
            return [types.TextContent(
                type="text",
                text=f"❌ Repository '{repository}' not found in client '{client}'"
            )]
            
        if not module_path.exists():
            return [types.TextContent(
                type="text",
                text=f"❌ Module '{module}' not found in repository '{repository}'"
            )]
            
        # Check if module has __manifest__.py
        manifest_path = module_path / "__manifest__.py"
        if not manifest_path.exists():
            return [types.TextContent(
                type="text",
                text=f"❌ Module '{module}' does not have a valid __manifest__.py file"
            )]
        
        # Create extra-addons directory if it doesn't exist
        extra_addons_path.mkdir(exist_ok=True)
        
        # Create symbolic link
        module_link = extra_addons_path / module
        try:
            # Remove existing link if it exists
            if module_link.exists() or module_link.is_symlink():
                module_link.unlink()
            
            # Create new link based on dev mode
            if is_dev_mode:
                relative_path = f"../.dev-repos/{current_branch}/{repository}/{module}"
            else:
                relative_path = f"../addons/{repository}/{module}"
            module_link.symlink_to(relative_path)
            
            # Update project configuration
            success = self._update_project_config_add_module(client_path, repository, module)
            
            if success:
                return [types.TextContent(
                    type="text",
                    text=f"✅ Successfully linked module '{module}' from '{repository}' and updated configuration"
                )]
            else:
                return [types.TextContent(
                    type="text",
                    text=f"⚠️ Module '{module}' linked but failed to update configuration"
                )]
                
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=f"❌ Failed to link module '{module}': {str(e)}"
            )]
    
    async def _unlink_module_with_config(self, client: str, repository: str, module: str):
        """Unlink a single module and update project configuration"""
        import json
        import os
        
        if not client or not repository or not module:
            return [types.TextContent(
                type="text",
                text="❌ Client, repository, and module are required"
            )]
        
        client_path = self.repo_path / "clients" / client
        extra_addons_path = client_path / "extra-addons"
        module_link = extra_addons_path / module
        
        # Check if client exists
        if not client_path.exists():
            return [types.TextContent(
                type="text",
                text=f"❌ Client '{client}' not found"
            )]
        
        # Remove symbolic link if it exists
        try:
            if module_link.exists() or module_link.is_symlink():
                module_link.unlink()
                link_removed = True
            else:
                link_removed = False
            
            # Update project configuration
            success = self._update_project_config_remove_module(client_path, repository, module)
            
            if link_removed and success:
                return [types.TextContent(
                    type="text",
                    text=f"✅ Successfully unlinked module '{module}' from '{repository}' and updated configuration"
                )]
            elif link_removed:
                return [types.TextContent(
                    type="text",
                    text=f"⚠️ Module '{module}' unlinked but failed to update configuration"
                )]
            elif success:
                return [types.TextContent(
                    type="text",
                    text=f"✅ Module '{module}' was not linked, but configuration updated"
                )]
            else:
                return [types.TextContent(
                    type="text",
                    text=f"⚠️ Module '{module}' was not linked and configuration unchanged"
                )]
                
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=f"❌ Failed to unlink module '{module}': {str(e)}"
            )]
    
    async def _rename_client_branch(self, client: str, old_branch: str, new_branch: str):
        """Rename a Git branch for a client"""
        import json
        
        if not client or not old_branch or not new_branch:
            return [types.TextContent(
                type="text",
                text="❌ Client, old_branch, and new_branch are required"
            )]
        
        client_path = self.repo_path / "clients" / client
        
        # Check if client exists
        if not client_path.exists():
            return [types.TextContent(
                type="text",
                text=f"❌ Client '{client}' not found"
            )]
        
        try:
            # Validate branch names
            if old_branch == new_branch:
                return [types.TextContent(
                    type="text",
                    text="❌ Old and new branch names cannot be the same"
                )]
            
            # Check if old branch exists locally
            check_result = self._run_command(["git", "branch", "--list", old_branch], cwd=client_path)
            if not check_result["success"] or not check_result["stdout"].strip():
                return [types.TextContent(
                    type="text",
                    text=f"❌ Branch '{old_branch}' not found in client '{client}'"
                )]
            
            # Check if new branch already exists
            check_result = self._run_command(["git", "branch", "--list", new_branch], cwd=client_path)
            if check_result["success"] and check_result["stdout"].strip():
                return [types.TextContent(
                    type="text",
                    text=f"❌ Branch '{new_branch}' already exists in client '{client}'"
                )]
            
            # Get current branch
            current_result = self._run_command(["git", "branch", "--show-current"], cwd=client_path)
            current_branch = current_result["stdout"].strip() if current_result["success"] else ""
            
            # Rename the branch
            rename_result = self._run_command(["git", "branch", "-m", old_branch, new_branch], cwd=client_path)
            
            if not rename_result["success"]:
                return [types.TextContent(
                    type="text",
                    text=f"❌ Failed to rename branch from '{old_branch}' to '{new_branch}': {rename_result['stderr']}"
                )]
            
            # If we were on the renamed branch, update the current branch tracking
            if current_branch == old_branch:
                # Update upstream tracking if it exists
                upstream_result = self._run_command(["git", "branch", "--unset-upstream"], cwd=client_path)
                # Try to set new upstream (if remote exists)
                self._run_command(["git", "push", "--set-upstream", "origin", new_branch], cwd=client_path)
            
            # Update project configuration if it references the old branch
            try:
                project_config_path = client_path / "project_config.json"
                if project_config_path.exists():
                    with open(project_config_path, 'r') as f:
                        config = json.load(f)
                    
                    # Update branch_configs if the old branch exists
                    if old_branch in config.get("branch_configs", {}):
                        branch_config = config["branch_configs"].pop(old_branch)
                        config["branch_configs"][new_branch] = branch_config
                        
                        # Update metadata
                        from datetime import datetime
                        config["metadata"]["last_updated"] = datetime.utcnow().isoformat() + "Z"
                        
                        with open(project_config_path, 'w') as f:
                            json.dump(config, f, indent=2)
            except Exception as config_error:
                # Branch rename succeeded, but config update failed
                print(f"Warning: Failed to update project config: {config_error}")
            
            return [types.TextContent(
                type="text",
                text=f"✅ Successfully renamed branch from '{old_branch}' to '{new_branch}' in client '{client}'"
            )]
            
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=f"❌ Failed to rename branch: {str(e)}"
            )]

    async def _build_client_branch_docker(self, client: str, branch: str, force: bool = False, no_cache: bool = False):
        """Build Docker image for a specific client branch"""
        try:
            script_path = self.repo_path / "scripts" / "build_client_branch_docker.sh"
            
            if not script_path.exists():
                return [types.TextContent(
                    type="text",
                    text=f"❌ Build script not found: {script_path}"
                )]
            
            # Build command arguments
            cmd = [str(script_path), client, branch]
            
            if force:
                cmd.append("--force")
            if no_cache:
                cmd.append("--no-cache")
            
            result = self._run_command(cmd)
            
            return [types.TextContent(
                type="text",
                text=result["stdout"] if result["success"] else f"❌ Build failed: {result['stderr']}"
            )]
            
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=f"❌ Error building Docker image: {str(e)}"
            )]
    
    async def _start_client_branch(self, client: str, branch: str, build: bool = False):
        """Start Docker service for a specific client branch using docker-compose"""
        try:
            script_path = self.repo_path / "scripts" / "start_client_branch_compose.sh"
            
            if not script_path.exists():
                return [types.TextContent(
                    type="text",
                    text=f"❌ Start script not found: {script_path}"
                )]
            
            # Build command arguments
            cmd = [str(script_path), client, branch]
            
            if build:
                cmd.append("--build")
            
            result = self._run_command(cmd)
            
            return [types.TextContent(
                type="text",
                text=result["stdout"] if result["success"] else f"❌ Start failed: {result['stderr']}"
            )]
            
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=f"❌ Error starting client branch: {str(e)}"
            )]
    
    async def _stop_client_branch(self, client: str, branch: str, clean_volumes: bool = False, stop_postgres: bool = False):
        """Stop Docker service for a specific client branch using docker-compose"""
        try:
            script_path = self.repo_path / "scripts" / "stop_client_branch_compose.sh"
            
            if not script_path.exists():
                return [types.TextContent(
                    type="text",
                    text=f"❌ Stop script not found: {script_path}"
                )]
            
            # Build command arguments
            cmd = [str(script_path), client, branch]
            
            if clean_volumes:
                cmd.append("--clean")
            # Note: stop_postgres is not needed with compose since PostgreSQL is managed separately
            
            result = self._run_command(cmd)
            
            return [types.TextContent(
                type="text",
                text=result["stdout"] if result["success"] else f"❌ Stop failed: {result['stderr']}"
            )]
            
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=f"❌ Error stopping client branch: {str(e)}"
            )]
    
    async def _get_client_branch_status(self, client: str, branch: str):
        """Get status of Docker services for a client branch"""
        try:
            import json
            
            service_name = f"odoo-alusage-{branch}-{client}"
            postgres_service = f"postgres-{client}"
            image_name = f"odoo-alusage-{client}:{branch}"
            
            # Check if containers exist and their status
            odoo_status = "not_found"
            postgres_status = "not_found"
            image_exists = False
            
            # Check Odoo service
            result = self._run_command(["docker", "container", "inspect", service_name])
            if result["success"]:
                try:
                    container_info = json.loads(result["stdout"])
                    if container_info and len(container_info) > 0:
                        odoo_status = container_info[0]["State"]["Status"]
                except:
                    odoo_status = "error"
            
            # Check PostgreSQL service
            result = self._run_command(["docker", "container", "inspect", postgres_service])
            if result["success"]:
                try:
                    container_info = json.loads(result["stdout"])
                    if container_info and len(container_info) > 0:
                        postgres_status = container_info[0]["State"]["Status"]
                except:
                    postgres_status = "error"
            
            # Check if image exists
            result = self._run_command(["docker", "image", "inspect", image_name])
            image_exists = result["success"]
            
            # Get URL
            url = f"https://{branch}.{client}.localhost"
            
            status_info = {
                "client": client,
                "branch": branch,
                "service_name": service_name,
                "postgres_service": postgres_service,
                "image_name": image_name,
                "odoo_status": odoo_status,
                "postgres_status": postgres_status,
                "image_exists": image_exists,
                "url": url,
                "overall_status": "running" if odoo_status == "running" and postgres_status == "running" else "stopped"
            }
            
            return [types.TextContent(
                type="text",
                text=json.dumps(status_info, indent=2)
            )]
            
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=f"❌ Error getting branch status: {str(e)}"
            )]
    
    async def _restart_client_branch(self, client: str, branch: str):
        """Restart Docker service for a specific client branch"""
        try:
            # Stop and then start the branch service
            await self._stop_client_branch(client, branch, clean_volumes=False, stop_postgres=False)
            
            # Wait a moment for proper cleanup
            import asyncio
            await asyncio.sleep(2)
            
            # Start the service again
            return await self._start_client_branch(client, branch, build=False)
            
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=f"❌ Error restarting client branch: {str(e)}"
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
    
    async def _list_submodules(self, client: str):
        """List Git submodules (addon repositories) for a client"""
        import os
        import json
        import subprocess
        
        if not client:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": "Client name is required"})
            )]
        
        client_dir = self.repo_path / "clients" / client
        if not client_dir.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": f"Client '{client}' not found"})
            )]
        
        try:
            submodules = []
            
            # Read .gitmodules to get the actual submodules defined for this branch
            gitmodules_file = client_dir / ".gitmodules"
            if gitmodules_file.exists():
                # Parse .gitmodules file
                gitmodules_content = gitmodules_file.read_text()
                import re
                
                # Find all submodule definitions
                submodule_pattern = r'\[submodule "([^"]+)"\]'
                path_pattern = r'path = (.+)'
                url_pattern = r'url = (.+)'
                branch_pattern = r'branch = (.+)'
                
                current_submodule = None
                current_info = {}
                
                for line in gitmodules_content.split('\n'):
                    line = line.strip()
                    if not line or line.startswith('#'):
                        continue
                    
                    # Check for submodule definition
                    submodule_match = re.match(submodule_pattern, line)
                    if submodule_match:
                        # Save previous submodule if exists
                        if current_submodule and current_info.get('path'):
                            submodules.append({
                                "name": current_submodule.split('/')[-1],  # Get last part of path as name
                                "path": current_info['path'],
                                "url": current_info.get('url', 'unknown'),
                                "branch": current_info.get('branch', ''),
                                "commit": "unknown",
                                "modules": []
                            })
                        
                        current_submodule = submodule_match.group(1)
                        current_info = {}
                        continue
                    
                    # Parse properties
                    if current_submodule:
                        if line.startswith('path = '):
                            current_info['path'] = line[7:].strip()
                        elif line.startswith('url = '):
                            current_info['url'] = line[6:].strip()
                        elif line.startswith('branch = '):
                            current_info['branch'] = line[9:].strip()
                
                # Save last submodule
                if current_submodule and current_info.get('path'):
                    submodules.append({
                        "name": current_submodule.split('/')[-1],
                        "path": current_info['path'],
                        "url": current_info.get('url', 'unknown'),
                        "branch": current_info.get('branch', ''),
                        "commit": "unknown",
                        "modules": []
                    })
            
            # Now get additional info for each submodule that actually exists
            for submodule_info in submodules:
                submodule_path = client_dir / submodule_info["path"]
                if submodule_path.exists() and submodule_path.is_dir():
                    # Try to get git info if it's a git repository
                    git_dir = submodule_path / ".git"
                    if git_dir.exists():
                        try:
                            # Get remote URL
                            result = subprocess.run(
                                ["git", "remote", "get-url", "origin"],
                                cwd=submodule_path,
                                capture_output=True,
                                text=True,
                                timeout=5
                            )
                            if result.returncode == 0:
                                submodule_info["url"] = result.stdout.strip()
                            
                            # Get current branch
                            result = subprocess.run(
                                ["git", "branch", "--show-current"],
                                cwd=submodule_path,
                                capture_output=True,
                                text=True,
                                timeout=5
                            )
                            if result.returncode == 0:
                                submodule_info["branch"] = result.stdout.strip()
                            
                            # Get current commit hash
                            result = subprocess.run(
                                ["git", "rev-parse", "--short", "HEAD"],
                                cwd=submodule_path,
                                capture_output=True,
                                text=True,
                                timeout=5
                            )
                            if result.returncode == 0:
                                submodule_info["commit"] = result.stdout.strip()
                                
                        except (subprocess.TimeoutExpired, subprocess.SubprocessError):
                            pass  # Keep default values
                    
                    # List modules (directories with __manifest__.py or __openerp__.py)
                    for module_dir in submodule_path.iterdir():
                        if module_dir.is_dir() and not module_dir.name.startswith('.'):
                            manifest_files = ["__manifest__.py", "__openerp__.py"]
                            if any((module_dir / manifest).exists() for manifest in manifest_files):
                                submodule_info["modules"].append(module_dir.name)
            
            result = {
                "success": True,
                "client": client,
                "submodules": submodules
            }
            
            return [types.TextContent(
                type="text",
                text=json.dumps(result, indent=2)
            )]
            
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": str(e)})
            )]
    
    async def _list_linked_modules(self, client: str):
        """List modules currently linked in extra-addons for a client"""
        import os
        import json
        
        if not client:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": "Client name is required"})
            )]
        
        client_dir = self.repo_path / "clients" / client
        if not client_dir.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": f"Client '{client}' not found"})
            )]
        
        try:
            linked_modules = []
            extra_addons_dir = client_dir / "extra-addons"
            
            if extra_addons_dir.exists():
                # List all symbolic links in extra-addons/
                for item in extra_addons_dir.iterdir():
                    if item.is_symlink():
                        linked_modules.append(item.name)
            
            result = {
                "success": True,
                "client": client,
                "modules": sorted(linked_modules)
            }
            
            return [types.TextContent(
                type="text",
                text=json.dumps(result, indent=2)
            )]
            
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": str(e)})
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
    
    async def _check_branch_docker_status(self, client: str, branch: str = None):
        """Check Docker image status for a client branch"""
        import json
        
        if not client:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": "Client name is required"})
            )]
        
        try:
            # Determine image name based on branch - follow build_branch_image.sh convention
            if branch and branch not in ["18.0", "17.0", "16.0", "master", "main"]:
                # Branch-specific image name - use same format as build_branch_image.sh
                branch_clean = re.sub(r'[^a-zA-Z0-9]', '-', branch)  # Same as build script
                # Default to 18.0 but check branch config for actual version
                odoo_version = "18.0"  # Could be enhanced to read from .odoo_branch_config
                image_name = f"odoo-alusage-{client}-{branch_clean}:{odoo_version}"
                deployment_image = f"odoo-alusage-{client}-{branch_clean}:{odoo_version}"
            else:
                # Default client image
                image_name = f"odoo-alusage-{client}:18.0"
                deployment_image = f"odoo-alusage-{client}:18.0"
            
            # Check if image exists locally
            inspect_result = self._run_command(["docker", "image", "inspect", image_name], cwd=self.repo_path)
            image_exists = inspect_result["success"]
            
            # Get image creation date if exists
            image_date = None
            if image_exists:
                try:
                    import json as json_lib
                    inspect_data = json_lib.loads(inspect_result["stdout"])
                    if inspect_data and len(inspect_data) > 0:
                        image_date = inspect_data[0].get("Created", "")
                except:
                    pass
            
            # Check if containers are running with this image
            ps_result = self._run_command(["docker", "ps", "--filter", f"ancestor={deployment_image}", "--format", "{{.Names}}"])
            running_containers = ps_result["stdout"].strip().split("\n") if ps_result["success"] and ps_result["stdout"].strip() else []
            
            # Check last Git commit in client directory to compare with image
            client_dir = self.repo_path / "clients" / client
            git_latest = None
            if client_dir.exists():
                git_result = self._run_command(["git", "log", "-1", "--format=%H|%ad", "--date=iso"], cwd=client_dir)
                if git_result["success"] and git_result["stdout"]:
                    parts = git_result["stdout"].strip().split("|")
                    if len(parts) >= 2:
                        git_latest = {
                            "hash": parts[0][:8],
                            "date": parts[1]
                        }
            
            # Determine status
            if not image_exists:
                status = "missing"
                status_message = "Docker image not found"
            elif not running_containers:
                status = "stopped"
                status_message = "Image exists but no containers running"
            else:
                # Compare dates if possible
                if image_date and git_latest:
                    try:
                        from datetime import datetime
                        image_dt = datetime.fromisoformat(image_date.replace('Z', '+00:00'))
                        git_dt = datetime.fromisoformat(git_latest["date"])
                        
                        if git_dt > image_dt:
                            status = "outdated"
                            status_message = "Image exists but code is newer"
                        else:
                            status = "running"
                            status_message = "Image is up to date and running"
                    except:
                        status = "running"
                        status_message = "Image exists and containers running"
                else:
                    status = "running"
                    status_message = "Image exists and containers running"
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "client": client,
                    "branch": branch,
                    "image_name": image_name,
                    "image_exists": image_exists,
                    "image_date": image_date,
                    "running_containers": running_containers,
                    "git_latest": git_latest,
                    "status": status,
                    "message": status_message
                }, indent=2)
            )]
            
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": str(e)})
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
        
        @self.http_app.options("/tools/call")
        async def options_tools_call():
            """Handle OPTIONS requests for CORS preflight"""
            return {"message": "CORS preflight OK"}
        
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
                return ToolCallResponse(
                    success=False,
                    result={
                        "type": "error",
                        "content": f"Error calling tool {request.name}: {str(e)}"
                    }
                )

        @self.http_app.websocket("/terminal/{client_name}")
        async def terminal_websocket(websocket: WebSocket, client_name: str):
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

        @self.http_app.websocket("/branch-switch/{client_name}")
        async def branch_switch_websocket(websocket: WebSocket, client_name: str):
            await websocket.accept()
            logger.info(f"Branch switch WebSocket connection opened for client: {client_name}")
            
            try:
                # Wait for branch switch request
                message = await websocket.receive_text()
                request = json.loads(message)
                target_branch = request.get('branch')
                create = request.get('create', False)
                
                if not target_branch:
                    await websocket.send_text(json.dumps({
                        "type": "error",
                        "message": "Branch name is required"
                    }))
                    await websocket.close()
                    return
                
                # Start branch switch with real-time progress
                await self._switch_client_branch_with_progress_websocket(
                    websocket, client_name, target_branch, create
                )
                
            except WebSocketDisconnect:
                logger.info(f"Branch switch WebSocket disconnected for client: {client_name}")
            except Exception as e:
                logger.error(f"Branch switch WebSocket error: {e}")
                try:
                    await websocket.send_text(json.dumps({
                        "type": "error", 
                        "message": str(e)
                    }))
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

    async def _get_git_config(self):
        """Get current Git configuration"""
        try:
            logger.info("Getting Git config...")
            config_file = self.repo_path / "config" / "git_config.json"
            logger.info(f"Git config file path: {config_file}")
            
            if config_file.exists():
                logger.info("Git config file exists, reading...")
                with open(config_file, 'r') as f:
                    config = json.load(f)
                    logger.info("Git config loaded successfully")
                    
                    return [types.TextContent(
                        type="text",
                        text=json.dumps(config, indent=2)
                    )]
            else:
                logger.info("Git config file does not exist, returning default")
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "userName": "",
                        "userEmail": ""
                    }, indent=2)
                )]
        except Exception as e:
            logger.error(f"Error in _get_git_config: {e}")
            return [types.TextContent(
                type="text",
                text=f"❌ Error reading Git config: {str(e)}"
            )]

    async def _save_git_config(self, user_name: str, user_email: str):
        """Save Git configuration"""
        try:
            logger.info(f"Saving Git config: {user_name}, {user_email}")
            
            if not user_name or not user_email:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "success": False,
                        "error": "User name and email are required"
                    }, indent=2)
                )]
            
            config_dir = self.repo_path / "config"
            config_dir.mkdir(exist_ok=True)
            
            config_file = config_dir / "git_config.json"
            
            config = {
                "userName": user_name,
                "userEmail": user_email
            }
            
            with open(config_file, 'w') as f:
                json.dump(config, f, indent=2)
            
            logger.info("Git config saved successfully")
            
            # Configure Git in the MCP container for immediate use
            try:
                import subprocess
                subprocess.run(['git', 'config', '--global', 'user.name', user_name], check=True)
                subprocess.run(['git', 'config', '--global', 'user.email', user_email], check=True)
                logger.info("Git global config updated in MCP container")
            except Exception as git_error:
                logger.warning(f"Could not update Git global config: {git_error}")
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "message": "✅ Git configuration saved successfully",
                    "config": config
                }, indent=2)
            )]
            
        except Exception as e:
            logger.error(f"Error in _save_git_config: {e}")
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": False,
                    "error": f"Failed to save Git config: {str(e)}"
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

    async def _get_client_branches(self, client_name: str):
        """Get Git branches for a client repository"""
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
            # Get all branches
            cmd = ["git", "branch", "-a", "--format=%(refname:short)|%(upstream:short)|%(HEAD)"]
            result = self._run_command(cmd, cwd=client_path)
            
            if result["return_code"] != 0:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "error": f"Git command failed: {result['stderr']}"
                    }, indent=2)
                )]
            
            branches = []
            current_branch = None
            
            # Parse branch information
            for line in result["stdout"].strip().split('\n'):
                if not line.strip():
                    continue
                    
                parts = line.split('|')
                if len(parts) >= 3:
                    branch_name = parts[0].strip()
                    upstream = parts[1].strip() if parts[1].strip() else None
                    is_current = parts[2].strip() == '*'
                    
                    # Skip remote branches that are already tracked locally
                    if branch_name.startswith('origin/'):
                        continue
                    
                    if is_current:
                        current_branch = branch_name
                    
                    # Determine branch type based on name
                    branch_type = "production"
                    if branch_name.startswith('staging-'):
                        branch_type = "staging"
                    elif branch_name.startswith('dev-'):
                        branch_type = "development"
                    elif branch_name in ['master', 'main']:
                        branch_type = "production"
                    elif branch_name.startswith(('18.0', '17.0', '16.0')):
                        branch_type = "production"
                    
                    branches.append({
                        "name": branch_name,
                        "type": branch_type,
                        "current": is_current,
                        "upstream": upstream
                    })
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "client": client_name,
                    "current_branch": current_branch,
                    "branches": branches
                }, indent=2)
            )]
            
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "error": f"Error getting branches for client '{client_name}': {str(e)}"
                }, indent=2)
            )]

    async def _create_client_branch(self, client_name: str, branch_name: str, source_branch: str = "18.0"):
        """Create a new Git branch for a client"""
        if not client_name or not branch_name:
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": "Client name and branch name are required"}, indent=2)
            )]
        
        client_path = self.repo_path / "clients" / client_name
        if not client_path.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": f"Client '{client_name}' not found"}, indent=2)
            )]
        
        try:
            # Check if branch already exists
            check_cmd = ["git", "rev-parse", "--verify", branch_name]
            check_result = self._run_command(check_cmd, cwd=client_path)
            
            if check_result["return_code"] == 0:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "error": f"Branch '{branch_name}' already exists"
                    }, indent=2)
                )]
            
            # Create new branch from source
            cmd = ["git", "checkout", "-b", branch_name, source_branch]
            result = self._run_command(cmd, cwd=client_path)
            
            if result["return_code"] != 0:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "error": f"Failed to create branch: {result['stderr']}"
                    }, indent=2)
                )]
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "client": client_name,
                    "branch": branch_name,
                    "source": source_branch,
                    "message": f"Branch '{branch_name}' created successfully from '{source_branch}'"
                }, indent=2)
            )]
            
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "error": f"Error creating branch '{branch_name}': {str(e)}"
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
                name="get_git_config",
                description="Get current Git configuration for commits",
                inputSchema={
                    "type": "object",
                    "properties": {},
                    "required": []
                }
            ),
            types.Tool(
                name="save_git_config",
                description="Save Git configuration for commits when creating clients",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "user_name": {
                            "type": "string",
                            "description": "Git user name for commits"
                        },
                        "user_email": {
                            "type": "string",
                            "description": "Git user email for commits"
                        }
                    },
                    "required": ["user_name", "user_email"]
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
                name="get_client_branches",
                description="Get Git branches for a client repository",
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
                name="create_client_branch",
                description="Create a new Git branch for a client",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "client": {
                            "type": "string",
                            "description": "Name of the client"
                        },
                        "branch": {
                            "type": "string",
                            "description": "Branch name to create"
                        },
                        "source": {
                            "type": "string",
                            "description": "Source branch to create from",
                            "default": "18.0"
                        }
                    },
                    "required": ["client", "branch"]
                }
            ),
            types.Tool(
                name="switch_client_branch",
                description="Switch to a different Git branch for a client",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "client": {
                            "type": "string",
                            "description": "Name of the client"
                        },
                        "branch": {
                            "type": "string",
                            "description": "Branch name to switch to"
                        }
                    },
                    "required": ["client", "branch"]
                }
            ),
            types.Tool(
                name="switch_client_branch_with_progress",
                description="Switch to a different Git branch for a client with detailed progress steps",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "client": {
                            "type": "string",
                            "description": "Name of the client"
                        },
                        "branch": {
                            "type": "string",
                            "description": "Branch name to switch to"
                        },
                        "create": {
                            "type": "boolean",
                            "description": "Create branch if it doesn't exist",
                            "default": False
                        }
                    },
                    "required": ["client", "branch"]
                }
            ),
            types.Tool(
                name="start_client_branch",
                description="Start Docker containers for a specific client branch",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "client": {
                            "type": "string",
                            "description": "Name of the client"
                        },
                        "branch": {
                            "type": "string",
                            "description": "Branch name to start"
                        }
                    },
                    "required": ["client", "branch"]
                }
            ),
            types.Tool(
                name="stop_client_branch",
                description="Stop Docker containers for a specific client branch",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "client": {
                            "type": "string",
                            "description": "Name of the client"
                        },
                        "branch": {
                            "type": "string",
                            "description": "Branch name to stop"
                        }
                    },
                    "required": ["client", "branch"]
                }
            ),
            types.Tool(
                name="restart_client_branch",
                description="Restart Docker containers for a specific client branch",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "client": {
                            "type": "string",
                            "description": "Name of the client"
                        },
                        "branch": {
                            "type": "string",
                            "description": "Branch name to restart"
                        }
                    },
                    "required": ["client", "branch"]
                }
            ),
            types.Tool(
                name="get_branch_logs",
                description="Get Docker logs for a specific client branch deployment",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "client": {
                            "type": "string",
                            "description": "Name of the client"
                        },
                        "branch": {
                            "type": "string",
                            "description": "Branch name"
                        },
                        "lines": {
                            "type": "integer",
                            "description": "Number of log lines to return",
                            "default": 100
                        }
                    },
                    "required": ["client", "branch"]
                }
            ),
            types.Tool(
                name="open_branch_shell",
                description="Open an interactive shell in a client branch container",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "client": {
                            "type": "string",
                            "description": "Name of the client"
                        },
                        "branch": {
                            "type": "string",
                            "description": "Branch name"
                        }
                    },
                    "required": ["client", "branch"]
                }
            ),
            types.Tool(
                name="get_branch_status",
                description="Get deployment status for a specific client branch",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "client": {
                            "type": "string",
                            "description": "Name of the client"
                        },
                        "branch": {
                            "type": "string",
                            "description": "Branch name"
                        }
                    },
                    "required": ["client", "branch"]
                }
            ),
            types.Tool(
                name="list_deployments",
                description="List all active branch deployments across all clients",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "client": {
                            "type": "string",
                            "description": "Optional: filter by specific client name"
                        }
                    }
                }
            ),
            types.Tool(
                name="get_traefik_config",
                description="Get current Traefik configuration (domain and protocol)",
                inputSchema={
                    "type": "object",
                    "properties": {}
                }
            ),
            types.Tool(
                name="set_traefik_config",
                description="Set Traefik configuration for branch deployments",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "domain": {
                            "type": "string",
                            "description": "Domain to use for branch URLs (e.g., 'local', 'localhost', 'dev')"
                        },
                        "protocol": {
                            "type": "string",
                            "description": "Protocol to use",
                            "enum": ["http", "https"],
                            "default": "http"
                        }
                    },
                    "required": ["domain"]
                }
            ),
            types.Tool(
                name="build_cloudron_app",
                description="Build Cloudron application for a client (production branches only)",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "client": {
                            "type": "string",
                            "description": "Client name"
                        },
                        "force": {
                            "type": "boolean",
                            "description": "Force rebuild even if image already exists",
                            "default": False
                        }
                    },
                    "required": ["client"]
                }
            ),
            types.Tool(
                name="deploy_cloudron_app",
                description="Deploy Cloudron application for a client (production branches only)",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "client": {
                            "type": "string",
                            "description": "Client name"
                        },
                        "action": {
                            "type": "string",
                            "description": "Deployment action",
                            "enum": ["install", "update", "uninstall"],
                            "default": "install"
                        }
                    },
                    "required": ["client"]
                }
            ),
            types.Tool(
                name="get_cloudron_config",
                description="Get Cloudron configuration for a client",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "client": {
                            "type": "string",
                            "description": "Client name"
                        }
                    },
                    "required": ["client"]
                }
            ),
            types.Tool(
                name="update_cloudron_config",
                description="Update Cloudron configuration for a client",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "client": {
                            "type": "string",
                            "description": "Client name"
                        },
                        "config": {
                            "type": "object",
                            "description": "Cloudron configuration object",
                            "properties": {
                                "server": {"type": "string"},
                                "app_id": {"type": "string"},
                                "docker_registry": {"type": "string"},
                                "docker_username": {"type": "string"},
                                "docker_password": {"type": "string"},
                                "cloudron_username": {"type": "string"},
                                "cloudron_password": {"type": "string"},
                                "app_version": {"type": "string"},
                                "contact_email": {"type": "string"},
                                "author_name": {"type": "string"},
                                "client_website": {"type": "string"}
                            }
                        }
                    },
                    "required": ["client", "config"]
                }
            ),
            types.Tool(
                name="get_cloudron_status",
                description="Get status of Cloudron deployment for a client",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "client": {
                            "type": "string",
                            "description": "Client name"
                        }
                    },
                    "required": ["client"]
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

    async def _start_client_branch(self, client_name: str, branch_name: str):
        """Start Docker containers for a specific client branch using V2 architecture"""
        if not client_name or not branch_name:
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": "Client name and branch name are required"}, indent=2)
            )]
        
        client_path = self.repo_path / "clients" / client_name
        if not client_path.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": f"Client '{client_name}' not found"}, indent=2)
            )]
        
        try:
            # Use V2 deployment script
            script_path = self.repo_path / "scripts" / "deploy_branch_v2.sh"
            cmd = [str(script_path), client_name, branch_name, "up"]
            result = self._run_command(cmd, cwd=client_path)
            
            if result["return_code"] != 0:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "error": f"Failed to start branch deployment: {result['stderr']}"
                    }, indent=2)
                )]
            
            # Parse container information from output
            clean_branch = branch_name.replace("/", "-").replace("_", "-")
            container_name = f"{clean_branch}-odoo-{client_name}"
            traefik_url = f"http://{clean_branch}.{client_name}.localhost"
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "client": client_name,
                    "branch": branch_name,
                    "container": container_name,
                    "traefik_url": traefik_url,
                    "message": f"Started branch deployment for '{branch_name}'"
                }, indent=2)
            )]
            
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "error": f"Error starting branch deployment for '{branch_name}': {str(e)}"
                }, indent=2)
            )]

    async def _stop_client_branch(self, client_name: str, branch_name: str):
        """Stop Docker containers for a specific client branch using V2 architecture"""
        if not client_name or not branch_name:
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": "Client name and branch name are required"}, indent=2)
            )]
        
        client_path = self.repo_path / "clients" / client_name
        if not client_path.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": f"Client '{client_name}' not found"}, indent=2)
            )]
        
        try:
            # Use V2 deployment script
            script_path = self.repo_path / "scripts" / "deploy_branch_v2.sh"
            cmd = [str(script_path), client_name, branch_name, "down"]
            result = self._run_command(cmd, cwd=client_path)
            
            if result["return_code"] != 0:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "error": f"Failed to stop branch deployment: {result['stderr']}"
                    }, indent=2)
                )]
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "client": client_name,
                    "branch": branch_name,
                    "message": f"Stopped branch deployment for '{branch_name}'"
                }, indent=2)
            )]
            
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "error": f"Error stopping branch deployment for '{branch_name}': {str(e)}"
                }, indent=2)
            )]

    async def _restart_client_branch(self, client_name: str, branch_name: str):
        """Restart Docker containers for a specific client branch using V2 architecture"""
        if not client_name or not branch_name:
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": "Client name and branch name are required"}, indent=2)
            )]
        
        client_path = self.repo_path / "clients" / client_name
        if not client_path.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": f"Client '{client_name}' not found"}, indent=2)
            )]
        
        try:
            # Use V2 deployment script
            script_path = self.repo_path / "scripts" / "deploy_branch_v2.sh"
            cmd = [str(script_path), client_name, branch_name, "restart"]
            result = self._run_command(cmd, cwd=client_path)
            
            if result["return_code"] != 0:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "error": f"Failed to restart branch deployment: {result['stderr']}"
                    }, indent=2)
                )]
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "client": client_name,
                    "branch": branch_name,
                    "message": f"Restarted branch deployment for '{branch_name}'"
                }, indent=2)
            )]
            
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "error": f"Error restarting branch deployment for '{branch_name}': {str(e)}"
                }, indent=2)
            )]

    async def _get_branch_logs(self, client_name: str, branch_name: str, lines: int = 100):
        """Get Docker logs for a specific client branch deployment using V2 architecture"""
        if not client_name or not branch_name:
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": "Client name and branch name are required"}, indent=2)
            )]
        
        try:
            # Use V2 deployment script to get logs
            script_path = self.repo_path / "scripts" / "deploy_branch_v2.sh"
            
            result = self._run_command([
                str(script_path), client_name, branch_name, "logs"
            ])
            
            if result["success"]:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "success": True,
                        "message": f"Logs for branch '{branch_name}'",
                        "logs": result["stdout"]
                    }, indent=2)
                )]
            else:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "error": f"Failed to get branch logs: {result['stderr']}"
                    }, indent=2)
                )]
        
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "error": f"Error getting logs for branch '{branch_name}': {str(e)}"
                }, indent=2)
            )]

    async def _open_branch_shell(self, client_name: str, branch_name: str):
        """Open an interactive shell in a client branch container using V2 architecture"""
        if not client_name or not branch_name:
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": "Client name and branch name are required"}, indent=2)
            )]
        
        try:
            # Use V2 deployment script to open shell
            script_path = self.repo_path / "scripts" / "deploy_branch_v2.sh"
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "message": f"To open shell for branch '{branch_name}', run:",
                    "command": f"{script_path} {client_name} {branch_name} shell",
                    "note": "This command must be run in a terminal as it requires interactive mode"
                }, indent=2)
            )]
        
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "error": f"Error preparing shell command for branch '{branch_name}': {str(e)}"
                }, indent=2)
            )]

    async def _get_branch_status(self, client_name: str, branch_name: str):
        """Get deployment status for a specific client branch using V2 architecture"""
        if not client_name or not branch_name:
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": "Client name and branch name are required"}, indent=2)
            )]
        
        try:
            # Use V2 deployment script to get status
            script_path = self.repo_path / "scripts" / "deploy_branch_v2.sh"
            
            result = self._run_command([
                str(script_path), client_name, branch_name, "status"
            ])
            
            if result["success"]:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "success": True,
                        "client": client_name,
                        "branch": branch_name,
                        "status": result["stdout"]
                    }, indent=2)
                )]
            else:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "error": f"Failed to get branch status: {result['stderr']}"
                    }, indent=2)
                )]
        
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "error": f"Error getting status for branch '{branch_name}': {str(e)}"
                }, indent=2)
            )]

    async def _list_deployments(self, client_name: Optional[str] = None):
        """List all active branch deployments across all clients or for a specific client"""
        try:
            # Get list of running containers with deployment labels
            result = self._run_command([
                "docker", "ps", "--format", 
                "{{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}\t{{.Labels}}",
                "--filter", "label=deployment.client"
            ])
            
            deployments = []
            if result["success"] and result["stdout"]:
                lines = result["stdout"].strip().split('\n')
                for line in lines:
                    parts = line.split('\t')
                    if len(parts) >= 5:
                        container_name = parts[0]
                        image = parts[1]
                        ports = parts[2]
                        status = parts[3]
                        labels = parts[4]
                        
                        # Parse labels to extract deployment info
                        deployment_info = {
                            "container_name": container_name,
                            "image": image,
                            "ports": ports,
                            "status": status
                        }
                        
                        # Extract deployment labels
                        for label in labels.split(','):
                            if '=' in label:
                                key, value = label.split('=', 1)
                                if key.startswith('deployment.'):
                                    field = key.replace('deployment.', '')
                                    deployment_info[field] = value
                        
                        # Filter by client if specified
                        if client_name is None or deployment_info.get('client') == client_name:
                            deployments.append(deployment_info)
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "deployments": deployments,
                    "total": len(deployments),
                    "filter": f"client={client_name}" if client_name else "all"
                }, indent=2)
            )]
        
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "error": f"Error listing deployments: {str(e)}"
                }, indent=2)
            )]

    async def _commit_client_changes(self, client: str, message: str = "Update module links"):
        """Commit current changes in client repository"""
        import json
        
        if not client:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": "Client name is required"})
            )]
        
        client_dir = self.repo_path / "clients" / client
        if not client_dir.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": f"Client '{client}' not found"})
            )]
        
        try:
            # Configure Git if not already configured
            config_check = self._run_command(["git", "config", "user.email"], cwd=client_dir)
            if not config_check["success"] or not config_check["stdout"].strip():
                self._run_command(["git", "config", "user.email", "mcp@odoo-client.local"], cwd=client_dir)
                self._run_command(["git", "config", "user.name", "MCP Server"], cwd=client_dir)
            
            # Check if there are changes to commit
            status_result = self._run_command(["git", "status", "--porcelain"], cwd=client_dir)
            
            if not status_result["success"]:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({"success": False, "error": f"Failed to check git status: {status_result['stderr']}"})
                )]
            
            if not status_result["stdout"].strip():
                return [types.TextContent(
                    type="text",
                    text=json.dumps({"success": True, "message": "No changes to commit", "committed": False})
                )]
            
            # Add all changes
            add_result = self._run_command(["git", "add", "."], cwd=client_dir)
            if not add_result["success"]:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({"success": False, "error": f"Failed to add changes: {add_result['stderr']}"})
                )]
            
            # Commit changes
            commit_result = self._run_command(["git", "commit", "-m", message], cwd=client_dir)
            if not commit_result["success"]:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({"success": False, "error": f"Failed to commit: {commit_result['stderr']}"})
                )]
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True, 
                    "message": f"Changes committed successfully: {message}",
                    "committed": True,
                    "commit_hash": commit_result["stdout"].strip()
                })
            )]
            
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": str(e)})
            )]
    
    async def _switch_client_branch(self, client: str, branch: str, create: bool = False):
        """Switch client repository to a specific Git branch"""
        import json
        
        if not client or not branch:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": "Client name and branch are required"})
            )]
        
        client_dir = self.repo_path / "clients" / client
        if not client_dir.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": f"Client '{client}' not found"})
            )]
        
        try:
            # Check current branch
            current_branch_result = self._run_command(["git", "branch", "--show-current"], cwd=client_dir)
            current_branch = current_branch_result["stdout"].strip() if current_branch_result["success"] else "unknown"
            
            # Clean extra-addons directory (symbolic links) before switch
            extra_addons_dir = client_dir / "extra-addons"
            if extra_addons_dir.exists():
                import os
                for item in extra_addons_dir.iterdir():
                    if item.is_symlink():
                        item.unlink()
                        logger.info(f"Removed symlink: {item}")
            
            # Also check for untracked submodule directories that might conflict
            addons_dir = client_dir / "addons"
            if addons_dir.exists():
                # Get list of untracked files/directories in addons/
                status_result = self._run_command(["git", "status", "--porcelain", "addons/"], cwd=client_dir)
                if status_result["success"]:
                    untracked_lines = [line for line in status_result["stdout"].split('\n') if line.startswith('??')]
                    for line in untracked_lines:
                        untracked_path = line[3:].strip()  # Remove '?? ' prefix
                        full_path = client_dir / untracked_path
                        if full_path.exists() and full_path.is_dir():
                            import shutil
                            shutil.rmtree(full_path)
                            logger.info(f"Removed untracked directory: {full_path}")
            
            # Reset any changes in tracked files
            reset_result = self._run_command(["git", "reset", "--hard"], cwd=client_dir)
            if not reset_result["success"]:
                logger.warning(f"Failed to reset working directory: {reset_result['stderr']}")
            
            # Check if branch exists
            branch_exists_result = self._run_command(["git", "show-ref", "--verify", "--quiet", f"refs/heads/{branch}"], cwd=client_dir)
            branch_exists = branch_exists_result["return_code"] == 0
            
            # If branch doesn't exist and create=True, create it
            if not branch_exists and create:
                create_result = self._run_command(["git", "checkout", "-b", branch], cwd=client_dir)
                if not create_result["success"]:
                    return [types.TextContent(
                        type="text",
                        text=json.dumps({"success": False, "error": f"Failed to create branch '{branch}': {create_result['stderr']}"})
                    )]
                
                # Clean addons directory completely before reinitializing submodules
                addons_dir = client_dir / "addons"
                if addons_dir.exists():
                    import shutil
                    shutil.rmtree(addons_dir)
                    logger.info(f"Cleaned addons directory for new branch: {addons_dir}")
                
                # Update submodules for new branch
                submodule_result = self._run_command(["git", "submodule", "update", "--init", "--recursive"], cwd=client_dir)
                if not submodule_result["success"]:
                    logger.warning(f"Failed to update submodules: {submodule_result['stderr']}")
                
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "success": True,
                        "message": f"Created and switched to new branch '{branch}' with clean submodules",
                        "previous_branch": current_branch,
                        "current_branch": branch,
                        "created": True,
                        "submodules_updated": submodule_result["success"]
                    })
                )]
            
            elif not branch_exists:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({"success": False, "error": f"Branch '{branch}' does not exist. Use create=true to create it."})
                )]
            
            # Switch to existing branch
            checkout_result = self._run_command(["git", "checkout", branch], cwd=client_dir)
            if not checkout_result["success"]:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({"success": False, "error": f"Failed to switch to branch '{branch}': {checkout_result['stderr']}"})
                )]
            
            # Clean submodule cache from .git/modules first to prevent stale submodules
            git_modules_dir = client_dir / ".git" / "modules" / "addons"
            if git_modules_dir.exists():
                import shutil
                shutil.rmtree(git_modules_dir)
                logger.info(f"Cleaned submodule cache: {git_modules_dir}")
            
            # Clean addons directory completely before reinitializing submodules
            addons_dir = client_dir / "addons"
            if addons_dir.exists():
                import shutil
                shutil.rmtree(addons_dir)
                logger.info(f"Cleaned addons directory: {addons_dir}")
            
            # Deinitialize all submodules to clean cache
            deinit_result = self._run_command(["git", "submodule", "deinit", "--all", "--force"], cwd=client_dir)
            if not deinit_result["success"]:
                logger.warning(f"Failed to deinitialize submodules: {deinit_result['stderr']}")
            
            # Sync submodules with .gitmodules to ensure only current branch submodules are active
            sync_result = self._run_command(["git", "submodule", "sync"], cwd=client_dir)
            if not sync_result["success"]:
                logger.warning(f"Failed to sync submodules: {sync_result['stderr']}")
            
            # Update submodules to match the branch - this will recreate only the ones defined in .gitmodules
            submodule_result = self._run_command(["git", "submodule", "update", "--init", "--recursive"], cwd=client_dir)
            if not submodule_result["success"]:
                logger.warning(f"Failed to update submodules: {submodule_result['stderr']}")
            
            # Clean up any stale submodule directories not in current .gitmodules
            gitmodules_file = client_dir / ".gitmodules"
            addons_dir = client_dir / "addons"  # Redefine since we deleted it earlier
            if gitmodules_file.exists() and addons_dir.exists():
                # Read defined submodules from .gitmodules
                defined_submodules = set()
                gitmodules_content = gitmodules_file.read_text()
                import re
                for line in gitmodules_content.split('\n'):
                    if line.strip().startswith('path = addons/'):
                        submodule_name = line.strip()[len('path = addons/'):].strip()
                        defined_submodules.add(submodule_name)
                
                # Remove any addons directory not in .gitmodules
                for item in addons_dir.iterdir():
                    if item.is_dir() and item.name not in defined_submodules:
                        import shutil
                        shutil.rmtree(item)
                        logger.info(f"Removed stale submodule directory: {item}")
                        
                        # Also clean the cache for this specific submodule
                        cache_dir = client_dir / ".git" / "modules" / "addons" / item.name
                        if cache_dir.exists():
                            shutil.rmtree(cache_dir)
                            logger.info(f"Removed stale submodule cache: {cache_dir}")
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "message": f"Switched to branch '{branch}' and updated submodules",
                    "previous_branch": current_branch,
                    "current_branch": branch,
                    "created": False,
                    "submodules_updated": submodule_result["success"]
                })
            )]
            
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": str(e)})
            )]
    
    async def _switch_client_branch_with_progress(self, client: str, branch: str, create: bool = False):
        """Switch client repository to a specific Git branch with detailed progress steps"""
        import json
        
        if not client or not branch:
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": False, 
                    "error": "Client name and branch are required",
                    "steps": []
                })
            )]
        
        client_dir = self.repo_path / "clients" / client
        if not client_dir.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": False, 
                    "error": f"Client '{client}' not found",
                    "steps": []
                })
            )]
        
        steps = []
        current_step = 0
        
        try:
            # Step 1: Check current branch
            current_step += 1
            steps.append({
                "step": current_step,
                "action": "Checking current branch",
                "status": "in_progress",
                "details": ""
            })
            
            current_branch_result = self._run_command(["git", "branch", "--show-current"], cwd=client_dir)
            current_branch = current_branch_result["stdout"].strip() if current_branch_result["success"] else "unknown"
            
            steps[-1].update({
                "status": "completed",
                "details": f"Current branch: {current_branch}"
            })
            
            # Step 2: Save current linked modules
            current_step += 1
            steps.append({
                "step": current_step,
                "action": "Saving current linked modules",
                "status": "in_progress",
                "details": ""
            })
            
            saved_modules = self._save_linked_modules(client_dir, current_branch)
            
            steps[-1].update({
                "status": "completed",
                "details": f"Saved {saved_modules} linked modules for branch '{current_branch}'"
            })
            
            # Step 3: Clean symbolic links
            current_step += 1
            steps.append({
                "step": current_step,
                "action": "Cleaning symbolic links",
                "status": "in_progress",
                "details": ""
            })
            
            extra_addons_dir = client_dir / "extra-addons"
            symlinks_removed = 0
            if extra_addons_dir.exists():
                import os
                for item in extra_addons_dir.iterdir():
                    if item.is_symlink():
                        item.unlink()
                        symlinks_removed += 1
            
            steps[-1].update({
                "status": "completed",
                "details": f"Removed {symlinks_removed} symbolic links"
            })
            
            # Step 4: Check if branch exists
            current_step += 1
            steps.append({
                "step": current_step,
                "action": "Checking branch existence",
                "status": "in_progress",
                "details": ""
            })
            
            branch_exists_result = self._run_command(["git", "show-ref", "--verify", "--quiet", f"refs/heads/{branch}"], cwd=client_dir)
            branch_exists = branch_exists_result["return_code"] == 0
            
            steps[-1].update({
                "status": "completed",
                "details": f"Branch '{branch}' {'exists' if branch_exists else 'does not exist'}"
            })
            
            # Step 5: Create branch if needed
            if not branch_exists and create:
                current_step += 1
                steps.append({
                    "step": current_step,
                    "action": f"Creating branch '{branch}'",
                    "status": "in_progress",
                    "details": ""
                })
                
                create_result = self._run_command(["git", "checkout", "-b", branch], cwd=client_dir)
                if not create_result["success"]:
                    steps[-1].update({
                        "status": "failed",
                        "details": f"Failed to create branch: {create_result['stderr']}"
                    })
                    return [types.TextContent(
                        type="text",
                        text=json.dumps({
                            "success": False, 
                            "error": f"Failed to create branch '{branch}': {create_result['stderr']}",
                            "steps": steps
                        })
                    )]
                
                steps[-1].update({
                    "status": "completed",
                    "details": f"Branch '{branch}' created successfully"
                })
            elif not branch_exists:
                current_step += 1
                steps.append({
                    "step": current_step,
                    "action": "Branch validation",
                    "status": "failed",
                    "details": f"Branch '{branch}' does not exist. Use create=true to create it."
                })
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "success": False, 
                        "error": f"Branch '{branch}' does not exist. Use create=true to create it.",
                        "steps": steps
                    })
                )]
            
            # Step 5: Handle uncommitted and untracked files
            current_step += 1
            steps.append({
                "step": current_step,
                "action": "Managing uncommitted changes",
                "status": "in_progress",
                "details": ""
            })
            
            # Check if there are any changes or untracked files
            status_result = self._run_command(["git", "status", "--porcelain"], cwd=client_dir)
            status_lines = status_result["stdout"].strip().split('\n') if status_result["success"] and status_result["stdout"].strip() else []
            
            untracked_files = []
            modified_files = []
            
            for line in status_lines:
                if line.startswith('??'):  # Untracked files
                    untracked_files.append(line[3:])
                elif line.strip():  # Modified files
                    modified_files.append(line[3:])
            
            # Add untracked files to Git (especially project_config.json)
            if untracked_files:
                for file in untracked_files:
                    if file == "project_config.json":  # Always add project config
                        add_result = self._run_command(["git", "add", file], cwd=client_dir)
                        
            # Now stash all changes (including previously untracked files)
            status_result2 = self._run_command(["git", "status", "--porcelain"], cwd=client_dir)
            has_changes = bool(status_result2["stdout"].strip()) if status_result2["success"] else False
            
            if has_changes:
                stash_result = self._run_command(["git", "stash", "push", "-m", f"Auto-stash before switching to {branch}"], cwd=client_dir)
                details = f"Added {len(untracked_files)} untracked files and stashed all changes"
                if not stash_result["success"]:
                    details = f"Stash failed: {stash_result['stderr']}"
            else:
                details = f"Added {len(untracked_files)} untracked files, no changes to stash"
            
            steps[-1].update({
                "status": "completed",
                "details": details
            })
            
            # Step 6: Switch to branch
            if branch_exists:
                current_step += 1
                steps.append({
                    "step": current_step,
                    "action": f"Switching to branch '{branch}'",
                    "status": "in_progress",
                    "details": ""
                })
                
                checkout_result = self._run_command(["git", "checkout", branch], cwd=client_dir)
                if not checkout_result["success"]:
                    steps[-1].update({
                        "status": "failed",
                        "details": f"Failed to switch: {checkout_result['stderr']}"
                    })
                    return [types.TextContent(
                        type="text",
                        text=json.dumps({
                            "success": False, 
                            "error": f"Failed to switch to branch '{branch}': {checkout_result['stderr']}",
                            "steps": steps
                        })
                    )]
                
                steps[-1].update({
                    "status": "completed",
                    "details": f"Successfully switched to branch '{branch}'"
                })
            
            # Step 7: Clean submodule cache
            current_step += 1
            steps.append({
                "step": current_step,
                "action": "Cleaning submodule cache",
                "status": "in_progress",
                "details": ""
            })
            
            git_modules_dir = client_dir / ".git" / "modules" / "addons"
            cache_cleaned = False
            if git_modules_dir.exists():
                import shutil
                shutil.rmtree(git_modules_dir)
                cache_cleaned = True
            
            steps[-1].update({
                "status": "completed",
                "details": f"Submodule cache {'cleaned' if cache_cleaned else 'already clean'}"
            })
            
            # Step 7: Clean addons directory
            current_step += 1
            steps.append({
                "step": current_step,
                "action": "Cleaning addons directory",
                "status": "in_progress",
                "details": ""
            })
            
            addons_dir = client_dir / "addons"
            addons_cleaned = False
            if addons_dir.exists():
                import shutil
                shutil.rmtree(addons_dir)
                addons_cleaned = True
            
            steps[-1].update({
                "status": "completed",
                "details": f"Addons directory {'cleaned' if addons_cleaned else 'already clean'}"
            })
            
            # Step 8: Deinitialize submodules
            current_step += 1
            steps.append({
                "step": current_step,
                "action": "Deinitializing submodules",
                "status": "in_progress",
                "details": ""
            })
            
            deinit_result = self._run_command(["git", "submodule", "deinit", "--all", "--force"], cwd=client_dir)
            
            steps[-1].update({
                "status": "completed" if deinit_result["success"] else "completed_with_warnings",
                "details": "Submodules deinitialized" if deinit_result["success"] else f"Submodules deinitialized with warnings: {deinit_result['stderr']}"
            })
            
            # Step 9: Sync submodules
            current_step += 1
            steps.append({
                "step": current_step,
                "action": "Syncing submodules with .gitmodules",
                "status": "in_progress",
                "details": ""
            })
            
            sync_result = self._run_command(["git", "submodule", "sync"], cwd=client_dir)
            
            steps[-1].update({
                "status": "completed" if sync_result["success"] else "completed_with_warnings",
                "details": "Submodules synced" if sync_result["success"] else f"Submodules synced with warnings: {sync_result['stderr']}"
            })
            
            # Step 10: Initialize and update submodules
            current_step += 1
            steps.append({
                "step": current_step,
                "action": "Initializing and updating submodules",
                "status": "in_progress",
                "details": ""
            })
            
            submodule_result = self._run_command(["git", "submodule", "update", "--init", "--recursive"], cwd=client_dir)
            
            # Parse submodule output to show which ones were cloned
            submodule_details = "Submodules updated"
            if submodule_result["success"] and submodule_result["stdout"]:
                cloned_count = submodule_result["stdout"].count("Submodule path")
                if cloned_count > 0:
                    submodule_details = f"Updated {cloned_count} submodules"
            
            steps[-1].update({
                "status": "completed" if submodule_result["success"] else "failed",
                "details": submodule_details if submodule_result["success"] else f"Failed to update submodules: {submodule_result['stderr']}"
            })
            
            # Step 11: Clean stale submodule directories
            current_step += 1
            steps.append({
                "step": current_step,
                "action": "Cleaning stale submodule directories",
                "status": "in_progress",
                "details": ""
            })
            
            gitmodules_file = client_dir / ".gitmodules"
            addons_dir = client_dir / "addons"  # Redefine since we deleted it earlier
            removed_count = 0
            
            if gitmodules_file.exists() and addons_dir.exists():
                # Read defined submodules from .gitmodules
                defined_submodules = set()
                gitmodules_content = gitmodules_file.read_text()
                for line in gitmodules_content.split('\n'):
                    if line.strip().startswith('path = addons/'):
                        submodule_name = line.strip()[len('path = addons/'):].strip()
                        defined_submodules.add(submodule_name)
                
                # Remove any addons directory not in .gitmodules
                for item in addons_dir.iterdir():
                    if item.is_dir() and item.name not in defined_submodules:
                        import shutil
                        shutil.rmtree(item)
                        removed_count += 1
                        
                        # Also clean the cache for this specific submodule
                        cache_dir = client_dir / ".git" / "modules" / "addons" / item.name
                        if cache_dir.exists():
                            shutil.rmtree(cache_dir)
            
            steps[-1].update({
                "status": "completed",
                "details": f"Removed {removed_count} stale submodule directories"
            })
            
            # Step 12: Restore linked modules for the target branch
            current_step += 1
            steps.append({
                "step": current_step,
                "action": "Restoring linked modules",
                "status": "in_progress",
                "details": ""
            })
            
            restored_modules = self._restore_linked_modules(client_dir, branch)
            
            steps[-1].update({
                "status": "completed",
                "details": f"Restored {restored_modules} linked modules for branch '{branch}'"
            })
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "message": f"Successfully switched to branch '{branch}' and updated submodules",
                    "previous_branch": current_branch,
                    "current_branch": branch,
                    "created": not branch_exists and create,
                    "submodules_updated": submodule_result["success"],
                    "steps": steps
                })
            )]
            
        except Exception as e:
            # Mark current step as failed if we have one
            if steps and steps[-1]["status"] == "in_progress":
                steps[-1].update({
                    "status": "failed",
                    "details": f"Error: {str(e)}"
                })
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": False, 
                    "error": str(e),
                    "steps": steps
                })
            )]

    async def _switch_client_branch_with_progress_websocket(self, websocket: WebSocket, client: str, branch: str, create: bool = False):
        """Switch client repository to a specific Git branch with real-time progress via WebSocket"""
        import json
        
        if not client or not branch:
            await websocket.send_text(json.dumps({
                "type": "error",
                "message": "Client name and branch are required"
            }))
            return

        client_dir = self.repo_path / "clients" / client
        if not client_dir.exists():
            await websocket.send_text(json.dumps({
                "type": "error",
                "message": f"Client '{client}' not found"
            }))
            return

        current_step = 0

        try:
            # Send start message
            await websocket.send_text(json.dumps({
                "type": "start",
                "message": f"Starting branch switch to '{branch}'"
            }))

            # Step 1: Check current branch
            current_step += 1
            step_data = {
                "step": current_step,
                "action": "Checking current branch",
                "status": "in_progress",
                "details": ""
            }
            await websocket.send_text(json.dumps({"type": "step", "data": step_data}))
            
            current_branch_result = self._run_command(["git", "branch", "--show-current"], cwd=client_dir)
            current_branch = current_branch_result["stdout"].strip() if current_branch_result["success"] else "unknown"
            
            step_data.update({
                "status": "completed",
                "details": f"Current branch: {current_branch}"
            })
            await websocket.send_text(json.dumps({"type": "step", "data": step_data}))

            # Step 2: Save current linked modules
            current_step += 1
            step_data = {
                "step": current_step,
                "action": "Saving current linked modules",
                "status": "in_progress",
                "details": ""
            }
            await websocket.send_text(json.dumps({"type": "step", "data": step_data}))
            
            saved_modules = self._save_linked_modules(client_dir, current_branch)
            
            step_data.update({
                "status": "completed",
                "details": f"Saved {saved_modules} linked modules for branch '{current_branch}'"
            })
            await websocket.send_text(json.dumps({"type": "step", "data": step_data}))

            # Step 3: Clean symbolic links
            current_step += 1
            step_data = {
                "step": current_step,
                "action": "Cleaning symbolic links",
                "status": "in_progress",
                "details": ""
            }
            await websocket.send_text(json.dumps({"type": "step", "data": step_data}))
            
            extra_addons_dir = client_dir / "extra-addons"
            symlinks_removed = 0
            if extra_addons_dir.exists():
                import os
                for item in extra_addons_dir.iterdir():
                    if item.is_symlink():
                        item.unlink()
                        symlinks_removed += 1
            
            step_data.update({
                "status": "completed",
                "details": f"Removed {symlinks_removed} symbolic links"
            })
            await websocket.send_text(json.dumps({"type": "step", "data": step_data}))

            # Step 4: Check if branch exists
            current_step += 1
            step_data = {
                "step": current_step,
                "action": "Checking branch existence",
                "status": "in_progress",
                "details": ""
            }
            await websocket.send_text(json.dumps({"type": "step", "data": step_data}))
            
            branch_exists_result = self._run_command(["git", "show-ref", "--verify", "--quiet", f"refs/heads/{branch}"], cwd=client_dir)
            branch_exists = branch_exists_result["return_code"] == 0
            
            step_data.update({
                "status": "completed",
                "details": f"Branch '{branch}' {'exists' if branch_exists else 'does not exist'}"
            })
            await websocket.send_text(json.dumps({"type": "step", "data": step_data}))

            # Step 5: Create branch if needed
            if not branch_exists and create:
                current_step += 1
                step_data = {
                    "step": current_step,
                    "action": f"Creating branch '{branch}'",
                    "status": "in_progress",
                    "details": ""
                }
                await websocket.send_text(json.dumps({"type": "step", "data": step_data}))
                
                create_result = self._run_command(["git", "checkout", "-b", branch], cwd=client_dir)
                if not create_result["success"]:
                    step_data.update({
                        "status": "failed",
                        "details": f"Failed to create branch: {create_result['stderr']}"
                    })
                    await websocket.send_text(json.dumps({"type": "step", "data": step_data}))
                    await websocket.send_text(json.dumps({
                        "type": "error",
                        "message": f"Failed to create branch '{branch}': {create_result['stderr']}"
                    }))
                    return
                
                step_data.update({
                    "status": "completed",
                    "details": f"Branch '{branch}' created successfully"
                })
                await websocket.send_text(json.dumps({"type": "step", "data": step_data}))
            elif not branch_exists:
                current_step += 1
                step_data = {
                    "step": current_step,
                    "action": "Branch validation",
                    "status": "failed",
                    "details": f"Branch '{branch}' does not exist. Use create=true to create it."
                }
                await websocket.send_text(json.dumps({"type": "step", "data": step_data}))
                await websocket.send_text(json.dumps({
                    "type": "error",
                    "message": f"Branch '{branch}' does not exist. Use create=true to create it."
                }))
                return

            # Step 5/6: Handle uncommitted and untracked files
            current_step += 1
            step_data = {
                "step": current_step,
                "action": "Managing uncommitted changes",
                "status": "in_progress",
                "details": ""
            }
            await websocket.send_text(json.dumps({"type": "step", "data": step_data}))
            
            # Check if there are any changes or untracked files
            status_result = self._run_command(["git", "status", "--porcelain"], cwd=client_dir)
            status_lines = status_result["stdout"].strip().split('\n') if status_result["success"] and status_result["stdout"].strip() else []
            
            untracked_files = []
            for line in status_lines:
                if line.startswith('??'):  # Untracked files
                    untracked_files.append(line[3:])
            
            # Add untracked files to Git (especially project_config.json)
            if untracked_files:
                for file in untracked_files:
                    if file == "project_config.json":  # Always add project config
                        add_result = self._run_command(["git", "add", file], cwd=client_dir)
                        
            # Now stash all changes
            status_result2 = self._run_command(["git", "status", "--porcelain"], cwd=client_dir)
            has_changes = bool(status_result2["stdout"].strip()) if status_result2["success"] else False
            
            if has_changes:
                stash_result = self._run_command(["git", "stash", "push", "-m", f"Auto-stash before switching to {branch}"], cwd=client_dir)
                details = f"Added {len(untracked_files)} untracked files and stashed all changes"
                if not stash_result["success"]:
                    details = f"Stash failed: {stash_result['stderr']}"
            else:
                details = f"Added {len(untracked_files)} untracked files, no changes to stash"
            
            step_data.update({
                "status": "completed",
                "details": details
            })
            await websocket.send_text(json.dumps({"type": "step", "data": step_data}))

            # Step 6/7: Switch to branch
            if branch_exists or create:
                current_step += 1
                step_data = {
                    "step": current_step,
                    "action": f"Switching to branch '{branch}'",
                    "status": "in_progress",
                    "details": ""
                }
                await websocket.send_text(json.dumps({"type": "step", "data": step_data}))
                
                checkout_result = self._run_command(["git", "checkout", branch], cwd=client_dir)
                if not checkout_result["success"]:
                    step_data.update({
                        "status": "failed",
                        "details": f"Failed to switch: {checkout_result['stderr']}"
                    })
                    await websocket.send_text(json.dumps({"type": "step", "data": step_data}))
                    await websocket.send_text(json.dumps({
                        "type": "error",
                        "message": f"Failed to switch to branch '{branch}': {checkout_result['stderr']}"
                    }))
                    return
                
                step_data.update({
                    "status": "completed",
                    "details": f"Successfully switched to branch '{branch}'"
                })
                await websocket.send_text(json.dumps({"type": "step", "data": step_data}))

            # Step 7/8: Clean submodule cache
            current_step += 1
            step_data = {
                "step": current_step,
                "action": "Cleaning submodule cache",
                "status": "in_progress",
                "details": ""
            }
            await websocket.send_text(json.dumps({"type": "step", "data": step_data}))
            
            git_modules_dir = client_dir / ".git" / "modules" / "addons"
            cache_cleaned = False
            if git_modules_dir.exists():
                import shutil
                shutil.rmtree(git_modules_dir)
                cache_cleaned = True
            
            step_data.update({
                "status": "completed",
                "details": f"Submodule cache {'cleaned' if cache_cleaned else 'already clean'}"
            })
            await websocket.send_text(json.dumps({"type": "step", "data": step_data}))

            # Step 8/9: Clean addons directory
            current_step += 1
            step_data = {
                "step": current_step,
                "action": "Cleaning addons directory",
                "status": "in_progress",
                "details": ""
            }
            await websocket.send_text(json.dumps({"type": "step", "data": step_data}))
            
            addons_dir = client_dir / "addons"
            addons_cleaned = False
            if addons_dir.exists():
                import shutil
                shutil.rmtree(addons_dir)
                addons_cleaned = True
            
            # Recreate the addons directory for submodules if needed
            gitmodules_file = client_dir / ".gitmodules"
            project_config_file = client_dir / "project_config.json"
            
            should_create_addons = False
            
            # Check if we have .gitmodules with submodules
            if gitmodules_file.exists():
                with open(gitmodules_file, 'r') as f:
                    content = f.read()
                    if '[submodule' in content:
                        should_create_addons = True
            
            # Check if we have modules defined in project_config.json
            if project_config_file.exists():
                import json
                try:
                    with open(project_config_file, 'r') as f:
                        config = json.load(f)
                        if config.get('linked_modules') and len(config['linked_modules']) > 0:
                            should_create_addons = True
                except:
                    pass
            
            if should_create_addons:
                addons_dir.mkdir(exist_ok=True)
                details = f"Addons directory {'cleaned and recreated' if addons_cleaned else 'created'} (submodules detected)"
            else:
                details = f"Addons directory {'cleaned' if addons_cleaned else 'skipped'} (no submodules detected)"
            
            step_data.update({
                "status": "completed",
                "details": details
            })
            await websocket.send_text(json.dumps({"type": "step", "data": step_data}))

            # Step 9/10: Deinitialize submodules
            current_step += 1
            step_data = {
                "step": current_step,
                "action": "Deinitializing submodules",
                "status": "in_progress",
                "details": ""
            }
            await websocket.send_text(json.dumps({"type": "step", "data": step_data}))
            
            deinit_result = self._run_command(["git", "submodule", "deinit", "--all", "--force"], cwd=client_dir)
            
            step_data.update({
                "status": "completed" if deinit_result["success"] else "completed_with_warnings",
                "details": "Submodules deinitialized" if deinit_result["success"] else f"Submodules deinitialized with warnings: {deinit_result['stderr']}"
            })
            await websocket.send_text(json.dumps({"type": "step", "data": step_data}))

            # Step 10/11: Sync submodules
            current_step += 1
            step_data = {
                "step": current_step,
                "action": "Syncing submodules with .gitmodules",
                "status": "in_progress",
                "details": ""
            }
            await websocket.send_text(json.dumps({"type": "step", "data": step_data}))
            
            sync_result = self._run_command(["git", "submodule", "sync"], cwd=client_dir)
            
            step_data.update({
                "status": "completed" if sync_result["success"] else "completed_with_warnings",
                "details": "Submodules synced" if sync_result["success"] else f"Submodules synced with warnings: {sync_result['stderr']}"
            })
            await websocket.send_text(json.dumps({"type": "step", "data": step_data}))

            # Step 11/12: Initialize and update submodules
            current_step += 1
            step_data = {
                "step": current_step,
                "action": "Initializing and updating submodules",
                "status": "in_progress",
                "details": "Running git submodule update --init --recursive..."
            }
            await websocket.send_text(json.dumps({"type": "step", "data": step_data}))
            
            # Ensure addons directory exists before submodule operations
            addons_dir = client_dir / "addons"
            if not addons_dir.exists():
                addons_dir.mkdir(exist_ok=True)
                step_data.update({
                    "details": "Created missing addons directory, running git submodule update --init --recursive..."
                })
                await websocket.send_text(json.dumps({"type": "step", "data": step_data}))
            
            # Configure git for better network handling
            self._run_command(["git", "config", "http.postBuffer", "524288000"], cwd=client_dir)
            self._run_command(["git", "config", "http.lowSpeedLimit", "0"], cwd=client_dir)
            self._run_command(["git", "config", "http.lowSpeedTime", "999999"], cwd=client_dir)
            
            # Try submodule update with retry mechanism
            max_retries = 3
            for attempt in range(max_retries):
                step_data.update({
                    "details": f"Running git submodule update --init --recursive... (attempt {attempt + 1}/{max_retries})"
                })
                await websocket.send_text(json.dumps({"type": "step", "data": step_data}))
                
                submodule_result = self._run_command(["git", "submodule", "update", "--init", "--recursive", "--jobs", "1"], cwd=client_dir)
                
                if submodule_result["success"]:
                    break
                elif attempt < max_retries - 1:
                    # Wait before retry
                    import asyncio
                    await asyncio.sleep(5)
                    step_data.update({
                        "details": f"Attempt {attempt + 1} failed, retrying in 5 seconds..."
                    })
                    await websocket.send_text(json.dumps({"type": "step", "data": step_data}))
            
            # Parse submodule output to show which ones were cloned
            submodule_details = "Submodules updated"
            if submodule_result["success"] and submodule_result["stdout"]:
                cloned_count = submodule_result["stdout"].count("Submodule path")
                if cloned_count > 0:
                    submodule_details = f"Updated {cloned_count} submodules"
                # Show actual stdout for debugging
                submodule_details += f"\n\nOutput:\n{submodule_result['stdout']}"
            
            # Enhanced error reporting
            if not submodule_result["success"]:
                error_details = f"SUBMODULE UPDATE FAILED!\n\nReturn code: {submodule_result.get('return_code', 'unknown')}\n\nSTDERR:\n{submodule_result.get('stderr', 'No stderr')}\n\nSTDOUT:\n{submodule_result.get('stdout', 'No stdout')}"
                step_data.update({
                    "status": "failed",
                    "details": error_details
                })
                await websocket.send_text(json.dumps({"type": "step", "data": step_data}))
                
                # Send explicit error message that will be visible longer
                await websocket.send_text(json.dumps({
                    "type": "error",
                    "message": f"CRITICAL: Submodule update failed!\n\n{error_details}"
                }))
                return
            else:
                step_data.update({
                    "status": "completed",
                    "details": submodule_details
                })
                await websocket.send_text(json.dumps({"type": "step", "data": step_data}))

            # Step 12/13: Clean stale submodule directories
            current_step += 1
            step_data = {
                "step": current_step,
                "action": "Cleaning stale submodule directories",
                "status": "in_progress",
                "details": ""
            }
            await websocket.send_text(json.dumps({"type": "step", "data": step_data}))
            
            gitmodules_file = client_dir / ".gitmodules"
            addons_dir = client_dir / "addons"  # Redefine since we deleted it earlier
            removed_count = 0
            
            if gitmodules_file.exists() and addons_dir.exists():
                # Read defined submodules from .gitmodules
                defined_submodules = set()
                gitmodules_content = gitmodules_file.read_text()
                for line in gitmodules_content.split('\n'):
                    if line.strip().startswith('path = addons/'):
                        submodule_name = line.strip()[len('path = addons/'):].strip()
                        defined_submodules.add(submodule_name)
                
                # Remove any addons directory not in .gitmodules
                for item in addons_dir.iterdir():
                    if item.is_dir() and item.name not in defined_submodules:
                        import shutil
                        shutil.rmtree(item)
                        removed_count += 1
                        
                        # Also clean the cache for this specific submodule
                        cache_dir = client_dir / ".git" / "modules" / "addons" / item.name
                        if cache_dir.exists():
                            shutil.rmtree(cache_dir)
            
            step_data.update({
                "status": "completed",
                "details": f"Removed {removed_count} stale submodule directories"
            })
            await websocket.send_text(json.dumps({"type": "step", "data": step_data}))

            # Step 13/14: Restore linked modules
            current_step += 1
            step_data = {
                "step": current_step,
                "action": "Restoring linked modules",
                "status": "in_progress",
                "details": ""
            }
            await websocket.send_text(json.dumps({"type": "step", "data": step_data}))
            
            restored_modules = self._restore_linked_modules(client_dir, branch)
            
            step_data.update({
                "status": "completed",
                "details": f"Restored {restored_modules} linked modules for branch '{branch}'"
            })
            await websocket.send_text(json.dumps({"type": "step", "data": step_data}))

            # Final success message
            await websocket.send_text(json.dumps({
                "type": "success",
                "message": f"Successfully switched to branch '{branch}' and updated submodules",
                "previous_branch": current_branch,
                "current_branch": branch
            }))

        except Exception as e:
            await websocket.send_text(json.dumps({
                "type": "error",
                "message": str(e)
            }))

    async def _get_client_git_status(self, client: str):
        """Get Git status of client repository including sync status with remote"""
        import json
        
        if not client:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": "Client name is required"})
            )]
        
        client_dir = self.repo_path / "clients" / client
        if not client_dir.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": f"Client '{client}' not found"})
            )]
        
        try:
            # Get current branch
            current_branch_result = self._run_command(["git", "branch", "--show-current"], cwd=client_dir)
            current_branch = current_branch_result["stdout"].strip() if current_branch_result["success"] else "unknown"
            
            # Get working directory status
            status_result = self._run_command(["git", "status", "--porcelain"], cwd=client_dir)
            has_changes = bool(status_result["stdout"].strip()) if status_result["success"] else False
            
            # Get remote info
            remote_result = self._run_command(["git", "remote", "get-url", "origin"], cwd=client_dir)
            remote_url = remote_result["stdout"].strip() if remote_result["success"] else "unknown"
            
            # Fetch remote to get latest info (non-blocking)
            fetch_result = self._run_command(["git", "fetch", "origin"], cwd=client_dir)
            fetch_success = fetch_result["success"]
            
            # Get commit comparison with remote
            sync_status = "unknown"
            ahead_count = 0
            behind_count = 0
            
            if fetch_success and current_branch != "unknown":
                # Check if remote branch exists
                remote_branch_result = self._run_command(
                    ["git", "show-ref", "--verify", "--quiet", f"refs/remotes/origin/{current_branch}"], 
                    cwd=client_dir
                )
                
                if remote_branch_result["return_code"] == 0:
                    # Get ahead/behind count
                    ahead_result = self._run_command(
                        ["git", "rev-list", "--count", f"origin/{current_branch}..HEAD"], 
                        cwd=client_dir
                    )
                    behind_result = self._run_command(
                        ["git", "rev-list", "--count", f"HEAD..origin/{current_branch}"], 
                        cwd=client_dir
                    )
                    
                    if ahead_result["success"] and behind_result["success"]:
                        ahead_count = int(ahead_result["stdout"].strip())
                        behind_count = int(behind_result["stdout"].strip())
                        
                        if ahead_count == 0 and behind_count == 0:
                            sync_status = "up_to_date"
                        elif ahead_count > 0 and behind_count == 0:
                            sync_status = "ahead"
                        elif ahead_count == 0 and behind_count > 0:
                            sync_status = "behind"
                        else:
                            sync_status = "diverged"
                else:
                    sync_status = "no_remote_branch"
            
            # Get last commit info
            last_commit_result = self._run_command(
                ["git", "log", "-1", "--pretty=format:%H|%an|%ad|%s", "--date=iso"], 
                cwd=client_dir
            )
            last_commit = {}
            if last_commit_result["success"] and last_commit_result["stdout"]:
                parts = last_commit_result["stdout"].split("|", 3)
                if len(parts) == 4:
                    last_commit = {
                        "hash": parts[0][:8],
                        "author": parts[1],
                        "date": parts[2],
                        "message": parts[3]
                    }
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "client": client,
                    "current_branch": current_branch,
                    "has_uncommitted_changes": has_changes,
                    "remote_url": remote_url,
                    "sync_status": sync_status,
                    "ahead_count": ahead_count,
                    "behind_count": behind_count,
                    "last_commit": last_commit,
                    "fetch_success": fetch_success
                }, indent=2)
            )]
            
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": str(e)})
            )]

    async def _update_client_submodules(self, client: str):
        """Update Git submodules for a client repository"""
        import json
        
        if not client:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": "Client name is required"})
            )]
        
        client_dir = self.repo_path / "clients" / client
        if not client_dir.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": f"Client '{client}' not found"})
            )]
        
        try:
            # Use the existing update_client_submodules.sh script
            script_path = self.repo_path / "scripts" / "update_client_submodules.sh"
            
            result = self._run_command([str(script_path), client])
            
            if result["success"]:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "success": True,
                        "message": f"Submodules updated successfully for client '{client}'",
                        "output": result["stdout"]
                    }, indent=2)
                )]
            else:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "success": False,
                        "error": f"Failed to update submodules for client '{client}'",
                        "stderr": result["stderr"],
                        "stdout": result["stdout"]
                    }, indent=2)
                )]
                
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": str(e)})
            )]

    async def _check_submodules_status(self, client: str):
        """Check status of submodules and detect outdated ones"""
        import json
        
        if not client:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": "Client name is required"})
            )]
        
        client_dir = self.repo_path / "clients" / client
        if not client_dir.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": f"Client '{client}' not found"})
            )]
        
        try:
            submodules_status = []
            
            # Get list of submodules
            status_result = self._run_command(["git", "submodule", "status"], cwd=client_dir)
            if not status_result["success"]:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({"success": False, "error": f"Failed to get submodule status: {status_result['stderr']}"})
                )]
            
            for line in status_result["stdout"].strip().split('\n'):
                if not line.strip():
                    continue
                    
                # Parse git submodule status output
                # Format: " abcdef1234 path/to/submodule (tag or branch)"
                parts = line.strip().split(' ', 2)
                if len(parts) >= 2:
                    current_commit = parts[0].lstrip(' -+')
                    submodule_path = parts[1]
                    
                    # Get remote latest commit for this submodule
                    submodule_dir = client_dir / submodule_path
                    if submodule_dir.exists():
                        # Fetch latest from remote
                        fetch_result = self._run_command(["git", "fetch", "origin"], cwd=submodule_dir)
                        
                        # Get current branch from .gitmodules
                        gitmodules_result = self._run_command(["git", "config", "-f", ".gitmodules", f"submodule.{submodule_path}.branch"], cwd=client_dir)
                        branch = gitmodules_result["stdout"].strip() if gitmodules_result["success"] else "main"
                        
                        # Get latest commit on remote branch
                        latest_result = self._run_command(["git", "rev-parse", f"origin/{branch}"], cwd=submodule_dir)
                        latest_commit = latest_result["stdout"].strip() if latest_result["success"] else current_commit
                        
                        # Check if update is available
                        needs_update = current_commit != latest_commit
                        
                        # Get commit messages for info
                        current_msg_result = self._run_command(["git", "log", "-1", "--pretty=format:%s", current_commit], cwd=submodule_dir)
                        current_msg = current_msg_result["stdout"].strip() if current_msg_result["success"] else "Unknown"
                        
                        if needs_update:
                            latest_msg_result = self._run_command(["git", "log", "-1", "--pretty=format:%s", latest_commit], cwd=submodule_dir)
                            latest_msg = latest_msg_result["stdout"].strip() if latest_msg_result["success"] else "Unknown"
                        else:
                            latest_msg = current_msg
                        
                        submodules_status.append({
                            "path": submodule_path,
                            "current_commit": current_commit,
                            "current_message": current_msg,
                            "latest_commit": latest_commit,
                            "latest_message": latest_msg,
                            "needs_update": needs_update,
                            "branch": branch
                        })
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "submodules": submodules_status
                }, indent=2)
            )]
                
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": str(e)})
            )]

    async def _update_submodule(self, client: str, submodule_path: str):
        """Update a specific submodule to latest version"""
        import json
        
        if not client or not submodule_path:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": "Client name and submodule path are required"})
            )]
        
        client_dir = self.repo_path / "clients" / client
        if not client_dir.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": f"Client '{client}' not found"})
            )]
        
        submodule_dir = client_dir / submodule_path
        if not submodule_dir.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": f"Submodule '{submodule_path}' not found"})
            )]
        
        try:
            # Get branch from .gitmodules
            gitmodules_result = self._run_command(["git", "config", "-f", ".gitmodules", f"submodule.{submodule_path}.branch"], cwd=client_dir)
            branch = gitmodules_result["stdout"].strip() if gitmodules_result["success"] else "main"
            
            # Fetch latest changes
            fetch_result = self._run_command(["git", "fetch", "origin"], cwd=submodule_dir)
            if not fetch_result["success"]:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({"success": False, "error": f"Failed to fetch: {fetch_result['stderr']}"})
                )]
            
            # Update to latest commit on branch
            update_result = self._run_command(["git", "checkout", f"origin/{branch}"], cwd=submodule_dir)
            if not update_result["success"]:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({"success": False, "error": f"Failed to update: {update_result['stderr']}"})
                )]
            
            # Get new commit info
            commit_result = self._run_command(["git", "rev-parse", "HEAD"], cwd=submodule_dir)
            new_commit = commit_result["stdout"].strip() if commit_result["success"] else "unknown"
            
            msg_result = self._run_command(["git", "log", "-1", "--pretty=format:%s"], cwd=submodule_dir)
            commit_msg = msg_result["stdout"].strip() if msg_result["success"] else "Unknown"
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "message": f"Submodule '{submodule_path}' updated successfully",
                    "new_commit": new_commit,
                    "commit_message": commit_msg,
                    "branch": branch
                }, indent=2)
            )]
                
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": str(e)})
            )]

    async def _update_all_submodules(self, client: str):
        """Update all outdated submodules to their latest versions"""
        import json
        
        if not client:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": "Client name is required"})
            )]
        
        try:
            # First check which submodules need updates
            status_result = await self._check_submodules_status(client)
            status_data = json.loads(status_result[0].text)
            
            if not status_data["success"]:
                return status_result
            
            outdated_submodules = [s for s in status_data["submodules"] if s["needs_update"]]
            
            if not outdated_submodules:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "success": True,
                        "message": "All submodules are already up to date",
                        "updated_count": 0
                    })
                )]
            
            # Update each outdated submodule
            updated_submodules = []
            failed_submodules = []
            
            for submodule in outdated_submodules:
                update_result = await self._update_submodule(client, submodule["path"])
                update_data = json.loads(update_result[0].text)
                
                if update_data["success"]:
                    updated_submodules.append({
                        "path": submodule["path"],
                        "old_commit": submodule["current_commit"],
                        "new_commit": update_data["new_commit"],
                        "message": update_data["commit_message"]
                    })
                else:
                    failed_submodules.append({
                        "path": submodule["path"],
                        "error": update_data["error"]
                    })
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": len(failed_submodules) == 0,
                    "message": f"Updated {len(updated_submodules)} submodules" + (f", {len(failed_submodules)} failed" if failed_submodules else ""),
                    "updated_count": len(updated_submodules),
                    "failed_count": len(failed_submodules),
                    "updated_submodules": updated_submodules,
                    "failed_submodules": failed_submodules
                }, indent=2)
            )]
                
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": str(e)})
            )]

    async def _add_oca_module_to_client(self, client: str, module_key: str, branch: str = None):
        """Add an OCA module repository to a client"""
        import json
        
        if not client or not module_key:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": "Client name and module key are required"})
            )]
        
        try:
            # Use the existing add_oca_module.sh script
            script_path = self.repo_path / "scripts" / "add_oca_module.sh"
            
            # Prepare command
            cmd = [str(script_path), client, module_key]
            if branch:
                cmd.extend(["--branch", branch])
            
            result = self._run_command(cmd)
            
            if result["success"]:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "success": True,
                        "message": f"OCA module '{module_key}' added successfully to client '{client}'",
                        "output": result["stdout"]
                    }, indent=2)
                )]
            else:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "success": False,
                        "error": f"Failed to add OCA module '{module_key}' to client '{client}'",
                        "stderr": result["stderr"],
                        "stdout": result["stdout"]
                    }, indent=2)
                )]
                
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": str(e)})
            )]

    async def _add_external_repo_to_client(self, client: str, repo_url: str, repo_name: str, branch: str = None):
        """Add an external Git repository to a client"""
        import json
        
        if not client or not repo_url or not repo_name:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": "Client name, repository URL, and repository name are required"})
            )]
        
        client_dir = self.repo_path / "clients" / client
        if not client_dir.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": f"Client '{client}' not found"})
            )]
        
        try:
            addons_dir = client_dir / "addons"
            repo_dir = addons_dir / repo_name
            
            # Check if repository already exists
            if repo_dir.exists():
                return [types.TextContent(
                    type="text",
                    text=json.dumps({"success": False, "error": f"Repository '{repo_name}' already exists"})
                )]
            
            # Create addons directory if it doesn't exist
            addons_dir.mkdir(exist_ok=True)
            
            # Add as submodule
            add_cmd = ["git", "submodule", "add", repo_url, f"addons/{repo_name}"]
            if branch:
                add_cmd.extend(["-b", branch])
            
            add_result = self._run_command(add_cmd, cwd=client_dir)
            
            if not add_result["success"]:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "success": False,
                        "error": f"Failed to add repository as submodule: {add_result['stderr']}"
                    })
                )]
            
            # Initialize and update the submodule
            init_result = self._run_command(["git", "submodule", "update", "--init", f"addons/{repo_name}"], cwd=client_dir)
            
            if not init_result["success"]:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "success": False,
                        "error": f"Failed to initialize submodule: {init_result['stderr']}"
                    })
                )]
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "message": f"External repository '{repo_name}' added successfully to client '{client}'",
                    "repo_url": repo_url,
                    "branch": branch or "default"
                }, indent=2)
            )]
                
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": str(e)})
            )]

    async def _change_submodule_branch(self, client: str, submodule_path: str, new_branch: str):
        """Change the branch of an existing submodule"""
        import json
        
        if not client or not submodule_path or not new_branch:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": "Client name, submodule path, and new branch are required"})
            )]
        
        client_dir = self.repo_path / "clients" / client
        if not client_dir.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": f"Client '{client}' not found"})
            )]
        
        submodule_dir = client_dir / submodule_path
        if not submodule_dir.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": f"Submodule '{submodule_path}' not found"})
            )]
        
        try:
            # Update .gitmodules file to set new branch
            config_result = self._run_command([
                "git", "config", "-f", ".gitmodules", f"submodule.{submodule_path}.branch", new_branch
            ], cwd=client_dir)
            
            if not config_result["success"]:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "success": False,
                        "error": f"Failed to update .gitmodules: {config_result['stderr']}"
                    })
                )]
            
            # Fetch latest changes in submodule
            fetch_result = self._run_command(["git", "fetch", "origin"], cwd=submodule_dir)
            
            # Switch to new branch
            checkout_result = self._run_command(["git", "checkout", f"origin/{new_branch}"], cwd=submodule_dir)
            
            if not checkout_result["success"]:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "success": False,
                        "error": f"Failed to switch to branch '{new_branch}': {checkout_result['stderr']}"
                    })
                )]
            
            # Commit the .gitmodules change
            add_result = self._run_command(["git", "add", ".gitmodules"], cwd=client_dir)
            commit_result = self._run_command([
                "git", "commit", "-m", f"Change {submodule_path} branch to {new_branch}"
            ], cwd=client_dir)
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "message": f"Submodule '{submodule_path}' branch changed to '{new_branch}' successfully",
                    "submodule_path": submodule_path,
                    "new_branch": new_branch
                }, indent=2)
            )]
                
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": str(e)})
            )]

    async def _remove_submodule(self, client: str, submodule_path: str):
        """Remove a submodule from a client"""
        import json
        
        if not client or not submodule_path:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": "Client name and submodule path are required"})
            )]
        
        client_dir = self.repo_path / "clients" / client
        if not client_dir.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": f"Client '{client}' not found"})
            )]
        
        submodule_dir = client_dir / submodule_path
        if not submodule_dir.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": f"Submodule '{submodule_path}' not found"})
            )]
        
        try:
            # Deinitialize submodule
            deinit_result = self._run_command(["git", "submodule", "deinit", "-f", submodule_path], cwd=client_dir)
            
            # Remove from .gitmodules and index
            rm_result = self._run_command(["git", "rm", submodule_path], cwd=client_dir)
            
            if not rm_result["success"]:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "success": False,
                        "error": f"Failed to remove submodule from git: {rm_result['stderr']}"
                    })
                )]
            
            # Remove submodule directory
            import shutil
            if submodule_dir.exists():
                shutil.rmtree(submodule_dir)
            
            # Remove from .git/modules
            git_modules_dir = client_dir / ".git" / "modules" / submodule_path
            if git_modules_dir.exists():
                shutil.rmtree(git_modules_dir)
            
            # Commit the removal
            commit_result = self._run_command([
                "git", "commit", "-m", f"Remove submodule {submodule_path}"
            ], cwd=client_dir)
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "message": f"Submodule '{submodule_path}' removed successfully from client '{client}'",
                    "submodule_path": submodule_path
                }, indent=2)
            )]
                
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": str(e)})
            )]

    async def _list_available_oca_modules(self, search: str = None):
        """List all available OCA modules"""
        import json
        
        try:
            # Use the existing list_oca_modules.sh script with --json option
            script_path = self.repo_path / "scripts" / "list_oca_modules.sh"
            
            cmd = [str(script_path), "--json"]
            if search:
                cmd.extend(["--pattern", search])
            
            result = self._run_command(cmd)
            
            if result["success"]:
                # The script now returns JSON directly, just parse and return it
                try:
                    parsed_result = json.loads(result["stdout"])
                    return [types.TextContent(
                        type="text",
                        text=json.dumps(parsed_result, indent=2)
                    )]
                except json.JSONDecodeError as e:
                    return [types.TextContent(
                        type="text",
                        text=json.dumps({
                            "success": False,
                            "error": f"Failed to parse script output as JSON: {e}"
                        })
                    )]
            else:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "success": False,
                        "error": f"Failed to list OCA modules: {result['stderr']}"
                    })
                )]
                
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": str(e)})
            )]

    async def _toggle_dev_mode(self, client: str, repository: str, branch: str = None):
        """Toggle development mode for a repository"""
        import json
        
        if not client or not repository:
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": False,
                    "error": "Client and repository are required"
                })
            )]
            
        try:
            script_path = self.repo_path / "scripts" / "toggle_dev_mode.sh"
            cmd = [str(script_path), client, repository]
            if branch:
                cmd.append(branch)
            
            result = self._run_command(cmd)
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": result["success"],
                    "message": f"Dev mode toggled for {repository}" if result["success"] else "Failed to toggle dev mode",
                    "output": result.get("stdout", ""),
                    "error": result.get("stderr", "") if not result["success"] else None
                })
            )]
            
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": False,
                    "error": str(e)
                })
            )]

    async def _get_dev_status(self, client: str, branch: str = None):
        """Get development status of repositories for a client"""
        import json
        import os
        
        if not client:
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": False,
                    "error": "Client is required"
                })
            )]
            
        try:
            client_dir = self.repo_path / "clients" / client
            if not client_dir.exists():
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "success": False,
                        "error": f"Client '{client}' not found"
                    })
                )]
            
            # Read dev config file
            dev_config_path = client_dir / ".dev-config.json"
            if not dev_config_path.exists():
                # No dev config = all repositories in production mode
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "success": True,
                        "repositories": {},
                        "message": "No development repositories configured"
                    })
                )]
            
            with open(dev_config_path, 'r') as f:
                dev_config = json.load(f)
            
            # If branch not specified, try to detect current branch
            if not branch:
                # Try to get current branch from git or branch config
                try:
                    result = self._run_command(["git", "branch", "--show-current"], cwd=str(client_dir))
                    if result["success"]:
                        git_branch = result["stdout"].strip()
                        # Try to map git branch to Odoo version
                        branch_config_path = client_dir / ".odoo_branch_config"
                        if branch_config_path.exists():
                            with open(branch_config_path, 'r') as f:
                                branch_config = json.load(f)
                                branch = branch_config.get(git_branch, "18.0")
                        else:
                            branch = "18.0"
                except:
                    branch = "18.0"
            
            # Filter repositories for the specified branch
            branch_repos = {}
            for repo_name, repo_data in dev_config.get("repositories", {}).items():
                if branch in repo_data.get("branches", {}):
                    branch_repos[repo_name] = repo_data["branches"][branch]
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "branch": branch,
                    "repositories": branch_repos
                })
            )]
            
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": False,
                    "error": str(e)
                })
            )]

    async def _sync_dev_links(self, client: str, branch: str = None):
        """Synchronize symbolic links for development/production modes"""
        import json
        
        if not client:
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": False,
                    "error": "Client is required"
                })
            )]
            
        try:
            # If branch not specified, try to detect current branch
            if not branch:
                client_dir = self.repo_path / "clients" / client
                try:
                    result = self._run_command(["git", "branch", "--show-current"], cwd=str(client_dir))
                    if result["success"]:
                        git_branch = result["stdout"].strip()
                        # Try to map git branch to Odoo version
                        branch_config_path = client_dir / ".odoo_branch_config"
                        if branch_config_path.exists():
                            with open(branch_config_path, 'r') as f:
                                branch_config = json.load(f)
                                branch = branch_config.get(git_branch, "18.0")
                        else:
                            branch = "18.0"
                except:
                    branch = "18.0"
            
            script_path = self.repo_path / "scripts" / "sync_dev_links.sh"
            cmd = [str(script_path), client, branch]
            
            result = self._run_command(cmd)
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": result["success"],
                    "message": f"Links synchronized for branch {branch}" if result["success"] else "Failed to sync links",
                    "output": result.get("stdout", ""),
                    "error": result.get("stderr", "") if not result["success"] else None
                })
            )]
            
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": False,
                    "error": str(e)
                })
            )]

    async def _rename_dev_branch(self, client: str, repository: str, new_branch_name: str, current_branch: str = None):
        """Rename a development branch in a repository"""
        import json
        
        if not client or not repository or not new_branch_name:
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": False,
                    "error": "Client, repository, and new branch name are required"
                })
            )]
            
        try:
            script_path = self.repo_path / "scripts" / "rename_dev_branch.sh"
            cmd = [str(script_path), client, repository, new_branch_name]
            if current_branch:
                cmd.append(current_branch)
            
            result = self._run_command(cmd)
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": result["success"],
                    "message": f"Development branch renamed to {new_branch_name}" if result["success"] else "Failed to rename dev branch",
                    "output": result.get("stdout", ""),
                    "error": result.get("stderr", "") if not result["success"] else None
                })
            )]
            
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": False,
                    "error": str(e)
                })
            )]

    async def _get_client_diff(self, client: str, branch: str = None):
        """Get diff of uncommitted changes in client repository"""
        import json
        
        if not client:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": "Client name is required"})
            )]
        
        client_dir = self.repo_path / "clients" / client
        if not client_dir.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": f"Client '{client}' not found"})
            )]
        
        try:
            # Get diff of uncommitted changes (both staged and unstaged)
            diff_result = self._run_command(["git", "diff", "HEAD"], cwd=client_dir)
            
            if not diff_result["success"]:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({"success": False, "error": "Failed to get git diff"})
                )]
            
            diff_content = diff_result["stdout"]
            if not diff_content.strip():
                diff_content = "No uncommitted changes found"
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "client": client,
                    "branch": branch,
                    "diff": diff_content
                }, indent=2)
            )]
            
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({"success": False, "error": str(e)})
            )]

    def _get_branch_suffix(self, branch_name: str) -> str:
        """Get suffix for branch-specific container names"""
        if branch_name.startswith("staging-"):
            return "-staging"
        elif branch_name.startswith("dev-"):
            return "-dev"
        elif branch_name in ["18.0", "17.0", "16.0", "master", "main"]:
            return ""  # Production branches don't get suffix
        else:
            return f"-{branch_name.replace('/', '-')}"

    async def _get_build_history(self, client: str, limit: int = 20):
        """Get Docker build history and image versions for a client"""
        import json
        
        if not client:
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": "Client name is required"}, indent=2)
            )]
        
        client_path = self.repo_path / "clients" / client
        if not client_path.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": f"Client '{client}' not found"}, indent=2)
            )]
        
        try:
            builds = []
            
            # Get all Docker images for this client
            images_result = self._run_command([
                "docker", "images", "--format", "{{.Repository}}:{{.Tag}}\t{{.CreatedAt}}\t{{.Size}}\t{{.ID}}",
                "--filter", f"reference=odoo-alusage-{client}*"
            ])
            
            if images_result["success"]:
                image_lines = images_result["stdout"].strip().split("\n")
                for line in image_lines:
                    if not line.strip():
                        continue
                    
                    parts = line.split("\t")
                    if len(parts) >= 4:
                        repo_tag, created_at, size, image_id = parts[:4]
                        repo, tag = repo_tag.split(":", 1) if ":" in repo_tag else (repo_tag, "latest")
                        
                        # Extract branch name from tag
                        branch_name = tag
                        # Remove timestamp and hash suffixes to get base branch
                        if "-202" in tag:  # Remove timestamp
                            branch_name = tag.split("-202")[0]
                        elif tag.endswith("-latest"):
                            branch_name = tag[:-7]  # Remove -latest
                        elif len(tag.split("-")) > 1 and len(tag.split("-")[-1]) == 7:  # Remove hash
                            branch_name = "-".join(tag.split("-")[:-1])
                        
                        # Get Git info for this branch if available
                        git_info = self._get_git_info_for_branch(client_path, branch_name)
                        
                        build = {
                            "id": f"build_{image_id[:12]}",
                            "image_tag": tag,
                            "branch": branch_name,
                            "created_at": created_at,
                            "size": size,
                            "image_id": image_id[:12],
                            "status": "success",  # Si l'image existe, le build a réussi
                            "type": "docker",
                            "duration": "Unknown",
                            "git_hash": git_info.get("hash", "unknown"),
                            "git_message": git_info.get("message", "Unknown commit"),
                            "author": git_info.get("author", "Unknown")
                        }
                        builds.append(build)
            
            # Sort by creation date (most recent first)
            builds = sorted(builds, key=lambda x: x["created_at"], reverse=True)
            
            # Limit results
            builds = builds[:limit]
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "builds": builds,
                    "total_images": len(builds)
                }, indent=2)
            )]
            
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": False,
                    "error": f"Error getting build history: {str(e)}"
                }, indent=2)
            )]
    
    def _get_git_info_for_branch(self, client_path, branch_name):
        """Get Git information for a specific branch"""
        try:
            # Switch to the branch temporarily to get its info
            result = self._run_command([
                "git", "log", "-1", "--format=%H|%an|%s|%ad", "--date=iso"
            ], cwd=client_path)
            
            if result["success"] and result["stdout"]:
                parts = result["stdout"].strip().split("|")
                if len(parts) >= 4:
                    return {
                        "hash": parts[0][:8],
                        "author": parts[1],
                        "message": parts[2],
                        "date": parts[3]
                    }
        except:
            pass
        
        return {"hash": "unknown", "author": "Unknown", "message": "Unknown commit", "date": "Unknown"}

    async def _get_traefik_config(self):
        """Get current Traefik configuration"""
        try:
            config_file = self.repo_path / "config" / "traefik_config.json"
            
            if config_file.exists():
                with open(config_file, 'r') as f:
                    config = json.load(f)
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "domain": config.get("domain", "local"),
                        "protocol": config.get("protocol", "http"),
                        "url_pattern": config.get("url_pattern", "{protocol}://{branch}.{client}.{domain}")
                    }, indent=2)
                )]
            else:
                # Return default configuration
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "domain": "local",
                        "protocol": "http",
                        "url_pattern": "{protocol}://{branch}.{client}.{domain}"
                    }, indent=2)
                )]
        except Exception as e:
            logger.error(f"Error getting Traefik config: {e}")
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": False,
                    "error": str(e)
                }, indent=2)
            )]

    async def _set_traefik_config(self, domain: str, protocol: str = "http"):
        """Set Traefik configuration"""
        try:
            config_dir = self.repo_path / "config"
            config_dir.mkdir(exist_ok=True)
            config_file = config_dir / "traefik_config.json"
            
            # Load existing config or create new one
            if config_file.exists():
                with open(config_file, 'r') as f:
                    config = json.load(f)
            else:
                config = {}
            
            # Update configuration
            config.update({
                "domain": domain,
                "protocol": protocol,
                "description": "Configuration du domaine Traefik pour les URLs des branches",
                "examples": {
                    "local": f"{protocol}://18.0.testclient.local (nécessite *.local dans /etc/hosts)",
                    "localhost": f"{protocol}://18.0.testclient.localhost (peut fonctionner directement)",
                    "dev": f"{protocol}://18.0.testclient.dev (nécessite *.dev dans /etc/hosts)"
                },
                "hosts_file_example": f"127.0.0.1 *.{domain}",
                "url_pattern": f"{protocol}://{{branch}}.{{client}}.{domain}"
            })
            
            # Save configuration
            with open(config_file, 'w') as f:
                json.dump(config, f, indent=2)
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "message": f"Traefik configuration updated: domain={domain}, protocol={protocol}",
                    "config": {
                        "domain": domain,
                        "protocol": protocol,
                        "url_pattern": f"{protocol}://{{branch}}.{{client}}.{domain}"
                    }
                }, indent=2)
            )]
        except Exception as e:
            logger.error(f"Error setting Traefik config: {e}")
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": False,
                    "error": str(e)
                }, indent=2)
            )]

    async def _build_cloudron_app(self, client: str, force: bool = False):
        """Build Cloudron application for a client (production branches only)"""
        if not client:
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": "Client name is required"}, indent=2)
            )]
        
        client_path = self.repo_path / "clients" / client
        if not client_path.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": f"Client '{client}' not found"}, indent=2)
            )]
        
        # Check if Cloudron is enabled for this client
        project_config_path = client_path / "project_config.json"
        if not project_config_path.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": "project_config.json not found for client"}, indent=2)
            )]
        
        try:
            with open(project_config_path, 'r') as f:
                project_config = json.load(f)
            
            cloudron_enabled = project_config.get("publication", {}).get("providers", {}).get("cloudron", {}).get("enabled", False)
            if not cloudron_enabled:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({"error": "Cloudron publication not enabled for this client"}, indent=2)
                )]
            
            # Check if we're on a production branch
            result = self._run_command(["git", "branch", "--show-current"], cwd=client_path)
            if not result["success"]:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({"error": "Failed to get current branch"}, indent=2)
                )]
            
            current_branch = result["stdout"].strip()
            production_branches = project_config.get("publication", {}).get("allowed_branches", ["18.0", "master", "main"])
            
            if current_branch not in production_branches:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "error": f"Cloudron publication only allowed on production branches: {production_branches}. Current branch: {current_branch}"
                    }, indent=2)
                )]
            
            # Execute Cloudron build script from cloudron directory
            cloudron_build_script = client_path / "cloudron" / "build.sh"
            cloudron_dir = client_path / "cloudron"
            
            if not cloudron_build_script.exists():
                return [types.TextContent(
                    type="text",
                    text=json.dumps({"error": "Cloudron build.sh script not found"}, indent=2)
                )]
            
            if not cloudron_dir.exists():
                return [types.TextContent(
                    type="text",
                    text=json.dumps({"error": "Cloudron directory not found"}, indent=2)
                )]
            
            cmd = ["./build.sh", "--push"]  # Always push when building from MCP
            if force:
                cmd.append("--force")
            
            result = self._run_command(cmd, cwd=cloudron_dir)
            
            # Check if the build was successful by looking for success indicators
            # Docker build can have warnings on stderr but still succeed
            build_successful = (
                result["success"] or 
                "Successfully built" in result["stdout"] or 
                "✨ Image construite avec succès" in result["stdout"]
            )
            
            if build_successful:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "success": True,
                        "client": client,
                        "branch": current_branch,
                        "message": "Cloudron application built successfully",
                        "output": result["stdout"],
                        "warnings": result["stderr"] if result["stderr"] else None
                    }, indent=2)
                )]
            else:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "error": f"Failed to build Cloudron application: {result['stderr']}",
                        "output": result["stdout"]
                    }, indent=2)
                )]
        
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": f"Error building Cloudron app: {str(e)}"}, indent=2)
            )]

    async def _deploy_cloudron_app(self, client: str, action: str = "install"):
        """Deploy Cloudron application for a client"""
        if not client:
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": "Client name is required"}, indent=2)
            )]
        
        client_path = self.repo_path / "clients" / client
        if not client_path.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": f"Client '{client}' not found"}, indent=2)
            )]
        
        # Check if Cloudron is enabled
        project_config_path = client_path / "project_config.json"
        if not project_config_path.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": "project_config.json not found for client"}, indent=2)
            )]
        
        try:
            with open(project_config_path, 'r') as f:
                project_config = json.load(f)
            
            cloudron_enabled = project_config.get("publication", {}).get("providers", {}).get("cloudron", {}).get("enabled", False)
            if not cloudron_enabled:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({"error": "Cloudron publication not enabled for this client"}, indent=2)
                )]
            
            # Check production branch
            result = self._run_command(["git", "branch", "--show-current"], cwd=client_path)
            if not result["success"]:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({"error": "Failed to get current branch"}, indent=2)
                )]
            
            current_branch = result["stdout"].strip()
            production_branches = project_config.get("publication", {}).get("allowed_branches", ["18.0", "master", "main"])
            
            if current_branch not in production_branches:
                return [types.TextContent(
                    type="text",
                    text=json.dumps({
                        "error": f"Cloudron deployment only allowed on production branches: {production_branches}. Current branch: {current_branch}"
                    }, indent=2)
                )]
            
            # Check if Cloudron deploy script exists
            cloudron_deploy_script = client_path / "cloudron" / "deploy.sh"
            cloudron_dir = client_path / "cloudron"
            
            if not cloudron_deploy_script.exists():
                return [types.TextContent(
                    type="text",
                    text=json.dumps({"error": "Cloudron deploy.sh script not found"}, indent=2)
                )]
            
            if not cloudron_dir.exists():
                return [types.TextContent(
                    type="text",
                    text=json.dumps({"error": "Cloudron directory not found"}, indent=2)
                )]
            
            # Cloudron CLI requires interactive terminal - provide instructions
            interactive_script = self.repo_path / "deploy_cloudron_interactive.sh"
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "error": "Cloudron deployment requires interactive terminal",
                    "solution": f"Please run this command in a terminal:\n\n./deploy_cloudron_interactive.sh {client}\n\nor manually:\n\ncd {cloudron_dir} && ./deploy.sh {action}",
                    "client": client,
                    "branch": current_branch,
                    "action": action,
                    "cloudron_directory": str(cloudron_dir),
                    "interactive_script": str(interactive_script)
                }, indent=2)
            )]
        
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": f"Error deploying Cloudron app: {str(e)}"}, indent=2)
            )]

    async def _get_cloudron_config(self, client: str):
        """Get Cloudron configuration for a client"""
        if not client:
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": "Client name is required"}, indent=2)
            )]
        
        client_path = self.repo_path / "clients" / client
        if not client_path.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": f"Client '{client}' not found"}, indent=2)
            )]
        
        cloudron_config_path = client_path / "cloudron" / "cloudron_config.json"
        if not cloudron_config_path.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": "Cloudron configuration not found for this client"}, indent=2)
            )]
        
        try:
            with open(cloudron_config_path, 'r') as f:
                config = json.load(f)
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "client": client,
                    "config": config
                }, indent=2)
            )]
        
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": f"Error reading Cloudron config: {str(e)}"}, indent=2)
            )]

    async def _update_cloudron_config(self, client: str, config: dict):
        """Update Cloudron configuration for a client"""
        if not client:
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": "Client name is required"}, indent=2)
            )]
        
        if not config:
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": "Configuration object is required"}, indent=2)
            )]
        
        client_path = self.repo_path / "clients" / client
        if not client_path.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": f"Client '{client}' not found"}, indent=2)
            )]
        
        cloudron_config_path = client_path / "cloudron" / "cloudron_config.json"
        if not cloudron_config_path.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": "Cloudron configuration not found for this client"}, indent=2)
            )]
        
        try:
            # Load existing config
            with open(cloudron_config_path, 'r') as f:
                existing_config = json.load(f)
            
            # Update cloudron section
            if "cloudron" in existing_config:
                existing_config["cloudron"].update(config)
            else:
                existing_config["cloudron"] = config
            
            # Update metadata
            existing_config["metadata"]["last_updated"] = f"{asyncio.get_event_loop().time():.3f}"
            
            # Save updated config
            with open(cloudron_config_path, 'w') as f:
                json.dump(existing_config, f, indent=2)
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "client": client,
                    "message": "Cloudron configuration updated successfully",
                    "config": existing_config
                }, indent=2)
            )]
        
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": f"Error updating Cloudron config: {str(e)}"}, indent=2)
            )]

    async def _get_cloudron_status(self, client: str):
        """Get status of Cloudron deployment for a client"""
        if not client:
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": "Client name is required"}, indent=2)
            )]
        
        client_path = self.repo_path / "clients" / client
        if not client_path.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": f"Client '{client}' not found"}, indent=2)
            )]
        
        cloudron_config_path = client_path / "cloudron" / "cloudron_config.json"
        if not cloudron_config_path.exists():
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "client": client,
                    "status": "not_configured",
                    "message": "Cloudron not configured for this client"
                }, indent=2)
            )]
        
        try:
            with open(cloudron_config_path, 'r') as f:
                config = json.load(f)
            
            # Get current branch
            result = self._run_command(["git", "branch", "--show-current"], cwd=client_path)
            current_branch = result["stdout"].strip() if result["success"] else "unknown"
            
            # Check if we're on a production branch
            production_branches = ["18.0", "master", "main"]  # From project config if available
            
            # Try to get Cloudron app status via CLI (if available)
            cloudron_server = config.get("cloudron", {}).get("server", "")
            app_id = f"{client}.odoo.{config.get('cloudron', {}).get('domain', 'localhost')}"
            
            # Simple status check
            status_info = {
                "client": client,
                "current_branch": current_branch,
                "is_production_branch": current_branch in production_branches,
                "cloudron_enabled": config.get("enabled", False),
                "cloudron_server": cloudron_server,
                "app_id": app_id,
                "last_updated": config.get("metadata", {}).get("last_updated", "unknown")
            }
            
            return [types.TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "status": status_info
                }, indent=2)
            )]
        
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=json.dumps({"error": f"Error getting Cloudron status: {str(e)}"}, indent=2)
            )]


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
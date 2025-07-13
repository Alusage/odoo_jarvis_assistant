#!/usr/bin/env python3
"""
MCP Server for Odoo Client Repository Generator

This server exposes all Odoo client management tools via the MCP protocol.
"""

import asyncio
import subprocess
import os
import sys
import logging
from pathlib import Path
from typing import Any, Dict, List, Optional

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


class OdooClientMCPServer:
    """MCP Server for Odoo Client Repository Generator"""
    
    def __init__(self, repo_path: str):
        self.repo_path = Path(repo_path).resolve()
        self.server = Server("odoo-client-generator")
        
        if not self.repo_path.exists():
            raise ValueError(f"Repository path '{repo_path}' does not exist")
        
        if not (self.repo_path / "Makefile").exists():
            raise ValueError(f"Makefile not found in '{repo_path}'. Not a valid repository.")
        
        self._setup_handlers()
    
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
            else:
                raise ValueError(f"Unknown tool: {name}")
        
        logger.info("✅ MCP handlers configured")
    
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


async def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Corrected MCP Server for Odoo Client Generator")
    parser.add_argument("repo_path", nargs="?", default=os.getcwd(), 
                       help="Path to the Odoo client generator repository")
    
    args = parser.parse_args()
    
    logger.info(f"🚀 Starting corrected MCP server for {args.repo_path}")
    
    try:
        server = OdooClientMCPServer(args.repo_path)
        
        logger.info("🔌 Starting MCP server with stdio...")
        
        # Run the MCP server using stdio
        async with stdio_server() as (read_stream, write_stream):
            await server.server.run(
                read_stream,
                write_stream,
                server.server.create_initialization_options()
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
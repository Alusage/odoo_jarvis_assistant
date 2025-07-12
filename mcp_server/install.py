#!/usr/bin/env python3
"""
Installation script for Odoo Client MCP Server
"""

import json
import subprocess
import sys
from pathlib import Path

def install_dependencies():
    """Install Python dependencies"""
    print("📦 Installing dependencies...")
    try:
        subprocess.run([sys.executable, "-m", "pip", "install", "-r", "requirements.txt"], 
                      check=True, capture_output=True)
        print("✅ Dependencies installed")
        return True
    except subprocess.CalledProcessError as e:
        print(f"❌ Failed to install dependencies: {e}")
        return False

def update_claude_config():
    """Update Claude Desktop configuration"""
    # Determine config path
    home = Path.home()
    if sys.platform == "darwin":  # macOS
        config_path = home / "Library" / "Application Support" / "Claude" / "claude_desktop_config.json"
    elif sys.platform == "win32":  # Windows
        config_path = Path(os.environ["APPDATA"]) / "Claude" / "claude_desktop_config.json"
    else:  # Linux
        config_path = home / ".config" / "Claude" / "claude_desktop_config.json"
    
    # Create config directory if it doesn't exist
    config_path.parent.mkdir(parents=True, exist_ok=True)
    
    # Get current paths
    server_path = Path(__file__).parent / "mcp_server.py"
    repo_path = Path(__file__).parent.parent
    
    # Create or update config
    config = {}
    if config_path.exists():
        try:
            config = json.loads(config_path.read_text())
        except json.JSONDecodeError:
            config = {}
    
    if "mcpServers" not in config:
        config["mcpServers"] = {}
    
    config["mcpServers"]["odoo-client-generator"] = {
        "command": "python3",
        "args": [str(server_path), str(repo_path)]
    }
    
    # Write config
    config_path.write_text(json.dumps(config, indent=2))
    print(f"✅ Claude Desktop config updated: {config_path}")
    
    return True

def main():
    """Main installation function"""
    print("🚀 Installing Odoo Client MCP Server...")
    print("=" * 40)
    
    # Install dependencies
    if not install_dependencies():
        return False
    
    # Update Claude config
    if not update_claude_config():
        return False
    
    print("=" * 40)
    print("🎉 Installation completed!")
    print("")
    print("📋 Next steps:")
    print("1. Restart Claude Desktop completely")
    print("2. You should see 'odoo-client-generator' server connected")
    print("3. Test with: 'Liste mes clients Odoo existants'")
    print("")
    print("🔧 Configuration:")
    server_path = Path(__file__).parent / "mcp_server.py"
    repo_path = Path(__file__).parent.parent
    print(f"   Server: {server_path}")
    print(f"   Repository: {repo_path}")
    
    return True

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
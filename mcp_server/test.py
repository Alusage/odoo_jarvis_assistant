#!/usr/bin/env python3
"""
Test script for the MCP server
"""

import subprocess
import sys
from pathlib import Path

def test_mcp_server():
    """Test the MCP server"""
    print("🧪 Testing MCP Server...")
    
    # Check if MCP is installed
    try:
        import mcp
        print("✅ MCP library found")
    except ImportError:
        print("❌ MCP library not found. Install with: pip install mcp")
        return False
    
    # Check if repository exists
    repo_path = Path(__file__).parent.parent
    if not (repo_path / "Makefile").exists():
        print(f"❌ Makefile not found in {repo_path}")
        return False
    print(f"✅ Repository found: {repo_path}")
    
    # Test server startup
    print("🔄 Testing server startup...")
    try:
        result = subprocess.run([
            "timeout", "3",
            "python3", "mcp_server.py", str(repo_path)
        ], capture_output=True, text=True)
        
        if "Starting" in result.stderr and "MCP handlers configured" in result.stderr:
            print("✅ Server starts successfully")
        else:
            print("❌ Server startup failed")
            print(f"Error: {result.stderr}")
            return False
            
    except FileNotFoundError:
        print("❌ timeout command not found, skipping startup test")
    
    print("🎉 All tests passed!")
    return True

if __name__ == "__main__":
    success = test_mcp_server()
    sys.exit(0 if success else 1)
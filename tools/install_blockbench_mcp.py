#!/usr/bin/env python3
"""
tools/install_blockbench_mcp.py - Automated installer for Blockbench MCP Server plugin.

Downloads and installs mcp.js into the local user's Blockbench plugins directory
across Windows, Linux, and macOS.
"""

import os
import sys
import urllib.request
from pathlib import Path

MCP_PLUGIN_URL = "https://jasonjgardner.github.io/blockbench-mcp-plugin/mcp.js"


def get_blockbench_plugins_dir() -> Path:
    if sys.platform.startswith("win"):
        appdata = os.environ.get("APPDATA")
        if appdata:
            return Path(appdata) / "Blockbench" / "plugins"
        return Path.home() / "AppData" / "Roaming" / "Blockbench" / "plugins"
    elif sys.platform.startswith("darwin"):
        return Path.home() / "Library" / "Application Support" / "Blockbench" / "plugins"
    else:
        # Linux (standard config or Flatpak)
        flatpak_path = Path.home() / ".var" / "app" / "net.blockbench.Blockbench" / "config" / "Blockbench" / "plugins"
        if flatpak_path.parent.exists():
            return flatpak_path
        return Path.home() / ".config" / "Blockbench" / "plugins"


def main():
    print("=" * 60)
    print(" Blockbench MCP Plugin Installer")
    print("=" * 60)

    plugins_dir = get_blockbench_plugins_dir()
    print(f"Target directory: {plugins_dir}")

    try:
        plugins_dir.mkdir(parents=True, exist_ok=True)
    except Exception as e:
        print(f"[ERROR] Failed to create plugins directory: {e}")
        sys.exit(1)

    dest_file = plugins_dir / "mcp.js"
    print(f"Downloading {MCP_PLUGIN_URL} -> {dest_file}...")

    try:
        req = urllib.request.Request(
            MCP_PLUGIN_URL,
            headers={"User-Agent": "CubeSiege-DevSetup/1.0"}
        )
        with urllib.request.urlopen(req, timeout=15) as resp:
            content = resp.read()
            dest_file.write_bytes(content)
        print(f"[SUCCESS] Plugin installed ({len(content)} bytes).")
    except Exception as e:
        print(f"[ERROR] Failed to download plugin: {e}")
        print("Alternative: download manually from https://jasonjgardner.github.io/blockbench-mcp-plugin/mcp.js")
        sys.exit(1)

    print("\nNext step to activate in Blockbench:")
    print("  1. Launch Blockbench desktop application.")
    print("  2. Open File -> Plugins -> Installed.")
    print(f"  3. Click 'Load Plugin from File' and select: {dest_file}")
    print("  4. Verify the server is running on http://localhost:3000/bb-mcp")
    print("=" * 60)


if __name__ == "__main__":
    main()

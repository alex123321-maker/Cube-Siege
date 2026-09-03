#!/usr/bin/env python3
"""
tools/gdmcp.py - Companion CLI for Godot MCP Native progressive discovery.
Enables fast queries (doctor, scene tree, project info, tools) without overwhelming
model context with hundreds of tool schemas.
"""

import argparse
import json
import os
import subprocess
import sys
from typing import Any, Dict, Optional
import urllib.request
import urllib.error

DEFAULT_URL = os.environ.get("GODOT_MCP_URL", "http://localhost:9080")
DEFAULT_TOKEN = os.environ.get("GODOT_MCP_TOKEN", "")


def send_cli_request(route: str, method: str = "GET", body: Optional[Dict[str, Any]] = None, timeout: int = 10) -> Dict[str, Any]:
    url = f"{DEFAULT_URL.rstrip('/')}{route}"
    headers = {
        "X-GDMCP-API-Version": "1",
        "Accept": "application/json"
    }
    if DEFAULT_TOKEN:
        headers["Authorization"] = f"Bearer {DEFAULT_TOKEN}"

    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"

    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            resp_data = response.read().decode("utf-8")
            if resp_data:
                return json.loads(resp_data)
            return {"status": "ok"}
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        return {"error": f"HTTP {e.code}: {e.reason}", "detail": err_body}
    except urllib.error.URLError as e:
        return {"error": f"Connection failed: {e.reason}", "reachable": False}
    except Exception as e:
        return {"error": str(e)}


def send_mcp_rpc(method: str, params: Optional[Dict[str, Any]] = None, timeout: int = 10) -> Dict[str, Any]:
    payload = {
        "jsonrpc": "2.0",
        "method": method,
        "params": params or {},
        "id": 1
    }
    return send_cli_request("/mcp", method="POST", body=payload, timeout=timeout)


def main():
    parser = argparse.ArgumentParser(description="Godot MCP CLI companion for Cube Siege")
    parser.add_argument("--url", default=DEFAULT_URL, help="Base URL of Godot MCP server")
    subparsers = parser.add_subparsers(dest="command", help="Available subcommands")

    # doctor
    subparsers.add_parser("doctor", help="Check Godot MCP connection and project health")

    # catalog
    subparsers.add_parser("catalog", help="List compact summary of all registered tools")

    # search
    search_parser = subparsers.add_parser("search", help="Search available tools")
    search_parser.add_argument("query", help="Search query")
    search_parser.add_argument("--limit", type=int, default=10, help="Max results")

    # schema
    schema_parser = subparsers.add_parser("schema", help="Get schema for a specific tool")
    schema_parser.add_argument("tool_name", help="Name of the tool")

    # project
    subparsers.add_parser("project-info", help="Get project information")

    # scene tree
    tree_parser = subparsers.add_parser("tree", help="Inspect current scene tree")
    tree_parser.add_argument("--depth", type=int, default=4, help="Tree inspection depth")

    # call
    call_parser = subparsers.add_parser("call", help="Call an MCP tool by name")
    call_parser.add_argument("tool_name", help="Name of tool to execute")
    call_parser.add_argument("--args", default="{}", help="JSON string of arguments")

    args = parser.parse_args()

    # Check for native gdmcp binary first if invoked with direct passthrough
    script_dir = os.path.dirname(os.path.abspath(__file__))
    gdmcp_bin = os.path.join(script_dir, "bin", "gdmcp.exe" if os.name == "nt" else "gdmcp")

    if not args.command:
        parser.print_help()
        sys.exit(0)

    if args.command == "doctor":
        res = send_cli_request("/cli/v1/doctor")
        print(json.dumps(res, indent=2, ensure_ascii=False))
    elif args.command == "catalog":
        res = send_cli_request("/cli/v1/catalog")
        print(json.dumps(res, indent=2, ensure_ascii=False))
    elif args.command == "search":
        res = send_cli_request(f"/cli/v1/tools/search?q={urllib.parse.quote(args.query)}&limit={args.limit}")
        print(json.dumps(res, indent=2, ensure_ascii=False))
    elif args.command == "schema":
        res = send_cli_request(f"/cli/v1/tools/{args.tool_name}")
        print(json.dumps(res, indent=2, ensure_ascii=False))
    elif args.command == "project-info":
        res = send_cli_request("/cli/v1/tools/get_project_info/execute", method="POST", body={"arguments": {}})
        print(json.dumps(res, indent=2, ensure_ascii=False))
    elif args.command == "tree":
        res = send_cli_request("/cli/v1/tools/get_scene_tree/execute", method="POST", body={"arguments": {"max_depth": args.depth}})
        print(json.dumps(res, indent=2, ensure_ascii=False))
    elif args.command == "call":
        try:
            call_args = json.loads(args.args)
        except Exception as e:
            print(json.dumps({"error": f"Invalid JSON in --args: {e}"}))
            sys.exit(1)
        res = send_cli_request(f"/cli/v1/tools/{args.tool_name}/execute", method="POST", body={"arguments": call_args})
        print(json.dumps(res, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()

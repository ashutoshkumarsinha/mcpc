#!/usr/bin/env python3
"""Minimal stdio MCP server for exercising the mcpc Swift client."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone

from mcp.server.fastmcp import FastMCP

mcp = FastMCP("MCPC Test Server")


@mcp.tool()
async def echo(message: str) -> str:
    """Return the input message unchanged."""
    return message


@mcp.tool()
async def add(a: int, b: int) -> str:
    """Add two integers and return the sum as text."""
    return str(a + b)


@mcp.tool()
async def server_info() -> str:
    """Return a JSON snapshot of this test server's capabilities."""
    return json.dumps(
        {
            "name": "MCPC Test Server",
            "tools": ["echo", "add", "server_info"],
            "resources": ["test://info", "test://time/utc"],
            "prompts": ["greet"],
        },
        indent=2,
    )


@mcp.resource("test://info")
def test_info() -> str:
    """Static metadata resource for read-resource tests."""
    return json.dumps({"purpose": "mcpc integration testing", "ok": True})


@mcp.resource("test://time/{zone}")
def test_time(zone: str) -> str:
    """Dynamic resource template; use zone 'utc' for a UTC timestamp."""
    now = datetime.now(timezone.utc)
    if zone.lower() == "utc":
        return now.isoformat()
    return now.astimezone().isoformat()


@mcp.prompt()
def greet(name: str, tone: str = "friendly") -> str:
    """Prompt template that asks the model to greet someone."""
    return f"Write a {tone} greeting for {name}."


def main() -> None:
    parser = argparse.ArgumentParser(description="MCPC test MCP server")
    parser.add_argument(
        "--transport",
        choices=("stdio", "sse"),
        default="stdio",
        help="Transport protocol (default: stdio)",
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()

    if args.transport == "sse":
        mcp.settings.host = args.host
        mcp.settings.port = args.port

    mcp.run(transport=args.transport)


if __name__ == "__main__":
    main()

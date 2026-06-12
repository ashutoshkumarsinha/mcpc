MCP Client — macOS MCP Client
==============================

Install
-------
1. Drag MCP Client.app to the Applications folder.
2. Copy config.toml.example to a folder where you will run MCP Client (for example ~/mcpc/config.toml).
3. Edit config.toml with your MCP server definitions.
4. Launch MCP Client from Applications.

Configuration
-------------
MCPC reads config.toml from the current working directory, or set MCPC_CONFIG to an absolute path.

CLI
---
The mcpc command-line tool is available from the project repository (make install) or swift build.

See docs/USER_GUIDE.md in the MCPC repository for full configuration examples.

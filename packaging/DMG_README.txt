MCP Client — macOS MCP Client
==============================

Install
-------
1. Drag MCP Client.app to the Applications folder.
2. Launch MCP Client from Applications.
3. On first launch, the app creates ~/.mcpc/ with config.toml and mcpc.log.
4. Add your MCP servers to ~/.mcpc/config.toml (or import from Cursor in the app).

Configuration
-------------
MCP Client stores config and logs in ~/.mcpc/:

  ~/.mcpc/config.toml   — server definitions
  ~/.mcpc/mcpc.log      — application logs

Override with MCPC_CONFIG or choose another file in the app sidebar.

CLI
---
The mcpc command-line tool is available from the project repository (make install) or swift build.

See docs/USER_GUIDE.md in the MCPC repository for full configuration examples.

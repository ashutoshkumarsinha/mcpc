import XCTest
@testable import MCPC

final class CursorMCPConfigImporterTests: XCTestCase {
    func testParsesStdioServer() throws {
        let json = """
        {
          "mcpServers": {
            "local": {
              "command": "node",
              "args": ["server.js"],
              "cwd": "/tmp/project",
              "env": { "FOO": "bar" }
            }
          }
        }
        """
        let preview = try CursorMCPConfigImporter.parse(json: json)
        XCTAssertEqual(preview.servers.count, 1)
        let server = try XCTUnwrap(preview.servers.first)
        XCTAssertEqual(server.name, "local")
        XCTAssertEqual(server.transport, .stdio)
        XCTAssertEqual(server.command, "node")
        XCTAssertEqual(server.args, ["server.js"])
        XCTAssertEqual(server.workingDirectory, "/tmp/project")
        XCTAssertEqual(server.env["FOO"], "bar")
    }

    func testParsesSSEServerFromURL() throws {
        let json = """
        {
          "mcpServers": {
            "remote": {
              "url": "http://127.0.0.1:8765/sse"
            }
          }
        }
        """
        let preview = try CursorMCPConfigImporter.parse(json: json)
        let server = try XCTUnwrap(preview.servers.first)
        XCTAssertEqual(server.transport, .sse)
        XCTAssertEqual(server.url, "http://127.0.0.1:8765/sse")
    }

    func testParsesStreamableHTTPServer() throws {
        let json = """
        {
          "mcpServers": {
            "remote": {
              "type": "streamable-http",
              "url": "http://127.0.0.1:8080/mcp"
            }
          }
        }
        """
        let preview = try CursorMCPConfigImporter.parse(json: json)
        let server = try XCTUnwrap(preview.servers.first)
        XCTAssertEqual(server.transport, .streamableHTTP)
    }

    func testMergeSkipExisting() {
        let base = AppConfig(
            app: AppSettings(),
            client: ClientSettings(),
            servers: [ServerConfig(name: "keep", transport: .stdio, command: "old")]
        )
        let imported = [
            ServerConfig(name: "keep", transport: .stdio, command: "new"),
            ServerConfig(name: "added", transport: .stdio, command: "echo"),
        ]
        let merged = CursorMCPConfigImporter.merge(imported: imported, into: base, onConflict: .skip)
        XCTAssertEqual(merged.servers.count, 2)
        XCTAssertEqual(merged.servers.first(where: { $0.name == "keep" })?.command, "old")
    }

    func testMissingServersRootThrows() {
        XCTAssertThrowsError(try CursorMCPConfigImporter.parse(json: "{}")) { error in
            XCTAssertTrue(error is CursorMCPImportError)
        }
    }
}

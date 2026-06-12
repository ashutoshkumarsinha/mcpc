import XCTest
@testable import MCPC

final class CursorMCPSyncTests: XCTestCase {
    func testSyncAddsAndTracksManagedServers() throws {
        let base = AppConfig(
            app: AppSettings(),
            client: ClientSettings(defaultServer: "manual"),
            servers: [
                ServerConfig(name: "manual", transport: .stdio, command: "echo"),
            ]
        )
        let json = """
        {
          "mcpServers": {
            "cursor-a": { "command": "node", "args": ["a.js"] },
            "cursor-b": { "url": "http://127.0.0.1:8080/sse" }
          }
        }
        """
        let result = try CursorMCPSync.sync(
            json: json,
            into: base,
            managedServerNames: [],
            onConflict: .replace
        )
        XCTAssertEqual(Set(result.added), ["cursor-a", "cursor-b"])
        XCTAssertTrue(result.config.servers.contains(where: { $0.name == "manual" }))
        XCTAssertTrue(result.config.client.mcpJSONSyncedServers.contains("cursor-a"))
    }

    func testSyncRemovesManagedServersMissingFromJSON() throws {
        let base = AppConfig(
            app: AppSettings(),
            client: ClientSettings(
                defaultServer: "manual",
                mcpJSONSyncedServers: ["gone", "manual"]
            ),
            servers: [
                ServerConfig(name: "manual", transport: .stdio, command: "echo"),
                ServerConfig(name: "gone", transport: .stdio, command: "echo"),
            ]
        )
        let json = """
        {
          "mcpServers": {
            "replacement": { "command": "echo" }
          }
        }
        """
        let result = try CursorMCPSync.sync(
            json: json,
            into: base,
            managedServerNames: ["gone"],
            onConflict: .replace
        )
        XCTAssertEqual(result.removed, ["gone"])
        XCTAssertTrue(result.config.servers.contains(where: { $0.name == "replacement" }))
        XCTAssertFalse(result.config.servers.contains(where: { $0.name == "gone" }))
        XCTAssertTrue(result.config.servers.contains(where: { $0.name == "manual" }))
    }

    func testResolvedWatchURLsExpandHomeAndRelativePaths() {
        let configURL = URL(fileURLWithPath: "/tmp/project/config.toml")
        let urls = CursorMCPPaths.resolvedWatchURLs(
            configuredPaths: ["~/custom/mcp.json", ".cursor/mcp.json"],
            configURL: configURL
        )
        XCTAssertEqual(urls.count, 2)
        XCTAssertTrue(urls[0].path.contains("/custom/mcp.json"))
        XCTAssertEqual(urls[1].path, "/tmp/project/.cursor/mcp.json")
    }
}

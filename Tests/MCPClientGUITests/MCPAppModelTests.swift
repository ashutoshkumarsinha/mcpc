import XCTest
@testable import MCPClientGUICore

@MainActor
final class MCPAppModelTests: XCTestCase {
    func testLoadConfigFromTemporaryFile() throws {
        let contents = """
        [app]
        name = "mcpc"
        version = "1.0.0"

        [client]
        default_server = "one"

        [[servers]]
        name = "one"
        transport = "stdio"
        command = "echo"
        """
        let url = try TestFixtures.writeTemporaryConfig(contents)
        let model = MCPAppModel(loadDefaultConfiguration: false)
        model.loadConfig(from: url, performInitialMCPSync: false)

        XCTAssertEqual(model.config?.servers.count, 1)
        XCTAssertEqual(model.selectedServerName, "one")
        XCTAssertNil(model.errorMessage)
    }

    func testImportCursorServersWritesConfig() throws {
        let baseURL = try TestFixtures.writeTemporaryConfig("""
        [app]
        name = "mcpc"
        version = "1.0.0"

        [client]
        default_server = "manual"

        [[servers]]
        name = "manual"
        transport = "stdio"
        command = "echo"
        """)
        let model = MCPAppModel(loadDefaultConfiguration: false)
        model.loadConfig(from: baseURL, performInitialMCPSync: false)

        let json = """
        { "mcpServers": { "imported": { "command": "node", "args": ["srv.js"] } } }
        """
        let message = try model.importCursorServers(json: json, conflictPolicy: .replace)
        XCTAssertTrue(message.contains("Added 1"))
        XCTAssertTrue(model.config?.servers.contains(where: { $0.name == "imported" }) == true)
        XCTAssertTrue(model.config?.servers.contains(where: { $0.name == "manual" }) == true)
    }

    func testConnectWithoutServerSetsError() async {
        let model = MCPAppModel(loadDefaultConfiguration: false)
        model.selectedServerName = nil
        model.connect()
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(model.errorMessage, "Select a server to connect.")
    }

    func testMCPContentFormatterText() {
        let text = MCPContentFormatter.text(.text("hello", annotations: nil))
        XCTAssertEqual(text, "hello")
    }
}

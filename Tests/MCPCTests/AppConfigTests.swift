import XCTest
@testable import MCPC

final class AppConfigTests: XCTestCase {
    func testLoadsValidConfig() throws {
        let configURL = TestFixtures.repositoryRoot.appendingPathComponent("config.toml")
        let config = try AppConfigLoader.load(from: configURL)
        XCTAssertEqual(config.app.name, "mcpc")
        XCTAssertFalse(config.servers.isEmpty)
        XCTAssertEqual(config.servers.first?.name, "test-server")
    }

    func testServerTransportAliases() {
        XCTAssertEqual(ServerTransport.parse("sse"), .sse)
        XCTAssertEqual(ServerTransport.parse("http_sse"), .sse)
        XCTAssertEqual(ServerTransport.parse("streamable_http"), .streamableHTTP)
        XCTAssertEqual(ServerTransport.parse("websocket"), .websocket)
        XCTAssertNil(ServerTransport.parse("unknown"))
    }

    func testDuplicateServerNamesRejected() throws {
        let contents = """
        [app]
        name = "mcpc"
        version = "1.0.0"

        [client]
        default_server = "a"

        [[servers]]
        name = "a"
        transport = "stdio"
        command = "echo"

        [[servers]]
        name = "a"
        transport = "stdio"
        command = "echo"
        """
        let url = try TestFixtures.writeTemporaryConfig(contents)
        XCTAssertThrowsError(try AppConfigLoader.load(from: url)) { error in
            XCTAssertTrue(String(describing: error).contains("Duplicate"))
        }
    }

    func testStdioServerRequiresCommand() throws {
        let contents = """
        [app]
        name = "mcpc"
        version = "1.0.0"

        [client]
        default_server = "bad"

        [[servers]]
        name = "bad"
        transport = "stdio"
        """
        let url = try TestFixtures.writeTemporaryConfig(contents)
        XCTAssertThrowsError(try AppConfigLoader.load(from: url)) { error in
            XCTAssertTrue(String(describing: error).contains("command"))
        }
    }

    func testSSEServerRequiresURL() throws {
        let contents = """
        [app]
        name = "mcpc"
        version = "1.0.0"

        [client]
        default_server = "remote"

        [[servers]]
        name = "remote"
        transport = "sse"
        """
        let url = try TestFixtures.writeTemporaryConfig(contents)
        XCTAssertThrowsError(try AppConfigLoader.load(from: url)) { error in
            XCTAssertTrue(String(describing: error).contains("url"))
        }
    }

    func testResolvedServerNameUsesDefault() throws {
        let config = AppConfig(
            app: AppSettings(),
            client: ClientSettings(defaultServer: "main"),
            servers: [ServerConfig(name: "main", transport: .stdio, command: "echo")]
        )
        XCTAssertEqual(try config.resolvedServerName(nil), "main")
        XCTAssertEqual(try config.resolvedServerName("main"), "main")
    }

    func testResolvedServerNameMissingDefaultThrows() throws {
        let config = AppConfig(
            app: AppSettings(),
            client: ClientSettings(defaultServer: ""),
            servers: []
        )
        XCTAssertThrowsError(try config.resolvedServerName(nil))
    }
}

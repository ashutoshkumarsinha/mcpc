import XCTest
@testable import MCPC

final class AppConfigWriterTests: XCTestCase {
    func testRoundTripWriteAndLoad() throws {
        let original = AppConfig(
            app: AppSettings(name: "mcpc", version: "2.0.0"),
            client: ClientSettings(
                defaultServer: "srv",
                protocolVersion: "2024-11-05",
                requestTimeoutSeconds: 60,
                mcpJSONHotReload: true,
                mcpJSONSyncedServers: ["imported"]
            ),
            logging: LoggingSettings(level: .debug, destination: .stderr),
            servers: [
                ServerConfig(
                    name: "srv",
                    transport: .sse,
                    url: "http://127.0.0.1:8765/sse",
                    reconnectBaseDelaySeconds: 2.5
                ),
            ]
        )

        let url = try TestFixtures.writeTemporaryConfig(AppConfigWriter.write(original))
        let loaded = try AppConfigLoader.load(from: url)

        XCTAssertEqual(loaded.app.name, "mcpc")
        XCTAssertEqual(loaded.app.version, "2.0.0")
        XCTAssertEqual(loaded.client.defaultServer, "srv")
        XCTAssertTrue(loaded.client.mcpJSONHotReload)
        XCTAssertEqual(loaded.client.mcpJSONSyncedServers, ["imported"])
        XCTAssertEqual(loaded.servers.first?.transport, .sse)
        XCTAssertEqual(loaded.servers.first?.reconnectBaseDelaySeconds, 2.5)
    }
}

import XCTest
@testable import MCPClientGUICore

@MainActor
final class MCPAppModelIntegrationTests: XCTestCase {
    private var configURL: URL?

    override func tearDown() async throws {
        if let configURL {
            try? FileManager.default.removeItem(at: configURL)
        }
        configURL = nil
    }

    func testConnectListToolsCallToolAndDisconnect() async throws {
        guard let uv = TestFixtures.uvExecutable() else {
            throw XCTSkip("uv not installed — required for bundled test server")
        }

        let contents = TestFixtures.stdioTestServerConfig(uvCommand: uv)
        configURL = try TestFixtures.writeTemporaryConfig(contents)

        let model = MCPAppModel(loadDefaultConfiguration: false)
        model.loadConfig(from: configURL, performInitialMCPSync: false)
        model.connect()

        try await waitUntil(timeoutSeconds: 30) {
            model.connectionState == .connected
        }

        XCTAssertFalse(model.tools.isEmpty)
        XCTAssertFalse(model.resources.isEmpty)
        XCTAssertFalse(model.prompts.isEmpty)

        if let echo = model.tools.first(where: { $0.name == "echo" }) {
            model.selectTool(echo)
            model.toolArgumentsJSON = #"{"message":"gui-test"}"#
            model.callSelectedTool()
            try await waitUntil(timeoutSeconds: 30) {
                !model.isBusy && model.output.contains("gui-test")
            }
        } else {
            XCTFail("echo tool not found")
        }

        await model.shutdown()
        model.stopMCPJSONWatching()
        XCTAssertEqual(model.connectionState, .disconnected)
    }

    func testPingThroughModel() async throws {
        guard let uv = TestFixtures.uvExecutable() else {
            throw XCTSkip("uv not installed — required for bundled test server")
        }

        let contents = TestFixtures.stdioTestServerConfig(uvCommand: uv)
        configURL = try TestFixtures.writeTemporaryConfig(contents)

        let model = MCPAppModel(loadDefaultConfiguration: false)
        model.loadConfig(from: configURL, performInitialMCPSync: false)
        model.connect()
        try await waitUntil(timeoutSeconds: 30) { model.connectionState == .connected }

        model.ping()
        try await waitUntil(timeoutSeconds: 30) { !model.isBusy && model.output == "pong" }

        await model.shutdown()
    }

    private func waitUntil(
        timeoutSeconds: Double,
        pollIntervalNanoseconds: UInt64 = 100_000_000,
        condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        XCTFail("Timed out after \(timeoutSeconds)s")
    }
}

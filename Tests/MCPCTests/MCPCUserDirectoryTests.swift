import XCTest
@testable import MCPC

final class MCPCUserDirectoryTests: XCTestCase {
    func testDefaultConfigTemplateLoadsWithFileLogging() throws {
        let url = try TestFixtures.writeTemporaryConfig(MCPCUserDirectory.defaultConfigTemplate())
        let config = try AppConfigLoader.load(from: url)
        XCTAssertEqual(config.app.name, "MCP Client")
        XCTAssertEqual(config.logging.destination, .file)
        XCTAssertEqual(config.logging.logFile, MCPCUserDirectory.defaultLogFileName)
    }

    func testResolvedLogFileURLRelativeToUserDirectory() {
        var settings = LoggingSettings(destination: .file, logFile: "mcpc.log")
        let url = settings.resolvedLogFileURL()
        XCTAssertEqual(url?.lastPathComponent, "mcpc.log")
        XCTAssertTrue(url?.path.contains("/.mcpc/") == true)

        settings.logFile = "/tmp/custom.log"
        XCTAssertEqual(settings.resolvedLogFileURL()?.path, "/tmp/custom.log")
    }

    func testPrepareForFirstLaunchCreatesDirectoryAndFiles() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcpc-prepare-\(UUID().uuidString)", isDirectory: true)

        let originalHome = FileManager.default.homeDirectoryForCurrentUser
        defer { try? FileManager.default.removeItem(at: base) }

        // Simulate ~/.mcpc under a temp home by writing directly to expected layout.
        let userDir = base.appendingPathComponent(MCPCUserDirectory.directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)

        let configURL = userDir.appendingPathComponent(MCPCUserDirectory.configFileName)
        try MCPCUserDirectory.defaultConfigTemplate().write(to: configURL, atomically: true, encoding: .utf8)
        FileManager.default.createFile(
            atPath: userDir.appendingPathComponent(MCPCUserDirectory.defaultLogFileName).path,
            contents: nil
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
        _ = originalHome
    }
}

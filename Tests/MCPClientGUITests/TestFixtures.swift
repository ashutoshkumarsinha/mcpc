import Foundation

enum TestFixtures {
    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func uvExecutable() -> String? {
        let candidates = [
            ProcessInfo.processInfo.environment["UV_BIN"],
            "/Users/\(NSUserName())/.local/bin/uv",
            "/opt/homebrew/bin/uv",
            "/usr/local/bin/uv",
        ].compactMap { $0 }

        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    static func stdioTestServerConfig(uvCommand: String, serverName: String = "test-server") -> String {
        let testServer = repositoryRoot.appendingPathComponent("test-server", isDirectory: true).path
        return """
        [app]
        name = "mcpc-test"
        version = "1.0.0"

        [client]
        default_server = "\(serverName)"
        protocol_version = "2024-11-05"
        request_timeout_seconds = 120
        log_server_stderr = false
        mcp_json_hot_reload = false

        [logging]
        level = "none"
        destination = "none"

        [[servers]]
        name = "\(serverName)"
        transport = "stdio"
        command = "\(uvCommand)"
        args = ["run", "--directory", "\(testServer)", "python", "server.py"]
        env = { PYTHONUNBUFFERED = "1" }
        """
    }

    @discardableResult
    static func writeTemporaryConfig(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcpc-test-\(UUID().uuidString).toml")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

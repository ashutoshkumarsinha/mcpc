import Foundation
@testable import MCPC

enum TestFixtures {
    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @discardableResult
    static func writeTemporaryConfig(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcpc-test-\(UUID().uuidString).toml")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

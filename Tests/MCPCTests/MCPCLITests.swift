import XCTest
@testable import MCPC
import MCPClient

final class MCPCLITests: XCTestCase {
    func testParsePingCommand() throws {
        let options = try MCPCLI.parseArguments(["mcpc", "ping"])
        if case .ping = options.command {
            XCTAssertNil(options.serverName)
        } else {
            XCTFail("Expected ping command")
        }
    }

    func testParseListServersWithConfigAndServer() throws {
        let options = try MCPCLI.parseArguments([
            "mcpc", "-c", "/tmp/custom.toml", "-s", "remote", "list-tools",
        ])
        XCTAssertEqual(options.configURL.path, "/tmp/custom.toml")
        XCTAssertEqual(options.serverName, "remote")
        if case .listTools = options.command {
        } else {
            XCTFail("Expected list-tools command")
        }
    }

    func testParseCallToolArguments() throws {
        let options = try MCPCLI.parseArguments([
            "mcpc", "call-tool", "echo", "--message", "hello",
        ])
        if case .callTool(let name, let arguments) = options.command {
            XCTAssertEqual(name, "echo")
            XCTAssertEqual(arguments["message"], .string("hello"))
        } else {
            XCTFail("Expected call-tool command")
        }
    }

    func testParseCallToolJSONArgs() throws {
        let options = try MCPCLI.parseArguments([
            "mcpc", "call-tool", "add", "--args", #"{"a":2,"b":40}"#,
        ])
        if case .callTool(let name, let arguments) = options.command {
            XCTAssertEqual(name, "add")
            XCTAssertEqual(arguments["a"], .integer(2))
            XCTAssertEqual(arguments["b"], .integer(40))
        } else {
            XCTFail("Expected call-tool command")
        }
    }

    func testParseGetPromptArguments() throws {
        let options = try MCPCLI.parseArguments([
            "mcpc", "get-prompt", "greet", "--name", "Swift", "--tone", "friendly",
        ])
        if case .getPrompt(let name, let arguments) = options.command {
            XCTAssertEqual(name, "greet")
            XCTAssertEqual(arguments["name"], "Swift")
            XCTAssertEqual(arguments["tone"], "friendly")
        } else {
            XCTFail("Expected get-prompt command")
        }
    }

    func testMissingCommandThrows() {
        XCTAssertThrowsError(try MCPCLI.parseArguments(["mcpc"])) { error in
            XCTAssertEqual(error as? MCPCLIError, .missingCommand)
        }
    }

    func testUnknownOptionThrows() {
        XCTAssertThrowsError(try MCPCLI.parseArguments(["mcpc", "--bogus"])) { error in
            if case .unknownOption(let option) = error as? MCPCLIError {
                XCTAssertEqual(option, "--bogus")
            } else {
                XCTFail("Expected unknownOption")
            }
        }
    }

    func testHelpRequested() {
        XCTAssertThrowsError(try MCPCLI.parseArguments(["mcpc", "--help"])) { error in
            XCTAssertEqual(error as? MCPCLIError, .helpRequested)
        }
    }
}

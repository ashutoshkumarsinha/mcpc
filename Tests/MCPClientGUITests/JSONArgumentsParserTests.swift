import XCTest
@testable import MCPClientGUICore
import MCPClient

final class JSONArgumentsParserTests: XCTestCase {
    func testDecodeObjectFromJSON() throws {
        let args = try JSONArgumentsParser.decodeObject(#"{"message":"hello"}"#)
        XCTAssertEqual(args["message"], .string("hello"))
    }

    func testDecodeEmptyStringDefaultsToEmptyObject() throws {
        let args = try JSONArgumentsParser.decodeObject("   ")
        XCTAssertTrue(args.isEmpty)
    }

    func testInvalidJSONThrows() {
        XCTAssertThrowsError(try JSONArgumentsParser.decodeObject("{bad"))
    }

    func testDecodeStringMapCoercesScalars() throws {
        let map = try JSONArgumentsParser.decodeStringMap(#"{"name":"Swift","count":3,"ok":true}"#)
        XCTAssertEqual(map["name"], "Swift")
        XCTAssertEqual(map["count"], "3")
        XCTAssertEqual(map["ok"], "true")
    }

    func testTemplateFromToolSchema() {
        let schema: AnyCodableValue = .object([
            "type": .string("object"),
            "properties": .object([
                "message": .object(["type": .string("string")]),
                "count": .object(["type": .string("integer")]),
            ]),
        ])
        let json = JSONArgumentsParser.template(for: schema)
        XCTAssertTrue(json.contains("\"message\""))
        XCTAssertTrue(json.contains("\"count\""))
    }
}

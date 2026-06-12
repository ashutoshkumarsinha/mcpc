import XCTest
@testable import MCPC

final class SSEJSONMessageFilterTests: XCTestCase {
    func testAcceptsJSONRPCObject() {
        let data = Data(#"{"jsonrpc":"2.0","id":1,"result":{}}"#.utf8)
        XCTAssertTrue(SSEJSONMessageFilter.isJSONRPCMessage(data))
    }

    func testRejectsPlainTextAcceptedBody() {
        let data = Data("Accepted".utf8)
        XCTAssertFalse(SSEJSONMessageFilter.isJSONRPCMessage(data))
    }

    func testRejectsEmptyData() {
        XCTAssertFalse(SSEJSONMessageFilter.isJSONRPCMessage(Data()))
    }
}

import Foundation
import XCTest
@testable import iPhoneLocationMove

final class TunnelXPCInterfaceTests: XCTestCase {
    func testClangProtocolCreatesCastableRemoteProxy() {
        let connection = NSXPCConnection(
            machServiceName: "com.cash.iPhoneLocationMove.invalid-test-service"
        )
        connection.remoteObjectInterface = NSXPCInterface(
            with: TunnelHelperXPCProtocol.self
        )
        connection.resume()
        defer { connection.invalidate() }

        let rawProxy = connection.remoteObjectProxyWithErrorHandler { _ in }

        XCTAssertNotNil(rawProxy as? TunnelHelperXPCProtocol)
    }
}

import XCTest
@testable import iPhoneLocationMove

final class AppShellTests: XCTestCase {
    func testMainWindowHasStableIdentifierForReopening() {
        XCTAssertEqual(AppWindow.mainID, "main")
    }
}

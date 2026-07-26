import Foundation
import XCTest
@testable import iPhoneLocationMove

@MainActor
final class RiskNoticeStoreTests: XCTestCase {
    func testFirstUseNoticeIsPersistedAfterAcknowledgement() throws {
        let suiteName = "RiskNoticeStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstLaunch = RiskNoticeStore(defaults: defaults)
        XCTAssertTrue(firstLaunch.needsFirstUseAcknowledgement)

        firstLaunch.acknowledgeFirstUse()

        XCTAssertFalse(firstLaunch.needsFirstUseAcknowledgement)
        let laterLaunch = RiskNoticeStore(defaults: defaults)
        XCTAssertFalse(laterLaunch.needsFirstUseAcknowledgement)
    }

    func testEverySimulationStartStillReturnsRiskNotice() {
        let store = RiskNoticeStore(
            defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard
        )
        store.acknowledgeFirstUse()

        XCTAssertEqual(
            store.noticeForSimulationStart(),
            RiskNotice.simulationStart
        )
        XCTAssertEqual(
            store.noticeForSimulationStart(),
            RiskNotice.simulationStart
        )
    }

    func testCopyMakesNoDetectionOrAccountSafetyPromise() {
        let copy = [
            RiskNotice.firstUse.message,
            RiskNotice.simulationStart.message,
        ].joined(separator: " ")

        XCTAssertFalse(copy.contains("不可偵測"))
        XCTAssertFalse(copy.contains("規避"))
        XCTAssertFalse(copy.contains("帳號安全保證"))
        XCTAssertTrue(copy.contains("第三方服務"))
        XCTAssertTrue(copy.contains("帳號風險"))
    }
}

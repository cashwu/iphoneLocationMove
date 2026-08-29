import XCTest
@testable import iPhoneLocationMove

final class DeviceFailurePresentationTests: XCTestCase {
    func testRequiredFailuresRemainDistinctAndActionable() {
        let failures: [DeviceLocationError] = [
            .timeout,
            .usbDisconnected,
            .authorizationDenied,
            .deviceLocked,
            .prerequisiteFailed(
                stage: .developerDiskImage,
                message: "image unavailable"
            ),
            .tunnelFailure("tunnel exited"),
            .helperFailure("helper exited"),
            .clearFailed("clear rejected"),
        ]
        let presentations = failures.map(DeviceFailurePresentation.make)

        XCTAssertEqual(
            Set(presentations.map(\.title)).count,
            failures.count
        )
        for presentation in presentations {
            XCTAssertFalse(presentation.message.isEmpty)
            XCTAssertFalse(presentation.recoveryTitle.isEmpty)
        }
    }

    func testClearFailureExplicitlyRefusesToClaimRealLocationWasRestored() {
        let presentation = DeviceFailurePresentation.make(
            for: .clearFailed("clear rejected")
        )

        XCTAssertEqual(presentation.recoveryAction, .retryClear)
        XCTAssertTrue(presentation.message.contains("不能宣稱"))
        XCTAssertTrue(presentation.message.contains("恢復真實定位"))
    }

    func testDeviceLockedTellsUserToUnlockInsteadOfShowingDDIFailure() {
        let presentation = DeviceFailurePresentation.make(for: .deviceLocked)

        XCTAssertEqual(presentation.recoveryAction, .unlockDevice)
        XCTAssertTrue(presentation.title.contains("鎖定"))
        XCTAssertTrue(presentation.message.contains("解鎖"))
    }

    func testUSBAndUncertainFailuresDoNotUseReadyOrActiveLanguage() {
        for failure in [
            DeviceLocationError.timeout,
            .usbDisconnected,
            .helperFailure("exited"),
            .tunnelFailure("ended"),
        ] {
            let presentation = DeviceFailurePresentation.make(for: failure)
            let copy = presentation.title + presentation.message
            XCTAssertFalse(copy.contains("已就緒"))
            XCTAssertFalse(copy.contains("模擬中"))
            XCTAssertFalse(copy.contains("已清除"))
        }
    }
}

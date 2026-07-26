import Foundation
import XCTest
@testable import iPhoneLocationMove

final class DeviceLocationClientTests: XCTestCase {
    func testCoordinateRejectsNonFiniteAndOutOfRangeInput() {
        XCTAssertNoThrow(try DeviceCoordinate(latitude: 25.033, longitude: 121.5654))
        XCTAssertThrowsError(try DeviceCoordinate(latitude: .nan, longitude: 0))
        XCTAssertThrowsError(try DeviceCoordinate(latitude: 91, longitude: 0))
        XCTAssertThrowsError(try DeviceCoordinate(latitude: 0, longitude: -181))
    }

    func testSimulationSessionIdentityIsExplicitAndStable() {
        let rawValue = UUID()
        let first = SimulationSessionID(rawValue: rawValue)
        let same = SimulationSessionID(rawValue: rawValue)
        let different = SimulationSessionID()

        XCTAssertEqual(first, same)
        XCTAssertNotEqual(first, different)
    }

    func testDeviceGenerationAdvancesAndFailsClosedAtExhaustion() throws {
        let generation = DeviceSessionGeneration(rawValue: 41)

        XCTAssertEqual(try generation.advanced(), DeviceSessionGeneration(rawValue: 42))
        XCTAssertThrowsError(
            try DeviceSessionGeneration(rawValue: .max).advanced()
        ) { error in
            XCTAssertEqual(error as? DeviceLocationError, .identityExhausted)
        }
    }

    func testIOS17SupportIsDerivedFromVersion() throws {
        let supported = try USBDevice(
            id: DeviceID("device-17"),
            name: "iPhone",
            operatingSystemVersion: OperatingSystemVersion(
                majorVersion: 17,
                minorVersion: 6,
                patchVersion: 1
            )
        )
        let unsupported = try USBDevice(
            id: DeviceID("device-16"),
            name: "Older iPhone",
            operatingSystemVersion: OperatingSystemVersion(
                majorVersion: 16,
                minorVersion: 7,
                patchVersion: 0
            )
        )

        XCTAssertEqual(supported.support, .supported)
        XCTAssertEqual(unsupported.support, .unsupported(minimumMajorVersion: 17))
    }

    func testPositionUnknownIsPayloadOfInterruptedState() throws {
        let device = try USBDevice(
            id: DeviceID("device-17"),
            name: "iPhone",
            operatingSystemVersion: OperatingSystemVersion(
                majorVersion: 17,
                minorVersion: 0,
                patchVersion: 0
            )
        )
        let session = PreparedDeviceSession(
            device: device,
            generation: DeviceSessionGeneration(rawValue: 1)
        )
        let interruption = DeviceInterruption(
            reason: .usbDisconnected,
            positionKnowledge: .unknown
        )

        XCTAssertEqual(
            DeviceSessionState.interrupted(session: session, interruption: interruption),
            .interrupted(session: session, interruption: interruption)
        )
        XCTAssertEqual(interruption.positionKnowledge, .unknown)
    }

    func testRuntimeStateRemainsTypedAndNotReadyOnIncompleteEnvironment() {
        let state = RuntimeAvailability.incompleteManagedEnvironment

        XCTAssertNotEqual(
            state,
            .ready(
                RuntimeInstallation(
                    executableURL: URL(fileURLWithPath: "/invalid"),
                    source: .appManaged
                )
            )
        )
    }

    func testErrorsNeededByUIRemainDistinct() {
        let errors: Set<DeviceLocationError> = [
            .timeout,
            .usbDisconnected,
            .authorizationDenied,
            .clearFailed("clear failed"),
            .positionUnknown,
            .staleGeneration,
        ]

        XCTAssertEqual(errors.count, 6)
    }
}

import Foundation

@MainActor
final class DeviceRecoveryCoordinator {
    private let adapter: PymobiledeviceAdapter
    private let simulation: SimulationStore

    init(
        adapter: PymobiledeviceAdapter,
        simulation: SimulationStore
    ) {
        self.adapter = adapter
        self.simulation = simulation
    }

    func handleUSBDisconnect(deviceID: DeviceID) async {
        simulation.handleDeviceInterruption(
            DeviceInterruption(
                reason: .usbDisconnected,
                positionKnowledge: .unknown
            )
        )
        await adapter.handleUSBDisconnect(deviceID: deviceID)
    }

    func reconnect() async throws -> PreparedDeviceSession {
        try await adapter.reconnect()
    }
}

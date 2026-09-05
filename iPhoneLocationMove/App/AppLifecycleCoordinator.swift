import Combine
import Foundation

@MainActor
protocol SimulationLifecycleControlling: AnyObject {
    var hasActiveSimulation: Bool { get }
    var cleanupFailure: DeviceLocationError? { get }
    func stopForQuit() async
}

protocol DeviceSessionQuitTeardown: Sendable {
    func teardownForQuit() async throws
}

enum AppTerminationDecision: Equatable, Sendable {
    case awaitingConfirmation
    case keepRunning
    case terminate
}

enum AppQuitState: Equatable, Sendable {
    case idle
    case confirmationRequired
    case cleaningUp
    case cleanupFailed(DeviceLocationError)
    case forceQuitWarning(DeviceLocationError?)
    case readyToTerminate(safelyCleared: Bool)
}

@MainActor
final class AppLifecycleCoordinator: ObservableObject {
    @Published private(set) var state: AppQuitState = .idle

    private var simulation: (any SimulationLifecycleControlling)?
    private var device: (any DeviceSessionQuitTeardown)?

    init(
        simulation: (any SimulationLifecycleControlling)? = nil,
        device: (any DeviceSessionQuitTeardown)? = nil
    ) {
        self.simulation = simulation
        self.device = device
    }

    func configure(
        simulation: any SimulationLifecycleControlling,
        device: any DeviceSessionQuitTeardown
    ) {
        self.simulation = simulation
        self.device = device
    }

    func handleMainWindowClosed() {
        // Closing a window is intentionally not an application-termination event.
    }

    func requestQuit() async -> AppTerminationDecision {
        if simulation?.hasActiveSimulation == true {
            state = .confirmationRequired
            return .awaitingConfirmation
        }
        return await performCleanup()
    }

    func confirmQuit() async -> AppTerminationDecision {
        await performCleanup()
    }

    func cancelQuit() {
        state = .idle
    }

    func requestForceQuit() {
        let failure: DeviceLocationError?
        if case let .cleanupFailed(currentFailure) = state {
            failure = currentFailure
        } else {
            failure = simulation?.cleanupFailure
        }
        state = .forceQuitWarning(failure)
    }

    func confirmForceQuit() -> AppTerminationDecision {
        guard case .forceQuitWarning = state else {
            return .keepRunning
        }
        state = .readyToTerminate(safelyCleared: false)
        return .terminate
    }

    private func performCleanup() async -> AppTerminationDecision {
        state = .cleaningUp

        if let simulation, simulation.hasActiveSimulation {
            await simulation.stopForQuit()
            if let failure = simulation.cleanupFailure {
                state = .cleanupFailed(failure)
                return .keepRunning
            }
        }

        do {
            try await device?.teardownForQuit()
            state = .readyToTerminate(safelyCleared: true)
            return .terminate
        } catch let failure as DeviceLocationError {
            state = .cleanupFailed(failure)
            return .keepRunning
        } catch {
            let failure = DeviceLocationError.transportFailure(
                error.localizedDescription
            )
            state = .cleanupFailed(failure)
            return .keepRunning
        }
    }
}

extension PymobiledeviceAdapter: DeviceSessionQuitTeardown {}

import Combine
import CoreLocation
import Foundation

@MainActor
protocol MacLocationProviding {
    func requestCurrentLocation() async throws -> MapCoordinate
}

enum MacLocationClientError: Error, Equatable, Sendable {
    case authorizationDenied
    case authorizationRestricted
    case locationServicesDisabled
    case locationFailed
    case invalidCoordinate
    case requestInProgress
    case cancelled
}

extension MacLocationClientError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .authorizationDenied, .authorizationRestricted:
            "無法取得 Mac 位置；請在「系統設定 → 隱私權與安全性 → 定位服務」允許此 App 使用位置。"
        case .locationServicesDisabled:
            "macOS 定位服務目前已關閉，無法取得 Mac 位置。"
        case .locationFailed, .invalidCoordinate:
            "目前無法取得有效的 Mac 位置。"
        case .requestInProgress:
            "Mac 位置要求仍在進行中。"
        case .cancelled:
            "Mac 位置要求已取消。"
        }
    }
}

@MainActor
protocol MacLocationManagerBoundary: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var onAuthorizationChange: (() -> Void)? { get set }
    var onLocations: (([CLLocation]) -> Void)? { get set }
    var onFailure: ((Error) -> Void)? { get set }

    func requestWhenInUseAuthorization()
    func requestLocation()
}

@MainActor
final class LiveMacLocationClient: MacLocationProviding {
    private struct ActiveRequest {
        let identity: ObjectIdentifier
        let manager: any MacLocationManagerBoundary
        let continuation: CheckedContinuation<MapCoordinate, Error>
        var didRequestLocation: Bool
    }

    private let locationServicesEnabled: @MainActor () -> Bool
    private let managerFactory: @MainActor () -> any MacLocationManagerBoundary
    private var activeRequest: ActiveRequest?

    init(
        locationServicesEnabled: @escaping @MainActor () -> Bool = {
            CLLocationManager.locationServicesEnabled()
        },
        managerFactory: @escaping @MainActor () -> any MacLocationManagerBoundary = {
            LiveMacLocationManagerBoundary()
        }
    ) {
        self.locationServicesEnabled = locationServicesEnabled
        self.managerFactory = managerFactory
    }

    func requestCurrentLocation() async throws -> MapCoordinate {
        guard !Task.isCancelled else {
            throw MacLocationClientError.cancelled
        }
        guard locationServicesEnabled() else {
            throw MacLocationClientError.locationServicesDisabled
        }
        guard activeRequest == nil else {
            throw MacLocationClientError.requestInProgress
        }

        let manager = managerFactory()
        let identity = ObjectIdentifier(manager)

        return try await withTaskCancellationHandler {
            return try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(
                        throwing: MacLocationClientError.cancelled
                    )
                    return
                }
                activeRequest = ActiveRequest(
                    identity: identity,
                    manager: manager,
                    continuation: continuation,
                    didRequestLocation: false
                )
                manager.onAuthorizationChange = { [weak self] in
                    self?.handleAuthorizationChange(for: identity)
                }
                manager.onLocations = { [weak self] locations in
                    self?.handleLocations(locations, for: identity)
                }
                manager.onFailure = { [weak self] _ in
                    self?.finish(
                        identity: identity,
                        result: .failure(
                            MacLocationClientError.locationFailed
                        )
                    )
                }
                handleAuthorizationChange(for: identity)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(
                    identity: identity,
                    result: .failure(MacLocationClientError.cancelled)
                )
            }
        }
    }

    private func handleAuthorizationChange(for identity: ObjectIdentifier) {
        guard var request = activeRequest,
              request.identity == identity
        else {
            return
        }

        switch request.manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            guard !request.didRequestLocation else {
                return
            }
            request.didRequestLocation = true
            activeRequest = request
            request.manager.requestLocation()
        case .notDetermined:
            request.manager.requestWhenInUseAuthorization()
        case .denied:
            finish(
                identity: identity,
                result: .failure(MacLocationClientError.authorizationDenied)
            )
        case .restricted:
            finish(
                identity: identity,
                result: .failure(
                    MacLocationClientError.authorizationRestricted
                )
            )
        @unknown default:
            finish(
                identity: identity,
                result: .failure(MacLocationClientError.locationFailed)
            )
        }
    }

    private func handleLocations(
        _ locations: [CLLocation],
        for identity: ObjectIdentifier
    ) {
        guard let location = locations.last else {
            finish(
                identity: identity,
                result: .failure(MacLocationClientError.locationFailed)
            )
            return
        }
        do {
            let coordinate = try MapCoordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            finish(identity: identity, result: .success(coordinate))
        } catch {
            finish(
                identity: identity,
                result: .failure(MacLocationClientError.invalidCoordinate)
            )
        }
    }

    private func finish(
        identity: ObjectIdentifier,
        result: Result<MapCoordinate, Error>
    ) {
        guard let request = activeRequest,
              request.identity == identity
        else {
            return
        }
        activeRequest = nil
        request.manager.onAuthorizationChange = nil
        request.manager.onLocations = nil
        request.manager.onFailure = nil
        request.continuation.resume(with: result)
    }
}

@MainActor
private final class LiveMacLocationManagerBoundary:
    NSObject,
    MacLocationManagerBoundary,
    @preconcurrency CLLocationManagerDelegate
{
    var onAuthorizationChange: (() -> Void)?
    var onLocations: (([CLLocation]) -> Void)?
    var onFailure: ((Error) -> Void)?

    private let manager: CLLocationManager

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func requestLocation() {
        manager.requestLocation()
    }

    func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        onAuthorizationChange?()
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        onLocations?(locations)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        onFailure?(error)
    }
}

@MainActor
final class MacLocationCoordinator: ObservableObject {
    @Published private(set) var coordinate: MapCoordinate?
    @Published private(set) var coordinateGeneration: DeviceSessionGeneration?
    @Published private(set) var message: String?

    private let provider: any MacLocationProviding
    private var desiredGeneration: DeviceSessionGeneration?
    private var requestedGenerations: Set<DeviceSessionGeneration> = []
    private var transitionTask: Task<Void, Never>?

    init(provider: any MacLocationProviding) {
        self.provider = provider
    }

    convenience init() {
        self.init(provider: LiveMacLocationClient())
    }

    func updateReadyGeneration(_ generation: DeviceSessionGeneration?) {
        guard desiredGeneration != generation else {
            return
        }
        desiredGeneration = generation

        let previousTask = transitionTask
        previousTask?.cancel()
        transitionTask = Task { @MainActor [weak self] in
            if let previousTask {
                await previousTask.value
            }
            guard let self,
                  !Task.isCancelled,
                  self.desiredGeneration == generation,
                  let generation,
                  !self.requestedGenerations.contains(generation)
            else {
                return
            }

            self.requestedGenerations.insert(generation)
            do {
                let coordinate = try await self.provider
                    .requestCurrentLocation()
                guard !Task.isCancelled,
                      self.desiredGeneration == generation
                else {
                    return
                }
                self.coordinate = coordinate
                self.coordinateGeneration = generation
                self.message = nil
            } catch {
                guard !Task.isCancelled,
                      self.desiredGeneration == generation
                else {
                    return
                }
                if let failure = error as? MacLocationClientError,
                   failure == .cancelled
                {
                    return
                }
                self.message = Self.presentation(for: error)
            }
        }
    }

    private static func presentation(for error: Error) -> String {
        if let failure = error as? MacLocationClientError,
           let description = failure.errorDescription
        {
            return description
        }
        return "目前無法取得 Mac 位置。"
    }
}

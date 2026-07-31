import Combine
import Foundation

struct MapCoordinate: Equatable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) throws {
        guard latitude.isFinite,
              (-90 ... 90).contains(latitude),
              longitude.isFinite,
              (-180 ... 180).contains(longitude)
        else {
            throw LocationMapError.invalidCoordinate
        }
        self.latitude = latitude
        self.longitude = longitude
    }
}

struct MapSearchGeneration: RawRepresentable, Comparable, Hashable, Sendable {
    let rawValue: UInt64

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    func advanced() throws -> Self {
        guard rawValue < UInt64.max else {
            throw LocationMapError.identityExhausted
        }
        return Self(rawValue: rawValue + 1)
    }
}

struct RouteRequestGeneration: RawRepresentable, Comparable, Hashable, Sendable {
    let rawValue: UInt64

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    func advanced() throws -> Self {
        guard rawValue < UInt64.max else {
            throw LocationMapError.identityExhausted
        }
        return Self(rawValue: rawValue + 1)
    }
}

struct MacRecenterGeneration: RawRepresentable, Comparable, Hashable, Sendable {
    let rawValue: UInt64

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    func advanced() throws -> Self {
        guard rawValue < UInt64.max else {
            throw LocationMapError.identityExhausted
        }
        return Self(rawValue: rawValue + 1)
    }
}

struct MapSearchPlace: Equatable, Hashable, Sendable {
    let coordinate: MapCoordinate
    let address: String?

    init(coordinate: MapCoordinate, address: String?) {
        self.coordinate = coordinate
        let normalizedAddress = address?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.address = normalizedAddress?.isEmpty == true ? nil : normalizedAddress
    }
}

struct MapSearchRequest: Equatable, Sendable {
    let generation: MapSearchGeneration
    let query: String
}

struct MapPreviewAddressRequest: Equatable, Sendable {
    let generation: MapSearchGeneration
    let coordinate: MapCoordinate
}

struct MapPreviewCameraIntent: Equatable, Sendable {
    let coordinate: MapCoordinate
    let identity: MapSearchGeneration
}

enum MapSearchApplication: Equatable, Sendable {
    case applied
    case stale
}

enum MapEndpoint: Equatable, Sendable {
    case a
    case b
}

struct MapEndpointSnapshot: Equatable, Sendable {
    let a: MapCoordinate
    let b: MapCoordinate
}

struct DirectionsRequest: Equatable, Sendable {
    let generation: RouteRequestGeneration
    let snapshot: MapEndpointSnapshot
}

struct MacInitialCenterIntent: Equatable, Sendable {
    let coordinate: MapCoordinate
    let generation: DeviceSessionGeneration
}

struct MacRecenterIntent: Equatable, Sendable {
    let coordinate: MapCoordinate
    let generation: MacRecenterGeneration
}

enum PedestrianDirectionsResponse: Equatable, Sendable {
    case routeAvailable([MapCoordinate], distance: Double)
    case noPedestrianRoute
    case cancelled
    case transientFailure(message: String)
}

enum DirectionsOutcome: Equatable, Sendable {
    case routeAvailable
    case noPedestrianRoute
    case cancelled
    case transientFailure
    case stale
}

enum MapRouteStatus: Equatable, Sendable {
    case idle
    case loading(MapEndpointSnapshot)
    case routeAvailable
    case noPedestrianRoute
    case cancelled
    case transientFailure(message: String)
}

struct MapRoutePreview: Equatable, Sendable {
    let polyline: [MapCoordinate]
    let endpointSnapshot: MapEndpointSnapshot
    let distance: Double
    let speedKilometersPerHour: Double
    let estimatedTime: TimeInterval

    fileprivate init(
        polyline: [MapCoordinate],
        endpointSnapshot: MapEndpointSnapshot,
        distance: Double,
        speedKilometersPerHour: Double
    ) {
        self.polyline = polyline
        self.endpointSnapshot = endpointSnapshot
        self.distance = distance
        self.speedKilometersPerHour = speedKilometersPerHour
        estimatedTime = distance / (speedKilometersPerHour / 3.6)
    }
}

enum LocationMapError: Error, Equatable, Sendable {
    case invalidCoordinate
    case invalidSearchQuery
    case invalidSpeed
    case invalidRoute
    case missingPreview
    case missingEndpoints
    case endpointsMustDiffer
    case staleSearchSelection
    case routePreviewUnavailable
    case macLocationUnavailable
    case identityExhausted
}

extension LocationMapError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidCoordinate:
            "座標無效。"
        case .invalidSearchQuery:
            "請輸入要搜尋的地名或地址。"
        case .invalidSpeed:
            "步行速度必須介於 1–7 km/h。"
        case .invalidRoute:
            "MapKit 回傳的步行路線資料無效。"
        case .missingPreview:
            "請先在地圖上預覽一個位置。"
        case .missingEndpoints:
            "請先選擇 A 與 B。"
        case .endpointsMustDiffer:
            "A 與 B 必須是不同位置。"
        case .staleSearchSelection:
            "搜尋結果已過期，請重新選擇。"
        case .routePreviewUnavailable:
            "目前沒有可確認的步行路線。"
        case .macLocationUnavailable:
            "尚未取得 Mac 目前位置。"
        case .identityExhausted:
            "要求識別碼已用盡，請重新啟動 App。"
        }
    }
}

@MainActor
final class LocationMapModel: ObservableObject {
    static let defaultWalkingSpeed = 4.5
    static let walkingSpeedRange = 1.0 ... 7.0

    @Published private(set) var preview: MapSearchPlace?
    @Published private(set) var previewCameraIntent: MapPreviewCameraIntent?
    @Published private(set) var searchResults: [MapSearchPlace] = []
    @Published private(set) var endpointA: MapSearchPlace?
    @Published private(set) var endpointB: MapSearchPlace?
    @Published private(set) var routePreview: MapRoutePreview?
    @Published private(set) var routeStatus: MapRouteStatus = .idle
    @Published private(set) var macLocationCoordinate: MapCoordinate?
    @Published private(set) var macInitialCenterIntent: MacInitialCenterIntent?
    @Published private(set) var macRecenterIntent: MacRecenterIntent?
    @Published private(set) var routeCameraIdentity: RouteRequestGeneration?
    @Published private(set) var walkingSpeedKilometersPerHour: Double
    @Published private(set) var mapSearchGeneration = MapSearchGeneration(
        rawValue: 0
    )
    @Published private(set) var routeRequestGeneration = RouteRequestGeneration(
        rawValue: 0
    )
    @Published private(set) var macRecenterGeneration = MacRecenterGeneration(
        rawValue: 0
    )

    private var activeSearchRequest: MapSearchRequest?
    private var activeDirectionsRequest: DirectionsRequest?
    private var userHasMapContext = false

    init() {
        walkingSpeedKilometersPerHour = Self.defaultWalkingSpeed
    }

    init(walkingSpeedKilometersPerHour: Double) throws {
        guard Self.isValidSpeed(walkingSpeedKilometersPerHour) else {
            throw LocationMapError.invalidSpeed
        }
        self.walkingSpeedKilometersPerHour = walkingSpeedKilometersPerHour
    }

    var endpointSnapshot: MapEndpointSnapshot? {
        guard let endpointA, let endpointB else {
            return nil
        }
        return MapEndpointSnapshot(
            a: endpointA.coordinate,
            b: endpointB.coordinate
        )
    }

    var selectionRequiresExplicitConfirmation: Bool {
        preview != nil
    }

    var canStartRoute: Bool {
        routeStatus == .routeAvailable
            && routePreview?.endpointSnapshot == endpointSnapshot
    }

    var canRetryDirections: Bool {
        if case .transientFailure = routeStatus {
            return endpointSnapshot != nil
        }
        return false
    }

    var canRecenterOnMac: Bool {
        macLocationCoordinate != nil
    }

    func beginSearch(query: String) throws -> MapSearchRequest {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            throw LocationMapError.invalidSearchQuery
        }

        recordUserMapContext()
        try advanceSearchOwnership()
        preview = nil
        previewCameraIntent = nil
        searchResults = []
        let request = MapSearchRequest(
            generation: mapSearchGeneration,
            query: normalizedQuery
        )
        activeSearchRequest = request
        return request
    }

    @discardableResult
    func receiveSearchResults(
        _ places: [MapSearchPlace],
        for request: MapSearchRequest
    ) -> MapSearchApplication {
        guard request == activeSearchRequest,
              request.generation == mapSearchGeneration
        else {
            return .stale
        }
        searchResults = places
        return .applied
    }

    func selectSearchResult(_ place: MapSearchPlace) throws {
        guard searchResults.contains(place) else {
            throw LocationMapError.staleSearchSelection
        }
        try advanceSearchOwnership()
        preview = place
        previewCameraIntent = MapPreviewCameraIntent(
            coordinate: place.coordinate,
            identity: mapSearchGeneration
        )
        activeSearchRequest = nil
    }

    @discardableResult
    func selectMapCoordinate(
        _ coordinate: MapCoordinate
    ) throws -> MapPreviewAddressRequest {
        recordUserMapContext()
        try advanceSearchOwnership()
        preview = MapSearchPlace(coordinate: coordinate, address: nil)
        previewCameraIntent = nil
        searchResults = []
        activeSearchRequest = nil
        return MapPreviewAddressRequest(
            generation: mapSearchGeneration,
            coordinate: coordinate
        )
    }

    @discardableResult
    func receivePreviewAddress(
        _ address: String,
        for request: MapPreviewAddressRequest
    ) -> MapSearchApplication {
        guard request.generation == mapSearchGeneration,
              preview?.coordinate == request.coordinate
        else {
            return .stale
        }
        preview = MapSearchPlace(
            coordinate: request.coordinate,
            address: address
        )
        return .applied
    }

    func clearSearch() throws {
        recordUserMapContext()
        try advanceSearchOwnership()
        preview = nil
        previewCameraIntent = nil
        searchResults = []
        activeSearchRequest = nil
    }

    func assignPreview(to endpoint: MapEndpoint) throws {
        guard let preview else {
            throw LocationMapError.missingPreview
        }
        recordUserMapContext()
        let nextGeneration = try routeRequestGeneration.advanced()
        switch endpoint {
        case .a:
            guard endpointB?.coordinate != preview.coordinate else {
                throw LocationMapError.endpointsMustDiffer
            }
            endpointA = preview
        case .b:
            guard endpointA?.coordinate != preview.coordinate else {
                throw LocationMapError.endpointsMustDiffer
            }
            endpointB = preview
        }
        invalidateDirectionsOwnership(nextGeneration: nextGeneration)
    }

    func beginDirections() throws -> DirectionsRequest {
        guard let endpointSnapshot else {
            throw LocationMapError.missingEndpoints
        }
        guard endpointSnapshot.a != endpointSnapshot.b else {
            throw LocationMapError.endpointsMustDiffer
        }

        recordUserMapContext()
        routeRequestGeneration = try routeRequestGeneration.advanced()
        let request = DirectionsRequest(
            generation: routeRequestGeneration,
            snapshot: endpointSnapshot
        )
        activeDirectionsRequest = request
        routePreview = nil
        routeCameraIdentity = nil
        routeStatus = .loading(endpointSnapshot)
        return request
    }

    @discardableResult
    func receiveDirections(
        _ response: PedestrianDirectionsResponse,
        for request: DirectionsRequest
    ) throws -> DirectionsOutcome {
        guard request == activeDirectionsRequest,
              request.generation == routeRequestGeneration,
              request.snapshot == endpointSnapshot
        else {
            return .stale
        }

        switch response {
        case .routeAvailable(let polyline, let distance):
            guard polyline.count >= 2,
                  distance.isFinite,
                  distance > 0
            else {
                activeDirectionsRequest = nil
                routePreview = nil
                routeStatus = .transientFailure(
                    message: LocationMapError.invalidRoute.errorDescription
                        ?? "MapKit 回傳的步行路線資料無效。"
                )
                throw LocationMapError.invalidRoute
            }
            activeDirectionsRequest = nil
            routePreview = MapRoutePreview(
                polyline: polyline,
                endpointSnapshot: request.snapshot,
                distance: distance,
                speedKilometersPerHour: walkingSpeedKilometersPerHour
            )
            routeCameraIdentity = request.generation
            routeStatus = .routeAvailable
            return .routeAvailable

        case .noPedestrianRoute:
            activeDirectionsRequest = nil
            routePreview = nil
            routeCameraIdentity = nil
            routeStatus = .noPedestrianRoute
            return .noPedestrianRoute

        case .cancelled:
            activeDirectionsRequest = nil
            routePreview = nil
            routeCameraIdentity = nil
            routeStatus = .cancelled
            return .cancelled

        case .transientFailure(let message):
            activeDirectionsRequest = nil
            let normalizedMessage = message.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            routePreview = nil
            routeCameraIdentity = nil
            routeStatus = .transientFailure(
                message: normalizedMessage.isEmpty
                    ? "暫時無法取得步行路線"
                    : normalizedMessage
            )
            return .transientFailure
        }
    }

    func confirmRoutePreview() throws -> MapRoutePreview {
        guard canStartRoute, let routePreview else {
            throw LocationMapError.routePreviewUnavailable
        }
        return routePreview
    }

    func setWalkingSpeed(kilometersPerHour: Double) throws {
        guard Self.isValidSpeed(kilometersPerHour) else {
            throw LocationMapError.invalidSpeed
        }
        walkingSpeedKilometersPerHour = kilometersPerHour
        if let routePreview {
            self.routePreview = MapRoutePreview(
                polyline: routePreview.polyline,
                endpointSnapshot: routePreview.endpointSnapshot,
                distance: routePreview.distance,
                speedKilometersPerHour: kilometersPerHour
            )
        }
    }

    func updateMacLocation(
        _ coordinate: MapCoordinate,
        for generation: DeviceSessionGeneration
    ) {
        macLocationCoordinate = coordinate
        guard macInitialCenterIntent == nil, !userHasMapContext else {
            return
        }
        macInitialCenterIntent = MacInitialCenterIntent(
            coordinate: coordinate,
            generation: generation
        )
    }

    func recordManualCameraInteraction() {
        recordUserMapContext()
    }

    func requestMacRecenter() throws {
        guard let macLocationCoordinate else {
            throw LocationMapError.macLocationUnavailable
        }
        recordUserMapContext()
        macRecenterGeneration = try macRecenterGeneration.advanced()
        macRecenterIntent = MacRecenterIntent(
            coordinate: macLocationCoordinate,
            generation: macRecenterGeneration
        )
    }

    func resetWorkspace() throws {
        let nextSearchGeneration = try mapSearchGeneration.advanced()
        let nextRouteGeneration = try routeRequestGeneration.advanced()
        let nextMacRecenterGeneration = try macLocationCoordinate.map { _ in
            try macRecenterGeneration.advanced()
        }

        mapSearchGeneration = nextSearchGeneration
        routeRequestGeneration = nextRouteGeneration
        activeSearchRequest = nil
        activeDirectionsRequest = nil
        preview = nil
        previewCameraIntent = nil
        searchResults = []
        endpointA = nil
        endpointB = nil
        routePreview = nil
        routeCameraIdentity = nil
        routeStatus = .idle
        walkingSpeedKilometersPerHour = Self.defaultWalkingSpeed

        macInitialCenterIntent = nil
        macRecenterIntent = nil
        if let macLocationCoordinate, let nextMacRecenterGeneration {
            macRecenterGeneration = nextMacRecenterGeneration
            macRecenterIntent = MacRecenterIntent(
                coordinate: macLocationCoordinate,
                generation: nextMacRecenterGeneration
            )
        } else {
            userHasMapContext = false
        }
    }

    private static func isValidSpeed(_ speed: Double) -> Bool {
        speed.isFinite && walkingSpeedRange.contains(speed)
    }

    private func advanceSearchOwnership() throws {
        mapSearchGeneration = try mapSearchGeneration.advanced()
    }

    private func invalidateDirectionsOwnership(
        nextGeneration: RouteRequestGeneration
    ) {
        routeRequestGeneration = nextGeneration
        activeDirectionsRequest = nil
        routePreview = nil
        routeCameraIdentity = nil
        routeStatus = .idle
    }

    private func recordUserMapContext() {
        userHasMapContext = true
        macInitialCenterIntent = nil
        macRecenterIntent = nil
    }
}

import XCTest
@testable import iPhoneLocationMove

@MainActor
final class LocationMapModelTests: XCTestCase {
    func testSelectedSearchResultBecomesPreviewAndRequiresExplicitConfirmation() throws {
        let model = LocationMapModel()
        let request = try model.beginSearch(query: "Taipei 101")
        let place = searchPlace(
            latitude: 25.033_968,
            longitude: 121.564_468,
            address: "台北 101"
        )

        XCTAssertEqual(
            model.receiveSearchResults([place], for: request),
            .applied
        )
        try model.selectSearchResult(place, from: request)

        XCTAssertEqual(model.preview, place)
        XCTAssertTrue(model.selectionRequiresExplicitConfirmation)
        XCTAssertNil(model.routePreview)
    }

    func testOlderSearchResponseCannotReplaceNewerQueryResults() throws {
        let model = LocationMapModel()
        let oldRequest = try model.beginSearch(query: "舊查詢")
        let newRequest = try model.beginSearch(query: "新查詢")
        let oldPlace = searchPlace(latitude: 25, longitude: 121, address: "舊地點")
        let newPlace = searchPlace(latitude: 24, longitude: 120, address: "新地點")

        XCTAssertEqual(
            model.receiveSearchResults([oldPlace], for: oldRequest),
            .stale
        )
        XCTAssertEqual(
            model.receiveSearchResults([newPlace], for: newRequest),
            .applied
        )

        XCTAssertEqual(model.searchResults, [newPlace])
    }

    func testMapClickInvalidatesInflightSearchAndIgnoresItsLateResponse() throws {
        let model = LocationMapModel()
        let request = try model.beginSearch(query: "尚未完成")
        let clicked = coordinate(latitude: 25.04, longitude: 121.53)
        let oldPlace = searchPlace(latitude: 22, longitude: 120, address: "舊結果")

        try model.selectMapCoordinate(clicked)

        XCTAssertGreaterThan(model.mapSearchGeneration, request.generation)
        XCTAssertEqual(model.preview?.coordinate, clicked)
        XCTAssertEqual(
            model.receiveSearchResults([oldPlace], for: request),
            .stale
        )
        XCTAssertEqual(model.preview?.coordinate, clicked)
    }

    func testClearingSearchInvalidatesLateResponseAndClearsPreviewOwnership() throws {
        let model = LocationMapModel()
        let request = try model.beginSearch(query: "待清除")
        try model.clearSearch()

        XCTAssertEqual(
            model.receiveSearchResults(
                [searchPlace(latitude: 25, longitude: 121, address: "晚到結果")],
                for: request
            ),
            .stale
        )
        XCTAssertNil(model.preview)
        XCTAssertTrue(model.searchResults.isEmpty)
        XCTAssertFalse(model.selectionRequiresExplicitConfirmation)
    }

    func testMapClickOnlyUpdatesLocalPreview() throws {
        let model = LocationMapModel()
        let clicked = coordinate(latitude: 23.5, longitude: 120.5)

        try model.selectMapCoordinate(clicked)

        XCTAssertEqual(
            model.preview,
            MapSearchPlace(coordinate: clicked, address: nil)
        )
        XCTAssertTrue(model.selectionRequiresExplicitConfirmation)
    }

    func testMapClickAddressResponseUsesPreviewOwnershipGeneration() throws {
        let model = LocationMapModel()
        let oldRequest = try model.selectMapCoordinate(
            coordinate(latitude: 23.5, longitude: 120.5)
        )
        let currentRequest = try model.selectMapCoordinate(
            coordinate(latitude: 25.0, longitude: 121.5)
        )

        XCTAssertEqual(
            model.receivePreviewAddress("舊地址", for: oldRequest),
            .stale
        )
        XCTAssertEqual(
            model.receivePreviewAddress("目前地址", for: currentRequest),
            .applied
        )
        XCTAssertEqual(model.preview?.address, "目前地址")
    }

    func testPreviewCanBeAssignedToDistinctAAndBEndpoints() throws {
        let model = LocationMapModel()
        let a = coordinate(latitude: 25.03, longitude: 121.56)
        let b = coordinate(latitude: 25.04, longitude: 121.57)

        try model.selectMapCoordinate(a)
        try model.assignPreview(to: .a)
        try model.selectMapCoordinate(b)
        try model.assignPreview(to: .b)

        XCTAssertEqual(
            model.endpointSnapshot,
            MapEndpointSnapshot(a: a, b: b)
        )
    }

    func testEndpointChangeWhileDirectionsIsInflightMakesOldRouteStale() throws {
        let model = try modelWithEndpoints()
        let request = try model.beginDirections()
        let changedA = coordinate(latitude: 24.99, longitude: 121.49)

        try model.selectMapCoordinate(changedA)
        try model.assignPreview(to: .a)
        let outcome = try model.receiveDirections(
            .routeAvailable(polyline(), distance: 900),
            for: request
        )

        XCTAssertEqual(outcome, .stale)
        XCTAssertNil(model.routePreview)
        XCTAssertEqual(model.routeStatus, .idle)
    }

    func testDirectionsOutcomesRemainDistinctAndKeepEndpoints() throws {
        let noRouteModel = try modelWithEndpoints()
        let noRouteSnapshot = try XCTUnwrap(noRouteModel.endpointSnapshot)
        let noRouteRequest = try noRouteModel.beginDirections()
        XCTAssertEqual(
            try noRouteModel.receiveDirections(
                .noPedestrianRoute,
                for: noRouteRequest
            ),
            .noPedestrianRoute
        )
        XCTAssertEqual(noRouteModel.routeStatus, .noPedestrianRoute)
        XCTAssertEqual(noRouteModel.endpointSnapshot, noRouteSnapshot)
        XCTAssertFalse(noRouteModel.canStartRoute)

        let cancelledModel = try modelWithEndpoints()
        let cancelledSnapshot = try XCTUnwrap(cancelledModel.endpointSnapshot)
        let cancelledRequest = try cancelledModel.beginDirections()
        XCTAssertEqual(
            try cancelledModel.receiveDirections(.cancelled, for: cancelledRequest),
            .cancelled
        )
        XCTAssertEqual(cancelledModel.routeStatus, .cancelled)
        XCTAssertEqual(cancelledModel.endpointSnapshot, cancelledSnapshot)

        let transientModel = try modelWithEndpoints()
        let transientSnapshot = try XCTUnwrap(transientModel.endpointSnapshot)
        let transientRequest = try transientModel.beginDirections()
        XCTAssertEqual(
            try transientModel.receiveDirections(
                .transientFailure(message: "offline"),
                for: transientRequest
            ),
            .transientFailure
        )
        XCTAssertEqual(
            transientModel.routeStatus,
            .transientFailure(message: "offline")
        )
        XCTAssertEqual(transientModel.endpointSnapshot, transientSnapshot)
        XCTAssertTrue(transientModel.canRetryDirections)
        XCTAssertFalse(transientModel.canStartRoute)
    }

    func testOutOfOrderDirectionsResponseIsReportedAsStale() throws {
        let model = try modelWithEndpoints()
        let oldRequest = try model.beginDirections()
        let currentRequest = try model.beginDirections()

        XCTAssertEqual(
            try model.receiveDirections(
                .routeAvailable(polyline(), distance: 900),
                for: oldRequest
            ),
            .stale
        )
        XCTAssertEqual(model.routeStatus, .loading(currentRequest.snapshot))
    }

    func testRoutePreviewHasImmutablePolylineSnapshotDistanceAndCurrentSpeedETA() throws {
        let model = try modelWithEndpoints()
        let request = try model.beginDirections()
        let originalPolyline = polyline()

        XCTAssertEqual(
            try model.receiveDirections(
                .routeAvailable(originalPolyline, distance: 900),
                for: request
            ),
            .routeAvailable
        )
        let confirmed = try model.confirmRoutePreview()

        XCTAssertEqual(model.routePreview?.endpointSnapshot, request.snapshot)
        XCTAssertEqual(model.routePreview?.polyline, originalPolyline)
        XCTAssertEqual(model.routePreview?.distance, 900)
        XCTAssertEqual(
            try XCTUnwrap(model.routePreview?.estimatedTime),
            720,
            accuracy: 0.000_001
        )
        XCTAssertTrue(model.canStartRoute)

        try model.setWalkingSpeed(kilometersPerHour: 6)
        XCTAssertEqual(
            try XCTUnwrap(model.routePreview?.estimatedTime),
            540,
            accuracy: 0.000_001
        )
        XCTAssertEqual(confirmed.polyline, originalPolyline)
        XCTAssertEqual(confirmed.estimatedTime, 720, accuracy: 0.000_001)

        try model.selectMapCoordinate(
            coordinate(latitude: 25.08, longitude: 121.60)
        )
        try model.assignPreview(to: .b)
        XCTAssertEqual(confirmed.polyline, originalPolyline)
        XCTAssertNil(model.routePreview)
    }

    func testInvalidInputFailsExplicitlyWithoutChangingOwnedState() throws {
        let model = LocationMapModel()

        XCTAssertThrowsError(try model.beginSearch(query: "   "))
        XCTAssertThrowsError(try model.beginDirections())
        XCTAssertThrowsError(try model.setWalkingSpeed(kilometersPerHour: 0))
        XCTAssertNil(model.preview)
        XCTAssertEqual(model.mapSearchGeneration, MapSearchGeneration(rawValue: 0))
    }

    private func modelWithEndpoints() throws -> LocationMapModel {
        let model = LocationMapModel()
        try model.selectMapCoordinate(
            coordinate(latitude: 25.03, longitude: 121.56)
        )
        try model.assignPreview(to: .a)
        try model.selectMapCoordinate(
            coordinate(latitude: 25.04, longitude: 121.57)
        )
        try model.assignPreview(to: .b)
        return model
    }

    private func polyline() -> [MapCoordinate] {
        [
            coordinate(latitude: 25.03, longitude: 121.56),
            coordinate(latitude: 25.035, longitude: 121.565),
            coordinate(latitude: 25.04, longitude: 121.57),
        ]
    }

    private func searchPlace(
        latitude: Double,
        longitude: Double,
        address: String
    ) -> MapSearchPlace {
        MapSearchPlace(
            coordinate: coordinate(latitude: latitude, longitude: longitude),
            address: address
        )
    }

    private func coordinate(
        latitude: Double,
        longitude: Double
    ) -> MapCoordinate {
        try! MapCoordinate(latitude: latitude, longitude: longitude)
    }
}

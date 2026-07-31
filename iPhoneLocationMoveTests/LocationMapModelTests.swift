import MapKit
import XCTest
@testable import iPhoneLocationMove

@MainActor
final class LocationMapModelTests: XCTestCase {
    func testDisplayedSearchResultsCanBeSelectedInSequence() throws {
        let model = LocationMapModel()
        let request = try model.beginSearch(query: "大坑")
        let placeA = searchPlace(
            latitude: 23.959_731,
            longitude: 120.738_768,
            address: "大坑"
        )
        let placeB = searchPlace(
            latitude: 24.184_092,
            longitude: 120.741_168,
            address: "大坑里"
        )
        XCTAssertEqual(
            model.receiveSearchResults([placeA, placeB], for: request),
            .applied
        )

        try model.selectSearchResult(placeA)
        let firstIntent = try XCTUnwrap(model.previewCameraIntent)
        try model.selectSearchResult(placeB)
        let secondIntent = try XCTUnwrap(model.previewCameraIntent)

        XCTAssertNotEqual(firstIntent.identity, secondIntent.identity)
        XCTAssertEqual(model.preview, placeB)
        XCTAssertEqual(secondIntent.coordinate, placeB.coordinate)
        XCTAssertEqual(secondIntent.identity, model.mapSearchGeneration)
        XCTAssertEqual(model.searchResults, [placeA, placeB])
    }

    func testSelectingSameDisplayedSearchResultAgainAdvancesCameraIntent() throws {
        let model = LocationMapModel()
        let request = try model.beginSearch(query: "大坑")
        let place = searchPlace(
            latitude: 23.959_731,
            longitude: 120.738_768,
            address: "大坑"
        )
        XCTAssertEqual(
            model.receiveSearchResults([place], for: request),
            .applied
        )

        try model.selectSearchResult(place)
        let firstGeneration = model.mapSearchGeneration
        let firstIntent = try XCTUnwrap(model.previewCameraIntent)
        try model.selectSearchResult(place)
        let secondIntent = try XCTUnwrap(model.previewCameraIntent)

        XCTAssertGreaterThan(model.mapSearchGeneration, firstGeneration)
        XCTAssertNotEqual(secondIntent.identity, firstIntent.identity)
        XCTAssertEqual(secondIntent.identity, model.mapSearchGeneration)
        XCTAssertEqual(model.preview, place)
    }

    func testSearchResultOutsideCurrentResultsIsRejectedWithoutChangingState() throws {
        let model = LocationMapModel()
        let request = try model.beginSearch(query: "大坑")
        let currentPlace = searchPlace(
            latitude: 23.959_731,
            longitude: 120.738_768,
            address: "大坑"
        )
        let stalePlace = searchPlace(
            latitude: 24.184_092,
            longitude: 120.741_168,
            address: "舊結果"
        )
        XCTAssertEqual(
            model.receiveSearchResults([currentPlace], for: request),
            .applied
        )
        try model.selectSearchResult(currentPlace)
        let preview = model.preview
        let generation = model.mapSearchGeneration
        let intent = model.previewCameraIntent
        let results = model.searchResults

        XCTAssertThrowsError(try model.selectSearchResult(stalePlace)) { error in
            XCTAssertEqual(error as? LocationMapError, .staleSearchSelection)
        }

        XCTAssertEqual(model.preview, preview)
        XCTAssertEqual(model.mapSearchGeneration, generation)
        XCTAssertEqual(model.previewCameraIntent, intent)
        XCTAssertEqual(model.searchResults, results)
    }

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
        try model.selectSearchResult(place)

        XCTAssertEqual(model.preview, place)
        XCTAssertTrue(model.selectionRequiresExplicitConfirmation)
        XCTAssertNil(model.routePreview)
    }

    func testPreviewCameraIntentFollowsSearchAndMapSelectionOwnership() throws {
        let model = LocationMapModel()
        let place = searchPlace(
            latitude: 25.033_968,
            longitude: 121.564_468,
            address: "台北 101"
        )
        let request = try model.beginSearch(query: "Taipei 101")
        XCTAssertEqual(model.receiveSearchResults([place], for: request), .applied)

        try model.selectSearchResult(place)

        let searchIntent = try XCTUnwrap(model.previewCameraIntent)
        XCTAssertEqual(searchIntent.coordinate, place.coordinate)
        XCTAssertEqual(searchIntent.identity, model.mapSearchGeneration)

        try model.selectMapCoordinate(
            coordinate(latitude: 25.04, longitude: 121.53)
        )

        XCTAssertNil(model.previewCameraIntent)
    }

    func testPreviewCameraIntentClearsWithPreviewOwnershipAndSurvivesFailures() throws {
        let model = LocationMapModel()
        let place = searchPlace(
            latitude: 25.033_968,
            longitude: 121.564_468,
            address: "台北 101"
        )
        let request = try model.beginSearch(query: "Taipei 101")
        XCTAssertEqual(model.receiveSearchResults([place], for: request), .applied)
        try model.selectSearchResult(place)
        let selectedIntent = try XCTUnwrap(model.previewCameraIntent)

        try model.selectSearchResult(place)
        let repeatedIntent = try XCTUnwrap(model.previewCameraIntent)
        XCTAssertNotEqual(repeatedIntent.identity, selectedIntent.identity)
        XCTAssertThrowsError(try model.beginSearch(query: "   "))
        XCTAssertEqual(model.previewCameraIntent, repeatedIntent)

        _ = try model.beginSearch(query: "新搜尋")
        XCTAssertNil(model.previewCameraIntent)

        let secondRequest = try model.beginSearch(query: "再次搜尋")
        XCTAssertEqual(
            model.receiveSearchResults([place], for: secondRequest),
            .applied
        )
        try model.selectSearchResult(place)
        XCTAssertNotNil(model.previewCameraIntent)

        try model.clearSearch()
        XCTAssertNil(model.previewCameraIntent)

        let thirdRequest = try model.beginSearch(query: "重置前搜尋")
        XCTAssertEqual(
            model.receiveSearchResults([place], for: thirdRequest),
            .applied
        )
        try model.selectSearchResult(place)
        XCTAssertNotNil(model.previewCameraIntent)

        try model.resetWorkspace()
        XCTAssertNil(model.previewCameraIntent)
    }

    func testPreviewAddressUpdateDoesNotCreateCameraIntent() throws {
        let model = LocationMapModel()
        let request = try model.selectMapCoordinate(
            coordinate(latitude: 25.04, longitude: 121.53)
        )

        XCTAssertEqual(
            model.receivePreviewAddress("點擊地址", for: request),
            .applied
        )

        XCTAssertEqual(model.preview?.address, "點擊地址")
        XCTAssertNil(model.previewCameraIntent)
    }

    func testStalePreviewAddressPreservesSearchCameraIntent() throws {
        let model = LocationMapModel()
        let staleAddressRequest = try model.selectMapCoordinate(
            coordinate(latitude: 25.04, longitude: 121.53)
        )
        let place = searchPlace(
            latitude: 25.033_968,
            longitude: 121.564_468,
            address: "台北 101"
        )
        let searchRequest = try model.beginSearch(query: "Taipei 101")
        XCTAssertEqual(
            model.receiveSearchResults([place], for: searchRequest),
            .applied
        )
        try model.selectSearchResult(place)
        let searchIntent = try XCTUnwrap(model.previewCameraIntent)

        XCTAssertEqual(
            model.receivePreviewAddress(
                "晚到地址",
                for: staleAddressRequest
            ),
            .stale
        )
        XCTAssertEqual(model.preview, place)
        XCTAssertEqual(model.previewCameraIntent, searchIntent)
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

    func testMacLocationMarkerDoesNotModifyPreviewEndpointsOrRouteState() throws {
        let model = try modelWithEndpoints()
        let request = try model.beginDirections()
        _ = try model.receiveDirections(
            .routeAvailable(polyline(), distance: 900),
            for: request
        )
        let preview = model.preview
        let endpointA = model.endpointA
        let endpointB = model.endpointB
        let routePreview = model.routePreview
        let routeStatus = model.routeStatus

        model.updateMacLocation(
            coordinate(latitude: 25.05, longitude: 121.55),
            for: DeviceSessionGeneration(rawValue: 1)
        )

        XCTAssertEqual(
            model.macLocationCoordinate,
            coordinate(latitude: 25.05, longitude: 121.55)
        )
        XCTAssertEqual(model.preview, preview)
        XCTAssertEqual(model.endpointA, endpointA)
        XCTAssertEqual(model.endpointB, endpointB)
        XCTAssertEqual(model.routePreview, routePreview)
        XCTAssertEqual(model.routeStatus, routeStatus)
    }

    func testFirstMacLocationCreatesInitialCenterIntentWithSessionIdentityOnce() throws {
        let model = LocationMapModel()
        let firstCoordinate = coordinate(latitude: 25.05, longitude: 121.55)
        let firstGeneration = DeviceSessionGeneration(rawValue: 1)

        model.updateMacLocation(firstCoordinate, for: firstGeneration)

        XCTAssertEqual(model.macInitialCenterIntent?.coordinate, firstCoordinate)
        XCTAssertEqual(model.macInitialCenterIntent?.generation, firstGeneration)
        let initialIntent = model.macInitialCenterIntent

        model.updateMacLocation(
            coordinate(latitude: 25.06, longitude: 121.56),
            for: firstGeneration
        )

        XCTAssertEqual(model.macInitialCenterIntent, initialIntent)
    }

    func testSearchInteractionRevokesMacInitialCenterEligibility() throws {
        let model = LocationMapModel()

        _ = try model.beginSearch(query: "台北車站")
        model.updateMacLocation(
            coordinate(latitude: 25.05, longitude: 121.55),
            for: DeviceSessionGeneration(rawValue: 1)
        )

        XCTAssertNotNil(model.macLocationCoordinate)
        XCTAssertNil(model.macInitialCenterIntent)
    }

    func testMapSelectionRevokesMacInitialCenterEligibility() throws {
        let model = LocationMapModel()

        try model.selectMapCoordinate(
            coordinate(latitude: 25.04, longitude: 121.53)
        )
        model.updateMacLocation(
            coordinate(latitude: 25.05, longitude: 121.55),
            for: DeviceSessionGeneration(rawValue: 1)
        )

        XCTAssertNotNil(model.macLocationCoordinate)
        XCTAssertNil(model.macInitialCenterIntent)
    }

    func testEndpointAndRouteInteractionsRevokeMacInitialCenterEligibility() throws {
        let endpointModel = LocationMapModel()
        try endpointModel.selectMapCoordinate(
            coordinate(latitude: 25.03, longitude: 121.56)
        )
        try endpointModel.assignPreview(to: .a)
        endpointModel.updateMacLocation(
            coordinate(latitude: 25.05, longitude: 121.55),
            for: DeviceSessionGeneration(rawValue: 1)
        )

        XCTAssertNotNil(endpointModel.macLocationCoordinate)
        XCTAssertNil(endpointModel.macInitialCenterIntent)

        let routeModel = try modelWithEndpoints()
        _ = try routeModel.beginDirections()
        routeModel.updateMacLocation(
            coordinate(latitude: 25.05, longitude: 121.55),
            for: DeviceSessionGeneration(rawValue: 1)
        )

        XCTAssertNotNil(routeModel.macLocationCoordinate)
        XCTAssertNil(routeModel.macInitialCenterIntent)
    }

    func testManualCameraInteractionRevokesMacInitialCenterEligibility() {
        let model = LocationMapModel()

        model.recordManualCameraInteraction()
        model.updateMacLocation(
            coordinate(latitude: 25.05, longitude: 121.55),
            for: DeviceSessionGeneration(rawValue: 1)
        )

        XCTAssertNotNil(model.macLocationCoordinate)
        XCTAssertNil(model.macInitialCenterIntent)
    }

    func testMacRecenterRequiresCurrentMacLocation() {
        let model = LocationMapModel()

        XCTAssertThrowsError(try model.requestMacRecenter()) { error in
            XCTAssertEqual(error as? LocationMapError, .macLocationUnavailable)
        }
        XCTAssertFalse(model.canRecenterOnMac)
        XCTAssertNil(model.macRecenterIntent)
    }

    func testMacRecenterPublishesNewIdentityForEveryRequest() throws {
        let model = LocationMapModel()
        let macLocation = coordinate(latitude: 25.05, longitude: 121.55)
        model.updateMacLocation(
            macLocation,
            for: DeviceSessionGeneration(rawValue: 1)
        )

        try model.requestMacRecenter()
        let firstIntent = try XCTUnwrap(model.macRecenterIntent)
        try model.requestMacRecenter()
        let secondIntent = try XCTUnwrap(model.macRecenterIntent)

        XCTAssertTrue(model.canRecenterOnMac)
        XCTAssertEqual(firstIntent.coordinate, macLocation)
        XCTAssertEqual(secondIntent.coordinate, macLocation)
        XCTAssertGreaterThan(secondIntent.generation, firstIntent.generation)
    }

    func testMacRecenterClearsPendingInitialCenterIntent() throws {
        let model = LocationMapModel()
        model.updateMacLocation(
            coordinate(latitude: 25.05, longitude: 121.55),
            for: DeviceSessionGeneration(rawValue: 1)
        )
        XCTAssertNotNil(model.macInitialCenterIntent)

        try model.requestMacRecenter()

        XCTAssertNil(model.macInitialCenterIntent)
        XCTAssertNotNil(model.macRecenterIntent)
    }

    func testManualCameraInteractionClearsPendingMacRecenterIntent() throws {
        let model = LocationMapModel()
        model.updateMacLocation(
            coordinate(latitude: 25.05, longitude: 121.55),
            for: DeviceSessionGeneration(rawValue: 1)
        )
        try model.requestMacRecenter()

        model.recordManualCameraInteraction()

        XCTAssertNil(model.macRecenterIntent)
    }

    func testResetWorkspaceClearsMapStateAndRestoresDefaultSpeed() throws {
        let model = LocationMapModel()
        let a = searchPlace(
            latitude: 25.03,
            longitude: 121.56,
            address: "A"
        )
        let searchRequest = try model.beginSearch(query: "A")
        XCTAssertEqual(
            model.receiveSearchResults([a], for: searchRequest),
            .applied
        )
        try model.selectSearchResult(a)
        try model.assignPreview(to: .a)
        try model.selectMapCoordinate(
            coordinate(latitude: 25.04, longitude: 121.57)
        )
        try model.assignPreview(to: .b)
        let directionsRequest = try model.beginDirections()
        _ = try model.receiveDirections(
            .routeAvailable(polyline(), distance: 900),
            for: directionsRequest
        )
        try model.setWalkingSpeed(kilometersPerHour: 6)

        let searchGeneration = model.mapSearchGeneration
        let routeGeneration = model.routeRequestGeneration
        try model.resetWorkspace()

        XCTAssertNil(model.preview)
        XCTAssertTrue(model.searchResults.isEmpty)
        XCTAssertNil(model.endpointA)
        XCTAssertNil(model.endpointB)
        XCTAssertNil(model.routePreview)
        XCTAssertNil(model.routeCameraIdentity)
        XCTAssertEqual(model.routeStatus, .idle)
        XCTAssertEqual(model.walkingSpeedKilometersPerHour, 4.5)
        XCTAssertGreaterThan(model.mapSearchGeneration, searchGeneration)
        XCTAssertGreaterThan(model.routeRequestGeneration, routeGeneration)
    }

    func testResetWorkspaceMakesInflightMapResponsesStale() throws {
        let searchModel = LocationMapModel()
        let searchRequest = try searchModel.beginSearch(query: "舊搜尋")
        try searchModel.resetWorkspace()
        XCTAssertEqual(
            searchModel.receiveSearchResults(
                [searchPlace(latitude: 25, longitude: 121, address: "晚到結果")],
                for: searchRequest
            ),
            .stale
        )

        let previewModel = LocationMapModel()
        let previewRequest = try previewModel.selectMapCoordinate(
            coordinate(latitude: 25.03, longitude: 121.56)
        )
        try previewModel.resetWorkspace()
        XCTAssertEqual(
            previewModel.receivePreviewAddress("晚到地址", for: previewRequest),
            .stale
        )

        let directionsModel = try modelWithEndpoints()
        let directionsRequest = try directionsModel.beginDirections()
        try directionsModel.resetWorkspace()
        XCTAssertEqual(
            try directionsModel.receiveDirections(
                .routeAvailable(polyline(), distance: 900),
                for: directionsRequest
            ),
            .stale
        )
    }

    func testResetWorkspaceRearmsInitialCenterWhenMacLocationIsUnavailable() throws {
        let model = LocationMapModel()
        model.recordManualCameraInteraction()

        try model.resetWorkspace()
        model.updateMacLocation(
            coordinate(latitude: 25.05, longitude: 121.55),
            for: DeviceSessionGeneration(rawValue: 1)
        )

        XCTAssertNotNil(model.macInitialCenterIntent)
        XCTAssertNil(model.macRecenterIntent)
    }

    func testResetWorkspacePublishesMacRecenterWhenLocationIsAvailable() throws {
        let model = LocationMapModel()
        let macLocation = coordinate(latitude: 25.05, longitude: 121.55)
        model.updateMacLocation(
            macLocation,
            for: DeviceSessionGeneration(rawValue: 1)
        )
        model.recordManualCameraInteraction()

        try model.resetWorkspace()

        XCTAssertNil(model.macInitialCenterIntent)
        XCTAssertEqual(model.macRecenterIntent?.coordinate, macLocation)
        XCTAssertEqual(
            model.macRecenterIntent?.generation,
            model.macRecenterGeneration
        )
    }

    func testReconnectOnlyUpdatesMarkerAfterInitialCenterIntentWasCreated() throws {
        let model = LocationMapModel()
        let initialCoordinate = coordinate(latitude: 25.05, longitude: 121.55)
        let reconnectedCoordinate = coordinate(latitude: 24.15, longitude: 120.68)

        model.updateMacLocation(
            initialCoordinate,
            for: DeviceSessionGeneration(rawValue: 1)
        )
        let initialIntent = try XCTUnwrap(model.macInitialCenterIntent)

        model.updateMacLocation(
            reconnectedCoordinate,
            for: DeviceSessionGeneration(rawValue: 2)
        )

        XCTAssertEqual(model.macLocationCoordinate, reconnectedCoordinate)
        XCTAssertEqual(model.macInitialCenterIntent, initialIntent)
        XCTAssertEqual(
            model.macInitialCenterIntent?.generation,
            DeviceSessionGeneration(rawValue: 1)
        )
    }

    func testRouteCameraIdentityUsesAcceptedRequestAndSurvivesAnnotationRedraw() throws {
        let model = try modelWithEndpoints()
        let firstRequest = try model.beginDirections()
        _ = try model.receiveDirections(
            .routeAvailable(polyline(), distance: 900),
            for: firstRequest
        )

        XCTAssertEqual(model.routeCameraIdentity, firstRequest.generation)

        model.updateMacLocation(
            coordinate(latitude: 25.05, longitude: 121.55),
            for: DeviceSessionGeneration(rawValue: 1)
        )

        XCTAssertEqual(model.routeCameraIdentity, firstRequest.generation)

        let secondRequest = try model.beginDirections()
        _ = try model.receiveDirections(
            .routeAvailable(polyline(), distance: 900),
            for: secondRequest
        )

        XCTAssertNotEqual(secondRequest.generation, firstRequest.generation)
        XCTAssertEqual(model.routeCameraIdentity, secondRequest.generation)
    }

    func testCameraEffectsApplyEachRouteIdentityOnce() {
        let effects = LocationMapCameraEffects()
        let first = RouteRequestGeneration(rawValue: 1)
        let second = RouteRequestGeneration(rawValue: 2)
        var applicationCount = 0

        effects.applyRoute(first) {
            applicationCount += 1
        }
        effects.applyRoute(first) {
            applicationCount += 1
        }
        effects.applyRoute(second) {
            applicationCount += 1
        }

        XCTAssertEqual(applicationCount, 2)
    }

    func testMapClickAndLateSearchResponsePreserveVisibleRegion() throws {
        let mapView = CameraOperationSpyMapView()
        let coordinator = LocationMapCanvas.Coordinator(
            onCoordinateSelected: { _ in },
            onManualCameraInteraction: {}
        )
        coordinator.mapView = mapView
        let initialRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 25.04, longitude: 121.53),
            latitudinalMeters: 200,
            longitudinalMeters: 200
        )
        mapView.establishRegion(initialRegion)
        let baselineCounts = mapView.cameraOperationCounts
        let baselineRegion = mapView.region

        let model = LocationMapModel()
        let staleRequest = try model.beginSearch(query: "尚未完成")
        let clicked = coordinate(latitude: 25.040_2, longitude: 121.530_2)
        let addressRequest = try model.selectMapCoordinate(clicked)

        coordinator.update(
            preview: model.preview,
            previewCameraIntent: model.previewCameraIntent,
            endpointA: nil,
            endpointB: nil,
            route: nil,
            routeCameraIdentity: nil,
            macLocation: nil,
            macInitialCenterIntent: nil,
            confirmedRouteMarkerCoordinate: nil
        )
        XCTAssertEqual(mapView.cameraOperationCounts, baselineCounts)
        assertRegion(mapView.region, equals: baselineRegion)

        XCTAssertEqual(
            model.receivePreviewAddress("點擊地址", for: addressRequest),
            .applied
        )
        coordinator.update(
            preview: model.preview,
            previewCameraIntent: model.previewCameraIntent,
            endpointA: nil,
            endpointB: nil,
            route: nil,
            routeCameraIdentity: nil,
            macLocation: nil,
            macInitialCenterIntent: nil,
            confirmedRouteMarkerCoordinate: nil
        )

        XCTAssertEqual(
            model.receiveSearchResults(
                [searchPlace(latitude: 22, longitude: 120, address: "舊結果")],
                for: staleRequest
            ),
            .stale
        )
        coordinator.update(
            preview: model.preview,
            previewCameraIntent: model.previewCameraIntent,
            endpointA: nil,
            endpointB: nil,
            route: nil,
            routeCameraIdentity: nil,
            macLocation: nil,
            macInitialCenterIntent: nil,
            confirmedRouteMarkerCoordinate: nil
        )

        let secondClicked = coordinate(
            latitude: 25.040_4,
            longitude: 121.530_4
        )
        try model.selectMapCoordinate(secondClicked)
        coordinator.update(
            preview: model.preview,
            previewCameraIntent: model.previewCameraIntent,
            endpointA: nil,
            endpointB: nil,
            route: nil,
            routeCameraIdentity: nil,
            macLocation: nil,
            macInitialCenterIntent: nil,
            confirmedRouteMarkerCoordinate: nil
        )

        XCTAssertEqual(mapView.cameraOperationCounts, baselineCounts)
        assertRegion(mapView.region, equals: baselineRegion)
        XCTAssertEqual(
            try annotation(titled: "預覽", in: mapView).coordinate.latitude,
            secondClicked.latitude,
            accuracy: 0.000_001
        )
    }

    func testSearchPreviewCentersOnceAndRedrawDoesNotReplay() throws {
        let model = LocationMapModel()
        let place = searchPlace(
            latitude: 25.033_968,
            longitude: 121.564_468,
            address: "台北 101"
        )
        let request = try model.beginSearch(query: "Taipei 101")
        XCTAssertEqual(model.receiveSearchResults([place], for: request), .applied)
        try model.selectSearchResult(place)

        let mapView = CameraOperationSpyMapView()
        let coordinator = LocationMapCanvas.Coordinator(
            onCoordinateSelected: { _ in },
            onManualCameraInteraction: {}
        )
        coordinator.mapView = mapView

        coordinator.update(
            preview: model.preview,
            previewCameraIntent: nil,
            endpointA: nil,
            endpointB: nil,
            route: nil,
            routeCameraIdentity: nil,
            macLocation: nil,
            macInitialCenterIntent: nil,
            confirmedRouteMarkerCoordinate: nil
        )
        let baselineCounts = mapView.cameraOperationCounts
        coordinator.update(
            preview: model.preview,
            previewCameraIntent: model.previewCameraIntent,
            endpointA: nil,
            endpointB: nil,
            route: nil,
            routeCameraIdentity: nil,
            macLocation: nil,
            macInitialCenterIntent: nil,
            confirmedRouteMarkerCoordinate: nil
        )
        let countsAfterCenter = mapView.cameraOperationCounts
        coordinator.update(
            preview: model.preview,
            previewCameraIntent: model.previewCameraIntent,
            endpointA: nil,
            endpointB: nil,
            route: nil,
            routeCameraIdentity: nil,
            macLocation: nil,
            macInitialCenterIntent: nil,
            confirmedRouteMarkerCoordinate: coordinate(
                latitude: 25.04,
                longitude: 121.57
            )
        )

        XCTAssertEqual(
            countsAfterCenter.setRegion,
            baselineCounts.setRegion + 1
        )
        XCTAssertEqual(countsAfterCenter.setCenter, baselineCounts.setCenter)
        XCTAssertEqual(
            countsAfterCenter.setVisibleMapRect,
            baselineCounts.setVisibleMapRect
        )
        XCTAssertEqual(mapView.cameraOperationCounts, countsAfterCenter)
    }

    func testReturningToSameSearchCoordinateUsesNewCameraIdentity() throws {
        let model = LocationMapModel()
        let placeA = searchPlace(
            latitude: 25.033_968,
            longitude: 121.564_468,
            address: "位置 A"
        )
        let firstRequest = try model.beginSearch(query: "位置 A")
        XCTAssertEqual(
            model.receiveSearchResults([placeA], for: firstRequest),
            .applied
        )
        try model.selectSearchResult(placeA)
        let firstIntent = try XCTUnwrap(model.previewCameraIntent)

        let mapView = CameraOperationSpyMapView()
        let coordinator = LocationMapCanvas.Coordinator(
            onCoordinateSelected: { _ in },
            onManualCameraInteraction: {}
        )
        coordinator.mapView = mapView
        coordinator.update(
            preview: model.preview,
            previewCameraIntent: nil,
            endpointA: nil,
            endpointB: nil,
            route: nil,
            routeCameraIdentity: nil,
            macLocation: nil,
            macInitialCenterIntent: nil,
            confirmedRouteMarkerCoordinate: nil
        )
        let baselineCounts = mapView.cameraOperationCounts
        coordinator.update(
            preview: model.preview,
            previewCameraIntent: firstIntent,
            endpointA: nil,
            endpointB: nil,
            route: nil,
            routeCameraIdentity: nil,
            macLocation: nil,
            macInitialCenterIntent: nil,
            confirmedRouteMarkerCoordinate: nil
        )

        try model.selectMapCoordinate(
            coordinate(latitude: 25.04, longitude: 121.53)
        )
        coordinator.update(
            preview: model.preview,
            previewCameraIntent: model.previewCameraIntent,
            endpointA: nil,
            endpointB: nil,
            route: nil,
            routeCameraIdentity: nil,
            macLocation: nil,
            macInitialCenterIntent: nil,
            confirmedRouteMarkerCoordinate: nil
        )

        let secondRequest = try model.beginSearch(query: "位置 A")
        XCTAssertEqual(
            model.receiveSearchResults([placeA], for: secondRequest),
            .applied
        )
        try model.selectSearchResult(placeA)
        let secondIntent = try XCTUnwrap(model.previewCameraIntent)
        coordinator.update(
            preview: model.preview,
            previewCameraIntent: secondIntent,
            endpointA: nil,
            endpointB: nil,
            route: nil,
            routeCameraIdentity: nil,
            macLocation: nil,
            macInitialCenterIntent: nil,
            confirmedRouteMarkerCoordinate: nil
        )

        XCTAssertNotEqual(firstIntent.identity, secondIntent.identity)
        XCTAssertEqual(
            mapView.cameraOperationCounts.setRegion,
            baselineCounts.setRegion + 2
        )
    }

    func testRouteFitConsumesSameRenderPreviewButNotLaterSearchIntent() throws {
        let mapView = CameraOperationSpyMapView()
        let coordinator = LocationMapCanvas.Coordinator(
            onCoordinateSelected: { _ in },
            onManualCameraInteraction: {}
        )
        coordinator.mapView = mapView
        let preview = searchPlace(
            latitude: 25.033_968,
            longitude: 121.564_468,
            address: "搜尋結果"
        )
        let route = polyline()
        let routeIdentity = RouteRequestGeneration(rawValue: 1)
        let sameRenderIntent = MapPreviewCameraIntent(
            coordinate: preview.coordinate,
            identity: MapSearchGeneration(rawValue: 1)
        )

        coordinator.update(
            preview: preview,
            previewCameraIntent: nil,
            endpointA: nil,
            endpointB: nil,
            route: route,
            routeCameraIdentity: nil,
            macLocation: nil,
            macInitialCenterIntent: nil,
            confirmedRouteMarkerCoordinate: nil
        )
        let baselineCounts = mapView.cameraOperationCounts
        coordinator.update(
            preview: preview,
            previewCameraIntent: sameRenderIntent,
            endpointA: nil,
            endpointB: nil,
            route: route,
            routeCameraIdentity: routeIdentity,
            macLocation: nil,
            macInitialCenterIntent: nil,
            confirmedRouteMarkerCoordinate: nil
        )
        coordinator.update(
            preview: preview,
            previewCameraIntent: sameRenderIntent,
            endpointA: nil,
            endpointB: nil,
            route: route,
            routeCameraIdentity: routeIdentity,
            macLocation: nil,
            macInitialCenterIntent: nil,
            confirmedRouteMarkerCoordinate: coordinate(
                latitude: 25.04,
                longitude: 121.57
            )
        )

        XCTAssertEqual(
            mapView.cameraOperationCounts.setVisibleMapRect,
            baselineCounts.setVisibleMapRect + 1
        )
        XCTAssertEqual(
            mapView.cameraOperationCounts.setRegion,
            baselineCounts.setRegion
        )
        XCTAssertEqual(
            mapView.cameraOperationCounts.setCenter,
            baselineCounts.setCenter
        )

        let laterIntent = MapPreviewCameraIntent(
            coordinate: preview.coordinate,
            identity: MapSearchGeneration(rawValue: 2)
        )
        coordinator.update(
            preview: preview,
            previewCameraIntent: laterIntent,
            endpointA: nil,
            endpointB: nil,
            route: route,
            routeCameraIdentity: routeIdentity,
            macLocation: nil,
            macInitialCenterIntent: nil,
            confirmedRouteMarkerCoordinate: nil
        )

        XCTAssertEqual(
            mapView.cameraOperationCounts.setVisibleMapRect,
            baselineCounts.setVisibleMapRect + 1
        )
        XCTAssertEqual(
            mapView.cameraOperationCounts.setRegion,
            baselineCounts.setRegion + 1
        )
        XCTAssertEqual(
            mapView.cameraOperationCounts.setCenter,
            baselineCounts.setCenter
        )
    }

    func testCameraEffectsApplyEachMacRecenterIdentityOnce() {
        let effects = LocationMapCameraEffects()
        let first = MacRecenterGeneration(rawValue: 1)
        let second = MacRecenterGeneration(rawValue: 2)
        var applicationCount = 0

        effects.applyMacRecenter(first) {
            applicationCount += 1
        }
        effects.applyMacRecenter(first) {
            applicationCount += 1
        }
        effects.applyMacRecenter(second) {
            applicationCount += 1
        }
        effects.applyMacRecenter(second) {
            applicationCount += 1
        }

        XCTAssertEqual(applicationCount, 2)
    }

    func testResetConfirmationContentReflectsCleanupOwnership() {
        let cleanup = ResetConfirmationContent.make(
            hasCleanupOwnership: true
        )
        XCTAssertEqual(cleanup.title, "確認重置並停止模擬？")
        XCTAssertTrue(
            cleanup.message.contains(
                "只有手機回覆 clear 成功後，App 才會顯示已恢復真實定位。"
            )
        )

        let localOnly = ResetConfirmationContent.make(
            hasCleanupOwnership: false
        )
        XCTAssertEqual(localOnly.title, "確認重置設定？")
        XCTAssertTrue(localOnly.message.contains("搜尋"))
        XCTAssertTrue(localOnly.message.contains("A/B"))
        XCTAssertTrue(localOnly.message.contains("路線"))
    }

    func testProgrammaticCameraChangeIsNotReportedAsManualInteraction() {
        let effects = LocationMapCameraEffects()
        var manualInteractionCount = 0

        effects.applyPreview(
            MapPreviewCameraIntent(
                coordinate: coordinate(latitude: 25.05, longitude: 121.55),
                identity: MapSearchGeneration(rawValue: 1)
            )
        ) {
            effects.regionWillChange(
                hasActiveGesture: true,
                onManualCameraInteraction: {
                    manualInteractionCount += 1
                }
            )
        }

        XCTAssertEqual(manualInteractionCount, 0)
    }

    func testActiveUserGestureReportsManualCameraInteraction() {
        let effects = LocationMapCameraEffects()
        var manualInteractionCount = 0

        effects.regionWillChange(
            hasActiveGesture: false,
            onManualCameraInteraction: {
                manualInteractionCount += 1
            }
        )
        effects.regionWillChange(
            hasActiveGesture: true,
            onManualCameraInteraction: {
                manualInteractionCount += 1
            }
        )

        XCTAssertEqual(manualInteractionCount, 1)
    }

    func testConfirmedIPhoneMarkerUpdatesInPlaceWithoutReplacingMapContent() throws {
        let mapView = CameraOperationSpyMapView()
        var manualInteractionCount = 0
        let coordinator = LocationMapCanvas.Coordinator(
            onCoordinateSelected: { _ in },
            onManualCameraInteraction: {
                manualInteractionCount += 1
            }
        )
        coordinator.mapView = mapView

        let preview = searchPlace(
            latitude: 25.032,
            longitude: 121.562,
            address: "預覽地址"
        )
        let endpointA = searchPlace(
            latitude: 25.03,
            longitude: 121.56,
            address: "起點"
        )
        let endpointB = searchPlace(
            latitude: 25.04,
            longitude: 121.57,
            address: "終點"
        )
        let macLocation = coordinate(latitude: 25.05, longitude: 121.55)
        let route = polyline()
        let routeIdentity = RouteRequestGeneration(rawValue: 1)
        let firstIPhoneLocation = coordinate(
            latitude: 25.033,
            longitude: 121.563
        )
        let secondIPhoneLocation = coordinate(
            latitude: 25.036,
            longitude: 121.566
        )

        coordinator.update(
            preview: preview,
            previewCameraIntent: nil,
            endpointA: endpointA,
            endpointB: endpointB,
            route: route,
            routeCameraIdentity: routeIdentity,
            macLocation: macLocation,
            macInitialCenterIntent: nil,
            confirmedRouteMarkerCoordinate: firstIPhoneLocation
        )

        let previewAnnotation = try annotation(titled: "預覽", in: mapView)
        let endpointAAnnotation = try annotation(titled: "A", in: mapView)
        let endpointBAnnotation = try annotation(titled: "B", in: mapView)
        let macAnnotation = try annotation(titled: "Mac 目前位置", in: mapView)
        let iPhoneAnnotation = try annotation(
            titled: "iPhone 模擬位置",
            in: mapView
        )
        let routeOverlay = try XCTUnwrap(mapView.overlays.first)
        let cameraCountsAfterInitialRender = mapView.cameraOperationCounts

        coordinator.update(
            preview: preview,
            previewCameraIntent: nil,
            endpointA: endpointA,
            endpointB: endpointB,
            route: route,
            routeCameraIdentity: routeIdentity,
            macLocation: macLocation,
            macInitialCenterIntent: nil,
            confirmedRouteMarkerCoordinate: secondIPhoneLocation
        )

        XCTAssertIdentical(
            try annotation(titled: "預覽", in: mapView),
            previewAnnotation
        )
        XCTAssertIdentical(
            try annotation(titled: "A", in: mapView),
            endpointAAnnotation
        )
        XCTAssertIdentical(
            try annotation(titled: "B", in: mapView),
            endpointBAnnotation
        )
        XCTAssertIdentical(
            try annotation(titled: "Mac 目前位置", in: mapView),
            macAnnotation
        )
        XCTAssertIdentical(
            try annotation(titled: "iPhone 模擬位置", in: mapView),
            iPhoneAnnotation
        )
        XCTAssertEqual(
            iPhoneAnnotation.coordinate.latitude,
            secondIPhoneLocation.latitude,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            iPhoneAnnotation.coordinate.longitude,
            secondIPhoneLocation.longitude,
            accuracy: 0.000_001
        )
        XCTAssertIdentical(try XCTUnwrap(mapView.overlays.first), routeOverlay)
        XCTAssertEqual(mapView.cameraOperationCounts, cameraCountsAfterInitialRender)
        XCTAssertEqual(manualInteractionCount, 0)

        coordinator.update(
            preview: preview,
            previewCameraIntent: nil,
            endpointA: endpointA,
            endpointB: endpointB,
            route: route,
            routeCameraIdentity: routeIdentity,
            macLocation: macLocation,
            macInitialCenterIntent: nil,
            confirmedRouteMarkerCoordinate: nil
        )

        XCTAssertNil(mapView.annotations.first { $0.title == "iPhone 模擬位置" })
        XCTAssertIdentical(
            try annotation(titled: "預覽", in: mapView),
            previewAnnotation
        )
        XCTAssertIdentical(
            try annotation(titled: "A", in: mapView),
            endpointAAnnotation
        )
        XCTAssertIdentical(
            try annotation(titled: "B", in: mapView),
            endpointBAnnotation
        )
        XCTAssertIdentical(
            try annotation(titled: "Mac 目前位置", in: mapView),
            macAnnotation
        )
        XCTAssertIdentical(try XCTUnwrap(mapView.overlays.first), routeOverlay)
        XCTAssertEqual(mapView.cameraOperationCounts, cameraCountsAfterInitialRender)
        XCTAssertEqual(manualInteractionCount, 0)
    }

    func testConfirmedIPhoneMarkerUpdatesDoNotReplayPreviewCameraOperation() {
        let mapView = CameraOperationSpyMapView()
        var manualInteractionCount = 0
        let coordinator = LocationMapCanvas.Coordinator(
            onCoordinateSelected: { _ in },
            onManualCameraInteraction: {
                manualInteractionCount += 1
            }
        )
        coordinator.mapView = mapView
        let preview = searchPlace(
            latitude: 25.032,
            longitude: 121.562,
            address: "預覽地址"
        )
        let previewCameraIntent = MapPreviewCameraIntent(
            coordinate: preview.coordinate,
            identity: MapSearchGeneration(rawValue: 1)
        )

        coordinator.update(
            preview: preview,
            previewCameraIntent: previewCameraIntent,
            endpointA: nil,
            endpointB: nil,
            route: nil,
            routeCameraIdentity: nil,
            macLocation: nil,
            macInitialCenterIntent: nil,
            confirmedRouteMarkerCoordinate: coordinate(
                latitude: 25.033,
                longitude: 121.563
            )
        )
        let cameraCountsAfterInitialRender = mapView.cameraOperationCounts
        XCTAssertGreaterThan(cameraCountsAfterInitialRender.setRegion, 0)
        XCTAssertEqual(cameraCountsAfterInitialRender.setCenter, 0)
        XCTAssertEqual(cameraCountsAfterInitialRender.setVisibleMapRect, 0)

        for offset in 1 ... 3 {
            coordinator.update(
                preview: preview,
                previewCameraIntent: previewCameraIntent,
                endpointA: nil,
                endpointB: nil,
                route: nil,
                routeCameraIdentity: nil,
                macLocation: nil,
                macInitialCenterIntent: nil,
                confirmedRouteMarkerCoordinate: coordinate(
                    latitude: 25.033 + Double(offset) / 1_000,
                    longitude: 121.563 + Double(offset) / 1_000
                )
            )
        }

        XCTAssertEqual(mapView.cameraOperationCounts, cameraCountsAfterInitialRender)
        XCTAssertEqual(manualInteractionCount, 0)
    }

    func testConfirmedIPhoneMarkerUpdatesDoNotReplayMacCameraOperation() {
        let mapView = CameraOperationSpyMapView()
        var manualInteractionCount = 0
        let coordinator = LocationMapCanvas.Coordinator(
            onCoordinateSelected: { _ in },
            onManualCameraInteraction: {
                manualInteractionCount += 1
            }
        )
        coordinator.mapView = mapView
        let macLocation = coordinate(latitude: 25.05, longitude: 121.55)
        let macCenterIntent = MacInitialCenterIntent(
            coordinate: macLocation,
            generation: DeviceSessionGeneration(rawValue: 1)
        )

        coordinator.update(
            preview: nil,
            previewCameraIntent: nil,
            endpointA: nil,
            endpointB: nil,
            route: nil,
            routeCameraIdentity: nil,
            macLocation: macLocation,
            macInitialCenterIntent: macCenterIntent,
            confirmedRouteMarkerCoordinate: coordinate(
                latitude: 25.033,
                longitude: 121.563
            )
        )
        let cameraCountsAfterInitialRender = mapView.cameraOperationCounts

        for offset in 1 ... 3 {
            coordinator.update(
                preview: nil,
                previewCameraIntent: nil,
                endpointA: nil,
                endpointB: nil,
                route: nil,
                routeCameraIdentity: nil,
                macLocation: macLocation,
                macInitialCenterIntent: macCenterIntent,
                confirmedRouteMarkerCoordinate: coordinate(
                    latitude: 25.033 + Double(offset) / 1_000,
                    longitude: 121.563 + Double(offset) / 1_000
                )
            )
        }

        XCTAssertEqual(mapView.cameraOperationCounts, cameraCountsAfterInitialRender)
        XCTAssertEqual(manualInteractionCount, 0)
    }

    func testNewAnnotationsAreConfiguredBeforeBeingAddedToMap() throws {
        let mapView = CameraOperationSpyMapView()
        let coordinator = LocationMapCanvas.Coordinator(
            onCoordinateSelected: { _ in },
            onManualCameraInteraction: {}
        )
        coordinator.mapView = mapView
        let endpointA = searchPlace(
            latitude: 25.03,
            longitude: 121.56,
            address: "起點"
        )

        coordinator.update(
            preview: nil,
            previewCameraIntent: nil,
            endpointA: endpointA,
            endpointB: nil,
            route: nil,
            routeCameraIdentity: nil,
            macLocation: nil,
            macInitialCenterIntent: nil,
            confirmedRouteMarkerCoordinate: nil
        )

        let stateAtInsertion = try XCTUnwrap(
            mapView.addedAnnotationStates.first { $0.title == "A" }
        )
        XCTAssertEqual(stateAtInsertion.latitude, 25.03, accuracy: 0.000_001)
        XCTAssertEqual(stateAtInsertion.longitude, 121.56, accuracy: 0.000_001)
    }

    func testEndpointAndIPhoneMarkersAreNotSuppressedByCollisionLayout() throws {
        let mapView = CameraOperationSpyMapView()
        let coordinator = LocationMapCanvas.Coordinator(
            onCoordinateSelected: { _ in },
            onManualCameraInteraction: {}
        )
        coordinator.mapView = mapView
        let sharedCoordinate = coordinate(latitude: 25.03, longitude: 121.56)

        coordinator.update(
            preview: nil,
            previewCameraIntent: nil,
            endpointA: MapSearchPlace(
                coordinate: sharedCoordinate,
                address: "起點"
            ),
            endpointB: nil,
            route: nil,
            routeCameraIdentity: nil,
            macLocation: nil,
            macInitialCenterIntent: nil,
            confirmedRouteMarkerCoordinate: sharedCoordinate
        )

        let endpointAnnotation = try annotation(titled: "A", in: mapView)
        let iPhoneAnnotation = try annotation(
            titled: "iPhone 模擬位置",
            in: mapView
        )
        let endpointView = try XCTUnwrap(
            coordinator.mapView(mapView, viewFor: endpointAnnotation)
        )
        let iPhoneView = try XCTUnwrap(
            coordinator.mapView(mapView, viewFor: iPhoneAnnotation)
        )

        XCTAssertEqual(endpointView.displayPriority, .required)
        XCTAssertEqual(endpointView.collisionMode, .none)
        XCTAssertEqual(iPhoneView.displayPriority, .required)
        XCTAssertEqual(iPhoneView.collisionMode, .none)
    }

    private func annotation(
        titled title: String,
        in mapView: MKMapView
    ) throws -> MKAnnotation {
        try XCTUnwrap(
            mapView.annotations.first {
                $0.title == title
            }
        )
    }

    private func assertRegion(
        _ actual: MKCoordinateRegion,
        equals expected: MKCoordinateRegion,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            actual.center.latitude,
            expected.center.latitude,
            accuracy: 0.000_001,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.center.longitude,
            expected.center.longitude,
            accuracy: 0.000_001,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.span.latitudeDelta,
            expected.span.latitudeDelta,
            accuracy: 0.000_001,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.span.longitudeDelta,
            expected.span.longitudeDelta,
            accuracy: 0.000_001,
            file: file,
            line: line
        )
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

@MainActor
private final class CameraOperationSpyMapView: MKMapView {
    struct AddedAnnotationState {
        let title: String?
        let latitude: CLLocationDegrees
        let longitude: CLLocationDegrees
    }

    struct Counts: Equatable {
        var setRegion = 0
        var setCenter = 0
        var setVisibleMapRect = 0
    }

    private(set) var cameraOperationCounts = Counts()
    private(set) var addedAnnotationStates: [AddedAnnotationState] = []
    private var isEstablishingRegion = false

    // Camera overrides intentionally do not call super during assertions.
    // Counts are the primary oracle; region checks only catch untracked paths.

    func establishRegion(_ region: MKCoordinateRegion) {
        isEstablishingRegion = true
        super.setRegion(region, animated: false)
        isEstablishingRegion = false
    }

    override func addAnnotation(_ annotation: MKAnnotation) {
        addedAnnotationStates.append(
            AddedAnnotationState(
                title: annotation.title ?? nil,
                latitude: annotation.coordinate.latitude,
                longitude: annotation.coordinate.longitude
            )
        )
        super.addAnnotation(annotation)
    }

    override func setVisibleMapRect(
        _ mapRect: MKMapRect,
        edgePadding insets: NSEdgeInsets,
        animated animate: Bool
    ) {
        if isEstablishingRegion {
            super.setVisibleMapRect(
                mapRect,
                edgePadding: insets,
                animated: animate
            )
            return
        }
        cameraOperationCounts.setVisibleMapRect += 1
    }

    override func setRegion(
        _ region: MKCoordinateRegion,
        animated animate: Bool
    ) {
        if isEstablishingRegion {
            super.setRegion(region, animated: animate)
            return
        }
        cameraOperationCounts.setRegion += 1
    }

    override func setCenter(
        _ coordinate: CLLocationCoordinate2D,
        animated: Bool
    ) {
        if isEstablishingRegion {
            super.setCenter(coordinate, animated: animated)
            return
        }
        cameraOperationCounts.setCenter += 1
    }
}

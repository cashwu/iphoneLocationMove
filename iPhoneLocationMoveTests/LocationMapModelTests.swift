import MapKit
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
        try model.selectSearchResult(a, from: searchRequest)
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
            coordinate(latitude: 25.05, longitude: 121.55)
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

        coordinator.update(
            preview: preview,
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

        for offset in 1 ... 3 {
            coordinator.update(
                preview: preview,
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
        var routeFit = 0
        var center = 0
    }

    private(set) var cameraOperationCounts = Counts()
    private(set) var addedAnnotationStates: [AddedAnnotationState] = []

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
        cameraOperationCounts.routeFit += 1
        super.setVisibleMapRect(
            mapRect,
            edgePadding: insets,
            animated: animate
        )
    }

    override func setRegion(
        _ region: MKCoordinateRegion,
        animated animate: Bool
    ) {
        cameraOperationCounts.center += 1
        super.setRegion(region, animated: animate)
    }
}

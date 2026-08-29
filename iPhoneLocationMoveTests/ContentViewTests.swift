import AppKit
import MapKit
import SwiftUI
import XCTest
@testable import iPhoneLocationMove

@MainActor
final class ContentViewTests: XCTestCase {
    func testDisconnectedSidebarTestingViewsDoNotAffectLayout() async throws {
        let (hostingView, window) = makeMapHostingView()
        defer { removeFromWindow(window) }

        await waitForViewUpdate(hostingView)

        try assertSidebarLayout(
            in: hostingView,
            requiredRegions: [
                "sidebar-device-status-region",
                "sidebar-speed-region",
            ],
            requiredPrimaryButtonIdentifiers: [
                "sidebar-button-mac-recenter",
                "sidebar-button-reset",
                "sidebar-button-directions",
                "sidebar-button-set-location",
                "sidebar-button-start-route",
            ]
        )
        assertTestingActionButtons(in: hostingView)
        attachSnapshot(of: hostingView, name: "sidebar-disconnected")
    }

    func testFavoriteToggleUpdatesTheRenderedHierarchy() async throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let favoritesStore = FavoritesStore(defaults: defaults)
        let model = LocationMapModel()
        _ = try model.selectMapCoordinate(
            MapCoordinate(latitude: 25.033964, longitude: 121.564468)
        )
        let (hostingView, window) = makeMapHostingView(
            model: model,
            favoritesStore: favoritesStore
        )
        defer { removeFromWindow(window) }

        await waitForViewUpdate(hostingView)
        XCTAssertTrue(hasButtonTitle("加入最愛", in: hostingView))
        let addToggle = try XCTUnwrap(
            findButton(in: hostingView, identifier: "favorite-toggle-add-action")
        )
        XCTAssertTrue(hasIdentifier("sidebar-button-favorite-toggle", in: hostingView))
        addToggle.performClick(nil)
        await waitForViewUpdate(hostingView)
        XCTAssertEqual(favoritesStore.favorites.count, 1)
        XCTAssertTrue(hasButtonTitle("取消最愛", in: hostingView))
        let removeToggle = try XCTUnwrap(
            findButton(in: hostingView, identifier: "favorite-toggle-remove-action")
        )
        removeToggle.performClick(nil)
        await waitForViewUpdate(hostingView)
        XCTAssertTrue(favoritesStore.favorites.isEmpty)
        XCTAssertTrue(hasButtonTitle("加入最愛", in: hostingView))
        XCTAssertTrue(hasIdentifier("sidebar-button-favorite-toggle", in: hostingView))
    }

    func testFavoriteRowSelectionUsesModelOwnershipBeforeViewCancellation() async throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let favoritesStore = FavoritesStore(defaults: defaults)
        let favorite = try searchPlace(latitude: 25, longitude: 121, address: "公司")
        favoritesStore.toggle(favorite)
        let model = LocationMapModel()
        let oldRequest = try model.beginSearch(query: "舊搜尋")
        var searchCancellations = 0
        var addressCancellations = 0
        let (hostingView, window) = makeMapHostingView(
            model: model,
            favoritesStore: favoritesStore,
            onSearchCancellationRequested: { searchCancellations += 1 },
            onPreviewAddressCancellationRequested: { addressCancellations += 1 }
        )
        defer { removeFromWindow(window) }

        await waitForViewUpdate(hostingView)
        let action = try XCTUnwrap(
            findButton(
                in: hostingView,
                identifier: "favorite-selection-action-\(favoritesStore.favorites[0].id.uuidString)"
            )
        )
        let mapView = try XCTUnwrap(findMapView(in: hostingView))
        action.performClick(nil)
        await waitForViewUpdate(hostingView)

        XCTAssertEqual(model.preview?.address, "公司")
        XCTAssertTrue(model.searchResults.isEmpty)
        XCTAssertEqual(model.receiveSearchResults([favorite], for: oldRequest), .stale)
        XCTAssertEqual(searchCancellations, 1)
        XCTAssertEqual(addressCancellations, 1)
        try await waitForMapCenter(favorite.coordinate, in: mapView)
    }

    func testFavoriteMutationAndWorkspaceResetRemainIndependentInSameHierarchy() async throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let favoritesStore = FavoritesStore(defaults: defaults)
        let first = try searchPlace(latitude: 25, longitude: 121, address: "公司")
        let second = try searchPlace(latitude: 24, longitude: 120, address: "家")
        favoritesStore.toggle(first)
        favoritesStore.toggle(second)
        let model = LocationMapModel()
        _ = try model.selectMapCoordinate(first.coordinate)
        let (hostingView, window) = makeMapHostingView(
            model: model,
            favoritesStore: favoritesStore
        )
        defer { removeFromWindow(window) }

        await waitForViewUpdate(hostingView)
        let firstID = try XCTUnwrap(favoritesStore.favorites.first?.id)
        favoritesStore.rename(id: firstID, to: "  辦公室  ")
        favoritesStore.remove(id: firstID)
        try model.resetWorkspace()
        await waitForViewUpdate(hostingView)

        XCTAssertNil(model.preview)
        XCTAssertEqual(favoritesStore.favorites.map(\.name), ["家"])
        XCTAssertTrue(hasIdentifier("sidebar-favorites-list", in: hostingView))
    }

    func testFavoriteRenameBlankRenameAndDeleteStayObservableInSameHierarchy() async throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let favoritesStore = FavoritesStore(defaults: defaults)
        let favorite = try searchPlace(latitude: 25, longitude: 121, address: "公司")
        favoritesStore.toggle(favorite)
        let model = LocationMapModel()
        _ = try model.selectMapCoordinate(favorite.coordinate)
        let simulationStore = makeSimulationStore(device: ResetTestSimulationDevice())
        await simulationStore.confirmPoint(
            try DeviceCoordinate(latitude: 25, longitude: 121),
            riskAccepted: true
        )
        let stateBeforeDelete = simulationStore.state
        let (hostingView, window) = makeMapHostingView(
            simulationStore: simulationStore,
            model: model,
            favoritesStore: favoritesStore
        )
        defer { removeFromWindow(window) }

        await waitForViewUpdate(hostingView)
        let mapView = try XCTUnwrap(findMapView(in: hostingView))
        let previewAnnotation = try await waitForPreviewMarker(
            at: favorite.coordinate,
            in: mapView
        )
        let id = try XCTUnwrap(favoritesStore.favorites.first?.id.uuidString)
        let rename = try XCTUnwrap(findButton(in: hostingView, identifier: "favorite-rename-action-\(id)"))
        rename.performClick(nil)
        await waitForViewUpdate(hostingView)
        let submitRename = try XCTUnwrap(findButton(in: hostingView, identifier: "favorite-submit-rename-action-\(id)"))
        submitRename.performClick(nil)
        await waitForViewUpdate(hostingView)
        XCTAssertEqual(favoritesStore.favorites.first?.name, "辦公室")
        XCTAssertTrue(hasIdentifier("favorite-row-name-辦公室", in: hostingView))
        let blank = try XCTUnwrap(findButton(in: hostingView, identifier: "favorite-blank-rename-action-\(id)"))
        blank.performClick(nil)
        await waitForViewUpdate(hostingView)
        let submitBlank = try XCTUnwrap(findButton(in: hostingView, identifier: "favorite-submit-blank-rename-action-\(id)"))
        submitBlank.performClick(nil)
        await waitForViewUpdate(hostingView)
        XCTAssertEqual(favoritesStore.favorites.first?.name, "辦公室")
        XCTAssertTrue(hasIdentifier("favorite-row-name-辦公室", in: hostingView))
        let delete = try XCTUnwrap(findButton(in: hostingView, identifier: "favorite-delete-action-\(id)"))
        delete.performClick(nil)
        await waitForViewUpdate(hostingView)
        XCTAssertTrue(favoritesStore.favorites.isEmpty)
        XCTAssertEqual(model.preview?.coordinate, favorite.coordinate)
        XCTAssertTrue(mapView.annotations.contains { $0 === previewAnnotation })
        XCTAssertEqual(previewAnnotation.coordinate.latitude, favorite.coordinate.latitude)
        XCTAssertEqual(previewAnnotation.coordinate.longitude, favorite.coordinate.longitude)
        XCTAssertEqual(simulationStore.state, stateBeforeDelete)
    }

    func testFavoritesListNeverPushesDeviceControlsOutOfTheSidebar() async throws {
        // The sidebar clears 620pt by only ~22pt, so an unbounded favourites
        // list used to push 設定位置 below the fold from the very first entry.
        let empty = try await favoritesList(favoriteCount: 0)
        let capped = try await favoritesList(favoriteCount: 20)
        let atLimit = try await favoritesList(favoriteCount: 6)
        let belowLimit = try await favoritesList(favoriteCount: 3)

        XCTAssertEqual(
            capped.setLocationMinY,
            empty.setLocationMinY,
            accuracy: 0.5
        )
        // Past the visible-row limit the section stops growing…
        XCTAssertEqual(
            try XCTUnwrap(capped.height),
            try XCTUnwrap(atLimit.height),
            accuracy: 0.5
        )
        // …and the rows stay reachable through a real scroller rather than
        // being clipped away.
        XCTAssertTrue(capped.scrollableRows)
        XCTAssertTrue(capped.lastRowVisibleAfterScrolling)
        XCTAssertFalse(belowLimit.scrollableRows)
        // …and below the limit the section still shrinks to its rows rather
        // than reserving the capped height.
        XCTAssertLessThan(
            try XCTUnwrap(belowLimit.height),
            try XCTUnwrap(atLimit.height) - 0.5
        )
    }

    private func favoritesList(
        favoriteCount: Int
    ) async throws -> (
        height: CGFloat?,
        setLocationMinY: CGFloat,
        scrollableRows: Bool,
        lastRowVisibleAfterScrolling: Bool
    ) {
        let suite = "iPhoneLocationMoveTests-favorites-cap-\(favoriteCount)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            UserDefaults.standard.removeSuite(named: suite)
        }
        let favoritesStore = FavoritesStore(defaults: defaults)
        for index in 0 ..< favoriteCount {
            favoritesStore.toggle(
                try searchPlace(
                    latitude: 25 + Double(index) * 0.01,
                    longitude: 121,
                    address: "地點\(index)"
                )
            )
        }
        let (hostingView, window) = makeMapHostingView(
            simulationStore: makeSimulationStore(
                device: ResetTestSimulationDevice()
            ),
            model: try configuredRouteModel(),
            favoritesStore: favoritesStore
        )
        defer { removeFromWindow(window) }

        await waitForViewUpdate(hostingView)
        try assertSidebarLayout(
            in: hostingView,
            requiredRegions: favoriteCount == 0 ? [] : ["sidebar-favorites-list"],
            requiredPrimaryButtonIdentifiers: ["sidebar-button-set-location"]
        )
        let regions = allSubviews(in: hostingView)
            .compactMap { $0 as? TestingLayoutRegionView }
        let setLocation = try XCTUnwrap(
            regions.first {
                $0.accessibilityIdentifier() == "sidebar-button-set-location"
            }
        )
        let setLocationFrame = setLocation.convert(setLocation.bounds, to: hostingView)
        let sidebarBounds = NSRect(
            x: 0,
            y: 0,
            width: 320,
            height: hostingView.bounds.height
        )
        XCTAssertGreaterThanOrEqual(
            setLocationFrame.minY,
            sidebarBounds.minY - 1,
            "set location is clipped below the sidebar"
        )
        XCTAssertLessThanOrEqual(
            setLocationFrame.maxY,
            sidebarBounds.maxY + 1,
            "set location is clipped above the sidebar"
        )
        guard favoriteCount > 0 else {
            return (nil, setLocationFrame.minY, false, true)
        }

        let list = try XCTUnwrap(
            regions.first {
                $0.accessibilityIdentifier() == "sidebar-favorites-list"
            }
        )
        // Rows existing in the hierarchy does not prove they are reachable —
        // a clipped stack renders all of them too. Require a real scroller
        // whose content outgrows its clip view.
        let listFrame = list.convert(list.bounds, to: hostingView)
        let rowScrollView = allSubviews(in: hostingView)
            .compactMap { $0 as? NSScrollView }
            .first {
                let frame = $0.convert($0.bounds, to: hostingView)
                return listFrame.contains(frame.origin)
                    && ($0.documentView?.bounds.height ?? 0)
                        > $0.contentView.bounds.height
            }
        var lastRowVisibleAfterScrolling = favoriteCount <= 5
        if let rowScrollView,
           let documentView = rowScrollView.documentView,
           let lastFavorite = favoritesStore.favorites.last,
           let lastRow = regions.first(where: {
               $0.accessibilityIdentifier()
                   == "favorite-row-name-\(lastFavorite.name)"
           })
        {
            let bottomY = max(
                documentView.bounds.minY,
                documentView.bounds.maxY - rowScrollView.contentView.bounds.height
            )
            rowScrollView.contentView.scroll(to: NSPoint(x: 0, y: bottomY))
            rowScrollView.reflectScrolledClipView(rowScrollView.contentView)
            let lastRowFrame = lastRow.convert(
                lastRow.bounds,
                to: rowScrollView.contentView
            )
            lastRowVisibleAfterScrolling = rowScrollView.contentView.bounds
                .contains(lastRowFrame.origin)
        }
        return (
            listFrame.height,
            setLocationFrame.minY,
            rowScrollView != nil,
            lastRowVisibleAfterScrolling
        )
    }

    func testConnectedSidebarRelayoutsObservedSimulationStates() async throws {
        let device = ResetTestSimulationDevice()
        let store = makeSimulationStore(device: device)
        let (hostingView, window) = makeMapHostingView(
            simulationStore: store,
            model: try configuredRouteModel()
        )
        defer { removeFromWindow(window) }

        await waitForViewUpdate(hostingView)
        try assertSidebarLayout(
            in: hostingView,
            requiredRegions: [
                "sidebar-speed-region",
                "sidebar-simulation-status-region",
            ],
            requiredPrimaryButtonIdentifiers: [
                "sidebar-button-mac-recenter",
                "sidebar-button-reset",
                "sidebar-button-directions",
                "sidebar-button-set-location",
            ]
        )
        assertTestingActionButtons(in: hostingView)
        attachSnapshot(of: hostingView, name: "sidebar-connected-idle")

        await device.suspendNextSet()
        let starting = Task {
            await store.confirmPoint(
                try! DeviceCoordinate(latitude: 25, longitude: 121),
                riskAccepted: true
            )
        }
        await device.waitForSetCount(1)
        await waitForViewUpdate(hostingView)
        scrollSidebarToBottom(in: hostingView)
        await waitForViewUpdate(hostingView)
        try assertSidebarLayout(
            in: hostingView,
            requiredRegions: [
                "sidebar-speed-region",
                "sidebar-simulation-status-region",
            ],
            requiredPrimaryButtonIdentifiers: [
                "sidebar-button-directions",
                "sidebar-button-set-location",
                "sidebar-button-start-route",
            ]
        )
        assertTestingActionButtons(in: hostingView)
        attachSnapshot(of: hostingView, name: "sidebar-connected-busy")
        await device.resumeSet()
        await starting.value

        try await store.startRoute(
            preview: routePreview(),
            speedKilometersPerHour: 4.5,
            roundTrip: false,
            riskAccepted: true
        )
        await waitForViewUpdate(hostingView)
        scrollSidebarToBottom(in: hostingView)
        await waitForViewUpdate(hostingView)
        try assertSidebarLayout(
            in: hostingView,
            requiredRegions: [
                "sidebar-speed-region",
                "sidebar-simulation-status-region",
            ],
            requiredPrimaryButtonIdentifiers: [
                "sidebar-button-directions",
                "sidebar-button-set-location",
                "sidebar-button-start-route",
                "sidebar-button-pause-route",
                "sidebar-button-stop-simulation",
            ]
        )
        assertTestingActionButtons(in: hostingView)

        try store.pause()
        guard await waitForRoutePhase(
            .paused,
            showing: "sidebar-button-resume-route",
            in: store,
            hostingView: hostingView
        ) else {
            return XCTFail("Paused route controls did not finish rendering")
        }
        await waitForViewUpdate(hostingView)
        try assertSidebarLayout(
            in: hostingView,
            requiredRegions: [
                "sidebar-speed-region",
                "sidebar-simulation-status-region",
            ],
            requiredPrimaryButtonIdentifiers: [
                "sidebar-button-directions",
                "sidebar-button-set-location",
                "sidebar-button-start-route",
                "sidebar-button-resume-route",
                "sidebar-button-stop-simulation",
            ]
        )
        assertTestingActionButtons(in: hostingView)

        await device.failNextClear(.clearFailed("layout-test"))
        await store.stop()
        await waitForViewUpdate(hostingView)
        guard case .stopping(_, let failure?) = store.state else {
            return XCTFail("Expected stopping failure")
        }
        XCTAssertEqual(failure, .clearFailed("layout-test"))
        try assertSidebarLayout(
            in: hostingView,
            requiredRegions: [
                "sidebar-speed-region",
                "sidebar-simulation-status-region",
                "sidebar-simulation-error-region",
            ],
            requiredPrimaryButtonIdentifiers: [
                "sidebar-button-directions",
                "sidebar-button-set-location",
                "sidebar-button-start-route",
                "sidebar-button-stop-simulation",
            ]
        )
        assertTestingActionButtons(in: hostingView)
        attachSnapshot(of: hostingView, name: "sidebar-clear-failure")
    }

    func testResetConfirmationClearsSearchAndTurnsOffRoundTrip() async throws {
        let model = try configuredRouteModel()
        let (hostingView, window) = makeMapHostingView(
            model: model,
            initialQuery: "保留中的搜尋",
            initialRoundTrip: true
        )
        defer { removeFromWindow(window) }

        let queryField = try XCTUnwrap(
            findTextField(in: hostingView, placeholder: "搜尋地名或地址")
        )
        XCTAssertEqual(queryField.stringValue, "保留中的搜尋")

        let roundTrip = try XCTUnwrap(
            findButton(in: hostingView, identifier: "round-trip-state")
        )
        XCTAssertEqual(roundTrip.state, .on)

        try await confirmReset(in: hostingView) {
            XCTAssertEqual(queryField.stringValue, "保留中的搜尋")
            XCTAssertEqual(roundTrip.state, .on)
            XCTAssertNotNil(model.endpointA)
            XCTAssertNotNil(model.endpointB)
            XCTAssertEqual(model.routeStatus, .routeAvailable)
        }

        XCTAssertEqual(queryField.stringValue, "")
        XCTAssertEqual(roundTrip.state, .off)
        XCTAssertNil(model.endpointA)
        XCTAssertNil(model.endpointB)
        XCTAssertEqual(model.routeStatus, .idle)
    }

    func testResetTestingSeamDoesNotPresentAppKitSheet() async throws {
        let (hostingView, window) = makeMapHostingView()
        defer { removeFromWindow(window) }

        let reset = try XCTUnwrap(
            findButton(in: hostingView, identifier: "workspace-reset-button")
        )
        reset.performClick(nil)
        await waitForViewUpdate(hostingView)

        XCTAssertNil(window.attachedSheet)
        let confirm = try XCTUnwrap(
            findButton(
                in: hostingView,
                identifier: "workspace-reset-confirmation-action"
            )
        )
        XCTAssertTrue(confirm.isEnabled)
    }

    func testResetIsDisabledForEveryBusySimulationState() async throws {
        let startingDevice = ResetTestSimulationDevice()
        await startingDevice.suspendNextSet()
        let startingStore = makeSimulationStore(device: startingDevice)
        let starting = Task {
            await startingStore.confirmPoint(
                try! DeviceCoordinate(latitude: 25, longitude: 121),
                riskAccepted: true
            )
        }
        await startingDevice.waitForSetCount(1)
        try assertResetDisabled(simulationStore: startingStore)
        await startingDevice.resumeSet()
        await starting.value

        let replacingDevice = ResetTestSimulationDevice()
        let replacingStore = makeSimulationStore(device: replacingDevice)
        try await replacingStore.startRoute(
            preview: routePreview(),
            speedKilometersPerHour: 7,
            roundTrip: false,
            riskAccepted: true
        )
        await replacingDevice.suspendNextSet()
        try replacingStore.tick(at: 1)
        await replacingDevice.waitForSetCount(2)
        let replacing = Task {
            await replacingStore.confirmPoint(
                try! DeviceCoordinate(latitude: 24, longitude: 120),
                riskAccepted: true
            )
        }
        await waitForState(replacingStore) {
            if case .replacing = $0 {
                return true
            }
            return false
        }
        try assertResetDisabled(simulationStore: replacingStore)
        await replacingDevice.resumeSet()
        await replacing.value

        let stoppingDevice = ResetTestSimulationDevice()
        let stoppingStore = makeSimulationStore(device: stoppingDevice)
        await stoppingStore.confirmPoint(
            try DeviceCoordinate(latitude: 25, longitude: 121),
            riskAccepted: true
        )
        await stoppingDevice.suspendNextClear()
        let stopping = Task { await stoppingStore.stop() }
        await stoppingDevice.waitForClearCount(1)
        try assertResetDisabled(simulationStore: stoppingStore)
        await stoppingDevice.resumeClear()
        await stopping.value
    }

    func testResetStopsOnlyWhenSimulationOwnsCleanup() async throws {
        let idleDevice = ResetTestSimulationDevice()
        let idleStore = makeSimulationStore(device: idleDevice)
        let (idleView, idleWindow) = makeMapHostingView(
            simulationStore: idleStore
        )
        defer { removeFromWindow(idleWindow) }
        try await confirmReset(in: idleView)
        let idleClearCount = await idleDevice.recordedClearCallCount()
        XCTAssertEqual(idleClearCount, 0)

        let activeDevice = ResetTestSimulationDevice()
        let activeStore = makeSimulationStore(device: activeDevice)
        await activeStore.confirmPoint(
            try DeviceCoordinate(latitude: 25, longitude: 121),
            riskAccepted: true
        )
        let (activeView, activeWindow) = makeMapHostingView(
            simulationStore: activeStore
        )
        defer { removeFromWindow(activeWindow) }
        try await confirmReset(in: activeView)
        await activeDevice.waitForClearCount(1)

        let activeClearCount = await activeDevice.recordedClearCallCount()
        XCTAssertEqual(activeClearCount, 1)
        XCTAssertEqual(activeStore.state, .idle)
    }

    func testResetClearFailureKeepsRetryAndResetWorkspace() async throws {
        let device = ResetTestSimulationDevice()
        let store = makeSimulationStore(device: device)
        await store.confirmPoint(
            try DeviceCoordinate(latitude: 25, longitude: 121),
            riskAccepted: true
        )
        await device.failNextClear(.clearFailed("reset-test"))
        let model = try configuredRouteModel()
        let (hostingView, window) = makeMapHostingView(
            simulationStore: store,
            model: model
        )
        defer { removeFromWindow(window) }

        try await confirmReset(in: hostingView)
        await device.waitForClearCount(1)
        await waitForViewUpdate(hostingView)

        guard case .stopping(_, let failure?) = store.state else {
            return XCTFail("Expected cleanup failure ownership")
        }
        XCTAssertEqual(failure, .clearFailed("reset-test"))
        let showsFailure = await waitForIdentifier(
            "simulation-cleanup-failure",
            in: hostingView
        )
        let showsRetry = await waitForIdentifier(
            "simulation-cleanup-retry",
            in: hostingView
        )
        XCTAssertTrue(showsFailure)
        XCTAssertTrue(showsRetry)
        XCTAssertNil(model.endpointA)
        XCTAssertNil(model.endpointB)
        XCTAssertEqual(model.routeStatus, .idle)
    }

    func testConfirmedRouteMarkerUpdatesSameAnnotationInSameHostingView() async throws {
        let harness = try ContentViewSimulationHarness()
        let (hostingView, window) = makeMapHostingView(simulationStore: harness.store)
        defer { removeFromWindow(window) }

        try await harness.store.startRoute(
            preview: routePreview(),
            speedKilometersPerHour: 7,
            roundTrip: false,
            riskAccepted: true
        )

        let mapView = try XCTUnwrap(findMapView(in: hostingView))
        let initialAnnotation = try await waitForRouteMarker(in: mapView)
        XCTAssertEqual(initialAnnotation.coordinate.latitude, 25, accuracy: 0.000_001)
        XCTAssertEqual(initialAnnotation.coordinate.longitude, 121, accuracy: 0.000_001)
        let initialLongitude = initialAnnotation.coordinate.longitude

        try harness.store.tick(at: 1)
        await harness.device.waitForSetCount(2)
        let updatedAnnotation = try await waitForRouteMarker(
            in: mapView,
            longitudeDifferentFrom: initialLongitude
        )

        XCTAssertTrue(initialAnnotation === updatedAnnotation)
        XCTAssertEqual(updatedAnnotation.coordinate.latitude, 25, accuracy: 0.000_001)
        XCTAssertGreaterThan(updatedAnnotation.coordinate.longitude, 121)
        XCTAssertLessThan(updatedAnnotation.coordinate.longitude, 121.001)
    }

    func testPositionUnknownRemovesConfirmedRouteMarkerFromSameHostingView() async throws {
        let harness = try ContentViewSimulationHarness()
        let (hostingView, window) = makeMapHostingView(simulationStore: harness.store)
        defer { removeFromWindow(window) }

        try await harness.store.startRoute(
            preview: routePreview(),
            speedKilometersPerHour: 7,
            roundTrip: false,
            riskAccepted: true
        )

        let mapView = try XCTUnwrap(findMapView(in: hostingView))
        let initialAnnotation = try await waitForRouteMarker(in: mapView)

        harness.store.handleDeviceInterruption(
            DeviceInterruption(
                reason: .transportFailure,
                positionKnowledge: .unknown
            )
        )

        let markerWasRemoved = await waitForRouteMarkerRemoval(
            initialAnnotation,
            from: mapView
        )
        XCTAssertTrue(markerWasRemoved)
    }

    func testClearSuccessRemovesConfirmedRouteMarkerFromSameHostingView() async throws {
        let harness = try ContentViewSimulationHarness()
        let (hostingView, window) = makeMapHostingView(simulationStore: harness.store)
        defer { removeFromWindow(window) }

        try await harness.store.startRoute(
            preview: routePreview(),
            speedKilometersPerHour: 7,
            roundTrip: false,
            riskAccepted: true
        )

        let mapView = try XCTUnwrap(findMapView(in: hostingView))
        let initialAnnotation = try await waitForRouteMarker(in: mapView)

        await harness.store.stop()

        let markerWasRemoved = await waitForRouteMarkerRemoval(
            initialAnnotation,
            from: mapView
        )
        XCTAssertTrue(markerWasRemoved)
    }

    func testSearchResultActionsMoveSamePreviewMarkerAndRecenterRepeatedSelection() async throws {
        let model = LocationMapModel()
        var searchCancellationRequestCount = 0
        var previewAddressCancellationRequestCount = 0
        let dakeng = try searchPlace(
            latitude: 24.181_230,
            longitude: 120.732_480,
            address: "大坑"
        )
        let dakengVillage = try searchPlace(
            latitude: 24.184_092,
            longitude: 120.741_168,
            address: "大坑里"
        )
        try configureSearchResults(
            [dakeng, dakengVillage],
            query: "大坑",
            in: model
        )
        let (hostingView, window) = makeMapHostingView(
            model: model,
            onSearchCancellationRequested: {
                searchCancellationRequestCount += 1
            },
            onPreviewAddressCancellationRequested: {
                previewAddressCancellationRequestCount += 1
            }
        )
        defer { removeFromWindow(window) }

        await waitForViewUpdate(hostingView)
        let mapView = try XCTUnwrap(findMapView(in: hostingView))
        let selectDakeng = try XCTUnwrap(
            findButton(
                in: hostingView,
                identifier: "search-result-selection-action-0"
            )
        )
        selectDakeng.performClick(nil)

        let firstAnnotation = try await waitForPreviewMarker(
            at: dakeng.coordinate,
            in: mapView
        )
        let firstCameraIntent = try XCTUnwrap(model.previewCameraIntent)
        XCTAssertEqual(model.preview, dakeng)
        XCTAssertEqual(searchCancellationRequestCount, 1)
        XCTAssertEqual(previewAddressCancellationRequestCount, 1)
        try await waitForMapCenter(dakeng.coordinate, in: mapView)

        let selectDakengVillage = try XCTUnwrap(
            findButton(
                in: hostingView,
                identifier: "search-result-selection-action-1"
            )
        )
        selectDakengVillage.performClick(nil)

        let secondAnnotation = try await waitForPreviewMarker(
            at: dakengVillage.coordinate,
            in: mapView
        )
        let secondCameraIntent = try XCTUnwrap(model.previewCameraIntent)
        XCTAssertTrue(firstAnnotation === secondAnnotation)
        XCTAssertEqual(model.preview, dakengVillage)
        XCTAssertNotEqual(firstCameraIntent.identity, secondCameraIntent.identity)
        XCTAssertEqual(searchCancellationRequestCount, 2)
        XCTAssertEqual(previewAddressCancellationRequestCount, 2)
        try await waitForMapCenter(dakengVillage.coordinate, in: mapView)

        let movedCoordinate = try MapCoordinate(
            latitude: 24.2,
            longitude: 120.7
        )
        mapView.setCenter(
            CLLocationCoordinate2D(
                latitude: movedCoordinate.latitude,
                longitude: movedCoordinate.longitude
            ),
            animated: false
        )
        let repeatedDakengVillage = try XCTUnwrap(
            findButton(
                in: hostingView,
                identifier: "search-result-selection-action-1"
            )
        )
        repeatedDakengVillage.performClick(nil)

        let repeatedCameraIntent = try XCTUnwrap(model.previewCameraIntent)
        XCTAssertNotEqual(
            secondCameraIntent.identity,
            repeatedCameraIntent.identity
        )
        XCTAssertEqual(searchCancellationRequestCount, 3)
        XCTAssertEqual(previewAddressCancellationRequestCount, 3)
        try await waitForMapCenter(dakengVillage.coordinate, in: mapView)
    }

    func testStaleRenderedSearchResultActionPreservesNewSearchOwnership() async throws {
        let model = LocationMapModel()
        var searchCancellationRequestCount = 0
        var previewAddressCancellationRequestCount = 0
        let oldPlace = try searchPlace(
            latitude: 24.181_230,
            longitude: 120.732_480,
            address: "舊結果"
        )
        try configureSearchResults([oldPlace], query: "舊搜尋", in: model)
        let (hostingView, window) = makeMapHostingView(
            model: model,
            onSearchCancellationRequested: {
                searchCancellationRequestCount += 1
            },
            onPreviewAddressCancellationRequested: {
                previewAddressCancellationRequestCount += 1
            }
        )
        defer { removeFromWindow(window) }

        await waitForViewUpdate(hostingView)
        let staleRenderedAction = try XCTUnwrap(
            findButton(
                in: hostingView,
                identifier: "search-result-selection-action-0"
            )
        )
        let newRequest = try model.beginSearch(query: "較新搜尋")
        let generationBeforeStaleAction = model.mapSearchGeneration

        // Intentionally trigger the retained action before SwiftUI can rebind it.
        staleRenderedAction.performClick(nil)

        XCTAssertEqual(searchCancellationRequestCount, 0)
        XCTAssertEqual(previewAddressCancellationRequestCount, 0)
        XCTAssertEqual(model.mapSearchGeneration, generationBeforeStaleAction)
        XCTAssertNil(model.preview)
        XCTAssertNil(model.previewCameraIntent)
        XCTAssertTrue(model.searchResults.isEmpty)
        let showsStaleSelectionError = await waitForIdentifier(
            "sidebar-workspace-message-region",
            in: hostingView
        )
        XCTAssertTrue(showsStaleSelectionError)

        let newPlace = try searchPlace(
            latitude: 24.149_992,
            longitude: 120.741_168,
            address: "較新結果"
        )
        XCTAssertEqual(
            model.receiveSearchResults([newPlace], for: newRequest),
            .applied
        )
        XCTAssertEqual(model.searchResults, [newPlace])
    }

    func testStaleRenderedSearchResultActionPreservesPreviewAddressOwnership() async throws {
        let model = LocationMapModel()
        var searchCancellationRequestCount = 0
        var previewAddressCancellationRequestCount = 0
        let oldPlace = try searchPlace(
            latitude: 24.181_230,
            longitude: 120.732_480,
            address: "舊結果"
        )
        try configureSearchResults([oldPlace], query: "舊搜尋", in: model)
        let (hostingView, window) = makeMapHostingView(
            model: model,
            onSearchCancellationRequested: {
                searchCancellationRequestCount += 1
            },
            onPreviewAddressCancellationRequested: {
                previewAddressCancellationRequestCount += 1
            }
        )
        defer { removeFromWindow(window) }

        await waitForViewUpdate(hostingView)
        let staleRenderedAction = try XCTUnwrap(
            findButton(
                in: hostingView,
                identifier: "search-result-selection-action-0"
            )
        )
        let currentCoordinate = try MapCoordinate(
            latitude: 24.2,
            longitude: 120.7
        )
        let addressRequest = try model.selectMapCoordinate(currentCoordinate)
        let generationBeforeStaleAction = model.mapSearchGeneration

        // Intentionally trigger the retained action before SwiftUI can rebind it.
        staleRenderedAction.performClick(nil)

        XCTAssertEqual(searchCancellationRequestCount, 0)
        XCTAssertEqual(previewAddressCancellationRequestCount, 0)
        XCTAssertEqual(model.mapSearchGeneration, generationBeforeStaleAction)
        XCTAssertEqual(model.preview?.coordinate, currentCoordinate)
        XCTAssertNil(model.preview?.address)
        XCTAssertNil(model.previewCameraIntent)
        let showsStaleSelectionError = await waitForIdentifier(
            "sidebar-workspace-message-region",
            in: hostingView
        )
        XCTAssertTrue(showsStaleSelectionError)
        XCTAssertEqual(
            model.receivePreviewAddress("目前地址", for: addressRequest),
            .applied
        )
        XCTAssertEqual(model.preview?.address, "目前地址")
    }

    func testSetupReadyReplacesDisconnectedControlsInSameHostingView() async throws {
        let store = try makeStore()
        let hostingView = NSHostingView(
            rootView: LocationWorkspaceView(
                store: store,
                macLocationCoordinator: MacLocationCoordinator(
                    provider: ContentViewMacLocationProvider()
                ),
                favoritesStore: FavoritesStore(defaults: makeIsolatedDefaults())
            )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        let initiallyDisconnected = await waitForIdentifier(
            "simulation-controls-disconnected",
            in: hostingView
        )
        XCTAssertTrue(initiallyDisconnected)
        XCTAssertFalse(
            hasIdentifier(
                "simulation-controls-connected",
                in: hostingView
            )
        )

        await store.start()

        let eventuallyConnected = await waitForIdentifier(
            "simulation-controls-connected",
            in: hostingView
        )
        XCTAssertTrue(eventuallyConnected)
        XCTAssertFalse(
            hasIdentifier(
                "simulation-controls-disconnected",
                in: hostingView
            )
        )
    }

    private func makeMapHostingView(
        simulationStore: SimulationStore? = nil,
        model: LocationMapModel = LocationMapModel(),
        favoritesStore: FavoritesStore = FavoritesStore(defaults: makeIsolatedDefaults()),
        initialQuery: String = "",
        initialRoundTrip: Bool = false,
        onSearchCancellationRequested: @escaping () -> Void = {},
        onPreviewAddressCancellationRequested: @escaping () -> Void = {}
    ) -> (NSHostingView<LocationMapView>, NSWindow) {
        let hostingView = NSHostingView(
            rootView: LocationMapView(
                simulationStore: simulationStore,
                macLocationCoordinator: MacLocationCoordinator(
                    provider: ContentViewMacLocationProvider()
                ),
                model: model,
                favoritesStore: favoritesStore,
                initialQuery: initialQuery,
                initialRoundTrip: initialRoundTrip,
                presentsResetConfirmationDialog: false,
                onSearchCancellationRequested: onSearchCancellationRequested,
                onPreviewAddressCancellationRequested:
                    onPreviewAddressCancellationRequested
            )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFrontRegardless()
        hostingView.layoutSubtreeIfNeeded()
        return (hostingView, window)
    }

    private func searchPlace(
        latitude: Double,
        longitude: Double,
        address: String
    ) throws -> MapSearchPlace {
        MapSearchPlace(
            coordinate: try MapCoordinate(
                latitude: latitude,
                longitude: longitude
            ),
            address: address
        )
    }

    private func configureSearchResults(
        _ places: [MapSearchPlace],
        query: String,
        in model: LocationMapModel
    ) throws {
        let request = try model.beginSearch(query: query)
        XCTAssertEqual(
            model.receiveSearchResults(places, for: request),
            .applied
        )
    }

    private func configuredRouteModel() throws -> LocationMapModel {
        let model = LocationMapModel()
        try model.selectMapCoordinate(
            MapCoordinate(latitude: 25.03, longitude: 121.56)
        )
        try model.assignPreview(to: .a)
        try model.selectMapCoordinate(
            MapCoordinate(latitude: 25.04, longitude: 121.57)
        )
        try model.assignPreview(to: .b)
        let request = try model.beginDirections()
        _ = try model.receiveDirections(
            .routeAvailable(
                [
                    try MapCoordinate(latitude: 25.03, longitude: 121.56),
                    try MapCoordinate(latitude: 25.04, longitude: 121.57),
                ],
                distance: 900
            ),
            for: request
        )
        return model
    }

    private func makeSimulationStore(
        device: ResetTestSimulationDevice
    ) -> SimulationStore {
        SimulationStore(
            device: device,
            generation: DeviceSessionGeneration(rawValue: 1),
            scheduler: ContentViewSimulationScheduler()
        )
    }

    private func assertResetDisabled(
        simulationStore: SimulationStore
    ) throws {
        let (hostingView, window) = makeMapHostingView(
            simulationStore: simulationStore
        )
        defer { removeFromWindow(window) }
        let reset = try XCTUnwrap(
            findButton(in: hostingView, identifier: "workspace-reset-button")
        )
        XCTAssertFalse(reset.isEnabled)
    }

    private func confirmReset(
        in hostingView: NSHostingView<LocationMapView>,
        beforeConfirmation: () throws -> Void = {}
    ) async throws {
        let reset = try XCTUnwrap(
            findButton(in: hostingView, identifier: "workspace-reset-button")
        )
        reset.performClick(nil)
        await waitForViewUpdate(hostingView)

        try beforeConfirmation()
        let confirm = try XCTUnwrap(
            findButton(
                in: hostingView,
                identifier: "workspace-reset-confirmation-action"
            )
        )
        XCTAssertTrue(confirm.isEnabled)
        confirm.performClick(nil)
        await waitForViewUpdate(hostingView)
    }

    private func waitForViewUpdate(_ hostingView: NSView) async {
        for _ in 0 ..< 10 {
            hostingView.window?.displayIfNeeded()
            await Task.yield()
        }
    }

    private func waitForState(
        _ store: SimulationStore,
        matching predicate: (SimulationStoreState) -> Bool
    ) async {
        while !predicate(store.state) {
            await Task.yield()
        }
    }

    private func waitForRoutePhase(
        _ phase: RouteSessionPhase,
        showing layoutRegionIdentifier: String,
        in store: SimulationStore,
        hostingView: NSView
    ) async -> Bool {
        for _ in 0 ..< 100 {
            hostingView.window?.displayIfNeeded()
            if store.routeSnapshot?.phase == phase,
               containsViewIdentifier(
                   layoutRegionIdentifier,
                   in: hostingView
               )
            {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func findButton(
        in root: NSView,
        identifier: String
    ) -> NSButton? {
        if let button = root as? NSButton,
           button.accessibilityIdentifier() == identifier
        {
            return button
        }
        return root.subviews.lazy.compactMap {
            self.findButton(in: $0, identifier: identifier)
        }.first
    }

    private func hasButtonTitle(_ title: String, in root: NSView) -> Bool {
        if let button = root as? NSButton, button.title == title {
            return true
        }
        return root.subviews.contains(where: { hasButtonTitle(title, in: $0) })
    }

    private func allSubviews(in root: NSView) -> [NSView] {
        root.subviews.flatMap { [$0] + allSubviews(in: $0) }
    }

    private func scrollSidebarToBottom(in hostingView: NSView) {
        guard
            let scrollView = allSubviews(in: hostingView)
                .compactMap({ $0 as? NSScrollView })
                .first(where: {
                    let frame = $0.convert($0.bounds, to: hostingView)
                    return frame.minX < 320
                        && frame.width <= 320
                        && ($0.documentView?.bounds.height ?? 0)
                            > $0.contentView.bounds.height
                }),
            let documentView = scrollView.documentView
        else {
            return
        }
        let bottomY = max(
            documentView.bounds.minY,
            documentView.bounds.maxY - scrollView.contentView.bounds.height
        )
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: bottomY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func assertSidebarLayout(
        in hostingView: NSView,
        requiredRegions: Set<String>,
        requiredPrimaryButtonIdentifiers: Set<String> = [],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let sidebarBounds = NSRect(
            x: 0,
            y: 0,
            width: 320,
            height: hostingView.bounds.height
        )
        let regions = allSubviews(in: hostingView).compactMap {
            $0 as? TestingLayoutRegionView
        }
        let buttonFrames = regions.compactMap { region -> (String, NSRect)? in
            let identifier = region.accessibilityIdentifier()
            guard identifier.hasPrefix("sidebar-button-") else {
                return nil
            }
            let frame = region.convert(region.bounds, to: hostingView)
            return frame.intersects(sidebarBounds) ? (identifier, frame) : nil
        }
        XCTAssertFalse(buttonFrames.isEmpty, file: file, line: line)

        for (identifier, frame) in buttonFrames {
            XCTAssertGreaterThanOrEqual(
                frame.minX,
                sidebarBounds.minX - 1,
                identifier,
                file: file,
                line: line
            )
            XCTAssertLessThanOrEqual(
                frame.maxX,
                sidebarBounds.maxX + 1,
                identifier,
                file: file,
                line: line
            )
        }

        for firstIndex in buttonFrames.indices {
            for secondIndex in buttonFrames.indices where secondIndex > firstIndex {
                let first = buttonFrames[firstIndex]
                let second = buttonFrames[secondIndex]
                let intersection = first.1.intersection(second.1)
                XCTAssertTrue(
                    intersection.isNull
                        || intersection.width <= 1
                        || intersection.height <= 1,
                    "\(first.0) overlaps \(second.0)",
                    file: file,
                    line: line
                )

                let verticalOverlap = min(first.1.maxY, second.1.maxY)
                    - max(first.1.minY, second.1.minY)
                if verticalOverlap > 1 {
                    let horizontalGap = max(
                        second.1.minX - first.1.maxX,
                        first.1.minX - second.1.maxX
                    )
                    XCTAssertGreaterThanOrEqual(
                        horizontalGap,
                        7,
                        "\(first.0) row spacing \(second.0)",
                        file: file,
                        line: line
                    )
                }
            }
        }

        let regionIdentifiers = Set(
            regions.map { $0.accessibilityIdentifier() }
        )
        XCTAssertTrue(
            requiredRegions.isSubset(of: regionIdentifiers),
            "Missing layout regions: \(requiredRegions.subtracting(regionIdentifiers))",
            file: file,
            line: line
        )
        for region in regions {
            let regionIdentifier = region.accessibilityIdentifier()
            guard !regionIdentifier.hasPrefix("sidebar-button-") else {
                continue
            }
            let regionFrame = region.convert(region.bounds, to: hostingView)
            guard regionFrame.intersects(sidebarBounds) else {
                continue
            }
            for (buttonIdentifier, buttonFrame) in buttonFrames {
                let intersection = buttonFrame.intersection(regionFrame)
                XCTAssertTrue(
                    intersection.isNull
                        || intersection.width <= 1
                        || intersection.height <= 1,
                    "\(buttonIdentifier) overlaps \(regionIdentifier)",
                    file: file,
                    line: line
                )
            }
        }

        let primaryFrames = buttonFrames.filter {
            requiredPrimaryButtonIdentifiers.contains($0.0)
        }
        XCTAssertEqual(
            Set(primaryFrames.map(\.0)),
            requiredPrimaryButtonIdentifiers,
            file: file,
            line: line
        )
        if let baseline = primaryFrames.first?.1.minX {
            for (identifier, frame) in primaryFrames.dropFirst() {
                XCTAssertEqual(
                    frame.minX,
                    baseline,
                    accuracy: 1,
                    identifier,
                    file: file,
                    line: line
                )
            }
        }
    }

    private func assertTestingActionButtons(
        in hostingView: NSView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let markers = allSubviews(in: hostingView).compactMap {
            $0 as? TestingActionButton
        }
        XCTAssertFalse(markers.isEmpty, file: file, line: line)
        for marker in markers {
            XCTAssertEqual(marker.frame.width, 0, accuracy: 1, file: file, line: line)
            XCTAssertEqual(marker.frame.height, 0, accuracy: 1, file: file, line: line)
            XCTAssertEqual(marker.alphaValue, 0, file: file, line: line)
            XCTAssertTrue(marker.focusRingType == .none, file: file, line: line)
            XCTAssertFalse(marker.acceptsFirstResponder, file: file, line: line)
            XCTAssertTrue(marker.refusesFirstResponder, file: file, line: line)
            XCTAssertFalse(marker.isAccessibilityElement(), file: file, line: line)
        }
    }

    private func attachSnapshot(of view: NSView, name: String) {
        guard
            let representation = view.bitmapImageRepForCachingDisplay(
                in: view.bounds
            )
        else {
            return XCTFail("Unable to create \(name) bitmap")
        }
        view.cacheDisplay(in: view.bounds, to: representation)
        guard
            let data = representation.representation(
                using: .png,
                properties: [:]
            )
        else {
            return XCTFail("Unable to encode \(name) bitmap")
        }
        let attachment = XCTAttachment(
            data: data,
            uniformTypeIdentifier: "public.png"
        )
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func findTextField(
        in root: NSView,
        placeholder: String
    ) -> NSTextField? {
        if let field = root as? NSTextField,
           field.placeholderString == placeholder
        {
            return field
        }
        return root.subviews.lazy.compactMap {
            self.findTextField(in: $0, placeholder: placeholder)
        }.first
    }

    private func removeFromWindow(_ window: NSWindow) {
        window.orderOut(nil)
        window.contentView = nil
    }

    private func routePreview() throws -> RoutePreview {
        try RoutePreview(points: [
            RoutePoint(
                coordinate: RouteCoordinate(latitude: 25, longitude: 121),
                cumulativeDistance: 0
            ),
            RoutePoint(
                coordinate: RouteCoordinate(latitude: 25, longitude: 121.001),
                cumulativeDistance: 100
            ),
        ])
    }

    private func findMapView(in root: NSView) -> MKMapView? {
        if let mapView = root as? MKMapView {
            return mapView
        }
        return root.subviews.lazy.compactMap(findMapView).first
    }

    private func waitForPreviewMarker(
        at coordinate: MapCoordinate,
        in mapView: MKMapView
    ) async throws -> MKAnnotation {
        for _ in 0 ..< 100 {
            mapView.window?.displayIfNeeded()
            if let annotation = mapView.annotations.first(where: {
                $0.title == "預覽"
                    && abs($0.coordinate.latitude - coordinate.latitude)
                        < 0.000_001
                    && abs($0.coordinate.longitude - coordinate.longitude)
                        < 0.000_001
            }) {
                return annotation
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw ContentViewTestError.previewMarkerNotFound
    }

    private func waitForMapCenter(
        _ coordinate: MapCoordinate,
        in mapView: MKMapView
    ) async throws {
        for _ in 0 ..< 100 {
            mapView.window?.displayIfNeeded()
            if abs(mapView.centerCoordinate.latitude - coordinate.latitude)
                < 0.000_001,
               abs(mapView.centerCoordinate.longitude - coordinate.longitude)
                < 0.000_001
            {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw ContentViewTestError.mapCenterDidNotUpdate
    }

    private func waitForRouteMarker(
        in mapView: MKMapView,
        longitudeDifferentFrom previousLongitude: CLLocationDegrees? = nil
    ) async throws -> MKAnnotation {
        for _ in 0 ..< 100 {
            mapView.window?.displayIfNeeded()
            if let annotation = routeMarker(in: mapView),
               previousLongitude.map({
                   abs(annotation.coordinate.longitude - $0) > 0.000_000_1
               }) ?? true
            {
                return annotation
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw ContentViewTestError.routeMarkerNotFound
    }

    private func waitForRouteMarkerRemoval(
        _ annotation: MKAnnotation,
        from mapView: MKMapView
    ) async -> Bool {
        for _ in 0 ..< 100 {
            mapView.window?.displayIfNeeded()
            if routeMarker(in: mapView) == nil,
               !mapView.annotations.contains(where: { $0 === annotation })
            {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func routeMarker(in mapView: MKMapView) -> MKAnnotation? {
        mapView.annotations.first { annotation in
            mapView.view(for: annotation)?
                .accessibilityIdentifier() == "iphone-route-marker"
        }
    }

    private func makeStore() throws -> DeviceSetupStore {
        let device = try USBDevice(
            id: DeviceID("content-view-device"),
            name: "iPhone",
            operatingSystemVersion: OperatingSystemVersion(
                majorVersion: 17,
                minorVersion: 0,
                patchVersion: 0
            )
        )
        return DeviceSetupStore(
            runtimeManager: ContentViewRuntime(),
            device: ContentViewDevice(device: device),
            helperAuthorizer: ContentViewAuthorizer(),
            lifecycleCoordinator: AppLifecycleCoordinator(),
            sleepObserver: SystemSleepObserver(
                notificationCenter: NotificationCenter(),
                willSleepNotification: Notification.Name("unused-sleep"),
                didWakeNotification: Notification.Name("unused-wake")
            )
        )
    }

    private func waitForIdentifier(
        _ identifier: String,
        in root: NSView
    ) async -> Bool {
        for _ in 0 ..< 100 {
            if hasIdentifier(identifier, in: root) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func hasIdentifier(
        _ identifier: String,
        in root: NSView
    ) -> Bool {
        if containsViewIdentifier(identifier, in: root) {
            return true
        }
        return NSAccessibility.unignoredChildrenForOnlyChild(from: root).contains {
            containsIdentifier(identifier, in: $0)
        }
    }

    private func containsViewIdentifier(
        _ identifier: String,
        in view: NSView
    ) -> Bool {
        view.accessibilityIdentifier() == identifier
            || view.subviews.contains {
                containsViewIdentifier(identifier, in: $0)
            }
    }

    private func containsIdentifier(
        _ identifier: String,
        in element: Any
    ) -> Bool {
        if let view = element as? NSView {
            if view.accessibilityIdentifier() == identifier {
                return true
            }
            return (view.accessibilityChildren() ?? []).contains {
                containsIdentifier(identifier, in: $0)
            }
        }
        if let accessibilityElement = element as? NSAccessibilityElement {
            if accessibilityElement.accessibilityIdentifier() == identifier {
                return true
            }
            return (accessibilityElement.accessibilityChildren() ?? []).contains {
                containsIdentifier(identifier, in: $0)
            }
        }
        if let accessibilityElement =
            element as? NSAccessibilityElementProtocol,
           accessibilityElement.accessibilityIdentifier?() == identifier {
            return true
        }
        return false
    }
}

private enum ContentViewTestError: Error {
    case mapCenterDidNotUpdate
    case previewMarkerNotFound
    case routeMarkerNotFound
}

@MainActor
private struct ContentViewMacLocationProvider: MacLocationProviding {
    func requestCurrentLocation() async throws -> MapCoordinate {
        throw MacLocationClientError.locationServicesDisabled
    }
}

private actor ContentViewRuntime: DeviceRuntimeManaging {
    func inspect() async -> RuntimeAvailability {
        .ready(
            RuntimeInstallation(
                executableURL: URL(fileURLWithPath: "/runtime/pymobiledevice3"),
                source: .existing
            )
        )
    }

    func install(
        progress: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) async -> RuntimeInstallResult {
        .cancelled
    }

    func cancelRuntimeInstallation() async {}
}

private actor ContentViewAuthorizer: TunnelHelperAuthorizing {
    func inspect() async -> TunnelHelperAuthorizationStatus {
        .enabled
    }

    func requestApproval() async -> TunnelHelperAuthorizationStatus {
        .enabled
    }
}

private actor ContentViewDevice: DeviceSessionPreparing {
    let device: USBDevice
    private var state: DeviceSessionState = .disconnected

    init(device: USBDevice) {
        self.device = device
    }

    func connect(
        selectedDeviceID: DeviceID?
    ) async throws -> PreparedDeviceSession {
        let session = PreparedDeviceSession(
            device: device,
            generation: DeviceSessionGeneration(rawValue: 1)
        )
        state = .ready(session)
        return session
    }

    func currentSessionState() async -> DeviceSessionState {
        state
    }

    func discoverUSBDevices() async throws -> [USBDevice] {
        [device]
    }

    func prepare(deviceID: DeviceID) async throws -> PreparedDeviceSession {
        try await connect(selectedDeviceID: deviceID)
    }

    func setLocation(
        _ coordinate: DeviceCoordinate,
        context: DeviceMutationContext
    ) async throws {}

    func clearLocation(context: DeviceCleanupContext) async throws {}
    func shutdown(generation: DeviceSessionGeneration) async {}
    func teardownForQuit() async throws {}
}

@MainActor
private struct ContentViewSimulationHarness {
    let device = ContentViewSimulationDevice()
    let store: SimulationStore

    init() throws {
        store = SimulationStore(
            device: device,
            generation: DeviceSessionGeneration(rawValue: 1),
            scheduler: ContentViewSimulationScheduler()
        )
    }
}

private actor ContentViewSimulationDevice: DeviceLocationClient {
    private var setCallCount = 0

    func waitForSetCount(_ count: Int) async {
        while setCallCount < count {
            await Task.yield()
        }
    }

    func discoverUSBDevices() async throws -> [USBDevice] {
        []
    }

    func prepare(deviceID: DeviceID) async throws -> PreparedDeviceSession {
        throw DeviceLocationError.deviceNotFound
    }

    func setLocation(
        _ coordinate: DeviceCoordinate,
        context: DeviceMutationContext
    ) async throws {
        setCallCount += 1
    }

    func clearLocation(context: DeviceCleanupContext) async throws {}
    func shutdown(generation: DeviceSessionGeneration) async {}
}

private actor ResetTestSimulationDevice: DeviceLocationClient {
    private var setCallCount = 0
    private var clearCallCount = 0
    private var shouldSuspendSet = false
    private var shouldSuspendClear = false
    private var pendingSet: CheckedContinuation<Void, Never>?
    private var pendingClear: CheckedContinuation<Void, Never>?
    private var nextClearFailure: DeviceLocationError?

    func suspendNextSet() {
        shouldSuspendSet = true
    }

    func suspendNextClear() {
        shouldSuspendClear = true
    }

    func failNextClear(_ failure: DeviceLocationError) {
        nextClearFailure = failure
    }

    func resumeSet() {
        pendingSet?.resume()
        pendingSet = nil
    }

    func resumeClear() {
        pendingClear?.resume()
        pendingClear = nil
    }

    func waitForSetCount(_ count: Int) async {
        while setCallCount < count {
            await Task.yield()
        }
    }

    func waitForClearCount(_ count: Int) async {
        while clearCallCount < count {
            await Task.yield()
        }
    }

    func recordedClearCallCount() -> Int {
        clearCallCount
    }

    func discoverUSBDevices() async throws -> [USBDevice] {
        []
    }

    func prepare(deviceID: DeviceID) async throws -> PreparedDeviceSession {
        throw DeviceLocationError.deviceNotFound
    }

    func setLocation(
        _ coordinate: DeviceCoordinate,
        context: DeviceMutationContext
    ) async throws {
        setCallCount += 1
        if shouldSuspendSet {
            shouldSuspendSet = false
            await withCheckedContinuation { continuation in
                pendingSet = continuation
            }
        }
    }

    func clearLocation(context: DeviceCleanupContext) async throws {
        clearCallCount += 1
        if shouldSuspendClear {
            shouldSuspendClear = false
            await withCheckedContinuation { continuation in
                pendingClear = continuation
            }
        }
        if let nextClearFailure {
            self.nextClearFailure = nil
            throw nextClearFailure
        }
    }

    func shutdown(generation: DeviceSessionGeneration) async {}
}

private actor ContentViewSimulationScheduler: SimulationScheduling {
    func now() -> TimeInterval {
        0
    }

    func waitForNextTick() async throws {
        try await Task.sleep(for: .seconds(60))
    }
}


/// Keeps view-hierarchy tests off `UserDefaults.standard`, whose real saved
/// favourites would otherwise change what the sidebar renders.
private func makeIsolatedDefaults() -> UserDefaults {
    let name = "iPhoneLocationMoveTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

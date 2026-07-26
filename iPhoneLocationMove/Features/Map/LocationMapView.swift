import MapKit
import SwiftUI

struct LocationMapView: View {
    @StateObject private var model = LocationMapModel()
    private let simulationStore: SimulationStore?
    @State private var query = ""
    @State private var searchRequest: MapSearchRequest?
    @State private var activeSearch: MKLocalSearch?
    @State private var activeGeocoder: CLGeocoder?
    @State private var activeDirections: MKDirections?
    @State private var message: String?

    init(simulationStore: SimulationStore? = nil) {
        self.simulationStore = simulationStore
    }

    var body: some View {
        HStack(spacing: 0) {
            controls
                .frame(width: 320)

            Divider()

            LocationMapCanvas(
                preview: model.preview,
                endpointA: model.endpointA,
                endpointB: model.endpointB,
                route: model.routePreview?.polyline,
                onCoordinateSelected: selectMapCoordinate
            )
        }
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("地圖與路線")
                    .font(.title2)

                searchControls
                searchResults
                previewControls
                endpointControls
                routeControls
                if let simulationStore {
                    SimulationControls(
                        mapModel: model,
                        simulationStore: simulationStore
                    )
                } else {
                    DisconnectedSimulationControls()
                }

                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("搜尋地名或地址", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit(performSearch)

            HStack {
                Button("搜尋", action: performSearch)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("清除") {
                    cancelSearch()
                    cancelPreviewAddressLookup()
                    query = ""
                    do {
                        try model.clearSearch()
                        message = nil
                    } catch {
                        show(error)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if !model.searchResults.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("搜尋結果")
                    .font(.headline)
                ForEach(
                    Array(model.searchResults.enumerated()),
                    id: \.offset
                ) { _, place in
                    Button {
                        selectSearchResult(place)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.address ?? "未命名地點")
                            Text(coordinateText(place.coordinate))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var previewControls: some View {
        if let preview = model.preview {
            GroupBox("目前預覽") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(preview.address ?? "地圖選點")
                    Text(coordinateText(preview.coordinate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("選點只會更新預覽；必須另行確認後才會改變 iPhone 位置。")
                        .font(.caption)

                    HStack {
                        Button("設為 A") {
                            assignPreview(to: .a)
                        }
                        Button("設為 B") {
                            assignPreview(to: .b)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var endpointControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("步行端點")
                .font(.headline)
            endpointRow(label: "A", place: model.endpointA)
            endpointRow(label: "B", place: model.endpointB)

            Button("建立步行路線", action: performDirections)
                .disabled(model.endpointSnapshot == nil)
        }
    }

    private var routeControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("速度")
                Spacer()
                Text(String(format: "%.1f km/h", model.walkingSpeedKilometersPerHour))
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { model.walkingSpeedKilometersPerHour },
                    set: { newValue in
                        do {
                            try model.setWalkingSpeed(
                                kilometersPerHour: newValue
                            )
                            if let simulationStore,
                               let route = simulationStore.routeSnapshot,
                               route.phase == .running || route.phase == .paused
                            {
                                try simulationStore.setSpeed(
                                    newValue,
                                    at: ProcessInfo.processInfo.systemUptime
                                )
                            }
                        } catch {
                            show(error)
                        }
                    }
                ),
                in: LocationMapModel.walkingSpeedRange,
                step: 0.5
            )

            switch model.routeStatus {
            case .idle:
                EmptyView()
            case .loading:
                ProgressView("正在取得步行路線…")
            case .routeAvailable:
                if let route = model.routePreview {
                    Text(
                        "\(distanceText(route.distance))・\(durationText(route.estimatedTime))"
                    )
                    .font(.headline)
                    Text("路線已可供確認開始。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .noPedestrianRoute:
                Text("A 與 B 之間沒有可用的步行路線。")
                    .foregroundStyle(.red)
            case .cancelled:
                Text("已取消步行路線要求。")
                    .foregroundStyle(.secondary)
            case .transientFailure(let message):
                Text(message)
                    .foregroundStyle(.red)
                Button("重試", action: performDirections)
            }
        }
    }

    private func endpointRow(
        label: String,
        place: MapSearchPlace?
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.headline)
                .frame(width: 20)
            if let place {
                Text(place.address ?? coordinateText(place.coordinate))
                    .lineLimit(2)
            } else {
                Text("尚未選擇")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func performSearch() {
        cancelSearch()
        cancelPreviewAddressLookup()
        do {
            let request = try model.beginSearch(query: query)
            searchRequest = request

            let mapRequest = MKLocalSearch.Request()
            mapRequest.naturalLanguageQuery = request.query
            let search = MKLocalSearch(request: mapRequest)
            activeSearch = search
            message = nil

            Task { @MainActor in
                do {
                    let response = try await search.start()
                    let places = response.mapItems.compactMap { item in
                        mapPlace(from: item)
                    }
                    _ = model.receiveSearchResults(places, for: request)
                } catch is CancellationError {
                    return
                } catch {
                    guard request.generation == model.mapSearchGeneration else {
                        return
                    }
                    message = "搜尋失敗：\(error.localizedDescription)"
                }
                if activeSearch === search {
                    activeSearch = nil
                }
            }
        } catch {
            show(error)
        }
    }

    private func selectSearchResult(_ place: MapSearchPlace) {
        guard let searchRequest else {
            return
        }
        cancelSearch()
        cancelPreviewAddressLookup()
        do {
            try model.selectSearchResult(place, from: searchRequest)
            self.searchRequest = nil
            message = nil
        } catch {
            show(error)
        }
    }

    private func selectMapCoordinate(_ coordinate: MapCoordinate) {
        cancelSearch()
        cancelPreviewAddressLookup()
        do {
            let request = try model.selectMapCoordinate(coordinate)
            searchRequest = nil
            message = nil
            lookupAddress(for: request)
        } catch {
            show(error)
        }
    }

    private func assignPreview(to endpoint: MapEndpoint) {
        cancelDirections()
        do {
            try model.assignPreview(to: endpoint)
            message = nil
        } catch {
            show(error)
        }
    }

    private func performDirections() {
        cancelDirections()
        do {
            let request = try model.beginDirections()
            let mapRequest = MKDirections.Request()
            mapRequest.source = mapItem(for: request.snapshot.a)
            mapRequest.destination = mapItem(for: request.snapshot.b)
            mapRequest.transportType = .walking

            let directions = MKDirections(request: mapRequest)
            activeDirections = directions
            message = nil

            Task { @MainActor in
                let response: PedestrianDirectionsResponse
                do {
                    let result = try await directions.calculate()
                    if let route = result.routes.first,
                       let coordinates = mapCoordinates(from: route.polyline)
                    {
                        response = .routeAvailable(
                            coordinates,
                            distance: route.distance
                        )
                    } else {
                        response = .noPedestrianRoute
                    }
                } catch is CancellationError {
                    response = .cancelled
                } catch {
                    response = directionsResponse(for: error)
                }

                do {
                    _ = try model.receiveDirections(response, for: request)
                } catch {
                    show(error)
                }
                if activeDirections === directions {
                    activeDirections = nil
                }
            }
        } catch {
            show(error)
        }
    }

    private func cancelSearch() {
        activeSearch?.cancel()
        activeSearch = nil
    }

    private func lookupAddress(for request: MapPreviewAddressRequest) {
        let geocoder = CLGeocoder()
        activeGeocoder = geocoder
        let location = CLLocation(
            latitude: request.coordinate.latitude,
            longitude: request.coordinate.longitude
        )

        Task { @MainActor in
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                if let placemark = placemarks.first {
                    let address = [
                        placemark.name,
                        placemark.locality,
                        placemark.administrativeArea,
                    ]
                    .compactMap { $0 }
                    .reduce(into: [String]()) { parts, part in
                        if !parts.contains(part) {
                            parts.append(part)
                        }
                    }
                    .joined(separator: " ")
                    if !address.isEmpty {
                        _ = model.receivePreviewAddress(address, for: request)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                guard request.generation == model.mapSearchGeneration else {
                    return
                }
                message = "地址查詢失敗：\(error.localizedDescription)"
            }
            if activeGeocoder === geocoder {
                activeGeocoder = nil
            }
        }
    }

    private func cancelPreviewAddressLookup() {
        activeGeocoder?.cancelGeocode()
        activeGeocoder = nil
    }

    private func cancelDirections() {
        activeDirections?.cancel()
        activeDirections = nil
    }

    private func mapPlace(from item: MKMapItem) -> MapSearchPlace? {
        guard let coordinate = try? MapCoordinate(
            latitude: item.placemark.coordinate.latitude,
            longitude: item.placemark.coordinate.longitude
        ) else {
            return nil
        }
        return MapSearchPlace(
            coordinate: coordinate,
            address: item.name ?? item.placemark.title
        )
    }

    private func mapItem(for coordinate: MapCoordinate) -> MKMapItem {
        let placemark = MKPlacemark(
            coordinate: CLLocationCoordinate2D(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        )
        return MKMapItem(placemark: placemark)
    }

    private func mapCoordinates(from polyline: MKPolyline) -> [MapCoordinate]? {
        var coordinates = Array(
            repeating: CLLocationCoordinate2D(),
            count: polyline.pointCount
        )
        polyline.getCoordinates(
            &coordinates,
            range: NSRange(location: 0, length: polyline.pointCount)
        )
        let converted = coordinates.compactMap {
            try? MapCoordinate(
                latitude: $0.latitude,
                longitude: $0.longitude
            )
        }
        return converted.count >= 2 ? converted : nil
    }

    private func directionsResponse(
        for error: Error
    ) -> PedestrianDirectionsResponse {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
           nsError.code == NSURLErrorCancelled
        {
            return .cancelled
        }
        if nsError.domain == MKError.errorDomain,
           nsError.code == MKError.Code.directionsNotFound.rawValue
        {
            return .noPedestrianRoute
        }
        return .transientFailure(message: error.localizedDescription)
    }

    private func coordinateText(_ coordinate: MapCoordinate) -> String {
        String(
            format: "%.6f, %.6f",
            coordinate.latitude,
            coordinate.longitude
        )
    }

    private func distanceText(_ meters: Double) -> String {
        if meters >= 1_000 {
            return String(format: "%.2f km", meters / 1_000)
        }
        return String(format: "%.0f m", meters)
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        String(format: "%.0f 分鐘", seconds / 60)
    }

    private func show(_ error: Error) {
        message = error.localizedDescription
    }
}

private struct DisconnectedSimulationControls: View {
    @State private var roundTrip = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("iPhone 定位")
                .font(.headline)
            Button("設定位置") {}
                .disabled(true)
            Toggle("往返循環", isOn: $roundTrip)
                .disabled(true)
            Button("開始步行路線") {}
                .disabled(true)
            Text("完成裝置準備後即可使用定位控制。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SimulationControls: View {
    private enum PendingMutation {
        case point(MapCoordinate)
        case route(MapRoutePreview)
        case stop
    }

    @ObservedObject var mapModel: LocationMapModel
    @ObservedObject var simulationStore: SimulationStore
    @State private var roundTrip = false
    @State private var pendingMutation: PendingMutation?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            Text("iPhone 定位")
                .font(.headline)

            if mapModel.preview != nil {
                Button("設定位置") {
                    guard let coordinate = mapModel.preview?.coordinate else {
                        return
                    }
                    pendingMutation = .point(coordinate)
                }
                .disabled(isBusy)
            }

            Toggle("往返循環", isOn: $roundTrip)
                .disabled(!mapModel.canStartRoute || isBusy)

            Button("開始步行路線") {
                do {
                    pendingMutation = .route(
                        try mapModel.confirmRoutePreview()
                    )
                } catch {
                    show(error)
                }
            }
            .disabled(!mapModel.canStartRoute || isBusy)

            routeActionButtons

            simulationStatus

            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { pendingMutation != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingMutation = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(confirmationButtonTitle) {
                performConfirmedMutation()
            }
            Button("取消", role: .cancel) {
                pendingMutation = nil
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    @ViewBuilder
    private var routeActionButtons: some View {
        if let route = simulationStore.routeSnapshot {
            HStack {
                switch route.phase {
                case .running:
                    Button("暫停") {
                        do {
                            try simulationStore.pause()
                            message = nil
                        } catch {
                            show(error)
                        }
                    }
                case .paused:
                    Button("繼續") {
                        do {
                            try simulationStore.resume(
                                at: ProcessInfo.processInfo.systemUptime
                            )
                            message = nil
                        } catch {
                            show(error)
                        }
                    }
                default:
                    EmptyView()
                }
            }
        }

        if hasCleanupOwnership {
            Button("停止模擬", role: .destructive) {
                pendingMutation = .stop
            }
            .disabled(isStoppingWithoutFailure)
        }
    }

    @ViewBuilder
    private var simulationStatus: some View {
        switch simulationStore.state {
        case .idle:
            Text("未啟用模擬定位")
                .foregroundStyle(.secondary)
        case .starting(let mode, _):
            ProgressView(mode == .point ? "正在設定位置…" : "正在開始路線…")
        case .replacing:
            ProgressView("正在安全取代目前模式…")
        case .pointActive(let point):
            Label(
                String(
                    format: "單點定位 %.6f, %.6f",
                    point.coordinate.latitude,
                    point.coordinate.longitude
                ),
                systemImage: "location.fill"
            )
        case .route(let route, let failure):
            VStack(alignment: .leading, spacing: 4) {
                Text(routePhaseText(route.phase))
                Text(
                    String(
                        format: "已確認 %.0f m・%.1f km/h",
                        route.confirmedDistance,
                        route.speedKilometersPerHour
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                if let failure {
                    Text(failureText(failure))
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        case .interrupted(_, let interruption, let failure):
            VStack(alignment: .leading, spacing: 4) {
                Text("模擬已中斷")
                    .foregroundStyle(.red)
                Text(interruption.positionKnowledge == .unknown
                    ? "目前無法確認手機端位置。"
                    : "手機端位置仍可確認。")
                Text(failureText(failure))
                    .font(.caption)
            }
        case .stopping(_, let failure):
            if let failure {
                VStack(alignment: .leading, spacing: 4) {
                    Text("清除定位失敗，尚未恢復真實位置。")
                        .foregroundStyle(.red)
                    Text(failureText(failure))
                        .font(.caption)
                }
            } else {
                ProgressView("正在清除模擬定位…")
            }
        }
    }

    private var isBusy: Bool {
        switch simulationStore.state {
        case .starting, .replacing:
            return true
        case .stopping(_, nil):
            return true
        default:
            return false
        }
    }

    private var hasCleanupOwnership: Bool {
        switch simulationStore.state {
        case .pointActive, .route, .interrupted, .stopping:
            return true
        case .idle, .starting, .replacing:
            return false
        }
    }

    private var isStoppingWithoutFailure: Bool {
        if case .stopping(_, nil) = simulationStore.state {
            return true
        }
        return false
    }

    private var confirmationTitle: String {
        switch pendingMutation {
        case .point, .route:
            RiskNotice.simulationStart.title
        case .stop:
            "確認停止並清除定位？"
        case nil:
            "確認操作"
        }
    }

    private var confirmationButtonTitle: String {
        switch pendingMutation {
        case .stop:
            "停止並清除"
        case .point, .route:
            RiskNotice.simulationStart.confirmationTitle
        case nil:
            "確認"
        }
    }

    private var confirmationMessage: String {
        switch pendingMutation {
        case .point, .route:
            RiskNotice.simulationStart.message
        case .stop:
            "只有手機回覆 clear 成功後，App 才會顯示已恢復真實定位。"
        case nil:
            ""
        }
    }

    private func performConfirmedMutation() {
        guard let pendingMutation else {
            return
        }
        self.pendingMutation = nil

        Task { @MainActor in
            switch pendingMutation {
            case .point(let coordinate):
                do {
                    try await confirmPoint(coordinate)
                    message = nil
                } catch {
                    show(error)
                }
            case .route(let mapPreview):
                do {
                    try await simulationStore.startRoute(
                        preview: try RoutePreview(mapPreview: mapPreview),
                        speedKilometersPerHour:
                            mapModel.walkingSpeedKilometersPerHour,
                        roundTrip: roundTrip,
                        riskAccepted: true
                    )
                    message = nil
                } catch {
                    show(error)
                }
            case .stop:
                await simulationStore.stop()
                if case .stopping(_, let failure) = simulationStore.state,
                   let failure {
                    message = failureText(failure)
                } else {
                    message = nil
                }
            }
        }
    }

    private func confirmPoint(_ coordinate: MapCoordinate) async throws {
        let deviceCoordinate = try DeviceCoordinate(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        await simulationStore.confirmPoint(
            deviceCoordinate,
            riskAccepted: true
        )
    }

    private func routePhaseText(_ phase: RouteSessionPhase) -> String {
        switch phase {
        case .idle:
            "路線未開始"
        case .preview:
            "路線預覽"
        case .running:
            "路線移動中"
        case .pausing:
            "正在確認暫停位置"
        case .paused:
            "路線已暫停"
        case .completed:
            "單程已完成，維持終點位置"
        case .interrupted:
            "路線已中斷"
        case .stopping:
            "正在停止路線"
        }
    }

    private func failureText(_ failure: DeviceLocationError) -> String {
        let presentation = DeviceFailurePresentation.make(for: failure)
        return "\(presentation.title)：\(presentation.message)"
    }

    private func show(_ error: Error) {
        message = error.localizedDescription
    }
}

extension RoutePreview {
    init(mapPreview: MapRoutePreview) throws {
        guard mapPreview.polyline.count >= 2,
              mapPreview.distance.isFinite,
              mapPreview.distance > 0
        else {
            throw LocationMapError.invalidRoute
        }

        var retainedCoordinates = [MapCoordinate]()
        var rawCumulativeDistances = [Double]()
        var cumulativeDistance = 0.0

        for coordinate in mapPreview.polyline {
            if let previous = retainedCoordinates.last {
                let distance = CLLocation(
                    latitude: previous.latitude,
                    longitude: previous.longitude
                ).distance(
                    from: CLLocation(
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude
                    )
                )
                guard distance > 0 else {
                    continue
                }
                cumulativeDistance += distance
            }
            retainedCoordinates.append(coordinate)
            rawCumulativeDistances.append(cumulativeDistance)
        }

        guard retainedCoordinates.count >= 2, cumulativeDistance > 0 else {
            throw LocationMapError.invalidRoute
        }

        let scale = mapPreview.distance / cumulativeDistance
        let points = zip(retainedCoordinates, rawCumulativeDistances).map {
            coordinate, rawDistance in
            RoutePoint(
                coordinate: RouteCoordinate(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                ),
                cumulativeDistance: rawDistance * scale
            )
        }
        try self.init(points: points)
    }
}

private struct LocationMapCanvas: NSViewRepresentable {
    let preview: MapSearchPlace?
    let endpointA: MapSearchPlace?
    let endpointB: MapSearchPlace?
    let route: [MapCoordinate]?
    let onCoordinateSelected: (MapCoordinate) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCoordinateSelected: onCoordinateSelected)
    }

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        context.coordinator.mapView = mapView
        let click = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.mapClicked(_:))
        )
        mapView.addGestureRecognizer(click)
        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onCoordinateSelected = onCoordinateSelected
        context.coordinator.update(
            preview: preview,
            endpointA: endpointA,
            endpointB: endpointB,
            route: route
        )
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        weak var mapView: MKMapView?
        var onCoordinateSelected: (MapCoordinate) -> Void
        private var centeredCoordinate: MapCoordinate?

        init(onCoordinateSelected: @escaping (MapCoordinate) -> Void) {
            self.onCoordinateSelected = onCoordinateSelected
        }

        @objc
        func mapClicked(_ recognizer: NSClickGestureRecognizer) {
            guard recognizer.state == .ended, let mapView else {
                return
            }
            let point = recognizer.location(in: mapView)
            let coordinate = mapView.convert(
                point,
                toCoordinateFrom: mapView
            )
            guard let mapCoordinate = try? MapCoordinate(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ) else {
                return
            }
            onCoordinateSelected(mapCoordinate)
        }

        func update(
            preview: MapSearchPlace?,
            endpointA: MapSearchPlace?,
            endpointB: MapSearchPlace?,
            route: [MapCoordinate]?
        ) {
            guard let mapView else {
                return
            }
            mapView.removeAnnotations(mapView.annotations)
            mapView.removeOverlays(mapView.overlays)

            addAnnotation(preview, title: "預覽")
            addAnnotation(endpointA, title: "A")
            addAnnotation(endpointB, title: "B")

            if let route, route.count >= 2 {
                var coordinates = route.map {
                    CLLocationCoordinate2D(
                        latitude: $0.latitude,
                        longitude: $0.longitude
                    )
                }
                let polyline = MKPolyline(
                    coordinates: &coordinates,
                    count: coordinates.count
                )
                mapView.addOverlay(polyline)
                mapView.setVisibleMapRect(
                    polyline.boundingMapRect,
                    edgePadding: NSEdgeInsets(
                        top: 40,
                        left: 40,
                        bottom: 40,
                        right: 40
                    ),
                    animated: true
                )
            } else if let preview,
                      preview.coordinate != centeredCoordinate
            {
                centeredCoordinate = preview.coordinate
                mapView.setRegion(
                    MKCoordinateRegion(
                        center: CLLocationCoordinate2D(
                            latitude: preview.coordinate.latitude,
                            longitude: preview.coordinate.longitude
                        ),
                        latitudinalMeters: 1_500,
                        longitudinalMeters: 1_500
                    ),
                    animated: true
                )
            }
        }

        func mapView(
            _ mapView: MKMapView,
            rendererFor overlay: MKOverlay
        ) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = .systemBlue
            renderer.lineWidth = 5
            return renderer
        }

        func mapView(
            _ mapView: MKMapView,
            viewFor annotation: MKAnnotation
        ) -> MKAnnotationView? {
            let identifier = "location-marker"
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: identifier
            ) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(
                    annotation: annotation,
                    reuseIdentifier: identifier
                )
            view.annotation = annotation
            view.canShowCallout = true
            return view
        }

        private func addAnnotation(
            _ place: MapSearchPlace?,
            title: String
        ) {
            guard let place, let mapView else {
                return
            }
            let annotation = MKPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(
                latitude: place.coordinate.latitude,
                longitude: place.coordinate.longitude
            )
            annotation.title = title
            annotation.subtitle = place.address
            mapView.addAnnotation(annotation)
        }
    }
}

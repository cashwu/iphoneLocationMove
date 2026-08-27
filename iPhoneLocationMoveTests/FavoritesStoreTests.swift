import Foundation
import XCTest
@testable import iPhoneLocationMove

@MainActor
final class FavoritesStoreTests: XCTestCase {
    func testToggleUsesAddressNameAndDeduplicatesByCoordinate() throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let coordinate = try MapCoordinate(latitude: 25.033964, longitude: 121.564468)
        let place = MapSearchPlace(coordinate: coordinate, address: "台北101")
        let store = FavoritesStore(defaults: defaults)

        store.toggle(place)
        store.toggle(MapSearchPlace(coordinate: coordinate, address: "不同地址"))

        XCTAssertTrue(store.favorites.isEmpty)
        store.toggle(place)
        XCTAssertEqual(store.favorites.count, 1)
        XCTAssertEqual(store.favorites[0].name, "台北101")
    }

    func testNilAddressUsesRoundedCoordinateName() throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let coordinate = try MapCoordinate(latitude: 25.033964, longitude: 121.564468)
        let store = FavoritesStore(defaults: defaults)

        store.toggle(MapSearchPlace(coordinate: coordinate, address: nil))

        XCTAssertEqual(store.favorites.first?.name, "25.03396, 121.56447")
    }

    func testRemoveRenameAndRoundTripPreserveOrder() throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let first = MapSearchPlace(coordinate: try MapCoordinate(latitude: 25, longitude: 121), address: "第一筆")
        let second = MapSearchPlace(coordinate: try MapCoordinate(latitude: 24, longitude: 120), address: "第二筆")
        let store = FavoritesStore(defaults: defaults)
        store.toggle(first)
        store.toggle(second)
        let firstID = try XCTUnwrap(store.favorites.first?.id)
        store.rename(id: firstID, to: "  公司  ")
        store.remove(id: UUID())

        let reloaded = FavoritesStore(defaults: defaults)
        XCTAssertEqual(reloaded.favorites.map(\.name), ["公司", "第二筆"])
        XCTAssertEqual(reloaded.favorites.map(\.coordinate), [first.coordinate, second.coordinate])
        store.rename(id: firstID, to: "   ")
        XCTAssertEqual(store.favorites.first?.name, "公司")
    }

    func testInvalidEntriesAreSkippedAndInvalidDocumentStartsEmpty() throws {
        let defaults = UserDefaults(suiteName: #function)!
        let valid = try MapCoordinate(latitude: 25, longitude: 121)
        let validDTO: [String: Any] = [
            "id": UUID().uuidString, "latitude": valid.latitude, "longitude": valid.longitude,
            "address": "有效", "name": "有效", "addedAt": Date().timeIntervalSinceReferenceDate
        ]
        let invalidCoordinate: [String: Any] = [
            "id": UUID().uuidString, "latitude": 91, "longitude": 121,
            "address": NSNull(), "name": "無效", "addedAt": Date().timeIntervalSinceReferenceDate
        ]
        let data = try JSONSerialization.data(withJSONObject: [validDTO, invalidCoordinate, ["name": "毀損"]])
        defaults.set(data, forKey: FavoritesStore.defaultsKey)
        let store = FavoritesStore(defaults: defaults)
        XCTAssertEqual(store.favorites.map(\.name), ["有效"])

        defaults.set(Data("{}".utf8), forKey: FavoritesStore.defaultsKey)
        XCTAssertTrue(FavoritesStore(defaults: defaults).favorites.isEmpty)
    }

    func testWriteFailureDoesNotChangeMemoryState() throws {
        let defaults = DiscardingUserDefaults()
        let store = FavoritesStore(defaults: defaults)
        let place = MapSearchPlace(
            coordinate: try MapCoordinate(latitude: 25, longitude: 121),
            address: "仍保留"
        )

        store.toggle(place)

        XCTAssertEqual(store.favorites.map(\.name), ["仍保留"])
    }
}

private final class DiscardingUserDefaults: UserDefaults {
    override func set(_ value: Any?, forKey defaultName: String) {}
}

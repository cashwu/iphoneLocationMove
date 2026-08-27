import Combine
import Foundation

struct FavoritePlace: Equatable, Identifiable, Sendable {
    let id: UUID
    let coordinate: MapCoordinate
    let address: String?
    var name: String
    let addedAt: Date
}

@MainActor
final class FavoritesStore: ObservableObject {
    static let defaultsKey = "favoritePlaces"

    @Published private(set) var favorites: [FavoritePlace]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        favorites = Self.load(from: defaults)
    }

    func isFavorite(_ coordinate: MapCoordinate) -> Bool {
        favorites.contains { $0.coordinate == coordinate }
    }

    func toggle(_ place: MapSearchPlace) {
        if let index = favorites.firstIndex(where: { $0.coordinate == place.coordinate }) {
            favorites.remove(at: index)
        } else {
            favorites.append(
                FavoritePlace(
                    id: UUID(),
                    coordinate: place.coordinate,
                    address: place.address,
                    name: Self.defaultName(for: place),
                    addedAt: Date()
                )
            )
        }
        persist()
    }

    func remove(id: UUID) {
        guard let index = favorites.firstIndex(where: { $0.id == id }) else {
            return
        }
        favorites.remove(at: index)
        persist()
    }

    func rename(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = favorites.firstIndex(where: { $0.id == id })
        else {
            return
        }
        favorites[index].name = trimmed
        persist()
    }

    private func persist() {
        let payload = favorites.map(FavoriteDTO.init)
        guard let data = try? JSONEncoder().encode(payload) else {
            return
        }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func load(from defaults: UserDefaults) -> [FavoritePlace] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              var container = try? JSONDecoder().unkeyedContainer(from: data)
        else {
            return []
        }

        var result: [FavoritePlace] = []
        while !container.isAtEnd {
            guard let decoder = try? container.superDecoder(),
                  let dto = try? FavoriteDTO(from: decoder),
                  let coordinate = try? MapCoordinate(
                      latitude: dto.latitude,
                      longitude: dto.longitude
                  )
            else {
                continue
            }
            result.append(dto.favoritePlace(coordinate: coordinate))
        }
        return result
    }

    private static func defaultName(for place: MapSearchPlace) -> String {
        if let address = place.address {
            return address
        }
        return String(
            format: "%.5f, %.5f",
            locale: Locale(identifier: "en_US_POSIX"),
            place.coordinate.latitude,
            place.coordinate.longitude
        )
    }
}

private struct FavoriteDTO: Codable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let address: String?
    let name: String
    let addedAt: Date

    init(_ favorite: FavoritePlace) {
        id = favorite.id
        latitude = favorite.coordinate.latitude
        longitude = favorite.coordinate.longitude
        address = favorite.address
        name = favorite.name
        addedAt = favorite.addedAt
    }

    func favoritePlace(coordinate: MapCoordinate) -> FavoritePlace {
        FavoritePlace(
            id: id,
            coordinate: coordinate,
            address: address,
            name: name,
            addedAt: addedAt
        )
    }
}

private extension JSONDecoder {
    func unkeyedContainer(from data: Data) throws -> UnkeyedDecodingContainer {
        try decode(UnkeyedContainerBox.self, from: data).container
    }
}

private struct UnkeyedContainerBox: Decodable {
    let container: UnkeyedDecodingContainer

    init(from decoder: Decoder) throws {
        container = try decoder.unkeyedContainer()
    }
}

import Foundation
import Observation
import SwiftUI

struct Concert: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var urls: [String]
}

/// Les programmes de concert : des listes jouées dans l'ordre choisi, pas de A à Z.
@MainActor
@Observable
final class Concerts {
    private(set) var all: [Concert]

    static let prefix = "Concert : "
    private static let fileName = "concerts.json"

    init() {
        all = DocumentsJSON.load([Concert].self, from: Self.fileName) ?? []
    }

    @discardableResult
    func create(name: String) -> Concert {
        let concert = Concert(id: UUID(), name: name, urls: [])
        all.append(concert)
        save()
        return concert
    }

    func rename(_ id: UUID, to name: String) {
        edit(id) { $0.name = name }
    }

    func delete(_ id: UUID) {
        all.removeAll { $0.id == id }
        save()
    }

    func add(_ url: String, to id: UUID) {
        edit(id) { if !$0.urls.contains(url) { $0.urls.append(url) } }
    }

    /// Les positions comptent dans concert.urls.
    func remove(at offsets: IndexSet, from id: UUID) {
        edit(id) { $0.urls.remove(atOffsets: offsets) }
    }

    func move(from source: IndexSet, to destination: Int, in id: UUID) {
        edit(id) { $0.urls.move(fromOffsets: source, toOffset: destination) }
    }

    func playlist(_ concert: Concert, in library: Library) -> Playlist {
        // La vue peut tenir une copie d'avant le dernier changement : on relit la version enregistrée.
        let current = all.first { $0.id == concert.id } ?? concert
        let ids = current.urls.compactMap { library.song(matching: $0)?.tabID }
        return Playlist(name: Self.prefix + current.name, ids: ids, keepsOrder: true)
    }

    func concert(forPlaylistName name: String) -> Concert? {
        all.first { Self.prefix + $0.name == name }
    }

    private func edit(_ id: UUID, _ change: (inout Concert) -> Void) {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        change(&all[index])
        save()
    }

    private func save() {
        DocumentsJSON.save(all, to: Self.fileName)
    }
}

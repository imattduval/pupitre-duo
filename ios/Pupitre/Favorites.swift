import Foundation
import Observation

/// Morceaux mis en favori, dans l'ordre d'ajout, gardés sur le téléphone (Documents/favoris.json).
@MainActor @Observable final class Favorites {
    static let name = "Mes favoris"
    static let icon = "star"

    private(set) var urls: [String] = []

    @ObservationIgnored private let file = URL.documentsDirectory.appending(path: "favoris.json")
    /// Fichier présent mais illisible : jamais écrasé, mis de côté à la première écriture.
    @ObservationIgnored private var unreadable = false

    init() {
        guard FileManager.default.fileExists(atPath: file.path()) else { return }
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([String].self, from: data) {
            urls = saved
        } else {
            unreadable = true
        }
    }

    func contains(_ url: String) -> Bool { urls.contains(where: Self.same(url)) }

    func toggle(_ url: String) {
        if contains(url) {
            remove(url)
        } else {
            urls.append(url)
            save()
        }
    }

    func remove(_ url: String) {
        guard contains(url) else { return }
        urls.removeAll(where: Self.same(url))
        save()
    }

    /// Le même morceau peut avoir deux formes de lien : comme library.song(matching:) et playlist(in:), on compare aussi le numéro UG.
    private static func same(_ url: String) -> (String) -> Bool {
        let id = Song(url: url, title: "", artist: "").tabID
        return { $0 == url || (id != nil && Song(url: $0, title: "", artist: "").tabID == id) }
    }

    /// Triée de A à Z comme les autres listes ; un favori retiré de la bibliothèque n'y apparaît plus.
    func playlist(in library: Library) -> Playlist {
        var wanted = Set(urls.compactMap { Song(url: $0, title: "", artist: "").tabID })
        return Playlist(name: Self.name, ids: library.alphabetical.compactMap(\.tabID).filter { wanted.remove($0) != nil })
    }

    private func save() {
        if unreadable {
            // Garde l'ancien fichier sous un autre nom ; s'il ne peut pas être déplacé, on n'écrit rien.
            let aside = file.appendingPathExtension("illisible")
            try? FileManager.default.removeItem(at: aside)
            guard (try? FileManager.default.moveItem(at: file, to: aside)) != nil else { return }
            unreadable = false
        }
        guard let data = try? JSONEncoder().encode(urls) else { return }
        try? data.write(to: file, options: .atomic)
    }
}

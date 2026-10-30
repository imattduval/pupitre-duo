import Foundation
import Observation

struct Song: Codable, Identifiable, Equatable {
    var url: String
    var title: String
    var artist: String
    var text: String?
    var transpose = 0
    var speed: Double = 30
    var scale: Double = 1

    var id: String { url }
    var isReady: Bool { text != nil }
}

/// Bibliothèque stockée uniquement sur le téléphone, dans un fichier du dossier de l'app.
@Observable
final class Library {
    private(set) var songs: [Song] = []
    private let file: URL

    init() {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        file = folder.appending(path: "bibliotheque.json")
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([Song].self, from: data) {
            songs = saved
        }
    }

    var readyCount: Int { songs.filter(\.isReady).count }
    var ready: [Song] { songs.filter(\.isReady) }

    func nextToImport(after url: String?) -> Song? {
        let missing = songs.filter { !$0.isReady }
        guard let url, let index = songs.firstIndex(where: { $0.url == url }) else { return missing.first }
        return songs[index...].dropFirst().first { !$0.isReady } ?? missing.first
    }

    @discardableResult
    func addList(_ items: [ImportedLink]) -> Int {
        var added = 0
        for item in items where !songs.contains(where: { $0.url == item.url }) {
            songs.append(Song(url: item.url, title: item.title, artist: item.artist))
            added += 1
        }
        save()
        return added
    }

    func store(url: String, title: String, artist: String, text: String) {
        if let index = songs.firstIndex(where: { $0.url == url }) {
            songs[index].text = text
            if songs[index].artist.isEmpty { songs[index].artist = artist }
        } else {
            songs.append(Song(url: url, title: title, artist: artist, text: text))
        }
        save()
    }

    func update(_ song: Song) {
        guard let index = songs.firstIndex(where: { $0.url == song.url }) else { return }
        songs[index] = song
        save()
    }

    func remove(_ song: Song) {
        songs.removeAll { $0.url == song.url }
        save()
    }

    func neighbour(of song: Song, step: Int) -> Song? {
        let list = ready
        guard !list.isEmpty, let index = list.firstIndex(where: { $0.url == song.url }) else { return nil }
        return list[(index + step + list.count) % list.count]
    }

    private func save() {
        if let data = try? JSONEncoder().encode(songs) {
            try? data.write(to: file, options: .atomic)
        }
    }
}

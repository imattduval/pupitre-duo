import Foundation
import Observation

/// Les morceaux marqués d'un drapeau pour les retravailler. Les étoiles restent aux favoris.
@MainActor
@Observable
final class WorkList {
    static let name = "À travailler"
    static let icon = "flag"

    private(set) var urls: [String]

    private static let fileName = "a-travailler.json"

    init() {
        urls = DocumentsJSON.load([String].self, from: Self.fileName) ?? []
    }

    func contains(_ url: String) -> Bool { urls.contains(url) }

    func toggle(_ url: String) {
        if contains(url) {
            remove(url)
        } else {
            urls.append(url)
            DocumentsJSON.save(urls, to: Self.fileName)
        }
    }

    func remove(_ url: String) {
        urls.removeAll { $0 == url }
        DocumentsJSON.save(urls, to: Self.fileName)
    }

    func playlist(in library: Library) -> Playlist {
        let wanted = Set(urls)
        return Playlist(name: Self.name, ids: library.songs.filter { wanted.contains($0.url) }.compactMap(\.tabID))
    }
}

/// Petit fichier JSON du dossier Documents, écrit d'un bloc comme la bibliothèque.
enum DocumentsJSON {
    static func url(_ name: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: name)
    }

    /// nil si le fichier n'existe pas encore. Un fichier illisible est mis de côté, jamais écrasé.
    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        let file = url(name)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        if let data = try? Data(contentsOf: file), let value = try? JSONDecoder().decode(T.self, from: data) {
            return value
        }
        try? FileManager.default.moveItem(at: file, to: url("\(name).illisible-\(Int(Date().timeIntervalSince1970))"))
        return nil
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url(name), options: .atomic)
    }
}

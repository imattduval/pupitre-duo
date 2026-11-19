import Foundation
import Observation

/// Quel morceau suit quel autre pendant une même séance, pour proposer la suite (Documents/enchainements.json).
@MainActor @Observable final class PlayTransitions {
    private struct Stored: Codable {
        var counts: [String: [String: Int]] = [:]
        /// Le dernier morceau compté est gardé sur disque : l'app peut être fermée entre deux morceaux.
        var last: String?
        var lastAt: Date?
    }

    private var stored = Stored()

    @ObservationIgnored private let file = URL.documentsDirectory.appending(path: "enchainements.json")
    /// Fichier présent mais illisible : jamais écrasé, mis de côté à la première écriture.
    @ObservationIgnored private var unreadable = false

    init() {
        guard FileManager.default.fileExists(atPath: file.path()) else { return }
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(Stored.self, from: data) {
            stored = saved
        } else {
            unreadable = true
        }
    }

    func record(_ url: String, at date: Date = .now) {
        // Au-delà de 45 minutes, ce n'est plus la même séance : pas d'enchaînement.
        if let last = stored.last, last != url, let lastAt = stored.lastAt,
           (0..<45 * 60).contains(date.timeIntervalSince(lastAt)) {
            stored.counts[last, default: [:]][url, default: 0] += 1
        }
        stored.last = url
        stored.lastAt = date
        save()
    }

    func next(after url: String) -> [String: Int] { stored.counts[url] ?? [:] }

    private func save() {
        if unreadable {
            // Garde l'ancien fichier sous un autre nom ; s'il ne peut pas être déplacé, on n'écrit rien.
            let aside = file.appendingPathExtension("illisible")
            try? FileManager.default.removeItem(at: aside)
            guard (try? FileManager.default.moveItem(at: file, to: aside)) != nil else { return }
            unreadable = false
        }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: file, options: .atomic)
    }
}

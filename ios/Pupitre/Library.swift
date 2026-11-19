import Foundation
import NaturalLanguage
import Observation

struct Song: Codable, Identifiable, Equatable {
    var url: String
    var title: String
    var artist: String
    var type: String?
    var language: String?
    var text: String?
    var transpose = 0
    var speed: Double = 30
    /// Vitesse en paroles seules, retenue à part ; nil tant qu'elle n'a pas été réglée.
    var lyricsSpeed: Double?
    /// Vitesse en accords seuls, retenue à part ; nil tant qu'elle n'a pas été réglée.
    var chordsSpeed: Double?
    var scale: Double = 1.4

    var id: String { url }
    var isReady: Bool { text != nil }
    /// Le numéro UG, à la fin du lien quelle que soit sa forme.
    /// Lu à la main : une expression régulière, appelée sur 995 morceaux à chaque écran, ralentissait tout.
    var tabID: Int? {
        let digits = url.utf8.reversed().prefix { $0 >= 48 && $0 <= 57 }
        return digits.isEmpty ? nil : Int(String(decoding: digits.reversed(), as: UTF8.self))
    }
    /// La lettre de la colonne alphabétique ; « # » pour ce qui ne commence pas par une lettre.
    var initial: String {
        let first = title.folding(options: .diacriticInsensitive, locale: nil).uppercased().first
        return first.map { $0.isLetter && $0.isASCII ? String($0) : "#" } ?? "#"
    }
}

struct Playlist: Decodable, Identifiable, Hashable {
    let name: String
    let ids: [Int]
    /// L'historique garde l'ordre des écoutes ; toutes les autres listes sont triées de A à Z.
    var isHistory = false
    /// Liste montrée dans l'ordre de ses ids (historique, plus joués, concert), pas de A à Z.
    var keepsOrder = false

    var id: String { name }

    private enum CodingKeys: String, CodingKey { case name, ids }
}

private struct Account: Decodable {
    struct Item: Decodable {
        let id: Int
        let url: String
        let title: String
        let artist: String
        let type: String
    }

    let songs: [Item]
    let playlists: [Playlist]
}

/// Bibliothèque stockée uniquement sur le téléphone, dans un fichier du dossier de l'app.
@Observable
final class Library {
    private(set) var songs: [Song] = []
    private(set) var playlists: [Playlist] = []
    /// Dernière ouverture et nombre d'ouvertures de chaque morceau, par lien. Fichier à part : le lecteur
    /// réenregistre sa copie du morceau et effacerait ce qui serait rangé dans le morceau lui-même.
    private(set) var playedAt: [String: Date] = [:]
    private(set) var playCounts: [String: Int] = [:]

    private struct HistoryFile: Codable {
        var playedAt: [String: Date]
        var counts: [String: Int]
        /// Les morceaux ouverts avant les dates, figés au premier lancement : un morceau chargé ensuite
        /// sans être joué (hors ligne, ou quitté avant 10 secondes) n'entre pas dans l'historique.
        var legacy: [String]?
    }
    private var legacy: Set<String> = []
    /// Vrai après une restauration : un chargement encore en cours sur l'ancienne bibliothèque ne réécrit pas les fichiers restaurés.
    @ObservationIgnored var isRetired = false
    private let file: URL
    private let historyFile: URL

    init() {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        file = folder.appending(path: "bibliotheque.json")
        historyFile = folder.appending(path: "historique.json")
        var savedLegacy: [String]?
        if let data = try? Data(contentsOf: historyFile) {
            if let saved = try? JSONDecoder().decode(HistoryFile.self, from: data) {
                playedAt = saved.playedAt
                playCounts = saved.counts
                savedLegacy = saved.legacy
            } else if let old = try? JSONDecoder().decode([String: Date].self, from: data) {
                // Première version : seulement les dates. Chaque morceau daté compte pour une écoute.
                playedAt = old
                playCounts = old.mapValues { _ in 1 }
            }
        }
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([Song].self, from: data) {
            songs = saved
        }
        if let savedLegacy {
            legacy = Set(savedLegacy)
        } else {
            legacy = Set(songs.filter { $0.isReady && playedAt[$0.url] == nil }.map(\.url))
            saveHistory()
        }
        // Une seule fois : l'ancienne taille par défaut (100 %) passe à 140 %.
        if !UserDefaults.standard.bool(forKey: "taille.140") {
            for index in songs.indices where songs[index].scale == 1 { songs[index].scale = 1.4 }
            save()
            UserDefaults.standard.set(true, forKey: "taille.140")
        }
        loadAccount()
        refresh()
    }

    /// La liste du compte UG (titres et liens, sans paroles). Les morceaux ne sont ajoutés
    /// qu'une fois : un morceau supprimé ne revient pas.
    private func loadAccount() {
        guard let address = Bundle.main.url(forResource: "compte", withExtension: "json"),
              let data = try? Data(contentsOf: address),
              let account = try? JSONDecoder().decode(Account.self, from: data) else { return }
        playlists = account.playlists
        let key = "compte.ajoute"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        var known = Set(songs.compactMap(\.tabID))
        for item in account.songs where known.insert(item.id).inserted {
            songs.append(Song(url: item.url, title: item.title, artist: item.artist, type: item.type))
        }
        save()
        UserDefaults.standard.set(true, forKey: key)
    }

    private struct Entry: Decodable {
        let decade: Int?
        let language: String?
    }

    @ObservationIgnored private lazy var classement: [Int: Entry] = {
        guard let address = Bundle.main.url(forResource: "classement", withExtension: "json"),
              let data = try? Data(contentsOf: address),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: entries.compactMap { key, value in Int(key).map { ($0, value) } })
    }()

    /// Pour les suggestions : décennie connue (0 veut dire inconnue dans le classement) et langue.
    func decade(of song: Song) -> Int? {
        song.tabID.flatMap { classement[$0]?.decade }.flatMap { $0 == 0 ? nil : $0 }
    }

    func language(of song: Song) -> String? {
        song.language ?? song.tabID.flatMap { classement[$0]?.language }
    }

    /// Listes calculées une fois à chaque changement de la bibliothèque, pas à chaque affichage.
    private(set) var decadePlaylists: [Playlist] = []
    private(set) var languagePlaylists: [Playlist] = []
    private(set) var history = Playlist(name: Library.historyName, ids: [], isHistory: true, keepsOrder: true)
    private(set) var mostPlayed = Playlist(name: Library.mostPlayedName, ids: [], keepsOrder: true)
    @ObservationIgnored private var byID: [Int: Song] = [:]
    @ObservationIgnored private var scopes: [Playlist: [Song]] = [:]

    private func refresh() {
        alphabetical = songs
            .map { (key: $0.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil), song: $0) }
            // Ce qui ne commence pas par une lettre passe après le Z, comme dans la colonne de lettres.
            .sorted { ($0.song.initial == "#" ? 1 : 0, $0.key) < ($1.song.initial == "#" ? 1 : 0, $1.key) }
            .map(\.song)
        byID = [:]
        for song in songs {
            if let id = song.tabID { byID[id] = song }
        }
        scopes = [:]
        decadePlaylists = makeDecadePlaylists()
        languagePlaylists = makeLanguagePlaylists()
        history = makeHistory()
        mostPlayed = makeMostPlayed()
    }

    /// Listes créées automatiquement. Vides tant que le classement n'est pas livré avec l'app.
    private func makeDecadePlaylists() -> [Playlist] {
        guard !classement.isEmpty else { return [] }
        var groups: [Int: [Int]] = [:]
        for song in alphabetical {
            guard let id = song.tabID else { continue }
            groups[classement[id]?.decade ?? 0, default: []].append(id)
        }
        return groups.keys.sorted { ($0 == 0 ? Int.max : $0) < ($1 == 0 ? Int.max : $1) }.map { decade in
            let name = decade == 0 ? "Date inconnue" : decade < 2000 ? "Années \(decade % 100)" : "Années \(decade)"
            return Playlist(name: name, ids: groups[decade] ?? [])
        }
    }

    private func makeLanguagePlaylists() -> [Playlist] {
        guard !classement.isEmpty else { return [] }
        var groups: [String: [Int]] = [:]
        for song in alphabetical {
            guard let id = song.tabID else { continue }
            // Les paroles chargées priment sur l'estimation faite d'après le titre et l'artiste.
            groups[song.language ?? classement[id]?.language ?? "Langue inconnue", default: []].append(id)
        }
        return ["Français", "Anglais", "Autres langues", "Langue inconnue"].compactMap { name in
            groups[name].map { Playlist(name: name, ids: $0) }
        }
    }

    private func detectLanguage(_ text: String) -> String? {
        let lyrics = text.components(separatedBy: "\n")
            .filter { !Chords.isChordLine($0) && !Chords.isSection($0) }
            .joined(separator: " ")
        guard lyrics.count > 40 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(lyrics)
        switch recognizer.dominantLanguage {
        case .french?: return "Français"
        case .english?: return "Anglais"
        case nil: return nil
        default: return "Autres langues"
        }
    }

    /// Toute la bibliothèque de A à Z, sans tenir compte des accents.
    private(set) var alphabetical: [Song] = []

    static let historyName = "Historique"
    static let mostPlayedName = "Les plus joués"

    /// Tous les morceaux déjà ouverts, du plus récent au plus ancien. Ceux ouverts avant que l'app
    /// note les dates (paroles déjà chargées, sans date) suivent, de A à Z.
    private func makeHistory() -> Playlist {
        let dated = songs
            .compactMap { song in playedAt[song.url].flatMap { date in song.tabID.map { ($0, date) } } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        let undated = alphabetical
            .filter { $0.isReady && playedAt[$0.url] == nil && legacy.contains($0.url) }
            .compactMap(\.tabID)
        return Playlist(name: Self.historyName, ids: dated + undated, isHistory: true, keepsOrder: true)
    }

    /// Les morceaux comptés depuis que l'app note les écoutes, du plus joué au moins joué ;
    /// à égalité, le plus récent d'abord.
    private func makeMostPlayed() -> Playlist {
        let ids = songs
            .compactMap { song -> (id: Int, count: Int, date: Date)? in
                guard let id = song.tabID, let count = playCounts[song.url], count > 0 else { return nil }
                return (id, count, playedAt[song.url] ?? .distantPast)
            }
            .sorted { ($0.count, $0.date) > ($1.count, $1.date) }
            .map(\.id)
        return Playlist(name: Self.mostPlayedName, ids: ids, keepsOrder: true)
    }

    func markPlayed(_ song: Song) {
        playedAt[song.url] = .now
        playCounts[song.url, default: 0] += 1
        history = makeHistory()
        mostPlayed = makeMostPlayed()
        saveHistory()
    }

    private func saveHistory() {
        guard !isRetired else { return }
        if let data = try? JSONEncoder().encode(HistoryFile(playedAt: playedAt, counts: playCounts, legacy: Array(legacy))) {
            try? data.write(to: historyFile, options: .atomic)
        }
    }

    func songs(in playlist: Playlist?) -> [Song] {
        guard let playlist else { return alphabetical }
        // L'historique suit l'ordre de la liste reçue : le lecteur garde celle de son ouverture.
        if playlist.keepsOrder { return playlist.ids.compactMap { byID[$0] } }
        // Clé = la liste entière : « À travailler » change d'ids sans que la bibliothèque change.
        if let cached = scopes[playlist] { return cached }
        let ids = Set(playlist.ids)
        let result = alphabetical.filter { $0.tabID.map(ids.contains) ?? false }
        scopes[playlist] = result
        return result
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

    /// Le même morceau peut avoir deux formes de lien : on compare aussi le numéro UG.
    func song(matching url: String) -> Song? {
        let id = Song(url: url, title: "", artist: "").tabID
        return songs.first { $0.url == url || (id != nil && $0.tabID == id) }
    }

    func store(url: String, title: String, artist: String, text: String) {
        let id = Song(url: url, title: "", artist: "").tabID
        if let index = songs.firstIndex(where: { $0.url == url || (id != nil && $0.tabID == id) }) {
            songs[index].text = text
            songs[index].language = detectLanguage(text)
            if songs[index].artist.isEmpty { songs[index].artist = artist }
        } else {
            songs.append(Song(url: url, title: title, artist: artist, language: detectLanguage(text), text: text))
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
        playedAt[song.url] = nil
        playCounts[song.url] = nil
        save()
    }

    func neighbour(of song: Song, step: Int, in playlist: Playlist?) -> Song? {
        // Un morceau ouvert depuis la recherche peut être hors de la playlist active.
        let scoped = songs(in: playlist)
        let list = scoped.contains { $0.url == song.url } ? scoped : songs
        guard !list.isEmpty, let index = list.firstIndex(where: { $0.url == song.url }) else { return nil }
        return list[(index + step + list.count) % list.count]
    }

    private func save() {
        guard !isRetired else { return }
        refresh()
        if let data = try? JSONEncoder().encode(songs) {
            try? data.write(to: file, options: .atomic)
        }
    }
}

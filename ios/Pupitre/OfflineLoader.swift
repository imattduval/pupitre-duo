import Foundation
import Observation

/// Charge, à la demande de l'utilisateur, les paroles d'une playlist pour jouer sans réseau.
/// Un morceau à la fois et 4 secondes entre deux : on ne martèle pas UG.
@MainActor
@Observable
final class OfflineLoader {
    enum State: Equatable { case idle, running, paused, finished, blocked }

    private(set) var state: State = .idle
    private(set) var playlistName: String?
    private(set) var total = 0
    private(set) var done = 0
    private(set) var failed = 0
    private(set) var currentURL: String?
    private(set) var blockedURL: URL?

    @ObservationIgnored private var pending: [Song] = []
    @ObservationIgnored private var skipped: [Song] = []
    @ObservationIgnored private var lastAsked: ContinuousClock.Instant?
    @ObservationIgnored private var library: Library?
    @ObservationIgnored private var loader: UGLoader?
    @ObservationIgnored private var task: Task<Void, Never>?

    init() {}

    func start(_ songs: [Song], playlistName: String, library: Library, loader: UGLoader) {
        guard state != .running, state != .paused else { return }
        pending = songs.filter { !$0.isReady }
        self.playlistName = playlistName
        self.library = library
        self.loader = loader
        skipped = []
        total = pending.count
        done = 0
        failed = 0
        blockedURL = nil
        launch()
    }

    /// Relance seulement les morceaux ignorés au dernier passage.
    func retry() {
        guard state == .finished, let library, let loader else { return }
        start(skipped, playlistName: playlistName ?? "", library: library, loader: loader)
    }

    func pause() {
        guard state == .running else { return }
        halt(.paused)
    }

    /// Reprend aussi après la vérification faite dans le navigateur, au morceau qui bloquait.
    func resume() {
        guard state == .paused || state == .blocked else { return }
        blockedURL = nil
        launch()
    }

    func stop() {
        halt(.idle)
        pending = []
        playlistName = nil
        blockedURL = nil
    }

    private func launch() {
        state = .running
        task = Task { await run() }
    }

    /// Le morceau en cours est abandonné et sera repris en premier.
    private func halt(_ next: State) {
        task?.cancel()
        task = nil
        currentURL = nil
        state = next
    }

    private func run() async {
        guard let library, let loader else { return }
        var failuresInARow = 0
        while let song = pending.first {
            if library.song(matching: song.url)?.isReady == false {
                // L'écart compte depuis la dernière demande, même annulée : une pause puis Reprendre ne l'abrège pas.
                if let lastAsked {
                    try? await Task.sleep(until: lastAsked + .seconds(4), clock: .continuous)
                    guard !Task.isCancelled else { return }
                }
                lastAsked = .now
                currentURL = song.url
                do {
                    let loaded = try await loader.song(at: song.url)
                    // Supprimé pendant le chargement : il ne doit pas revenir.
                    if library.song(matching: song.url) != nil {
                        library.store(url: song.url,
                                      title: song.title.isEmpty ? loaded.title : song.title,
                                      artist: song.artist.isEmpty ? loaded.artist : song.artist,
                                      text: loaded.text)
                    }
                    failuresInARow = 0
                } catch {
                    guard !Task.isCancelled else { return }
                    if (error as? LoadError) == .needsBrowser {
                        blockedURL = URL(string: song.url)
                        halt(.blocked)
                        return
                    }
                    failed += 1
                    skipped.append(song)
                    pending.removeFirst()
                    currentURL = nil
                    // Les tabs interactives échouent toujours ; deux autres échecs de suite : UG refuse peut-être sans le dire.
                    if song.type?.contains("Chords") ?? true { failuresInARow += 1 }
                    if failuresInARow >= 2, !pending.isEmpty {
                        blockedURL = URL(string: song.url)
                        halt(.blocked)
                        return
                    }
                    continue
                }
                guard !Task.isCancelled else { return }
            }
            // Prêt : chargé à l'instant, ouvert entre-temps ou juste avant une pause. Absent : supprimé entre-temps.
            if library.song(matching: song.url) == nil { total -= 1 } else { done += 1 }
            pending.removeFirst()
            currentURL = nil
        }
        task = nil
        state = .finished
    }
}

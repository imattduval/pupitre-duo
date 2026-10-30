import SwiftUI

struct LibraryView: View {
    @Environment(Library.self) private var library
    @State private var loader = UGLoader()
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var searched = false
    @State private var isSearching = false
    @State private var playing: Song?
    @State private var browsing: BrowserTarget?
    @State private var loadingURL: String?
    @State private var message: String?

    @State private var playlist: Playlist?

    private var scope: [Song] { library.songs(in: playlist) }

    private var filtered: [Song] {
        guard !query.isEmpty else { return scope }
        return scope.filter { ($0.title + " " + $0.artist).localizedCaseInsensitiveContains(query) }
    }

    private var countLabel: String {
        let ready = scope.filter(\.isReady).count
        return ready == scope.count ? "\(scope.count) morceaux" : "\(ready) sur \(scope.count) prêts"
    }

    var body: some View {
        NavigationStack {
            List {
                if !filtered.isEmpty {
                    Section(countLabel) {
                        ForEach(filtered) { row($0) }
                            .onDelete { offsets in
                                offsets.map { filtered[$0] }.forEach(library.remove)
                            }
                    }
                }
                if isSearching {
                    Section("Ultimate Guitar") {
                        HStack { ProgressView(); Text("Recherche…").foregroundStyle(.secondary) }
                    }
                } else if searched {
                    Section("Ultimate Guitar") {
                        if results.isEmpty {
                            Text("Aucun morceau en accords trouvé.").foregroundStyle(.secondary)
                        }
                        ForEach(results) { resultRow($0) }
                    }
                }
            }
            .overlay {
                if library.songs.isEmpty && !searched && !isSearching {
                    ContentUnavailableView("Cherche un morceau",
                                           systemImage: "music.note.list",
                                           description: Text("Touche la loupe, écris un titre ou un artiste, puis valide."))
                }
            }
            .searchable(text: $query, prompt: "Titre ou artiste")
            .onSubmit(of: .search) { Task { await search() } }
            .onChange(of: query) { _, text in
                if text.isEmpty { results = []; searched = false }
            }
            .navigationTitle(playlist?.name ?? "Tous mes tabs")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Playlists", systemImage: "music.note.list") {
                        Button("Tous mes tabs") { playlist = nil }
                        group("Par décennie", library.decadePlaylists)
                        group("Par langue", library.languagePlaylists)
                        group("Mes playlists", library.playlists)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Ultimate Guitar", systemImage: "globe") {
                        browsing = BrowserTarget(url: Self.home)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let message {
                    Text(message)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.black, in: .rect(cornerRadius: 12))
                        .padding(.bottom, 24)
                }
            }
        }
        .environment(loader)
        #if DEBUG
        // Test sur appareil : ouvre un morceau déjà chargé (devicectl ne peut pas toucher l'écran).
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-ouvrir"), index + 1 < arguments.count {
                playing = library.ready.first { $0.title.localizedCaseInsensitiveContains(arguments[index + 1]) }
            }
        }
        #endif
        .fullScreenCover(item: $playing) { song in
            PlayerView(song: song, playlist: playlist)
        }
        .sheet(item: $browsing) { target in
            BrowserView(start: target.url)
                .environment(loader)
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [Playlist]) -> some View {
        if !items.isEmpty {
            Menu(title) {
                ForEach(items) { item in
                    Button("\(item.name) · \(item.ids.count)") { playlist = item }
                }
            }
        }
    }

    private func row(_ song: Song) -> some View {
        Button {
            if song.isReady {
                playing = song
            } else {
                Task { await open(url: song.url) }
            }
        } label: {
            HStack {
                labels(title: song.title, artist: song.artist)
                Spacer()
                if loadingURL == song.url {
                    ProgressView()
                } else if !song.isReady {
                    Text("À charger").font(.subheadline).foregroundStyle(Palette.chord)
                }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(loadingURL != nil)
    }

    private func resultRow(_ result: SearchResult) -> some View {
        Button {
            Task { await open(url: result.url, fallbackTitle: result.title, fallbackArtist: result.artist) }
        } label: {
            HStack {
                labels(title: result.title + ((result.version ?? 1) > 1 ? " (ver \(result.version!))" : ""),
                       artist: result.artist)
                Spacer()
                if loadingURL == result.url {
                    ProgressView()
                } else if let rating = result.rating, let votes = result.votes {
                    Text("★ \(rating, format: .number.precision(.fractionLength(1))) · \(votes)")
                        .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(loadingURL != nil)
    }

    private func labels(title: String, artist: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            if !artist.isEmpty {
                Text(artist).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        isSearching = true
        defer { isSearching = false; searched = true }
        do {
            results = try await loader.search(text)
                .sorted { ($0.votes ?? 0) > ($1.votes ?? 0) }
        } catch LoadError.needsBrowser {
            results = []
            show("Ultimate Guitar demande une vérification.")
            browsing = BrowserTarget(url: Self.home)
        } catch {
            results = []
            show("Recherche indisponible sur ce réseau. Essaie en Wi-Fi.")
        }
    }

    /// Charge le morceau choisi en arrière-plan, l'enregistre sur le téléphone et l'ouvre.
    private func open(url: String, fallbackTitle: String? = nil, fallbackArtist: String? = nil) async {
        if let saved = library.songs.first(where: { $0.url == url && $0.isReady }) {
            playing = saved
            return
        }
        loadingURL = url
        defer { loadingURL = nil }
        do {
            let loaded = try await loader.song(at: url)
            library.store(url: url,
                          title: fallbackTitle ?? loaded.title,
                          artist: fallbackArtist ?? loaded.artist,
                          text: loaded.text)
            playing = library.songs.first { $0.url == url }
        } catch LoadError.needsBrowser {
            browsing = URL(string: url).map { BrowserTarget(url: $0) }
        } catch {
            // Les tabs interactives (Official, Tabs) ne sont souvent pas du texte : on montre la page.
            if let song = library.songs.first(where: { $0.url == url }),
               let type = song.type, !type.contains("Chords") {
                browsing = URL(string: url).map { BrowserTarget(url: $0) }
            } else {
                show("Chargement impossible. Essaie en Wi-Fi.")
            }
        }
    }

    private func show(_ text: String) {
        message = text
        Task {
            try? await Task.sleep(for: .seconds(3))
            if message == text { message = nil }
        }
    }

    private static let home = URL(string: "https://www.ultimate-guitar.com/")!
}

struct BrowserTarget: Identifiable {
    let url: URL
    var id: URL { url }
}

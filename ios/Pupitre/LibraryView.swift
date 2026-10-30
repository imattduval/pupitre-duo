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

    private var filtered: [Song] {
        guard !query.isEmpty else { return library.songs }
        return library.songs.filter { ($0.title + " " + $0.artist).localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !filtered.isEmpty {
                    Section(library.readyCount == library.songs.count
                            ? "\(library.songs.count) morceaux"
                            : "\(library.readyCount) sur \(library.songs.count) prêts") {
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
            .navigationTitle("Pupitre")
            .toolbar {
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
        .fullScreenCover(item: $playing) { song in
            PlayerView(song: song)
        }
        .sheet(item: $browsing) { target in
            BrowserView(start: target.url)
                .environment(loader)
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
            show("Chargement impossible. Vérifie le réseau.")
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

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
    @State private var activeLetter: String?
    @State private var isChoosingPlaylist = false
    @State private var isSearchPresented = false
    @FocusState private var isSearchFocused: Bool
    @AppStorage("playlist.ouverte") private var savedPlaylist = ""

    private var scope: [Song] { library.songs(in: playlist) }

    private var filtered: [Song] {
        guard !query.isEmpty else { return scope }
        // Une recherche couvre toute la bibliothèque, pas seulement la playlist ouverte.
        return library.songs.filter { ($0.title + " " + $0.artist).localizedStandardContains(query) }
    }

    private var countLabel: String {
        let ready = scope.filter(\.isReady).count
        return ready == scope.count ? "\(scope.count) morceaux" : "\(ready) sur \(scope.count) prêts"
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
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
            .contentMargins(.trailing, query.isEmpty ? 40 : 0, for: .scrollContent)
            .overlay(alignment: .trailing) {
                if query.isEmpty, !filtered.isEmpty {
                    alphabetBar(proxy)
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
            .searchable(text: $query, isPresented: $isSearchPresented, prompt: "Titre ou artiste")
            .searchFocused($isSearchFocused)
            .onSubmit(of: .search) { Task { await search() } }
            .task(id: query) {
                // Cherche seul dès que la frappe s'arrête.
                guard query.count >= 3 else {
                    results = []
                    searched = false
                    return
                }
                try? await Task.sleep(for: .seconds(0.7))
                if !Task.isCancelled { await search() }
            }
            .navigationTitle(playlist?.name ?? "Tous mes tabs")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Playlists", systemImage: "music.note.list") { isChoosingPlaylist = true }
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
        .sheet(isPresented: $isChoosingPlaylist) { playlistChooser }
        .task {
            // Rouvre la dernière playlist utilisée.
            let all = library.playlists + library.decadePlaylists + library.languagePlaylists
            playlist = all.first { $0.name == savedPlaylist }
        }
        #if DEBUG
        // Test sur appareil : ouvre un morceau déjà chargé (devicectl ne peut pas toucher l'écran).
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-ouvrir"), index + 1 < arguments.count {
                playing = library.ready.first { $0.title.localizedCaseInsensitiveContains(arguments[index + 1]) }
            }
            if arguments.contains("-boutonRecherche") {
                try? await Task.sleep(for: .seconds(2))
                openSearch()
            }
            if let index = arguments.firstIndex(of: "-chercher"), index + 1 < arguments.count {
                isSearchPresented = true
                query = arguments[index + 1]
            }
        }
        #endif
        .fullScreenCover(item: $playing) { song in
            PlayerView(song: song, playlist: playlist, onSearch: openSearch)
                .environment(loader)
        }
        .sheet(item: $browsing) { target in
            BrowserView(start: target.url)
                .environment(loader)
        }
    }

    private static let letters = (65...90).map { String(UnicodeScalar($0)) } + ["#"]

    /// Grosses lettres à droite : toucher ou glisser le doigt va au premier titre de la lettre.
    private func alphabetBar(_ proxy: ScrollViewProxy) -> some View {
        let present = Set(scope.map(\.initial))
        return GeometryReader { geometry in
            VStack(spacing: 0) {
                ForEach(Self.letters, id: \.self) { letter in
                    Text(letter)
                        .font(.system(size: min(20, geometry.size.height / 27 * 0.8), weight: .bold))
                        .foregroundStyle(present.contains(letter) ? Palette.chord : Color.secondary.opacity(0.35))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let index = Int(value.location.y / geometry.size.height * CGFloat(Self.letters.count))
                let letter = Self.letters[min(Self.letters.count - 1, max(0, index))]
                guard letter != activeLetter else { return }
                activeLetter = letter
                if let song = scope.first(where: { $0.initial == letter }) {
                    proxy.scrollTo(song.id, anchor: .top)
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }.onEnded { _ in activeLetter = nil })
        }
        .frame(width: 44)
        .padding(.bottom, 64)
        .accessibilityHidden(true)
    }

    private func openSearch() {
        playing = nil
        query = ""
        isSearchPresented = true
        Task {
            // Le clavier ne s'ouvre qu'une fois le lecteur refermé.
            try? await Task.sleep(for: .seconds(0.6))
            isSearchFocused = true
        }
    }

    private func select(_ item: Playlist?) {
        playlist = item
        savedPlaylist = item?.name ?? ""
        isChoosingPlaylist = false
    }

    private var playlistChooser: some View {
        NavigationStack {
            List {
                Button {
                    select(nil)
                } label: {
                    chooserLabel("Tous mes tabs", count: library.songs.count, selected: playlist == nil)
                }
                chooserSection("Mes playlists", library.playlists)
                chooserSection("Par décennie", library.decadePlaylists)
                chooserSection("Par langue", library.languagePlaylists)
            }
            .buttonStyle(.plain)
            .navigationTitle("Playlists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { isChoosingPlaylist = false }
                }
            }
        }
    }

    @ViewBuilder
    private func chooserSection(_ title: String, _ items: [Playlist]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { item in
                    Button {
                        select(item)
                    } label: {
                        chooserLabel(item.name, count: item.ids.count, selected: playlist?.name == item.name)
                    }
                }
            }
        }
    }

    private func chooserLabel(_ name: String, count: Int, selected: Bool) -> some View {
        HStack {
            Text(name).font(.headline)
            Spacer()
            Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
            if selected {
                Image(systemName: "checkmark").foregroundStyle(Palette.chord)
            }
        }
        .frame(minHeight: 52)
        .contentShape(.rect)
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
            let found = try await loader.search(text)
            guard query.trimmingCharacters(in: .whitespaces) == text else { return }
            results = found.sorted { ($0.votes ?? 0) > ($1.votes ?? 0) }
        } catch LoadError.needsBrowser {
            results = []
            show("Ultimate Guitar demande une vérification.")
            browsing = BrowserTarget(url: Self.home)
        } catch {
            results = []
            show("Ultimate Guitar ne répond pas sur ce réseau. Essaie en Wi-Fi.")
        }
    }

    /// Charge le morceau choisi en arrière-plan, l'enregistre sur le téléphone et l'ouvre.
    private func open(url: String, fallbackTitle: String? = nil, fallbackArtist: String? = nil) async {
        if let saved = library.song(matching: url), saved.isReady {
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
            playing = library.song(matching: url)
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

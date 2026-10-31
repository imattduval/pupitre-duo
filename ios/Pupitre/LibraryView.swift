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
    @State private var searchOrigin: Song?
    @State private var resumesPlayer = false
    @State private var isClosedScreen = false
    @State private var areFavoritesOpen = false
    @State private var isChoosingPlaylist = false
    @State private var isSearchPresented = false
    @FocusState private var isSearchFocused: Bool
    @AppStorage("playlist.ouverte") private var savedPlaylist = ""
    @AppStorage("playlists.favorites") private var savedFavorites = ""

    private var scope: [Song] { library.songs(in: playlist) }

    private var filtered: [Song] {
        guard !query.isEmpty else { return scope }
        // Une recherche couvre toute la bibliothèque, pas seulement la playlist ouverte.
        return library.songs.filter { ($0.title + " " + $0.artist).localizedStandardContains(query) }
    }

    private var showsAlphabet: Bool { query.isEmpty && !filtered.isEmpty }

    /// Tous mes tabs et les listes automatiques sont triés par titre. Une playlist du compte
    /// garde son ordre, celui du set, donc pas de séparation par lettre.
    private var isAlphabetical: Bool {
        guard let playlist else { return true }
        return !library.playlists.contains(playlist)
    }

    private var letterGroups: [(letter: String, songs: [Song])] {
        let groups = Dictionary(grouping: scope, by: \.initial)
        return Self.letters.compactMap { letter in groups[letter].map { (letter, $0) } }
    }

    private var countLabel: String {
        let ready = scope.filter(\.isReady).count
        return ready == scope.count ? "\(scope.count) morceaux" : "\(ready) sur \(scope.count) prêts"
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                if query.isEmpty, !library.songs.isEmpty {
                    favoritesSection
                }
                if !filtered.isEmpty {
                    if query.isEmpty, isAlphabetical {
                        Text(countLabel)
                            .font(.subheadline).foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                        ForEach(letterGroups, id: \.letter) { group in
                            // Une vraie ligne, pas un titre de section : un saut la place sous la barre du haut.
                            Section {
                                Text(group.letter)
                                    .font(.title2.bold())
                                    .foregroundStyle(Palette.chord)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .id("lettre-" + group.letter)
                            }
                            .listSectionSpacing(0)
                            Section {
                                ForEach(group.songs) { row($0) }
                                    .onDelete { offsets in
                                        offsets.map { group.songs[$0] }.forEach(library.remove)
                                    }
                            }
                            .listSectionSpacing(14)
                        }
                    } else {
                        Section(countLabel) {
                            ForEach(filtered) { row($0) }
                                .onDelete { offsets in
                                    offsets.map { filtered[$0] }.forEach(library.remove)
                                }
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
            // Largeur fixe : la liste ne bouge pas quand les lettres s'effacent.
            .padding(.trailing, 46)
            .overlay(alignment: .trailing) {
                alphabetBar(proxy)
                    .opacity(showsAlphabet ? 1 : 0)
                    .allowsHitTesting(showsAlphabet)
                    // Le clavier passe par-dessus : les lettres gardent leur taille et leur place.
                    .ignoresSafeArea(.keyboard)
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
            // Garde la barre du haut pendant la recherche, sinon tout remonte d'un coup.
            .searchPresentationToolbarBehavior(.avoidHidingContent)
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
            .navigationTitle(playlist?.name ?? "Toutes les tabs")
            // Titre fixe : la colonne de lettres ne bouge pas pendant le défilement.
            .navigationBarTitleDisplayMode(.inline)
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
                if searchOrigin != nil, query.isEmpty {
                    Button(action: returnToSong) {
                        Label("Annuler – revenir à la tab", systemImage: "arrow.uturn.backward")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .frame(minHeight: 52)
                            .background(Palette.chord, in: .capsule)
                            .foregroundStyle(.black)
                            .contentShape(.capsule)
                    }
                    .padding(.bottom, 12)
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(for: .seconds(5))
                        if !Task.isCancelled {
                            withAnimation(.easeOut(duration: 0.8)) { searchOrigin = nil }
                        }
                    }
                }
            }
            // Fondu aussi quand la frappe commence.
            .animation(.easeOut(duration: 0.3), value: query.isEmpty)
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
        // L'écran fermé fait 466 points sur son petit côté, l'écran ouvert plus de 620.
        // Mesuré sans le clavier : l'ouvrir ne doit pas faire croire à l'écran fermé.
        .background {
            Color.clear
                .onGeometryChange(for: Bool.self) { min($0.size.width, $0.size.height) < 560 } action: { closed in
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-ferme") { isClosedScreen = true; return }
                    #endif
                    isClosedScreen = closed
                }
                .ignoresSafeArea(.keyboard)
        }
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
            if let index = arguments.firstIndex(of: "-favoris"), index + 1 < arguments.count {
                savedFavorites = arguments[index + 1].replacingOccurrences(of: ",", with: "\n")
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
        .fullScreenCover(item: $playing, onDismiss: { resumesPlayer = false }) { song in
            PlayerView(song: song, playlist: playlist, resume: resumesPlayer, onSearch: { openSearch(from: $0) })
                .environment(loader)
        }
        .sheet(item: $browsing) { target in
            BrowserView(start: target.url)
                .environment(loader)
        }
    }

    private var favoriteNames: [String] {
        savedFavorites.split(separator: "\n").map(String.init)
    }

    private var favorites: [Playlist] {
        let all = library.playlists + library.decadePlaylists + library.languagePlaylists
        return favoriteNames.compactMap { name in all.first { $0.name == name } }
    }

    private func toggleFavorite(_ name: String) {
        var names = favoriteNames
        if let index = names.firstIndex(of: name) { names.remove(at: index) } else { names.append(name) }
        savedFavorites = names.joined(separator: "\n")
    }

    /// Grosses tuiles en haut de l'accueil pour passer d'une playlist favorite à l'autre.
    private var favoritesSection: some View {
        Section {
            if favorites.isEmpty {
                Button {
                    isChoosingPlaylist = true
                } label: {
                    Label("Choisir mes playlists favorites", systemImage: "star")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.chord)
            } else if isClosedScreen && !areFavoritesOpen {
                // Écran fermé : une seule tuile, les favoris se déplient quand on la touche.
                Button {
                    areFavoritesOpen = true
                } label: {
                    HStack {
                        Text(playlist?.name ?? "Toutes les tabs").font(.title3.bold()).lineLimit(1)
                        Spacer()
                        Text("\(scope.count)").monospacedDigit().opacity(0.7)
                        Image(systemName: "chevron.down").font(.headline)
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(Palette.chord, in: .rect(cornerRadius: 14))
                    .foregroundStyle(.black)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], spacing: 8) {
                    favoriteTile("Toutes les tabs", count: library.songs.count, isSelected: playlist == nil) { select(nil) }
                    ForEach(favorites) { item in
                        favoriteTile(item.name, count: item.ids.count, isSelected: playlist?.name == item.name) { select(item) }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }

    private func favoriteTile(_ name: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.title3.bold()).lineLimit(2).minimumScaleFactor(0.7)
                Text("\(count)").font(.subheadline).monospacedDigit().opacity(0.7)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(isSelected ? Palette.chord : Palette.panel, in: .rect(cornerRadius: 14))
            .foregroundStyle(isSelected ? Color.black : Color.white)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private static let letters = (65...90).map { String(UnicodeScalar($0)) } + ["#"]

    /// Grosses lettres à droite : toucher ou glisser le doigt va au premier titre de la lettre.
    private func alphabetBar(_ proxy: ScrollViewProxy) -> some View {
        let present = Set(scope.map(\.initial))
        return GeometryReader { geometry in
            VStack(spacing: 0) {
                ForEach(Self.letters, id: \.self) { letter in
                    Text(letter)
                        .font(.system(size: min(26, geometry.size.height / 27 * 0.95), weight: .heavy))
                        .minimumScaleFactor(0.5)
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
                    if isAlphabetical {
                        proxy.scrollTo("lettre-" + letter, anchor: .top)
                        // Après un grand saut, la position n'est juste qu'une fois les lignes mesurées.
                        Task {
                            try? await Task.sleep(for: .milliseconds(80))
                            proxy.scrollTo("lettre-" + letter, anchor: .top)
                        }
                    } else {
                        proxy.scrollTo(song.id, anchor: .top)
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }.onEnded { _ in activeLetter = nil })
        }
        .frame(width: 46)
        .padding(.bottom, 56)
        .accessibilityHidden(true)
    }

    private func openSearch(from song: Song? = nil) {
        playing = nil
        searchOrigin = song
        query = ""
        isSearchPresented = true
        Task {
            // Le clavier ne s'ouvre qu'une fois le lecteur refermé.
            try? await Task.sleep(for: .seconds(0.6))
            isSearchFocused = true
        }
    }

    /// Annule un clic par erreur sur la recherche : le morceau rouvre au même endroit.
    private func returnToSong() {
        guard let song = searchOrigin.flatMap({ library.song(matching: $0.url) }) else { return }
        searchOrigin = nil
        query = ""
        isSearchFocused = false
        isSearchPresented = false
        dismissKeyboard()
        resumesPlayer = true
        playing = song
    }

    private func select(_ item: Playlist?) {
        playlist = item
        savedPlaylist = item?.name ?? ""
        isChoosingPlaylist = false
        areFavoritesOpen = false
    }

    private var playlistChooser: some View {
        NavigationStack {
            List {
                Button {
                    select(nil)
                } label: {
                    chooserLabel("Toutes les tabs", count: library.songs.count, selected: playlist == nil)
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
                    HStack(spacing: 0) {
                        Button {
                            select(item)
                        } label: {
                            chooserLabel(item.name, count: item.ids.count, selected: playlist?.name == item.name)
                        }
                        Button {
                            toggleFavorite(item.name)
                        } label: {
                            Image(systemName: favoriteNames.contains(item.name) ? "star.fill" : "star")
                                .font(.title2)
                                .foregroundStyle(Palette.chord)
                                .frame(width: 56, height: 52)
                                .contentShape(.rect)
                        }
                        .accessibilityLabel(favoriteNames.contains(item.name) ? "Retirer des favoris" : "Mettre en favori")
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
        isSearchFocused = false
        dismissKeyboard()
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

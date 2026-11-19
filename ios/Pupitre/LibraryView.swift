import SwiftUI

struct LibraryView: View {
    @Environment(Library.self) private var library
    @Environment(WorkList.self) private var workList
    @Environment(Concerts.self) private var concerts
    @Environment(OfflineLoader.self) private var offline
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
    @State private var showsMostPlayed = false
    @State private var isManagingConcerts = false
    @State private var pendingSong: Song?
    @State private var hasShownBlockedPage = false
    /// Recalculées seulement quand les concerts ou la bibliothèque changent : relier liens et morceaux coûte cher.
    @State private var concertPlaylists: [Playlist] = []
    @FocusState private var isSearchFocused: Bool
    @AppStorage("playlist.ouverte") private var savedPlaylist = ""
    @AppStorage("playlists.favorites") private var savedFavorites = ""

    private var isHistory: Bool { playlist?.isHistory == true }
    /// L'historique et « À travailler » se relisent à chaque fois : ils changent pendant qu'on joue.
    private var current: Playlist? {
        if isHistory { return showsMostPlayed ? library.mostPlayed : library.history }
        if playlist?.name == WorkList.name { return workList.playlist(in: library) }
        return playlist
    }
    private var scope: [Song] { library.songs(in: current) }

    private var filtered: [Song] {
        guard !query.isEmpty else { return scope }
        // Une recherche couvre toute la bibliothèque, pas seulement la playlist ouverte.
        return library.songs.filter { ($0.title + " " + $0.artist).localizedStandardContains(query) }
    }

    /// Les listes sont triées par titre, sauf celles qui ont leur ordre : historique, plus joués, concerts.
    private var isAlphabetical: Bool { !(current?.keepsOrder ?? false) }

    private var showsAlphabet: Bool { query.isEmpty && !filtered.isEmpty && isAlphabetical }

    private var allPlaylists: [Playlist] {
        [library.history, workList.playlist(in: library)] + concertPlaylists
            + library.playlists + library.decadePlaylists + library.languagePlaylists
    }

    /// Jamais toute la bibliothèque d'un coup : seulement les listes faites à la main.
    private var canLoadOffline: Bool {
        guard let name = current?.name else { return false }
        return name == WorkList.name || name.hasPrefix(Concerts.prefix) || library.playlists.contains { $0.name == name }
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
                if query.isEmpty, isHistory {
                    Picker("Historique", selection: $showsMostPlayed) {
                        Text("Récents").tag(false)
                        Text("Les plus joués").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.extraLarge)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                if query.isEmpty {
                    offlineSection
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
                                    .onDelete { offsets in deleteRows(offsets.map { group.songs[$0] }) }
                            }
                            .listSectionSpacing(14)
                        }
                    } else {
                        Section(countLabel) {
                            ForEach(filtered) { row($0) }
                                .onDelete { offsets in deleteRows(offsets.map { filtered[$0] }) }
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
            // Nouvelle playlist : liste reconstruite d'un coup, plus rapide que comparer 995 lignes une à une.
            .id(current?.name ?? "")
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
                if isHistory, showsMostPlayed, scope.isEmpty, query.isEmpty {
                    ContentUnavailableView("Rien de compté pour l'instant",
                                           systemImage: "chart.bar",
                                           description: Text("Les écoutes sont comptées depuis cette version : un morceau compte quand il reste ouvert plus de 10 secondes."))
                } else if isHistory, scope.isEmpty, query.isEmpty {
                    ContentUnavailableView("Aucun morceau joué",
                                           systemImage: "clock",
                                           description: Text("Les morceaux ouverts s'ajoutent ici, du plus récent au plus ancien."))
                } else if current?.name == WorkList.name, scope.isEmpty, query.isEmpty {
                    ContentUnavailableView("Rien à travailler",
                                           systemImage: WorkList.icon,
                                           description: Text("Dans le lecteur, touche le drapeau d'un morceau pour le retrouver ici."))
                } else if library.songs.isEmpty && !searched && !isSearching {
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
                    isSearching = false
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
                            .background(Palette.button, in: .capsule)
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
        // Le morceau d'un concert s'ouvre une fois les feuilles refermées : deux présentations à la fois échouent.
        .sheet(isPresented: $isChoosingPlaylist, onDismiss: {
            if let song = pendingSong { pendingSong = nil; play(song) } else { openBlockedPage() }
        }) { stores(playlistChooser) }
        .task {
            // Rouvre la dernière playlist utilisée.
            refreshConcerts()
            playlist = allPlaylists.first { $0.name == savedPlaylist }
        }
        .onChange(of: concerts.all) { old, _ in refreshConcerts(previous: old) }
        .onChange(of: library.songs.count) { refreshConcerts() }
        .task(id: offline.state) {
            if offline.state != .blocked { hasShownBlockedPage = false }
            switch offline.state {
            case .blocked:
                show("Ultimate Guitar ne répond plus ou demande une vérification.")
                openBlockedPage()
            case .finished where offline.failed == 0:
                // Des morceaux non chargés : le bandeau reste, avec Réessayer.
                try? await Task.sleep(for: .seconds(5))
                if !Task.isCancelled { offline.stop() }
            default:
                break
            }
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
        // Un morceau ouvert depuis la recherche : au retour, la barre est vide et refermée.
        .onChange(of: playing?.id) { _, id in
            guard id != nil, !query.isEmpty || isSearchPresented else { return }
            query = ""
            results = []
            searched = false
            isSearchPresented = false
        }
        .fullScreenCover(item: $playing, onDismiss: { resumesPlayer = false; openBlockedPage() }) { song in
            stores(PlayerView(song: song, playlist: current, resume: resumesPlayer, onSearch: { openSearch(from: $0) }))
        }
        .sheet(item: $browsing) { target in
            stores(BrowserView(start: target.url))
        }
    }

    /// Une fois par arrêt, dès que rien n'est ouvert par-dessus : aussi à la fermeture du lecteur ou des playlists.
    private func openBlockedPage() {
        guard offline.state == .blocked, !hasShownBlockedPage, playing == nil, !isChoosingPlaylist, browsing == nil,
              let url = offline.blockedURL else { return }
        hasShownBlockedPage = true
        browsing = BrowserTarget(url: url)
    }

    /// Le lecteur et les feuilles sont présentés hors de la pile : on leur repasse ce qu'elle partage.
    private func stores(_ view: some View) -> some View {
        view.environment(loader).environment(workList).environment(concerts).environment(offline)
    }

    /// Concert renommé, supprimé ou réordonné : la playlist ouverte et les favoris suivent.
    private func refreshConcerts(previous: [Concert]? = nil) {
        concertPlaylists = concerts.all.map { concerts.playlist($0, in: library) }
        for concert in previous ?? concerts.all {
            let oldName = Concerts.prefix + concert.name
            let newName = concerts.all.first { $0.id == concert.id }.map { Concerts.prefix + $0.name }
            if newName != oldName, favoriteNames.contains(oldName) {
                savedFavorites = favoriteNames.compactMap { $0 == oldName ? newName : $0 }.joined(separator: "\n")
            }
            if playlist?.name == oldName {
                playlist = concertPlaylists.first { $0.name == newName }
                savedPlaylist = playlist?.name ?? ""
            }
        }
    }

    /// Dans un concert ou « À travailler », balayer retire le morceau de la liste, pas de la bibliothèque.
    private func deleteRows(_ removed: [Song]) {
        let name = query.isEmpty ? current?.name : nil
        if let name, let concert = concerts.concert(forPlaylistName: name) {
            let urls = Set(removed.map(\.url))
            // Les positions comptent dans concert.urls, qui peut garder des liens sans morceau.
            let offsets = concert.urls.indices.filter { index in
                library.song(matching: concert.urls[index]).map { urls.contains($0.url) } ?? false
            }
            concerts.remove(at: IndexSet(offsets), from: concert.id)
        } else if name == WorkList.name {
            removed.forEach { workList.remove($0.url) }
        } else {
            removed.forEach(library.remove)
        }
    }

    private func startConcert(_ concert: Concert) {
        let item = concerts.playlist(concert, in: library)
        pendingSong = library.songs(in: item).first
        isManagingConcerts = false
        select(item)
    }

    private func play(_ song: Song) {
        if song.isReady {
            playing = song
        } else {
            Task { await open(url: song.url) }
        }
    }

    private var favoriteNames: [String] {
        savedFavorites.split(separator: "\n").map(String.init)
    }

    private var favorites: [Playlist] {
        favoriteNames.compactMap { name in allPlaylists.first { $0.name == name } }
    }

    private func toggleFavorite(_ name: String) {
        var names = favoriteNames
        if let index = names.firstIndex(of: name) { names.remove(at: index) } else { names.append(name) }
        savedFavorites = names.joined(separator: "\n")
    }

    /// Grosses tuiles en haut de l'accueil pour passer d'une playlist favorite à l'autre.
    private var favoritesSection: some View {
        // « À travailler » a toujours sa tuile : en favori aussi, elle ne doit pas apparaître deux fois.
        let work = workList.playlist(in: library)
        let isWorkSelected = playlist?.name == WorkList.name
        let others = favorites.filter { $0.name != WorkList.name }
        return Section {
            if isClosedScreen && !areFavoritesOpen {
                // Écran fermé : une seule tuile, les favoris se déplient quand on la touche.
                HStack(spacing: 8) {
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
                        .background(Palette.button, in: .rect(cornerRadius: 14))
                        .foregroundStyle(.black)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    Button {
                        select(work)
                    } label: {
                        Image(systemName: isWorkSelected ? WorkList.icon + ".fill" : WorkList.icon)
                            .font(.title2.bold())
                            .frame(width: 60, height: 60)
                            .background(isWorkSelected ? Palette.button : Palette.panel, in: .rect(cornerRadius: 14))
                            .foregroundStyle(isWorkSelected ? Color.black : Palette.chord)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(WorkList.name)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], spacing: 8) {
                    favoriteTile("Toutes les tabs", count: library.songs.count, isSelected: playlist == nil) { select(nil) }
                    favoriteTile(WorkList.name, icon: WorkList.icon, count: work.ids.count, isSelected: isWorkSelected) { select(work) }
                    ForEach(others) { item in
                        favoriteTile(item.name, count: item.ids.count, isSelected: playlist?.name == item.name) { select(item) }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                if others.isEmpty {
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
                }
            }
        }
    }

    private func favoriteTile(_ name: String, icon: String? = nil, count: Int, isSelected: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let icon { Image(systemName: icon).font(.headline) }
                    Text(name).font(.title3.bold()).lineLimit(2).minimumScaleFactor(0.7)
                }
                Text("\(count)").font(.subheadline).monospacedDigit().opacity(0.7)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(isSelected ? Palette.button : Palette.panel, in: .rect(cornerRadius: 14))
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
                if scope.contains(where: { $0.initial == letter }) {
                    proxy.scrollTo("lettre-" + letter, anchor: .top)
                    // Après un grand saut, la position n'est juste qu'une fois les lignes mesurées.
                    Task {
                        try? await Task.sleep(for: .milliseconds(80))
                        proxy.scrollTo("lettre-" + letter, anchor: .top)
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
                Section(WorkList.name) {
                    let work = workList.playlist(in: library)
                    Button {
                        select(work)
                    } label: {
                        chooserLabel(work.name, icon: WorkList.icon, count: work.ids.count, selected: playlist?.name == work.name)
                    }
                }
                chooserSection("Déjà joués", [library.history])
                Section("Concerts") {
                    ForEach(concertPlaylists) { chooserRow($0) }
                    Button {
                        isManagingConcerts = true
                    } label: {
                        Label("Gérer les concerts", systemImage: "list.number")
                            .font(.headline)
                            .foregroundStyle(Palette.chord)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .contentShape(.rect)
                    }
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
            .sheet(isPresented: $isManagingConcerts) {
                ConcertsView(onStart: startConcert)
            }
        }
    }

    @ViewBuilder
    private func chooserSection(_ title: String, _ items: [Playlist]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { chooserRow($0) }
            }
        }
    }

    private func chooserRow(_ item: Playlist) -> some View {
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

    private func chooserLabel(_ name: String, icon: String? = nil, count: Int, selected: Bool) -> some View {
        HStack {
            if let icon { Image(systemName: icon).foregroundStyle(Palette.chord) }
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
            play(song)
        } label: {
            HStack {
                labels(title: song.title, artist: song.artist)
                Spacer()
                if isHistory, showsMostPlayed, query.isEmpty {
                    Text("\(library.playCounts[song.url] ?? 0) ×")
                        .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                } else if isHistory, query.isEmpty {
                    if let date = library.playedAt[song.url] {
                        Text(date, format: .relative(presentation: .named))
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text("date inconnue").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if loadingURL == song.url || offline.currentURL == song.url {
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

    /// En haut d'une playlist : de quoi la charger pour jouer sans réseau, puis où en est le chargement.
    @ViewBuilder
    private var offlineSection: some View {
        if offline.state != .idle {
            Section { offlineBanner }
        } else if canLoadOffline {
            let missing = scope.filter { !$0.isReady }
            if !missing.isEmpty {
                Section {
                    Button {
                        offline.start(missing, playlistName: current?.name ?? "", library: library, loader: loader)
                    } label: {
                        Label("Charger pour jouer hors ligne (\(missing.count) \(missing.count == 1 ? "morceau" : "morceaux"))",
                              systemImage: "arrow.down.circle")
                            .font(.headline)
                            .foregroundStyle(Palette.chord)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var offlineBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let name = offline.playlistName {
                Text(name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            switch offline.state {
            case .finished where offline.failed == 0:
                Label("Prêt pour jouer sans réseau", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Palette.chord)
            case .finished:
                Text("\(offline.done) sur \(offline.total) chargés · \(offline.failed) non \(offline.failed == 1 ? "chargé" : "chargés")")
                    .font(.headline).monospacedDigit()
                HStack(spacing: 8) {
                    bannerButton("Réessayer", "arrow.clockwise", primary: true) { offline.retry() }
                    bannerButton("Fermer", "xmark") { offline.stop() }
                }
            case .blocked:
                Text("Ultimate Guitar ne répond plus ou demande une vérification").font(.headline)
                // Pleine largeur : sur l'écran fermé, trois boutons côte à côte coupaient « Ouvrir la page ».
                bannerButton("Ouvrir la page", "safari", primary: true) {
                    hasShownBlockedPage = true
                    browsing = offline.blockedURL.map { BrowserTarget(url: $0) }
                }
                HStack(spacing: 8) {
                    bannerButton("Reprendre", "play.fill") { offline.resume() }
                    bannerButton("Arrêter", "stop.fill") { offline.stop() }
                }
            default:
                Text("\(offline.done) sur \(offline.total) chargés").font(.headline).monospacedDigit()
                ProgressView(value: Double(offline.done + offline.failed), total: Double(max(offline.total, 1)))
                Text("Un morceau à la fois, en Wi-Fi").font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    if offline.state == .paused {
                        bannerButton("Reprendre", "play.fill", primary: true) { offline.resume() }
                    } else {
                        bannerButton("Pause", "pause.fill", primary: true) { offline.pause() }
                    }
                    bannerButton("Arrêter", "stop.fill") { offline.stop() }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func bannerButton(_ title: String, _ icon: String, primary: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(primary ? Palette.button : Palette.background, in: .rect(cornerRadius: 12))
                .foregroundStyle(primary ? Color.black : Color.white)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
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
        do {
            let found = try await loader.search(text)
            // Une frappe plus récente a relancé la recherche : c'est elle qui affichera ses résultats.
            guard !Task.isCancelled, query.trimmingCharacters(in: .whitespaces) == text else { return }
            results = found.sorted { ($0.votes ?? 0) > ($1.votes ?? 0) }
            isSearching = false
            searched = true
        } catch is CancellationError {
            return
        } catch LoadError.needsBrowser {
            isSearching = false
            searched = true
            results = []
            offline.pause()
            show("Ultimate Guitar demande une vérification.")
            browsing = BrowserTarget(url: Self.home)
        } catch {
            guard !Task.isCancelled else { return }
            isSearching = false
            searched = true
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
            offline.pause()
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

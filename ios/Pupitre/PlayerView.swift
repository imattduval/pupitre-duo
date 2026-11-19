import SwiftUI
import UIKit

@MainActor
func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

struct PlayerView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State var song: Song
    /// Figée à l'ouverture : « Les plus joués » et « À travailler » changent pendant qu'on joue.
    @State var playlist: Playlist?
    /// Vrai pour le seul morceau rouvert après une fausse manœuvre ; un autre morceau repart du début.
    @State var resume = false
    let onSearch: (Song) -> Void
    @Environment(UGLoader.self) private var loader
    @Environment(WorkList.self) private var workList
    @Environment(Favorites.self) private var favorites
    @Environment(PlayTransitions.self) private var transitions
    @Environment(Moods.self) private var moods
    @State private var tappedChord: TappedChord?
    @State private var isLoading = false
    @State private var message: String?
    @State private var isPlaying = false
    @State private var mode = SheetMode.full
    /// Suggestions du morceau dont l'adresse est notée : celles du précédent ne s'affichent jamais sous le suivant.
    @State private var upNext: (url: String, rows: [UpNextRow]) = ("", [])
    @State private var hidesStatusBar = false
    @State private var isClosedScreen = false
    @State private var controlsHidden = false
    @State private var controlsActivity = 0

    var body: some View {
        GeometryReader { proxy in
            // Duo ouvert en paysage : le texte à gauche, les commandes en colonne à droite.
            let isWide = proxy.size.width > proxy.size.height
            let insets = proxy.safeAreaInsets
            // Écran fermé : 466 points sur son petit côté, contre plus de 620 une fois ouvert.
            let isClosed = min(proxy.size.width + insets.leading + insets.trailing,
                               proxy.size.height + insets.top + insets.bottom) < 560
            let isClosedPortrait = isClosed && !isWide
            let layout = isWide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
              VStack(spacing: 0) {
                if isWide {
                    Text("\(song.title) · \(song.artist)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Décalé pour rester hors de l'arrondi de l'écran.
                        .padding(.leading, isClosed ? 14 : 34).padding(.trailing, 8).padding(.top, 14).padding(.bottom, 4)
                } else {
                    header(topInset: insets.top, isClosed: isClosed, trailing: insets.trailing)
                    Divider().padding(.trailing, isClosedPortrait ? insets.trailing : 0)
                }
                SheetView(song: song, mode: mode, speed: shownSpeed, isPlaying: $isPlaying,
                          startOffset: resume ? SheetView.lastOffset : nil,
                          topInset: 0,
                          sideInset: isClosed && isWide ? 8 : 16,
                          upNext: upNext.url == song.url ? upNext.rows : [],
                          onScale: { value in change { $0.scale = value } },
                          onBack: { dismiss() },
                          onTap: textTapped,
                          onChord: { chord in
                              // En plein défilement, toucher le texte garde son rôle : pause ou rappel des commandes.
                              if isPlaying || controlsHidden { textTapped() } else { tappedChord = TappedChord(name: chord) }
                          },
                          onUpNext: openSuggested)
                    .id(song.url)
                    .overlay {
                        if isLoading {
                            ProgressView().controlSize(.large)
                                .padding(24)
                                .background(.black.opacity(0.8), in: .rect(cornerRadius: 16))
                        } else if let message {
                            Text(message)
                                .multilineTextAlignment(.center)
                                .padding(16)
                                .background(.black.opacity(0.9), in: .rect(cornerRadius: 22))
                                .padding(.horizontal, 24)
                        }
                    }
              }
              // Les commandes se replient et le texte gagne leur hauteur.
              if !controlsHidden {
              Divider()
              Group {
                  if isWide {
                      // La bande de l'heure existe seulement si iOS la réserve à droite.
                      let strip = insets.trailing
                      sideControls(width: isClosed ? 122 : max(strip, 0) + (strip > 40 ? 34 : 126), top: isClosed ? 10 : strip > 40 ? 130 : 8, isClosed: isClosed)
                  } else if isClosed {
                      closedControls
                  } else if proxy.size.width >= 600 {
                      oneLineControls
                  } else { controls }
              }
              .padding(.bottom, isWide ? 16 : max(12, insets.bottom * 0.4))
              .background(isWide ? Palette.background : Palette.panel)
              }
            }
            .overlay(alignment: .bottomTrailing) {
                if controlsHidden {
                    Button(action: showControls) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title3.bold())
                            .frame(width: 52, height: 52)
                            .background(Palette.panel, in: .circle)
                            .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                            .contentShape(.circle)
                    }
                    .accessibilityLabel("Afficher les commandes")
                    .foregroundStyle(.primary)
                    .padding(.trailing, 16)
                    .padding(.bottom, 24)
                    .transition(.opacity)
                }
            }
            .ignoresSafeArea(edges: isWide ? [.top, .bottom, .leading, .trailing] : isClosedPortrait ? [.top, .bottom, .trailing] : [.top, .bottom])
        }
        .background(Palette.background)
        .sheet(item: $tappedChord) { chord in
            PianoChordView(chord: chord.name)
                .presentationDetents([.medium, .large])
        }
        // Écran fermé en vertical : l'heure et le réseau laissent la place au morceau. Ouvert, on les garde.
        .onGeometryChange(for: Bool.self) { $0.size.height > $0.size.width && $0.size.width < 560 } action: { hidesStatusBar = $0 }
        .statusBarHidden(hidesStatusBar)
        // Écran fermé en vertical seulement ; en paysage, les commandes restent : élargir le texte le ferait sauter.
        .onGeometryChange(for: Bool.self) { $0.size.height > $0.size.width && $0.size.width < 560 } action: { isClosedScreen = $0 }
        // Pendant le défilement, les commandes s'effacent après 10 secondes sans y toucher.
        .task(id: "\(isPlaying)-\(isClosedScreen)-\(controlsActivity)") {
            guard isPlaying, isClosedScreen else {
                withAnimation(.easeOut(duration: 0.25)) { controlsHidden = false }
                return
            }
            try? await Task.sleep(for: .seconds(10))
            if !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.6)) { controlsHidden = true }
            }
        }
        // Un morceau affiché 10 secondes, y compris par Suivant et Précédent, entre dans l'historique ;
        // moins, c'est un toucher par erreur. Changer de morceau ou fermer annule l'attente.
        .task(id: song.url) {
            try? await Task.sleep(for: .seconds(10))
            if !Task.isCancelled {
                library.markPlayed(song)
                transitions.record(song.url)
            }
        }
        // Jamais dans body : le moteur parcourt toute la bibliothèque, et les ambiances prennent des secondes.
        .task(id: song.url) { await suggestNext() }
        .task {
            // iOS peut rendre le clavier à la recherche pendant la transition vers le lecteur.
            dismissKeyboard()
            try? await Task.sleep(for: .seconds(0.4))
            dismissKeyboard()
        }
    }

    /// Duo ouvert : l'heure occupe le haut à droite, le titre se place dans la même bande, à sa gauche.
    private func header(topInset: CGFloat, isClosed: Bool, trailing: CGFloat) -> some View {
        HStack(spacing: 4) {
            iconButton("chevron.left", label: "Retour à la liste") { dismiss() }
            VStack(alignment: .leading, spacing: 0) {
                Text(song.title).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
                Text(song.artist).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            markButtons(side: false)
            if !isClosed {
                iconButton("backward.end.fill", label: "Morceau précédent") { go(-1) }
                iconButton("forward.end.fill", label: "Morceau suivant") { go(1) }
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, isClosed ? trailing + 6 : topInset > 30 ? 180 : 6)
        .padding(.top, 6)
        .frame(minHeight: max(56, topInset))
    }

    // Grosses cibles pour viser sans regarder. « Défiler » et l'affichage sont en diagonale
    // et de couleurs différentes pour ne pas les confondre.
    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) { playButton; speed; searchButton() }
            HStack(spacing: 8) { key; textSize; modeButton() }
        }
        .padding(.horizontal, 8).padding(.top, 8)
        .frame(maxWidth: .infinity)
    }

    // Paysage : tout tient dans la bande de droite, sous l'heure ; le texte garde le reste de l'écran.
    private func sideControls(width: CGFloat, top: CGFloat, isClosed: Bool) -> some View {
        ViewThatFits(in: .vertical) {
            if isClosed { closedSideColumn } else { sideColumn }
            ScrollView(showsIndicators: false) { if isClosed { closedSideColumn } else { sideColumn } }
        }
        .padding(.leading, 4).padding(.trailing, 12).padding(.top, top)
        .frame(width: width)
        .frame(maxHeight: .infinity)
    }

    // Écran fermé : pincer règle la taille et toucher le texte lance le défilement, donc commandes réduites.
    private var closedControls: some View {
        HStack(alignment: .bottom, spacing: 6) {
            compactPlay.frame(width: 58)
            compactSpeed
            compactKey
            compactMode.frame(width: 72)
            compactSearch.frame(width: 48)
        }
        .padding(.horizontal, 12).padding(.top, 8)
        .frame(maxWidth: .infinity)
    }

    private var closedSideColumn: some View {
        // Calé en haut : selon le sens du paysage, la caméra arrive en bas à droite.
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                sideButton("chevron.left", label: "Retour à la liste", height: 46) { dismiss() }
                compactSearch
            }
            compactPlay
            compactSpeed
            compactKey
            compactMode
            // Rangée à part : trois boutons sur la première passeraient sous 44 points de large.
            HStack(spacing: 4) { markButtons(side: true) }
            Spacer(minLength: 0)
        }
    }

    private var compactPlay: some View {
        Button { isPlaying.toggle() } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.title3.bold())
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Palette.button, in: .rect(cornerRadius: 17))
                .foregroundStyle(.black)
                .contentShape(.rect)
        }
        .accessibilityLabel(isPlaying ? "Pause" : "Lecture")
    }

    // Portrait ouvert : tout sur une ligne, le texte gagne la hauteur d'une rangée de boutons.
    private var oneLineControls: some View {
        HStack(spacing: 6) {
            playButton.frame(minWidth: 84)
            compactSpeed
            compactKey
            compactSize
            modeButton(width: 78)
            searchButton(width: 52)
        }
        .padding(.horizontal, 12).padding(.top, 8)
        .frame(maxWidth: .infinity)
    }

    private var compactSpeed: some View {
        sideStepper(icon: "speedometer", label: "Vitesse", value: "\(Int(shownSpeed))",
                    minus: { changeSpeed(by: -5) }, plus: { changeSpeed(by: 5) })
    }

    private var compactKey: some View {
        sideStepper(icon: "music.note", label: "Ton", value: song.transpose > 0 ? "+\(song.transpose)" : "\(song.transpose)",
                    minus: { change { $0.transpose -= 1 } },
                    plus: { change { $0.transpose += 1 } })
    }

    private var compactSize: some View {
        sideStepper(icon: "textformat.size", label: "Texte", value: "\(Int((song.scale * 100).rounded()))%",
                    minus: { change { $0.scale = max(0.6, $0.scale - 0.1) } },
                    plus: { change { $0.scale = min(2, $0.scale + 0.1) } })
    }

    private var sideColumn: some View {
        VStack(spacing: 6) {
            // Calé en bas : le vide reste sous l'heure, où iOS peut afficher ses propres éléments.
            Spacer(minLength: 0)
            // Même ordre que l'écran fermé : retour et recherche en haut, étoile et drapeau en bas.
            HStack(spacing: 4) {
                sideButton("chevron.left", label: "Retour à la liste", height: 46) { dismiss() }
                compactSearch
            }
            HStack(spacing: 4) {
                sideButton("backward.end.fill", label: "Morceau précédent", height: 46) { go(-1) }
                sideButton("forward.end.fill", label: "Morceau suivant", height: 46) { go(1) }
            }
            playButton
            compactSpeed
            compactKey
            compactSize
            compactMode
            // Rangée à part : trois boutons avec le retour passeraient sous 44 points de large.
            HStack(spacing: 4) { markButtons(side: true) }
        }
    }

    private var compactMode: some View {
        Button(action: cycleMode) {
            Text(mode.label)
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Palette.section, in: .rect(cornerRadius: 20))
                .foregroundStyle(.black)
                .contentShape(.rect)
        }
        .accessibilityLabel(modeDescription)
    }

    private var compactSearch: some View {
        Button { onSearch(song) } label: {
            Image(systemName: "magnifyingglass")
                .font(.title3.bold())
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Palette.panel, in: .capsule)
                .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
                .contentShape(.rect)
        }
        .accessibilityLabel("Rechercher un morceau")
        .foregroundStyle(.primary)
    }

    private func sideStepper(icon: String, label: String, value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.footnote).foregroundStyle(.secondary)
                Text(value).font(.headline).monospacedDigit().lineLimit(1).fixedSize()
            }
            HStack(spacing: 4) {
                sideButton("minus", label: "\(label) moins", height: 46, action: minus)
                sideButton("plus", label: "\(label) plus", height: 46, action: plus)
            }
        }
    }

    /// Bouton entouré de la barre de paysage : on voit où toucher sans regarder longtemps.
    private func sideButton(_ icon: String, label: String, height: CGFloat, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3.bold())
                .frame(maxWidth: .infinity, minHeight: height)
                .background(Palette.panel, in: .rect(cornerRadius: 17))
                .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.35), lineWidth: 1))
                .contentShape(.rect)
        }
        .accessibilityLabel(label)
        .foregroundStyle(tint)
    }

    /// Étoile « Mes favoris » puis drapeau « À travailler », toujours côte à côte, remplis et jaunes quand le morceau y est.
    @ViewBuilder
    private func markButtons(side: Bool) -> some View {
        let isFavorite = favorites.contains(song.url)
        markButton(isFavorite ? "star.fill" : Favorites.icon, isOn: isFavorite,
                   label: isFavorite ? "Retirer de Mes favoris" : "Ajouter à Mes favoris", side: side, action: toggleFavorite)
        let isWork = workList.contains(song.url)
        markButton(isWork ? "flag.fill" : WorkList.icon, isOn: isWork,
                   label: isWork ? "Retirer de À travailler" : "Ajouter à À travailler", side: side, action: toggleWork)
    }

    @ViewBuilder
    private func markButton(_ icon: String, isOn: Bool, label: String, side: Bool, action: @escaping () -> Void) -> some View {
        let tint = isOn ? Palette.chord : Color.primary
        if side {
            sideButton(icon, label: label, height: 46, tint: tint, action: action)
        } else {
            iconButton(icon, label: label, tint: tint, action: action)
        }
    }

    private var playButton: some View {
        Button { isPlaying.toggle() } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.title.bold())
                .frame(maxWidth: .infinity, minHeight: 68)
                .background(Palette.button, in: .rect(cornerRadius: 22))
                .foregroundStyle(.black)
                .contentShape(.rect)
        }
        .accessibilityLabel(isPlaying ? "Pause" : "Lecture")
    }

    private func searchButton(width: CGFloat = 76) -> some View {
        Button { onSearch(song) } label: {
            Image(systemName: "magnifyingglass")
                .font(.title2.bold())
                .frame(width: width, height: 68)
                .background(Palette.background, in: .rect(cornerRadius: 22))
                .contentShape(.rect)
        }
        .accessibilityLabel("Rechercher un morceau")
        .foregroundStyle(.primary)
    }

    private var speed: some View {
        stepper(icon: "speedometer", label: "Vitesse", value: "\(Int(shownSpeed))",
                minus: { changeSpeed(by: -5) }, plus: { changeSpeed(by: 5) })
    }

    /// Chaque affichage a sa vitesse ; tant qu'elle n'est pas réglée, 70 % du complet en paroles seules, la même en accords seuls.
    private var shownSpeed: Double {
        switch mode {
        case .full: song.speed
        case .lyrics: song.lyricsSpeed ?? max(5, (song.speed * 0.7 / 5).rounded() * 5)
        case .chords: song.chordsSpeed ?? song.speed
        }
    }

    private func changeSpeed(by step: Double) {
        let value = min(150, max(5, shownSpeed + step))
        change {
            switch mode {
            case .full: $0.speed = value
            case .lyrics: $0.lyricsSpeed = value
            case .chords: $0.chordsSpeed = value
            }
        }
    }

    private var key: some View {
        stepper(icon: "music.note", label: "Ton", value: song.transpose > 0 ? "+\(song.transpose)" : "\(song.transpose)",
                minus: { change { $0.transpose -= 1 } },
                plus: { change { $0.transpose += 1 } })
    }

    private var textSize: some View {
        stepper(icon: "textformat.size", label: "Texte", value: "\(Int((song.scale * 100).rounded()))%",
                minus: { change { $0.scale = max(0.6, $0.scale - 0.1) } },
                plus: { change { $0.scale = min(2, $0.scale + 0.1) } })
    }

    /// Le bouton montre l'affichage en cours ; « Complet » est le plus long des trois libellés.
    private func modeButton(width: CGFloat = 96) -> some View {
        Button(action: cycleMode) {
            Text(mode.label)
                .font(.headline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: width, height: 68)
                .background(Palette.section, in: .rect(cornerRadius: 22))
                .foregroundStyle(.black)
                .contentShape(.rect)
        }
        .accessibilityLabel(modeDescription)
    }

    private var modeDescription: String { "Affichage : \(mode.label). Toucher pour passer à \(mode.next.label)" }

    private func cycleMode() {
        mode = mode.next
        controlsActivity += 1
    }

    private func stepper(icon: String, label: String, value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            stepButton("minus", label: "\(label) moins", action: minus)
            VStack(spacing: 2) {
                Image(systemName: icon).font(.body).foregroundStyle(.secondary)
                Text(value).font(.subheadline.bold()).monospacedDigit().lineLimit(1).fixedSize()
            }
            .frame(minWidth: 42)
            stepButton("plus", label: "\(label) plus", action: plus)
        }
        .frame(maxWidth: .infinity)
        .background(Palette.background, in: .rect(cornerRadius: 22))
    }

    private func stepButton(_ icon: String, label: String, height: CGFloat = 68, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2.bold())
                .frame(maxWidth: .infinity, minHeight: height)
                .contentShape(.rect)
        }
        .accessibilityLabel(label)
        .foregroundStyle(.primary)
    }

    private func iconButton(_ icon: String, label: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).frame(width: 44, height: 44).contentShape(.rect)
        }
        .accessibilityLabel(label)
        .foregroundStyle(tint)
    }

    private func toggleWork() {
        workList.toggle(song.url)
        controlsActivity += 1
        flash(workList.contains(song.url) ? "Ajouté à À travailler" : "Retiré")
    }

    private func toggleFavorite() {
        favorites.toggle(song.url)
        controlsActivity += 1
        guard favorites.contains(song.url) else {
            flash("Retiré des favoris")
            return
        }
        // Déjà rangé dans une playlist UG : le dire évite d'aller l'y ajouter une seconde fois.
        let lists = song.tabID.map { id in library.playlists.filter { $0.ids.contains(id) } } ?? []
        switch lists.count {
        case 0: flash("Ajouté aux favoris")
        case 1: flash("Ajouté aux favoris · déjà dans « \(lists[0].name) »", seconds: 2.5)
        default: flash("Ajouté aux favoris · déjà dans \(lists.count) playlists", seconds: 2.5)
        }
    }

    private func flash(_ text: String, seconds: Double = 1.5) {
        message = text
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if message == text { message = nil }
        }
    }

    private func showControls() {
        withAnimation(.easeOut(duration: 0.25)) { controlsHidden = false }
        controlsActivity += 1
    }

    /// Commandes cachées : le premier toucher les rappelle, le suivant met en pause ou relance.
    private func textTapped() {
        if controlsHidden { showControls() } else { isPlaying.toggle() }
    }

    private func change(_ edit: (inout Song) -> Void) {
        edit(&song)
        controlsActivity += 1
        library.update(song)
    }

    /// Passe au morceau voisin de la playlist et le charge s'il ne l'est pas encore.
    /// Un morceau illisible (tab interactive, réseau) est sauté pour ne jamais rester bloqué.
    private func go(_ step: Int) {
        guard !isLoading else { return }
        leaveSong()
        Task {
            isLoading = true
            defer { isLoading = false }
            var current = song
            for _ in 0..<4 {
                guard let next = library.neighbour(of: current, step: step, in: playlist) else { return }
                if let ready = await loaded(next) {
                    song = ready
                    return
                }
                current = next
            }
            // Pas d'attente ici : tant que le chargement tourne, le message resterait caché derrière.
            flash("Morceaux indisponibles. Essaie en Wi-Fi.", seconds: 2.5)
        }
    }

    /// Ouvre une suggestion ; la playlist ne change pas, Suivant et Précédent suivent la règle de neighbour().
    private func openSuggested(_ url: String) {
        guard !isLoading, let next = library.songs.first(where: { $0.url == url }) else { return }
        leaveSong()
        Task {
            isLoading = true
            defer { isLoading = false }
            if let ready = await loaded(next) { song = ready } else { flash("Morceau indisponible. Essaie en Wi-Fi.", seconds: 2.5) }
        }
    }

    /// Changer de morceau repart du début, en affichage complet.
    private func leaveSong() {
        isPlaying = false
        mode = .full
        resume = false
    }

    /// Le morceau avec ses paroles, demandées à UG seulement s'il ne les a pas encore ; nil si elles ne viennent pas.
    private func loaded(_ next: Song) async -> Song? {
        if next.isReady { return next }
        guard let page = try? await loader.song(at: next.url) else { return nil }
        library.store(url: next.url, title: next.title, artist: next.artist, text: page.text)
        return library.songs.first { $0.url == next.url }
    }

    /// D'abord avec les ambiances connues ; puis, si Apple Intelligence est là, après avoir noté ce morceau
    /// et les plus proches qui n'en ont pas, pour que l'ambiance compte dès ce morceau-ci.
    private func suggestNext() async {
        let current = song
        let playedAfter = transitions.next(after: current.url)
        let songs = Dictionary(library.songs.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        func candidate(_ song: Song) -> SuggestionCandidate {
            SuggestionCandidate(url: song.url, title: song.title, artist: song.artist,
                                language: library.language(of: song), decade: library.decade(of: song),
                                isReady: song.isReady, mood: moods.mood(for: song.url))
        }
        func refresh() -> [SuggestionCandidate] {
            let all = library.songs.map(candidate)
            let found = SuggestionEngine.suggestions(for: candidate(current), among: all, playedAfter: playedAfter)
            upNext = (current.url, found.compactMap { suggestion in
                songs[suggestion.url].map { UpNextRow(url: $0.url, title: $0.title, artist: $0.artist, reason: suggestion.reason) }
            })
            return all
        }
        let all = refresh()
        guard moods.isAvailable else { return }
        // Douze au plus, les plus proches d'abord : le modèle d'Apple prend plusieurs secondes par morceau.
        let close = SuggestionEngine.suggestions(for: candidate(current), among: all.filter { $0.isReady && $0.mood == nil },
                                                 playedAfter: playedAfter, limit: 12)
        await moods.analyze([current] + close.compactMap { songs[$0.url] })
        guard !Task.isCancelled else { return }
        _ = refresh()
    }
}

private struct TappedChord: Identifiable {
    let name: String
    var id: String { name }
}

/// Ce que montre le lecteur ; un seul bouton fait tourner complet → paroles → accords.
enum SheetMode {
    case full, lyrics, chords

    var label: String {
        switch self {
        case .full: "Complet"
        case .lyrics: "Paroles"
        case .chords: "Accords"
        }
    }

    var next: SheetMode {
        switch self {
        case .full: .lyrics
        case .lyrics: .chords
        case .chords: .full
        }
    }
}

struct UpNextRow: Equatable, Identifiable {
    let url: String
    let title: String
    let artist: String
    let reason: String
    var id: String { url }
}

/// « À jouer ensuite », hébergé sous le texte dans le même défilement : on le voit en arrivant à la fin.
private struct UpNextView: View {
    let rows: [UpNextRow]
    let onOpen: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("À jouer ensuite")
                .font(.title3.bold())
                .foregroundStyle(Palette.section)
                .accessibilityAddTraits(.isHeader)
            ForEach(rows) { row in
                Button { onOpen(row.url) } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                            Text(row.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(row.reason).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .background(Palette.panel, in: .rect(cornerRadius: 14))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(row.title), \(row.artist). \(row.reason)")
                .accessibilityHint("Ouvre ce morceau")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Racine à part, hors de l'arbre de l'app : elle n'hérite ni du mode sombre ni de la teinte.
        .environment(\.colorScheme, .dark)
    }
}

/// Texte à chasse fixe qui ne revient jamais à la ligne, pour garder les accords alignés.
struct SheetView: UIViewRepresentable {
    /// Où en était le dernier morceau refermé, pour y revenir après un clic par erreur.
    static var lastOffset: CGFloat = 0

    let song: Song
    let mode: SheetMode
    let speed: Double
    @Binding var isPlaying: Bool
    let startOffset: CGFloat?
    let topInset: CGFloat
    let sideInset: CGFloat
    let upNext: [UpNextRow]
    let onScale: (Double) -> Void
    let onBack: () -> Void
    let onTap: () -> Void
    let onChord: (String) -> Void
    let onUpNext: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(isPlaying: $isPlaying) }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = SheetScrollView()
        scroll.onWidthChange = { [weak coordinator = context.coordinator] in coordinator?.layout() }
        scroll.backgroundColor = .clear
        scroll.alwaysBounceVertical = true
        scroll.isAccessibilityElement = false
        scroll.accessibilityIdentifier = "sheet"
        let label = context.coordinator.label
        label.numberOfLines = 0
        label.accessibilityIdentifier = "sheet.text"
        scroll.addSubview(label)
        scroll.addSubview(context.coordinator.footer.view)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.delegate = context.coordinator
        scroll.addGestureRecognizer(tap)
        scroll.addGestureRecognizer(UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinched)))
        let back = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.swipedRight))
        back.delegate = context.coordinator
        scroll.addGestureRecognizer(back)
        scroll.panGestureRecognizer.require(toFail: back)
        context.coordinator.scroll = scroll
        context.coordinator.pendingOffset = startOffset
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.isPlayingBinding = $isPlaying
        coordinator.speed = speed
        if coordinator.topInset != topInset || coordinator.sideInset != sideInset {
            coordinator.topInset = topInset
            coordinator.sideInset = sideInset
            coordinator.layout()
        }
        coordinator.onScale = onScale
        coordinator.onBack = onBack
        coordinator.onTap = onTap
        coordinator.onChord = onChord
        coordinator.onUpNext = onUpNext
        coordinator.render(song: song, mode: mode)
        coordinator.setUpNext(upNext)
        coordinator.setPlaying(isPlaying)
    }

    static func dismantleUIView(_ uiView: UIScrollView, coordinator: Coordinator) {
        lastOffset = uiView.contentOffset.y
        coordinator.setPlaying(false)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let label = UILabel()
        weak var scroll: UIScrollView?
        var isPlayingBinding: Binding<Bool>
        var speed: Double = 30
        private var link: CADisplayLink?
        private var accumulated: CGFloat = 0
        private var signature = ""
        private var lines: [Chords.Line] = []
        /// Les lignes telles qu'affichées (après passage à la ligne), pour retrouver l'accord touché.
        private var visible: [Chords.Line] = []
        private var columnWidth: CGFloat = 10
        private var scale: Double = 1

        init(isPlaying: Binding<Bool>) { isPlayingBinding = isPlaying }

        var onScale: (Double) -> Void = { _ in }
        var onBack: () -> Void = {}
        var onTap: () -> Void = {}
        var onChord: (String) -> Void = { _ in }
        var onUpNext: (String) -> Void = { _ in }
        private var upNext: [UpNextRow] = []
        /// Les suggestions sous le texte. Le bouton passe par onUpNext, la vue n'est refaite que si les lignes changent.
        fileprivate lazy var footer: UIHostingController<UpNextView> = {
            let host = UIHostingController(rootView: UpNextView(rows: [], onOpen: { _ in }))
            host.view.backgroundColor = .clear
            host.view.isHidden = true
            // Dans le défilement, les marges de sécurité décaleraient les lignes selon la position.
            host.safeAreaRegions = []
            return host
        }()
        private var pinchStart: Double = 1
        private var pointsPerSecond: Double = 20
        var pendingOffset: CGFloat?
        var topInset: CGFloat = 0
        var sideInset: CGFloat = 16

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            if let chord = chord(at: gesture.location(in: label)) { onChord(chord) } else { onTap() }
        }

        /// La ligne vient de TextKit, avec le texte et la largeur du label ; la colonne, de la chasse fixe.
        private func chord(at point: CGPoint) -> String? {
            guard let text = label.attributedText, text.length > 0,
                  point.y >= 0, point.y < label.bounds.height else { return nil }
            let storage = NSTextStorage(attributedString: text)
            let manager = NSLayoutManager()
            let container = NSTextContainer(size: CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            manager.addTextContainer(container)
            storage.addLayoutManager(manager)
            // usedRect ne calcule pas la mise en page lui-même : sans ça il vaut 0.
            manager.ensureLayout(for: container)
            // Si UILabel et TextKit diffèrent d'un rien par ligne, l'écart s'accumulerait en bas des longs morceaux.
            let used = manager.usedRect(for: container).height
            let y = point.y * used / label.bounds.height
            let index = manager.characterIndex(for: CGPoint(x: point.x, y: y), in: container,
                                               fractionOfDistanceBetweenInsertionPoints: nil)
            let row = (text.string as NSString).substring(to: min(index, text.length)).reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
            guard row < visible.count, visible[row].kind == .chord else { return nil }
            return Self.chord(in: visible[row].text, at: Int((point.x / columnWidth).rounded(.down)))
        }

        /// L'accord le plus proche de la colonne, à un caractère près de chaque côté ; jamais un « | » ou un « x2 ».
        static func chord(in line: String, at column: Int) -> String? {
            let characters = Array(line)
            var best: (distance: Int, chord: String)?
            var start = 0
            while start < characters.count {
                guard !characters[start].isWhitespace else { start += 1; continue }
                var end = start
                while end < characters.count, !characters[end].isWhitespace { end += 1 }
                let word = String(characters[start..<end])
                let distance = column < start ? start - column : column >= end ? column - end + 1 : 0
                if distance <= 1, distance < (best?.distance ?? 2), Chords.isChordLine(word) { best = (distance, word) }
                start = end
            }
            return best?.chord
        }

        @objc func pinched(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                pinchStart = scale
            case .changed:
                let value = min(2, max(0.6, (pinchStart * gesture.scale * 20).rounded() / 20))
                if value != scale { onScale(value) }
            default:
                break
            }
        }

        // Le texte ne défile jamais à l'horizontale : glisser vers la droite, partout, ramène à la liste.
        @objc func swipedRight(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .changed else { return }
            if gesture.translation(in: gesture.view).x > 70 {
                gesture.isEnabled = false
                onBack()
            }
        }

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return velocity.x > 0 && velocity.x > abs(velocity.y) * 2
        }

        // Un toucher sur une suggestion reste à son bouton : ni pause, ni clavier d'accord, ni touche annulée.
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            !(gesture is UITapGestureRecognizer && touch.view?.isDescendant(of: footer.view) == true)
        }

        func setUpNext(_ rows: [UpNextRow]) {
            guard rows != upNext else { return }
            upNext = rows
            footer.rootView = UpNextView(rows: rows, onOpen: { [weak self] url in self?.onUpNext(url) })
            footer.view.isHidden = rows.isEmpty
            placeFooter()
        }

        func render(song: Song, mode: SheetMode) {
            let key = "\(song.url)|\(song.transpose)|\(song.scale)|\(mode)"
            guard key != signature else { return }
            signature = key
            scale = song.scale
            let text = song.text ?? ""
            let flats = Chords.prefersFlats(text)
            lines = text.components(separatedBy: "\n").compactMap { raw in
                var line = raw
                while line.last?.isWhitespace == true { line.removeLast() }
                if Chords.isSection(line) { return Chords.Line(text: line, kind: .section) }
                if Chords.isChordLine(line) {
                    if mode == .lyrics { return nil }
                    return Chords.Line(text: Chords.transpose(line, by: song.transpose, flats: flats), kind: .chord)
                }
                // Accords seuls : les paroles partent, les lignes vides restent pour le tri qui suit.
                if mode == .chords, !line.isEmpty { return nil }
                return Chords.Line(text: line, kind: .lyric)
            }
            if mode != .full { lines = Chords.withoutInnerBlanks(lines) }
            layout()
        }

        func layout() {
            guard let scroll, scroll.bounds.width > 0 else { return }
            let inset = sideInset
            let available = scroll.bounds.width - inset * 2
            let unit = ("M" as NSString).size(withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 100, weight: .regular)]).width / 100
            // Taille liée à la largeur de l'écran, pas à la ligne la plus longue : une longue ligne
            // passe à la ligne au lieu de rapetisser tout le morceau.
            let size = max(14, available / 35) * scale
            visible = Chords.wrap(lines, width: max(10, Int(available / (size * unit))))
            columnWidth = ("M" as NSString).size(withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: size, weight: .bold)]).width
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = size * 0.18
            paragraph.lineBreakMode = .byClipping
            let output = NSMutableAttributedString()
            for (index, line) in visible.enumerated() {
                output.append(NSAttributedString(string: line.text + (index < visible.count - 1 ? "\n" : ""), attributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: size, weight: line.kind == .lyric ? .regular : .bold),
                    .foregroundColor: line.kind == .chord ? UIColor(Palette.chord) : line.kind == .section ? UIColor(Palette.section) : .white,
                    .paragraphStyle: paragraph,
                ]))
            }
            // Garde le même passage à l'écran quand le texte change de taille.
            let position = scroll.contentSize.height > 0 ? scroll.contentOffset.y / scroll.contentSize.height : 0
            label.attributedText = output
            let needed = label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
            label.frame = CGRect(x: inset, y: inset + topInset, width: available, height: needed.height)
            // Une vitesse de 30 parcourt tout le texte en 3 min 30, quels que soient sa taille et le mode.
            pointsPerSecond = Double(needed.height) / 210
            placeFooter()
            scroll.contentOffset.y = position * scroll.contentSize.height
            if let pendingOffset, !lines.isEmpty {
                scroll.contentOffset.y = pendingOffset
                self.pendingOffset = nil
            }
        }

        /// Les suggestions sous le texte. Le vide de fin rétrécit d'autant : la dernière ligne s'arrête au même endroit,
        /// et le défilement automatique, qui va jusqu'en bas, finit sur les suggestions.
        private func placeFooter() {
            guard let scroll else { return }
            var extra: CGFloat = 0
            if !upNext.isEmpty, label.frame.width > 0 {
                let gap: CGFloat = 40
                let height = footer.sizeThatFits(in: CGSize(width: label.frame.width, height: .greatestFiniteMagnitude)).height
                footer.view.frame = CGRect(x: label.frame.minX, y: label.frame.maxY + gap, width: label.frame.width, height: height)
                extra = gap + height
            }
            scroll.contentSize = CGSize(width: scroll.bounds.width,
                                        height: label.frame.maxY + extra + max(sideInset, scroll.bounds.height * 0.55 - extra))
        }

        func setPlaying(_ playing: Bool) {
            if playing, link == nil {
                accumulated = 0
                // En fin de morceau, « Défiler » repart du début.
                if let scroll, scroll.contentOffset.y >= scroll.contentSize.height - scroll.bounds.height - 1 {
                    scroll.contentOffset.y = 0
                }
                let link = CADisplayLink(target: self, selector: #selector(tick))
                link.add(to: .main, forMode: .common)
                self.link = link
            } else if !playing {
                link?.invalidate()
                link = nil
            }
        }

        @objc private func tick(_ link: CADisplayLink) {
            guard let scroll, !scroll.isTracking, !scroll.isDecelerating else { return }
            accumulated += CGFloat(speed / 30 * pointsPerSecond * (link.targetTimestamp - link.timestamp))
            let scaleFactor = scroll.traitCollection.displayScale
            let step = (accumulated * scaleFactor).rounded(.down) / scaleFactor
            guard step > 0 else { return }
            accumulated -= step
            let end = scroll.contentSize.height - scroll.bounds.height
            if scroll.contentOffset.y >= end {
                isPlayingBinding.wrappedValue = false
                return
            }
            scroll.contentOffset.y = min(end, scroll.contentOffset.y + step)
        }
    }

    /// Recalcule la taille du texte quand la largeur change (ouverture du Duo, rotation).
    final class SheetScrollView: UIScrollView {
        var onWidthChange: (() -> Void)?
        private var lastWidth: CGFloat = 0

        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.width != lastWidth else { return }
            lastWidth = bounds.width
            onWidthChange?()
        }
    }
}

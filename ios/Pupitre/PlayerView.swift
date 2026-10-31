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
    let playlist: Playlist?
    var resume = false
    let onSearch: (Song) -> Void
    @Environment(UGLoader.self) private var loader
    @State private var isLoading = false
    @State private var message: String?
    @State private var isPlaying = false
    @State private var lyricsOnly = false
    @State private var hidesStatusBar = false

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
                SheetView(song: song, lyricsOnly: lyricsOnly, isPlaying: $isPlaying,
                          startOffset: resume ? SheetView.lastOffset : nil,
                          topInset: 0,
                          sideInset: isClosed && isWide ? 8 : 16,
                          onScale: { value in change { $0.scale = value } },
                          onBack: { dismiss() })
                    .id(song.url)
                    .overlay {
                        if isLoading {
                            ProgressView().controlSize(.large)
                                .padding(24)
                                .background(.black.opacity(0.8), in: .rect(cornerRadius: 16))
                        } else if let message {
                            Text(message)
                                .padding(16)
                                .background(.black.opacity(0.9), in: .rect(cornerRadius: 22))
                        }
                    }
              }
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
            .ignoresSafeArea(edges: isWide ? [.top, .bottom, .leading, .trailing] : isClosedPortrait ? [.top, .bottom, .trailing] : [.top, .bottom])
        }
        .background(Palette.background)
        // Écran fermé en vertical : l'heure et le réseau laissent la place au morceau. Ouvert, on les garde.
        .onGeometryChange(for: Bool.self) { $0.size.height > $0.size.width && $0.size.width < 560 } action: { hidesStatusBar = $0 }
        .statusBarHidden(hidesStatusBar)
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

    // Grosses cibles pour viser sans regarder. « Défiler » et « Paroles » sont en diagonale
    // et de couleurs différentes pour ne pas les confondre.
    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) { playButton; speed; searchButton() }
            HStack(spacing: 8) { key; textSize; lyricsButton() }
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
            compactLyrics.frame(width: 72)
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
            compactLyrics
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
            lyricsButton(width: 78)
            searchButton(width: 52)
        }
        .padding(.horizontal, 12).padding(.top, 8)
        .frame(maxWidth: .infinity)
    }

    private var compactSpeed: some View {
        sideStepper(icon: "speedometer", label: "Vitesse", value: "\(Int(song.speed))",
                    minus: { change { $0.speed = max(5, $0.speed - 5) } },
                    plus: { change { $0.speed = min(150, $0.speed + 5) } })
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
            sideButton("chevron.left", label: "Retour à la liste", height: 46) { dismiss() }
            HStack(spacing: 4) {
                sideButton("backward.end.fill", label: "Morceau précédent", height: 46) { go(-1) }
                sideButton("forward.end.fill", label: "Morceau suivant", height: 46) { go(1) }
            }
            playButton
            compactSpeed
            compactKey
            compactSize
            compactLyrics
            compactSearch
        }
    }

    private var compactLyrics: some View {
        Button { lyricsOnly.toggle() } label: {
            Text(lyricsOnly ? "Accords" : "Paroles")
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Palette.section, in: .rect(cornerRadius: 20))
                .foregroundStyle(.black)
                .contentShape(.rect)
        }
        .accessibilityLabel(lyricsOnly ? "Afficher les accords" : "Paroles seules")
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
    private func sideButton(_ icon: String, label: String, height: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3.bold())
                .frame(maxWidth: .infinity, minHeight: height)
                .background(Palette.panel, in: .rect(cornerRadius: 17))
                .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.35), lineWidth: 1))
                .contentShape(.rect)
        }
        .accessibilityLabel(label)
        .foregroundStyle(.primary)
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
        stepper(icon: "speedometer", label: "Vitesse", value: "\(Int(song.speed))",
                minus: { change { $0.speed = max(5, $0.speed - 5) } },
                plus: { change { $0.speed = min(150, $0.speed + 5) } })
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

    private func lyricsButton(width: CGFloat = 96) -> some View {
        Button { lyricsOnly.toggle() } label: {
            Text(lyricsOnly ? "Accords" : "Paroles")
                .font(.headline.bold())
                .lineLimit(1)
                .fixedSize()
                .frame(width: width, height: 68)
                .background(Palette.section, in: .rect(cornerRadius: 22))
                .foregroundStyle(.black)
                .contentShape(.rect)
        }
        .accessibilityLabel(lyricsOnly ? "Afficher les accords" : "Paroles seules")
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

    private func iconButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).frame(width: 44, height: 44).contentShape(.rect)
        }
        .accessibilityLabel(label)
        .foregroundStyle(.primary)
    }

    private func change(_ edit: (inout Song) -> Void) {
        edit(&song)
        library.update(song)
    }

    /// Passe au morceau voisin de la playlist et le charge s'il ne l'est pas encore.
    /// Un morceau illisible (tab interactive, réseau) est sauté pour ne jamais rester bloqué.
    private func go(_ step: Int) {
        guard !isLoading else { return }
        isPlaying = false
        lyricsOnly = false
        Task {
            isLoading = true
            defer { isLoading = false }
            var current = song
            for _ in 0..<4 {
                guard let next = library.neighbour(of: current, step: step, in: playlist) else { return }
                if next.isReady {
                    song = next
                    return
                }
                if let loaded = try? await loader.song(at: next.url) {
                    library.store(url: next.url, title: next.title, artist: next.artist, text: loaded.text)
                    if let saved = library.songs.first(where: { $0.url == next.url }) { song = saved }
                    return
                }
                current = next
            }
            message = "Morceaux indisponibles. Essaie en Wi-Fi."
            try? await Task.sleep(for: .seconds(2.5))
            message = nil
        }
    }
}

/// Texte à chasse fixe qui ne revient jamais à la ligne, pour garder les accords alignés.
struct SheetView: UIViewRepresentable {
    /// Où en était le dernier morceau refermé, pour y revenir après un clic par erreur.
    static var lastOffset: CGFloat = 0

    let song: Song
    let lyricsOnly: Bool
    @Binding var isPlaying: Bool
    let startOffset: CGFloat?
    let topInset: CGFloat
    let sideInset: CGFloat
    let onScale: (Double) -> Void
    let onBack: () -> Void

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
        scroll.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped)))
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
        coordinator.speed = song.speed
        if coordinator.topInset != topInset || coordinator.sideInset != sideInset {
            coordinator.topInset = topInset
            coordinator.sideInset = sideInset
            coordinator.layout()
        }
        coordinator.onScale = onScale
        coordinator.onBack = onBack
        coordinator.render(song: song, lyricsOnly: lyricsOnly)
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
        private var scale: Double = 1

        init(isPlaying: Binding<Bool>) { isPlayingBinding = isPlaying }

        var onScale: (Double) -> Void = { _ in }
        var onBack: () -> Void = {}
        private var pinchStart: Double = 1
        private var pointsPerSecond: Double = 20
        var pendingOffset: CGFloat?
        var topInset: CGFloat = 0
        var sideInset: CGFloat = 16

        @objc func tapped() { isPlayingBinding.wrappedValue.toggle() }

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

        func render(song: Song, lyricsOnly: Bool) {
            let key = "\(song.url)|\(song.transpose)|\(song.scale)|\(lyricsOnly)"
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
                    if lyricsOnly { return nil }
                    return Chords.Line(text: Chords.transpose(line, by: song.transpose, flats: flats), kind: .chord)
                }
                return Chords.Line(text: line, kind: .lyric)
            }
            if lyricsOnly { lines = Chords.withoutInnerBlanks(lines) }
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
            let visible = Chords.wrap(lines, width: max(10, Int(available / (size * unit))))
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
            scroll.contentSize = CGSize(width: scroll.bounds.width,
                                        height: needed.height + inset + topInset + scroll.bounds.height * 0.55)
            scroll.contentOffset.y = position * scroll.contentSize.height
            if let pendingOffset, !lines.isEmpty {
                scroll.contentOffset.y = pendingOffset
                self.pendingOffset = nil
            }
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

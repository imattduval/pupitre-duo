import SwiftUI
import UIKit

struct PlayerView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State var song: Song
    let playlist: Playlist?
    @State private var isPlaying = false
    @State private var lyricsOnly = false

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                header(topInset: proxy.safeAreaInsets.top)
                Divider()
                SheetView(song: song, lyricsOnly: lyricsOnly, isPlaying: $isPlaying)
                    .id(song.url)
                Divider()
                controls
                    .padding(.bottom, max(8, proxy.safeAreaInsets.bottom * 0.4))
                    .background(Palette.panel)
            }
            .ignoresSafeArea(edges: [.top, .bottom])
        }
        .background(Palette.background)
        .onChange(of: isPlaying) { _, playing in
            // L'écran reste allumé pendant le défilement.
            UIApplication.shared.isIdleTimerDisabled = playing
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    /// Duo ouvert : l'heure occupe le haut à droite, le titre se place dans la même bande, à sa gauche.
    private func header(topInset: CGFloat) -> some View {
        HStack(spacing: 4) {
            iconButton("chevron.left", label: "Retour à la liste") { dismiss() }
            VStack(alignment: .leading, spacing: 0) {
                Text(song.title).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
                Text(song.artist).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            iconButton("backward.end.fill", label: "Morceau précédent") { go(-1) }
            iconButton("forward.end.fill", label: "Morceau suivant") { go(1) }
        }
        .padding(.leading, 6)
        .padding(.trailing, topInset > 30 ? 180 : 6)
        .padding(.top, 6)
        .frame(minHeight: max(56, topInset))
    }

    // Grosses cibles pour viser sans regarder. « Défiler » et « Paroles » sont en diagonale
    // et de couleurs différentes pour ne pas les confondre.
    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) { playButton; speed }
            HStack(spacing: 8) { key; textSize; lyricsButton }
        }
        .padding(.horizontal, 8).padding(.top, 8)
        .frame(maxWidth: .infinity)
    }

    private var playButton: some View {
        Button { isPlaying.toggle() } label: {
            Text(isPlaying ? "Pause" : "Défiler")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, minHeight: 68)
                .background(Palette.chord, in: .rect(cornerRadius: 14))
                .foregroundStyle(.black)
                .contentShape(.rect)
        }
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

    private var lyricsButton: some View {
        Button { lyricsOnly.toggle() } label: {
            Text(lyricsOnly ? "Accords" : "Paroles")
                .font(.headline.bold())
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .frame(minHeight: 68)
                .background(Palette.section, in: .rect(cornerRadius: 14))
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
        .background(Palette.background, in: .rect(cornerRadius: 14))
    }

    private func stepButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2.bold())
                .frame(maxWidth: .infinity, minHeight: 68)
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

    private func go(_ step: Int) {
        guard let next = library.neighbour(of: song, step: step, in: playlist) else { return }
        isPlaying = false
        lyricsOnly = false
        song = next
    }
}

/// Texte à chasse fixe qui ne revient jamais à la ligne, pour garder les accords alignés.
private struct SheetView: UIViewRepresentable {
    let song: Song
    let lyricsOnly: Bool
    @Binding var isPlaying: Bool

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
        context.coordinator.scroll = scroll
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.isPlayingBinding = $isPlaying
        coordinator.speed = song.speed
        coordinator.render(song: song, lyricsOnly: lyricsOnly)
        coordinator.setPlaying(isPlaying)
    }

    static func dismantleUIView(_ uiView: UIScrollView, coordinator: Coordinator) {
        coordinator.setPlaying(false)
    }

    final class Coordinator: NSObject {
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

        @objc func tapped() { isPlayingBinding.wrappedValue.toggle() }

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
            layout()
        }

        func layout() {
            guard let scroll, scroll.bounds.width > 0 else { return }
            let inset: CGFloat = 16
            let available = scroll.bounds.width - inset * 2
            let longest = max(20, lines.map(\.text.count).max() ?? 20)
            let unit = ("M" as NSString).size(withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 100, weight: .regular)]).width / 100
            let size = min(34, max(11, available / (CGFloat(longest) * unit) - 0.1)) * scale
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
            label.attributedText = output
            let needed = label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
            label.frame = CGRect(x: inset, y: inset, width: available, height: needed.height)
            scroll.contentSize = CGSize(width: scroll.bounds.width,
                                        height: needed.height + inset + scroll.bounds.height * 0.55)
        }

        func setPlaying(_ playing: Bool) {
            if playing, link == nil {
                accumulated = 0
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
            accumulated += CGFloat(speed * (link.targetTimestamp - link.timestamp))
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

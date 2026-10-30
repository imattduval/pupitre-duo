import SwiftUI
import UIKit

struct PlayerView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State var song: Song
    @State private var isPlaying = false
    @State private var lyricsOnly = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            SheetView(song: song, lyricsOnly: lyricsOnly, isPlaying: $isPlaying)
                .id(song.url)
            Divider()
            controls
        }
        .background(Palette.background)
        .onChange(of: isPlaying) { _, playing in
            // L'écran reste allumé pendant le défilement.
            UIApplication.shared.isIdleTimerDisabled = playing
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var header: some View {
        HStack(spacing: 8) {
            iconButton("chevron.left", label: "Retour à la liste") { dismiss() }
            VStack(alignment: .leading, spacing: 0) {
                Text(song.title).font(.headline).lineLimit(1)
                Text(song.artist).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            iconButton("backward.end.fill", label: "Morceau précédent") { go(-1) }
            iconButton("forward.end.fill", label: "Morceau suivant") { go(1) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) { playButton; speed; key; textSize; lyricsButton }
            VStack(spacing: 8) {
                HStack(spacing: 18) { playButton; speed }
                HStack(spacing: 18) { key; textSize; lyricsButton }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Palette.panel)
    }

    private var playButton: some View {
        Button(isPlaying ? "Pause" : "Défiler") { isPlaying.toggle() }
            .font(.headline)
            .frame(minWidth: 110, minHeight: 48)
            .background(Palette.chord, in: .rect(cornerRadius: 12))
            .foregroundStyle(.black)
    }

    private var speed: some View {
        stepper(title: "Vitesse", value: "\(Int(song.speed))",
                minus: { change { $0.speed = max(5, $0.speed - 5) } },
                plus: { change { $0.speed = min(150, $0.speed + 5) } })
    }

    private var key: some View {
        stepper(title: "Ton", value: song.transpose > 0 ? "+\(song.transpose)" : "\(song.transpose)",
                minus: { change { $0.transpose -= 1 } },
                plus: { change { $0.transpose += 1 } })
    }

    private var textSize: some View {
        stepper(title: "Texte", value: "\(Int((song.scale * 100).rounded()))%",
                minus: { change { $0.scale = max(0.6, $0.scale - 0.1) } },
                plus: { change { $0.scale = min(2, $0.scale + 0.1) } })
    }

    private var lyricsButton: some View {
        Button("Paroles") { lyricsOnly.toggle() }
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel("Paroles seules")
            .frame(minHeight: 48)
            .foregroundStyle(lyricsOnly ? Palette.chord : .primary)
    }

    private func stepper(title: String, value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 2) {
            iconButton("minus", label: "\(title) moins", action: minus)
            VStack(spacing: 0) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.subheadline.bold()).monospacedDigit()
            }
            .frame(minWidth: 46)
            iconButton("plus", label: "\(title) plus", action: plus)
        }
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
        guard let next = library.neighbour(of: song, step: step) else { return }
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
        private var lines: [(String, UIColor, Bool)] = []
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
                if Chords.isSection(line) { return (line, UIColor(Palette.section), true) }
                if Chords.isChordLine(line) {
                    if lyricsOnly { return nil }
                    return (Chords.transpose(line, by: song.transpose, flats: flats), UIColor(Palette.chord), true)
                }
                return (line, .white, false)
            }
            layout()
        }

        func layout() {
            guard let scroll, scroll.bounds.width > 0 else { return }
            let inset: CGFloat = 16
            let available = scroll.bounds.width - inset * 2
            let longest = max(20, lines.map(\.0.count).max() ?? 20)
            let unit = ("M" as NSString).size(withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 100, weight: .regular)]).width / 100
            let size = min(34, max(11, available / (CGFloat(longest) * unit) - 0.1)) * scale
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = size * 0.18
            paragraph.lineBreakMode = .byClipping
            let output = NSMutableAttributedString()
            for (index, (line, color, bold)) in lines.enumerated() {
                output.append(NSAttributedString(string: line + (index < lines.count - 1 ? "\n" : ""), attributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular),
                    .foregroundColor: color,
                    .paragraphStyle: paragraph,
                ]))
            }
            label.attributedText = output
            let needed = label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
            label.frame = CGRect(x: inset, y: inset, width: max(available, needed.width), height: needed.height)
            scroll.contentSize = CGSize(width: max(scroll.bounds.width, needed.width + inset * 2),
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

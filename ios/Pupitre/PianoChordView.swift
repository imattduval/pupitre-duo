import SwiftUI

/// Feuille qui montre où poser les doigts pour un accord, sur deux octaves.
struct PianoChordView: View {
    private let chord: String
    @Environment(\.dismiss) private var dismiss
    @State private var inversion = 0

    init(chord: String) {
        self.chord = chord
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(chord)
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.chord)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let parsed = ChordNotes.parse(chord) {
                let flats = ChordNotes.prefersFlats(chord)
                let keys = ChordNotes.voicing(parsed, inversion: inversion)
                let names = keys.map { ChordNotes.frenchName($0, flats: flats) }
                Text(names.joined(separator: " · "))
                    .font(.title2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                PianoKeyboard(keys: keys, flats: flats)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(names.joined(separator: ", "))
                    .animation(.easeOut(duration: 0.15), value: keys)
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    let count = ChordNotes.inversionCount(parsed)
                    if count > 1 {
                        bigButton("Renversement suivant", filled: true) { inversion = (inversion + 1) % count }
                    }
                    bigButton("Fermer", filled: false) { dismiss() }
                }
            } else {
                Text("Accord non reconnu")
                    .font(.title2.bold())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                bigButton("Fermer", filled: false) { dismiss() }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationBackground(Palette.panel)
    }

    private func bigButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(filled ? Palette.button : Palette.background, in: .rect(cornerRadius: 22))
                .foregroundStyle(filled ? Color.black : Color.primary)
                .contentShape(.rect)
        }
    }
}

/// Deux octaves à partir d'un do ; les touches de l'accord portent le nom de leur note.
private struct PianoKeyboard: View {
    let keys: [Int]
    let flats: Bool

    private static let whites = [0, 2, 4, 5, 7, 9, 11]
    private static let blacks = (0..<24).filter { !whites.contains($0 % 12) }

    var body: some View {
        GeometryReader { geometry in
            let white = geometry.size.width / 14
            let black = white * 0.62
            ZStack(alignment: .topLeading) {
                ForEach(0..<14, id: \.self) { index in
                    key(index / 7 * 12 + Self.whites[index % 7], width: white - 2, height: geometry.size.height, isBlack: false)
                        .offset(x: CGFloat(index) * white + 1)
                }
                ForEach(Self.blacks, id: \.self) { note in
                    // Une touche noire est à cheval sur la blanche qui la précède et la suivante.
                    let left = CGFloat((note - 1) / 12 * 7 + Self.whites.firstIndex(of: (note - 1) % 12)! + 1)
                    key(note, width: black, height: geometry.size.height * 0.62, isBlack: true)
                        .offset(x: left * white - black / 2)
                }
            }
        }
        .aspectRatio(14 / 5, contentMode: .fit)
    }

    private func key(_ note: Int, width: CGFloat, height: CGFloat, isBlack: Bool) -> some View {
        let isOn = keys.contains(note)
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: isBlack ? 4 : 7, bottomTrailingRadius: isBlack ? 4 : 7)
        return shape
            .fill(isOn ? Palette.chord : isBlack ? Palette.background : Color.white.opacity(0.9))
            .overlay { if isBlack { shape.stroke(Palette.background, lineWidth: 2) } }
            .overlay(alignment: .bottom) {
                if isOn {
                    // Lisible depuis le tabouret : 13 points au moins, quitte à déborder un peu d'une touche noire.
                    Text(ChordNotes.frenchName(note, flats: flats))
                        .font(.system(size: max(13, width * 0.4), weight: .bold))
                        .foregroundStyle(.black)
                        .fixedSize()
                        .padding(.bottom, width * 0.25)
                }
            }
            .frame(width: width, height: height)
    }
}

import Foundation

enum Chords {
    private static let chord = /^\(?[A-G](?:#|b)?(?:maj|min|m|M|sus|dim|aug|add|no|omit|\+|-|°|ø|\d|\(|\)|,|#|b)*(?:\/[A-G](?:#|b)?)?\)?$/
    private static let filler = /^(?:\||\|\||-|–|\/|%|\(?(?:[xX]\d{1,2}|\d{1,2}[xX])\)?|\(?N\.C\.?\)?|\.+|:|\(|\))$/
    private static let root = /(^\(?|\/)([A-G](?:#|b)?)/
    private static let sharps = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let flats = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
    private static let notes: [String: Int] = [
        "C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6,
        "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11, "Cb": 11, "E#": 5, "B#": 0, "Fb": 4,
    ]

    struct Line {
        enum Kind { case chord, lyric, section }
        var text: String
        var kind: Kind
    }

    /// Sans accords, les lignes vides ne sont utiles qu'avant une nouvelle section.
    static func withoutInnerBlanks(_ lines: [Line]) -> [Line] {
        lines.indices.compactMap { index in
            guard lines[index].text.trimmingCharacters(in: .whitespaces).isEmpty else { return lines[index] }
            let next = lines[(index + 1)...].first { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            let previousIsBlank = index > 0 && lines[index - 1].text.trimmingCharacters(in: .whitespaces).isEmpty
            return next?.kind == .section && !previousIsBlank ? lines[index] : nil
        }
    }

    /// Passe à la ligne ce qui dépasse. Une ligne d'accords et ses paroles sont coupées
    /// à la même colonne, pour que chaque accord reste au-dessus de sa syllabe.
    static func wrap(_ lines: [Line], width: Int) -> [Line] {
        var output: [Line] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let next = index + 1 < lines.count ? lines[index + 1] : nil
            if line.kind == .chord, let next, next.kind == .lyric, !next.text.isEmpty {
                var chords = Array(line.text)
                var lyric = Array(next.text)
                while max(chords.count, lyric.count) > width {
                    let cut = column(chords: chords, lyric: lyric, width: width)
                    appendPair(chords: chords.prefix(cut), lyric: lyric.prefix(cut), to: &output)
                    chords = Array(chords.dropFirst(cut))
                    lyric = Array(lyric.dropFirst(cut))
                }
                appendPair(chords: chords[...], lyric: lyric[...], to: &output)
                index += 2
            } else {
                var rest = Array(line.text)
                while rest.count > width {
                    let cut = column(chords: line.kind == .chord ? rest : [], lyric: line.kind == .chord ? [] : rest, width: width)
                    output.append(Line(text: String(rest.prefix(cut)), kind: line.kind))
                    rest = Array(rest.dropFirst(cut))
                }
                output.append(Line(text: String(rest), kind: line.kind))
                index += 1
            }
        }
        return output
    }

    /// Une suite de ligne sans accord ne laisse pas de ligne vide au-dessus de ses paroles.
    private static func appendPair(chords: ArraySlice<Character>, lyric: ArraySlice<Character>, to output: inout [Line]) {
        if chords.contains(where: { $0 != " " }) {
            output.append(Line(text: String(chords), kind: .chord))
        }
        if lyric.contains(where: { $0 != " " }) {
            output.append(Line(text: String(lyric), kind: .lyric))
        }
    }

    /// Dernière colonne avant la largeur qui ne coupe ni un mot ni un accord.
    private static func column(chords: [Character], lyric: [Character], width: Int) -> Int {
        func isBlank(_ text: [Character], _ position: Int) -> Bool {
            position < 0 || position >= text.count || text[position] == " "
        }
        func splits(_ text: [Character], at cut: Int) -> Bool {
            !isBlank(text, cut - 1) && !isBlank(text, cut)
        }
        var cut = width
        while cut > width / 2 {
            if !splits(chords, at: cut) && !splits(lyric, at: cut) { return cut }
            cut -= 1
        }
        return width
    }

    static func isSection(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("[") && trimmed.hasSuffix("]") && trimmed.count > 2
    }

    static func isChordLine(_ line: String) -> Bool {
        var words = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return false }
        // « Intro: Am G » ou « Refrain : C G » : l'étiquette devant la grille n'en fait pas des paroles.
        if words[0].hasSuffix(":") { words.removeFirst() } else if words.count > 1, words[1] == ":" { words.removeFirst(2) }
        var found = 0
        for word in words {
            if word.wholeMatch(of: chord) != nil { found += 1 }
            else if word.wholeMatch(of: filler) == nil { return false }
        }
        return found > 0
    }

    static func prefersFlats(_ text: String) -> Bool {
        text.matches(of: /\b[A-G]b/).count > text.matches(of: /\b[A-G]#/).count
    }

    /// Transpose en gardant chaque accord au-dessus de sa syllabe, même si son nom change de longueur.
    static func transpose(_ line: String, by steps: Int, flats useFlats: Bool) -> String {
        guard steps != 0 else { return line }
        var output = ""
        var debt = 0
        for part in line.matches(of: /\s+|\S+/).map({ String($0.output) }) {
            if part.first?.isWhitespace == true {
                let keep = max(1, part.count - debt)
                debt -= part.count - keep
                output += String(repeating: " ", count: keep)
            } else {
                let moved = part.wholeMatch(of: chord) == nil ? part : part.replacing(root) { match in
                    String(match.output.1) + name(of: String(match.output.2), by: steps, flats: useFlats)
                }
                debt += moved.count - part.count
                output += moved
            }
        }
        return output
    }

    private static func name(of note: String, by steps: Int, flats useFlats: Bool) -> String {
        let index = ((notes[note] ?? 0) + steps) % 12
        return (useFlats ? flats : sharps)[(index + 12) % 12]
    }
}

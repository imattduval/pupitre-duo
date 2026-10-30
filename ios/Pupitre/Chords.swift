import Foundation

enum Chords {
    private static let chord = /^\(?[A-G](?:#|b)?(?:maj|min|m|M|sus|dim|aug|add|no|omit|\+|-|°|ø|\d|\(|\)|,|#|b)*(?:\/[A-G](?:#|b)?)?\)?$/
    private static let filler = /^(?:\||\|\||-|–|\/|%|[xX]\d+|\d+[xX]|\.+|:|\(|\))$/
    private static let root = /(^\(?|\/)([A-G](?:#|b)?)/
    private static let sharps = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let flats = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
    private static let notes: [String: Int] = [
        "C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6,
        "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11, "Cb": 11, "E#": 5, "B#": 0, "Fb": 4,
    ]

    static func isSection(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("[") && trimmed.hasSuffix("]") && trimmed.count > 2
    }

    static func isChordLine(_ line: String) -> Bool {
        let words = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return false }
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

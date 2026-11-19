import Foundation

/// Notes d'un accord écrit comme dans les tabs, pour le montrer sur un clavier.
enum ChordNotes {
    struct Parsed: Equatable {
        let root: Int
        let bass: Int?
        let pitchClasses: [Int]
    }

    private static let letters = Array("CDEFGAB")
    private static let naturals = [0, 2, 4, 5, 7, 9, 11]
    private static let sharpNames = ["do", "do#", "ré", "ré#", "mi", "fa", "fa#", "sol", "sol#", "la", "la#", "si"]
    private static let flatNames = ["do", "réb", "ré", "mib", "mi", "fa", "solb", "sol", "lab", "la", "sib", "si"]
    /// Lettre de chaque intervalle au-dessus de la fondamentale (tierce = 2, quinte = 4…), pour savoir s'il s'écrit en dièse ou en bémol.
    private static let degrees = [0, 1, 1, 2, 2, 3, 4, 4, 4, 5, 6, 6]

    private static let qualities: [String: [Int]] = {
        let table: [([String], [Int])] = [
            (["", "M", "maj"], [0, 4, 7]),
            (["m", "min", "-"], [0, 3, 7]),
            (["7"], [0, 4, 7, 10]),
            (["maj7", "M7", "7M", "Δ", "Δ7"], [0, 4, 7, 11]),
            (["m7", "min7", "-7"], [0, 3, 7, 10]),
            (["m7b5", "m7-5", "min7b5", "-7b5", "ø", "ø7"], [0, 3, 6, 10]),
            (["dim", "°"], [0, 3, 6]),
            (["dim7", "°7"], [0, 3, 6, 9]),
            (["aug", "+", "5+", "#5"], [0, 4, 8]),
            (["7#5", "7+5", "aug7", "+7"], [0, 4, 8, 10]),
            (["7b5", "7-5"], [0, 4, 6, 10]),
            (["sus2"], [0, 2, 7]),
            (["sus4", "sus"], [0, 5, 7]),
            (["7sus4", "7sus"], [0, 5, 7, 10]),
            (["add9", "add2"], [0, 4, 7, 2]),
            (["madd9", "madd2", "minadd9"], [0, 3, 7, 2]),
            (["add11", "add4"], [0, 4, 7, 5]),
            (["6", "M6", "maj6"], [0, 4, 7, 9]),
            (["m6", "min6"], [0, 3, 7, 9]),
            (["6/9", "69"], [0, 4, 7, 9, 2]),
            (["9"], [0, 4, 7, 10, 2]),
            (["m9", "min9"], [0, 3, 7, 10, 2]),
            (["maj9", "M9", "Δ9"], [0, 4, 7, 11, 2]),
            (["7b9", "7-9"], [0, 4, 7, 10, 1]),
            (["7#9", "7+9"], [0, 4, 7, 10, 3]),
            (["11"], [0, 4, 7, 10, 2, 5]),
            (["m11", "min11"], [0, 3, 7, 10, 2, 5]),
            (["13"], [0, 4, 7, 10, 2, 9]),
            (["m13", "min13"], [0, 3, 7, 10, 2, 9]),
            (["5"], [0, 7]),
            (["mmaj7", "mM7", "m7M", "minmaj7", "-maj7", "mΔ", "mΔ7"], [0, 3, 7, 11]),
        ]
        return Dictionary(uniqueKeysWithValues: table.flatMap { keys, intervals in keys.map { ($0, intervals) } })
    }()

    static func parse(_ chord: String) -> Parsed? {
        guard let head = note(cleaned(chord)) else { return nil }
        var quality = head.rest
        var bass: Int?
        if let slash = quality.lastIndex(of: "/"), let low = note(quality[quality.index(after: slash)...]), low.rest.isEmpty {
            bass = low.pc
            quality = quality[..<slash]
        }
        guard let intervals = qualities[String(quality)] else { return nil }
        return Parsed(root: head.pc, bass: bass, pitchClasses: intervals.map { mod12(head.pc + $0) })
    }

    static func frenchName(_ pitchClass: Int, flats: Bool) -> String {
        (flats ? flatNames : sharpNames)[mod12(pitchClass)]
    }

    /// Accord serré (moins d'une octave) au-dessus de la basse ; le renversement choisit la note la plus grave.
    static func voicing(_ parsed: Parsed, inversion: Int) -> [Int] {
        let count = parsed.pitchClasses.count
        let start = parsed.pitchClasses[(inversion % count + count) % count]
        let floor = parsed.bass ?? -1
        let low = floor + 1 + mod12(start - floor - 1)
        // Une note qui sortirait des deux octaves redescend d'une octave : elle reste au-dessus de la basse.
        let upper = parsed.pitchClasses.map { low + mod12($0 - start) }.map { $0 > 23 ? $0 - 12 : $0 }.sorted()
        return (parsed.bass.map { [$0] } ?? []) + upper
    }

    /// Un accord barré impose déjà sa basse : pas d'autre renversement à proposer.
    static func inversionCount(_ parsed: Parsed) -> Int {
        parsed.bass == nil ? parsed.pitchClasses.count : 1
    }

    /// Bémols si l'accord s'écrit mieux ainsi (Cm → mib, C7 → sib), dièses sinon (D → fa#).
    static func prefersFlats(_ chord: String) -> Bool {
        let text = cleaned(chord)
        guard let parsed = parse(chord), let root = note(text) else { return false }
        var marks = parsed.pitchClasses.map { mod12($0 - naturals[(root.letter + degrees[mod12($0 - parsed.root)]) % 7]) }
        if let slash = text.lastIndex(of: "/"), let bass = note(text[text.index(after: slash)...]) {
            marks.append(mod12(bass.pc - naturals[bass.letter]))
        }
        return marks.filter { $0 == 11 }.count > marks.filter { $0 == 1 }.count
    }

    /// (G) ou Am(maj7) : les parenthèses ne changent pas les notes.
    private static func cleaned(_ chord: String) -> Substring {
        Substring(chord.filter { $0 != "(" && $0 != ")" && !$0.isWhitespace })
    }

    private static func note(_ text: Substring) -> (pc: Int, letter: Int, rest: Substring)? {
        guard let first = text.first, let letter = letters.firstIndex(of: first) else { return nil }
        var rest = text.dropFirst()
        var pc = naturals[letter]
        if rest.first == "#" { pc += 1; rest = rest.dropFirst() }
        else if rest.first == "b" { pc += 11; rest = rest.dropFirst() }
        return (mod12(pc), letter, rest)
    }

    private static func mod12(_ value: Int) -> Int { (value % 12 + 12) % 12 }
}

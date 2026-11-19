// Test autonome de ChordNotes : xcrun swiftc -enable-bare-slash-regex Pupitre/ChordNotes.swift tools/test-accords.swift -o test-accords && ./test-accords

func check(_ chord: String, _ pitchClasses: [Int], bass: Int? = nil, line: UInt = #line) {
    guard let parsed = ChordNotes.parse(chord) else { preconditionFailure("\(chord) non reconnu", line: line) }
    precondition(parsed.pitchClasses == pitchClasses, "\(chord) : \(parsed.pitchClasses) au lieu de \(pitchClasses)", line: line)
    precondition(parsed.bass == bass, "\(chord) : basse \(String(describing: parsed.bass))", line: line)
}

// Plusieurs fichiers compilés ensemble : le code de premier niveau n'est permis que dans main.swift, d'où @main.
@main enum TestAccords {
    static func main() {
        check("C", [0, 4, 7])
        check("Cmaj7", [0, 4, 7, 11])
        check("CM7", [0, 4, 7, 11])
        check("C7M", [0, 4, 7, 11])
        check("CΔ", [0, 4, 7, 11])
        check("F#m7b5", [6, 9, 0, 4])
        check("Bø", [11, 2, 5, 9])
        check("Bb7", [10, 2, 5, 8])
        check("Dm", [2, 5, 9])
        check("Dmin", [2, 5, 9])
        check("Ebm7", [3, 6, 10, 1])
        check("C#m", [1, 4, 8])
        check("Cdim", [0, 3, 6])
        check("C°7", [0, 3, 6, 9])
        check("Cdim7", [0, 3, 6, 9])
        check("Caug", [0, 4, 8])
        check("C+", [0, 4, 8])
        check("Dsus2", [2, 4, 9])
        check("Dsus4", [2, 7, 9])
        check("A7sus4", [9, 2, 4, 7])
        check("Cadd9", [0, 4, 7, 2])
        check("Cadd2", [0, 4, 7, 2])
        check("C6", [0, 4, 7, 9])
        check("Am6", [9, 0, 4, 6])
        check("G9", [7, 11, 2, 5, 9])
        check("Am9", [9, 0, 4, 7, 11])
        check("Fmaj9", [5, 9, 0, 4, 7])
        check("C11", [0, 4, 7, 10, 2, 5])
        check("C13", [0, 4, 7, 10, 2, 9])
        check("E5", [4, 11])
        check("Am(maj7)", [9, 0, 4, 8])
        check("G7(b9)", [7, 11, 2, 5, 8])
        check("C6/9", [0, 4, 7, 9, 2])
        check("(G)", [7, 11, 2])
        check("(Am/G)", [9, 0, 4], bass: 7)
        check("Am/G", [9, 0, 4], bass: 7)
        check("C/E", [0, 4, 7], bass: 4)
        check("D/F#", [2, 6, 9], bass: 6)
        check("Db/Ab", [1, 5, 8], bass: 8)

        for invalid in ["", "H7", "Cxyz", "N.C.", "C/X", "am", "x2", "C7(b9,#11)"] {
            precondition(ChordNotes.parse(invalid) == nil, "« \(invalid) » ne devrait pas être reconnu")
        }

        precondition(ChordNotes.frenchName(1, flats: false) == "do#")
        precondition(ChordNotes.frenchName(1, flats: true) == "réb")
        precondition(ChordNotes.frenchName(10, flats: true) == "sib")
        precondition(ChordNotes.frenchName(7, flats: true) == "sol")
        precondition(ChordNotes.frenchName(-1, flats: false) == "si")

        let c = ChordNotes.parse("C")!
        precondition(ChordNotes.inversionCount(c) == 3)
        precondition(ChordNotes.voicing(c, inversion: 0) == [0, 4, 7])
        precondition(ChordNotes.voicing(c, inversion: 1) == [4, 7, 12])
        precondition(ChordNotes.voicing(c, inversion: 2) == [7, 12, 16])
        precondition(ChordNotes.voicing(c, inversion: 3) == [0, 4, 7])
        precondition(ChordNotes.voicing(ChordNotes.parse("F#m7b5")!, inversion: 0) == [6, 9, 12, 16])
        precondition(ChordNotes.voicing(ChordNotes.parse("Am/G")!, inversion: 0) == [7, 9, 12, 16])
        precondition(ChordNotes.voicing(ChordNotes.parse("C/E")!, inversion: 0) == [4, 12, 16, 19])
        precondition(ChordNotes.voicing(ChordNotes.parse("G/B")!, inversion: 0) == [11, 14, 19, 23])
        precondition(ChordNotes.inversionCount(ChordNotes.parse("Am/G")!) == 1)

        for (chord, flats) in [("Cm", true), ("C7", true), ("Bb", true), ("Em7b5", true), ("Cdim7", true), ("Db/F", true),
                               ("D7", false), ("A", false), ("F#m7b5", false), ("Caug", false), ("B7", false), ("D/F#", false)] {
            precondition(ChordNotes.prefersFlats(chord) == flats, "\(chord) : bémols attendus = \(flats)")
        }

        // Toutes les formes, sur les 12 fondamentales, avec ou sans basse : le clavier de deux octaves suffit toujours.
        let suffixes = ["", "m", "7", "maj7", "m7", "m7b5", "dim", "dim7", "aug", "7#5", "sus2", "sus4", "7sus4", "add9", "madd9",
                        "6", "m6", "6/9", "9", "m9", "maj9", "7b9", "7#9", "11", "m11", "13", "m13", "5", "m(maj7)"]
        let notes = ["C", "C#", "Db", "D", "Eb", "E", "F", "F#", "Gb", "G", "Ab", "A", "Bb", "B"]
        var tested = 0
        for root in notes {
            for suffix in suffixes {
                for bass in [""] + notes.map({ "/" + $0 }) {
                    let chord = root + suffix + bass
                    guard let parsed = ChordNotes.parse(chord) else { preconditionFailure("\(chord) non reconnu") }
                    for inversion in 0..<ChordNotes.inversionCount(parsed) {
                        let keys = ChordNotes.voicing(parsed, inversion: inversion)
                        precondition(keys.allSatisfy { (0...23).contains($0) }, "\(chord) hors clavier : \(keys)")
                        precondition(zip(keys, keys.dropFirst()).allSatisfy { $0 < $1 }, "\(chord) pas du grave à l'aigu : \(keys)")
                        precondition(Set(keys.map { $0 % 12 }) == Set(parsed.pitchClasses + (parsed.bass.map { [$0] } ?? [])), "\(chord) : notes \(keys)")
                        if let low = parsed.bass { precondition(keys.first == low, "\(chord) : basse pas en premier") }
                        tested += 1
                    }
                }
            }
        }

        print("ok (\(tested) voicings vérifiés)")
    }
}

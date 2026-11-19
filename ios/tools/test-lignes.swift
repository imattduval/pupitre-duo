// Test autonome de Chords.isChordLine : xcrun swiftc -enable-bare-slash-regex Pupitre/Chords.swift tools/test-lignes.swift -o test-lignes && ./test-lignes

// Plusieurs fichiers compilés ensemble : le code de premier niveau n'est permis que dans main.swift, d'où @main.
@main enum TestLignes {
    static func main() {
        // Grilles qu'UG livre avec une étiquette, une reprise ou un silence : des accords, pas des paroles.
        for line in ["Am G C F", "Intro: Am G C F", "Refrain : C G Am F", "Am G C F (x2)", "Am G C F  (2x)",
                     "Am G x2", "| Am | G |", "N.C.  Am", "(N.C.) G", "Intro : Am G"] {
            precondition(Chords.isChordLine(line), "« \(line) » devrait être une ligne d'accords")
        }
        // Paroles, étiquettes seules et mots isolés touchés dans une grille : jamais un accord.
        for line in ["Elle: A la claire fontaine", "Intro:", "(x2)", "Capo: 3", "", "Refrain :", "N.C."] {
            precondition(!Chords.isChordLine(line), "« \(line) » ne devrait pas être une ligne d'accords")
        }
        // Transposée, l'étiquette reste telle quelle et la reprise aussi.
        precondition(Chords.transpose("Intro: Am G (x2)", by: 2, flats: false) == "Intro: Bm A (x2)")
        print("ok")
    }
}

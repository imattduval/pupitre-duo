// Test autonome de SuggestionEngine, sur Mac :
// xcrun swiftc lot2/Mood.swift lot2/Suggestions.swift tools/test-suggestions.swift -o test-suggestions && ./test-suggestions

func song(_ url: String, artist: String = "", language: String? = nil, decade: Int? = nil,
          ready: Bool = true, energy: Int? = nil, tags: [String] = []) -> SuggestionCandidate {
    SuggestionCandidate(url: url, title: url, artist: artist, language: language, decade: decade,
                        isReady: ready, mood: energy.map { Mood(energy: $0, tags: tags) })
}

// Plusieurs fichiers compilés ensemble : le code de premier niveau n'est permis que dans main.swift, d'où @main.
@main enum TestSuggestions {
    static func main() {
        let current = song("a", artist: "Brel", language: "Français", decade: 1960, energy: 2, tags: ["mélancolique"])

        // L'enchaînement fréquent passe devant le morceau le plus ressemblant.
        let twin = song("twin", artist: "brél ", language: "Français", decade: 1960, energy: 2, tags: ["mélancolique"])
        let habit = song("habit", artist: "Daft Punk", decade: 2000, energy: 5, tags: ["dansant"])
        var result = SuggestionEngine.suggestions(for: current, among: [twin, habit], playedAfter: ["habit": 3])
        precondition(result == [Suggestion(url: "habit", reason: "Souvent joué après"),
                                Suggestion(url: "twin", reason: "Même artiste")], "\(result)")

        // Un seul enchaînement peut être un hasard : petit bonus, jamais « Souvent joué après », et rien sans autre motif.
        result = SuggestionEngine.suggestions(for: current, among: [song("peer", decade: 1960), song("once", decade: 1960), song("alone")],
                                              playedAfter: ["once": 1, "alone": 1])
        precondition(result == [Suggestion(url: "once", reason: "Même époque"),
                                Suggestion(url: "peer", reason: "Même époque")], "\(result)")

        // Le morceau en cours n'est jamais proposé, même joué après lui-même.
        result = SuggestionEngine.suggestions(for: current, among: [current, twin], playedAfter: ["a": 5])
        precondition(!result.contains { $0.url == "a" }, "\(result)")

        // Même énergie et même ambiance devant une énergie éloignée ; sans aucun motif, rien.
        let close = song("close", energy: 2, tags: ["rêveur"])
        let far = song("far", decade: 1960, energy: 5, tags: ["festif"])
        let stranger = song("stranger", language: "Français", energy: 5, tags: ["festif"])
        result = SuggestionEngine.suggestions(for: current, among: [far, stranger, close], playedAfter: [:])
        precondition(result.map(\.url) == ["close", "far"], "\(result)")
        precondition(result[0].reason == "Même énergie" && result[1].reason == "Même époque", "\(result)")
        let shared = SuggestionEngine.suggestions(
            for: song("b", energy: 3, tags: ["calme", "rêveur"]),
            among: [song("c", energy: 3, tags: ["rêveur", "calme"])], playedAfter: [:])
        precondition(shared == [Suggestion(url: "c", reason: "Même ambiance")], "\(shared)")

        // Limite respectée ; à score égal, les paroles déjà chargées d'abord.
        let many = (0..<10).map { song("m\($0)", artist: "Brel", ready: $0 == 7) }
        result = SuggestionEngine.suggestions(for: current, among: many, playedAfter: [:], limit: 3)
        precondition(result.map(\.url) == ["m7", "m0", "m1"], "\(result)")
        precondition(SuggestionEngine.suggestions(for: current, among: many, playedAfter: [:], limit: 0).isEmpty)

        // Résultat indépendant de l'ordre reçu.
        precondition(SuggestionEngine.suggestions(for: current, among: many.reversed(), playedAfter: [:])
                        == SuggestionEngine.suggestions(for: current, among: many, playedAfter: [:]))

        // Décennie 0 = « Date inconnue » : deux dates inconnues ne donnent pas « Même époque ».
        precondition(SuggestionEngine.suggestions(for: song("u1", decade: 0), among: [song("u2", decade: 0)],
                                                  playedAfter: [:]).isEmpty)

        // Liste vide → aucune suggestion.
        precondition(SuggestionEngine.suggestions(for: current, among: [], playedAfter: ["x": 2]).isEmpty)

        print("ok")
    }
}

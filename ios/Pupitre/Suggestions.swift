import Foundation

/// Ce que le moteur sait d'un morceau ; rempli par l'appelant, pour que le moteur reste testable sans l'app.
struct SuggestionCandidate {
    let url: String
    let title: String
    let artist: String
    let language: String?
    let decade: Int?
    let isReady: Bool
    let mood: Mood?
}

struct Suggestion: Equatable {
    let url: String
    let reason: String
}

/// Morceaux à jouer après le morceau en cours, du plus pertinent au moins pertinent.
enum SuggestionEngine {
    static func suggestions(for current: SuggestionCandidate, among candidates: [SuggestionCandidate],
                            playedAfter: [String: Int], limit: Int = 6) -> [Suggestion] {
        let artist = key(current.artist)
        var scored: [Scored] = []
        for candidate in candidates where candidate.url != current.url {
            var score = 0
            var reason: String?
            var best = 0
            // Le premier motif le mieux noté l'emporte : l'ordre des appels départage les égalités.
            func add(_ label: String, _ points: Int) {
                score += points
                if points > best { best = points; reason = label }
            }
            // Ce qu'on a vraiment joué ensuite passe avant toute ressemblance : 20 points dépassent le total des autres motifs.
            // Une seule fois peut être un hasard (Suivant pour choisir, toucher par erreur) : petit bonus, sans motif affiché.
            let times = playedAfter[candidate.url] ?? 0
            if times >= 2 { add("Souvent joué après", 20 * times) } else if times == 1 { score += 2 }
            if !artist.isEmpty, key(candidate.artist) == artist { add("Même artiste", 4) }
            if let mine = current.mood, let theirs = candidate.mood {
                let shared = Set(mine.tags).intersection(theirs.tags).count
                if shared > 0 { add("Même ambiance", 2 * shared) }
                let gap = abs(mine.energy - theirs.energy)
                if gap <= 1 { add("Même énergie", 3 - gap) }
            }
            // 0 = « Date inconnue » dans Library : deux dates inconnues ne font pas une même époque.
            if let mine = current.decade, let theirs = candidate.decade, mine > 0, theirs > 0, abs(mine - theirs) <= 10 {
                add("Même époque", mine == theirs ? 2 : 1)
            }
            // Sans motif à afficher, pas de suggestion : la langue seule ne fait que départager.
            guard let reason else { continue }
            if let language = current.language, language == candidate.language { score += 1 }
            scored.append(Scored(suggestion: Suggestion(url: candidate.url, reason: reason), score: score,
                                 isReady: candidate.isReady, title: key(candidate.title)))
        }
        return scored.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            // À score égal, un morceau aux paroles déjà chargées se joue tout de suite.
            if a.isReady != b.isReady { return a.isReady }
            if a.title != b.title { return a.title < b.title }
            return a.suggestion.url < b.suggestion.url
        }
        .prefix(max(limit, 0))
        .map(\.suggestion)
    }

    private struct Scored {
        let suggestion: Suggestion
        let score: Int
        let isReady: Bool
        let title: String
    }

    private static func key(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }
}

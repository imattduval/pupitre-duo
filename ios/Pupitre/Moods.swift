import Foundation
import FoundationModels
import Observation

/// Ambiance de chaque morceau, notée par le modèle d'Apple sur l'appareil et gardée dans Documents/ambiances.json.
@MainActor @Observable final class Moods {
    /// Liste fermée : des mots libres rendraient les ambiances impossibles à comparer entre morceaux.
    nonisolated static let vocabulary = [
        "calme", "mélancolique", "romantique", "joyeux", "festif",
        "nostalgique", "intense", "rêveur", "dansant", "engagé",
    ]

    private(set) var moods: [String: Mood] = [:]
    private(set) var isAvailable = false
    private(set) var isAnalyzing = false

    @ObservationIgnored private let file: URL
    /// Jeton plutôt que verrou : un .task annulé puis relancé par SwiftUI ne doit pas bloquer la nouvelle analyse.
    @ObservationIgnored private var run = 0

    init() {
        file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "ambiances.json")
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([String: Mood].self, from: data) {
            moods = saved
        }
        if #available(iOS 26.0, *) { isAvailable = SystemLanguageModel.default.isAvailable }
    }

    func mood(for url: String) -> Mood? { moods[url] }

    /// Note les morceaux un par un ; le dernier appel gagne, ceux que le modèle refuse sont retentés à l'appel suivant.
    func analyze(_ songs: [Song]) async {
        guard #available(iOS 26.0, *) else { return }
        // Relu à chaque fois : le modèle peut finir de se télécharger, ou Apple Intelligence être coupée, en cours de route.
        isAvailable = SystemLanguageModel.default.isAvailable
        guard isAvailable else { return }
        run += 1
        let mine = run
        isAnalyzing = true
        defer { if run == mine { isAnalyzing = false } }
        // Paroles chargées seulement : une note devinée sur le titre serait figée pour toujours.
        for song in songs where moods[song.url] == nil && song.isReady {
            if Task.isCancelled || run != mine { return }
            guard let mood = await judge(song) else { continue }
            // Annulée pendant le modèle (restauration en cours) : ne pas réécrire ambiances.json avec l'ancien état.
            if Task.isCancelled { return }
            moods[song.url] = mood
            save()
        }
    }

    @available(iOS 26.0, *)
    private func judge(_ song: Song) async -> Mood? {
        let full = Self.prompt(for: song, withLyrics: true)
        if let mood = await ask(full) { return mood }
        // Le filtre d'Apple refuse souvent des paroles (mort, violence…) ; le type d'erreur change entre iOS 26 et 27, donc on retente sans elles.
        let bare = Self.prompt(for: song, withLyrics: false)
        guard bare != full, !Task.isCancelled else { return nil }
        return await ask(bare)
    }

    @available(iOS 26.0, *)
    private func ask(_ prompt: String) async -> Mood? {
        // Une session neuve par morceau : le contexte du précédent ne doit ni influencer ni remplir le suivant.
        let session = LanguageModelSession(instructions: Self.instructions)
        do {
            let answer = try await session.respond(to: prompt, generating: MoodJudgement.self).content
            // Le guide contraint déjà la sortie ; on revérifie pour ne jamais garder un mot hors liste.
            var tags: [String] = []
            for tag in answer.tags where Self.vocabulary.contains(tag) && !tags.contains(tag) { tags.append(tag) }
            guard !tags.isEmpty else { return nil }
            return Mood(energy: min(max(answer.energy, 1), 5), tags: Array(tags.prefix(3)))
        } catch {
            return nil
        }
    }

    private static let instructions = """
        Tu juges l'énergie et l'ambiance d'une chanson connue, d'après son titre, son artiste et le début de ses paroles.
        Énergie : 1 = très calme (ballade douce), 3 = modérée, 5 = très énergique (rock rapide, morceau à danser).
        Choisis une à trois ambiances dans la liste proposée, les plus justes d'abord.
        Si tu ne connais pas la chanson, juge d'après le titre et les paroles.
        """

    private static func prompt(for song: Song, withLyrics: Bool) -> String {
        // Les accords et les titres de section ne disent rien de l'ambiance et prendraient la place des paroles.
        let lyrics = (song.text ?? "").components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !Chords.isChordLine($0) && !Chords.isSection($0) }
            .joined(separator: "\n")
        var prompt = "Titre : \(song.title)\nArtiste : \(song.artist)"
        if withLyrics, !lyrics.isEmpty { prompt += "\nDébut des paroles :\n\(lyrics.prefix(400))" }
        return prompt
    }

    private func save() {
        if let data = try? JSONEncoder().encode(moods) {
            try? data.write(to: file, options: .atomic)
        }
    }
}

@available(iOS 26.0, *)
@Generable(description: "Énergie et ambiance d'une chanson")
private struct MoodJudgement {
    @Guide(description: "Énergie de 1 (très calme) à 5 (très énergique)", .range(1...5))
    var energy: Int

    @Guide(description: "Une à trois ambiances", .count(1...3), .element(.anyOf(Moods.vocabulary)))
    var tags: [String]
}

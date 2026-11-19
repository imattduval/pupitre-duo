import Foundation

/// Énergie et ambiance d'un morceau. À part de Moods.swift pour que les suggestions se testent sur Mac sans FoundationModels.
struct Mood: Codable, Equatable {
    /// 1 (très calme) … 5 (très énergique).
    var energy: Int
    /// Une à trois ambiances prises dans Moods.vocabulary.
    var tags: [String]
}

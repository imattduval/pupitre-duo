import SwiftUI

@main
struct PupitreApp: App {
    // Gardés ici, pas dans une vue racine : Library() relit (et parfois réécrit) ses fichiers à chaque création.
    @State private var library = Library()
    @State private var workList = WorkList()
    @State private var concerts = Concerts()
    @State private var offline = OfflineLoader()
    @State private var favorites = Favorites()
    @State private var transitions = PlayTransitions()
    @State private var moods = Moods()
    @State private var backup = Backup()
    /// Change après une restauration : toute la liste repart de zéro avec les stores relus.
    @State private var generation = 0
    @State private var backupSheet = BackupSheet()
    @State private var moodTask: Task<Void, Never>?
    /// Morceaux déjà soumis au modèle depuis le lancement : un refus n'est pas retenté en boucle.
    @State private var moodsTried: Set<String> = []
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .id(generation)
                .environment(library)
                .environment(workList)
                .environment(concerts)
                .environment(offline)
                .environment(favorites)
                .environment(transitions)
                .environment(moods)
                .environment(backup)
                .environment(backupSheet)
                // À la racine, hors de la liste recréée : la feuille reste ouverte et montre le résultat de la restauration.
                .sheet(isPresented: $backupSheet.isShown) {
                    BackupView(onRestored: reloadStores).environment(backup)
                }
                .preferredColorScheme(.dark)
                .tint(Palette.chord)
                // Au piano, l'écran ne doit jamais s'éteindre tant que l'app est ouverte.
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = true
                    restartMoodAnalysis(active: scenePhase == .active)
                }
                .onChange(of: scenePhase) { _, phase in
                    UIApplication.shared.isIdleTimerDisabled = phase == .active
                    // Quitter l'app met la sauvegarde à jour ; rien ne part sans dossier choisi ni pendant une pause.
                    if phase == .background { backup.saveIfConfigured() }
                    restartMoodAnalysis(active: phase == .active)
                }
        }
    }

    /// Après une restauration : chaque store relit les fichiers restaurés.
    private func reloadStores() {
        // Arrêtés d'abord : un chargement ou une analyse en cours réécrirait l'ancien état par-dessus.
        offline.stop()
        moodTask?.cancel()
        moodTask = nil
        library = Library()
        workList = WorkList()
        concerts = Concerts()
        favorites = Favorites()
        transitions = PlayTransitions()
        moods = Moods()
        moodsTried = []
        generation += 1
        restartMoodAnalysis(active: scenePhase == .active)
    }

    /// Une seule analyse de fond, seulement au premier plan : arrêtée en quittant, relancée au retour.
    private func restartMoodAnalysis(active: Bool) {
        moodTask?.cancel()
        moodTask = nil
        guard active else { return }
        moodTask = Task { await analyzeMoods() }
    }

    /// Note un par un les morceaux prêts sans ambiance ; le modèle tourne hors du fil principal.
    private func analyzeMoods() async {
        while !Task.isCancelled {
            // Deux analyses à la fois se coupent (le dernier appel gagne) : celle du lecteur passe d'abord.
            if moods.isAnalyzing {
                try? await Task.sleep(for: .seconds(2))
                continue
            }
            guard let song = library.songs.first(where: {
                $0.isReady && moods.mood(for: $0.url) == nil && !moodsTried.contains($0.url)
            }) else { return }
            await moods.analyze([song])
            // Apple Intelligence coupée ou modèle pas encore prêt : on réessaiera au prochain retour.
            guard !Task.isCancelled, moods.isAvailable else { return }
            moodsTried.insert(song.url)
        }
    }
}

/// Ouverture de la feuille de sauvegarde, tenue à la racine de l'app, au-dessus de la liste.
@Observable final class BackupSheet {
    var isShown = false
}

enum Palette {
    static let background = Color(red: 0.067, green: 0.071, blue: 0.078)
    static let panel = Color(red: 0.106, green: 0.114, blue: 0.129)
    static let chord = Color(red: 1.0, green: 0.784, blue: 0.361)
    /// Aplats des boutons : moins lumineux que le jaune des accords, pour ne pas éblouir dans le noir.
    static let button = Color(red: 0.80, green: 0.60, blue: 0.24)
    static let section = Color(red: 0.498, green: 0.714, blue: 1.0)
}

import SwiftUI

@main
struct PupitreApp: App {
    @State private var library = Library()
    @State private var workList = WorkList()
    @State private var concerts = Concerts()
    @State private var offline = OfflineLoader()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(library)
                .environment(workList)
                .environment(concerts)
                .environment(offline)
                .preferredColorScheme(.dark)
                .tint(Palette.chord)
                // Au piano, l'écran ne doit jamais s'éteindre tant que l'app est ouverte.
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
                .onChange(of: scenePhase) { _, phase in
                    UIApplication.shared.isIdleTimerDisabled = phase == .active
                }
        }
    }
}

enum Palette {
    static let background = Color(red: 0.067, green: 0.071, blue: 0.078)
    static let panel = Color(red: 0.106, green: 0.114, blue: 0.129)
    static let chord = Color(red: 1.0, green: 0.784, blue: 0.361)
    /// Aplats des boutons : moins lumineux que le jaune des accords, pour ne pas éblouir dans le noir.
    static let button = Color(red: 0.80, green: 0.60, blue: 0.24)
    static let section = Color(red: 0.498, green: 0.714, blue: 1.0)
}

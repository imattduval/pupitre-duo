import SwiftUI

@main
struct PupitreApp: App {
    @State private var library = Library()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(library)
                .preferredColorScheme(.dark)
                .tint(Palette.chord)
        }
    }
}

enum Palette {
    static let background = Color(red: 0.067, green: 0.071, blue: 0.078)
    static let panel = Color(red: 0.106, green: 0.114, blue: 0.129)
    static let chord = Color(red: 1.0, green: 0.784, blue: 0.361)
    static let section = Color(red: 0.498, green: 0.714, blue: 1.0)
}

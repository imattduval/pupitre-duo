import SwiftUI
import UniformTypeIdentifiers

/// Feuille « Sauvegarde iCloud Drive » : choisir le dossier, sauvegarder, restaurer.
struct BackupView: View {
    @Environment(Backup.self) private var backup
    @Environment(\.dismiss) private var dismiss
    @State private var isPickingFolder = false
    @State private var isConfirmingRestore = false
    @State private var isConfirmingSave = false
    @State private var pickerError: String?
    @State private var restoredCount: Int?
    private let onRestored: () -> Void

    init(onRestored: @escaping () -> Void) {
        self.onRestored = onRestored
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Pupitre copie vos morceaux, listes et réglages dans le fichier « \(Backup.fileName) », dans le dossier d'iCloud Drive de votre choix, et le met à jour chaque fois que vous quittez l'app.")
                    Text("Si ce dossier contient déjà une sauvegarde, elle n'est remplacée qu'après une restauration ou une sauvegarde faite à la main.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        status("folder", "Dossier", backup.folderName ?? "Aucun dossier choisi")
                        status("clock", "Dernière sauvegarde",
                               backup.lastSave?.formatted(date: .abbreviated, time: .shortened) ?? "Aucune")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.panel, in: .rect(cornerRadius: 14))

                    if backup.awaitsChoice {
                        Label("\(backup.lastSave == nil ? "" : "Une sauvegarde\(backupDate) est déjà dans ce dossier. ")Sauvegarde automatique en pause : Restaurer la récupère, Sauvegarder maintenant la remplace.",
                              systemImage: "pause.circle.fill")
                            .foregroundStyle(Palette.chord)
                    }

                    if let message = pickerError ?? backup.lastError {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.chord)
                    } else if let restoredCount {
                        Label(restoredCount == 1 ? "1 fichier restauré." : "\(restoredCount) fichiers restaurés.",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Palette.section)
                    }

                    bigButton("Choisir le dossier", icon: "folder", filled: backup.folderName == nil) {
                        pickerError = nil
                        isPickingFolder = true
                    }
                    if backup.folderName != nil {
                        // Après une réinstallation, le bouton plein doit être celui qui récupère, pas celui qui écrase.
                        bigButton("Sauvegarder maintenant", icon: "icloud.and.arrow.up", filled: !backup.awaitsChoice) {
                            if backup.lastSave != nil || backup.awaitsChoice {
                                isConfirmingSave = true
                            } else {
                                save()
                            }
                        }
                        bigButton("Restaurer", icon: "icloud.and.arrow.down", filled: backup.awaitsChoice) {
                            isConfirmingRestore = true
                        }
                    }
                }
                .padding(20)
            }
            .background(Palette.background)
            .navigationTitle("Sauvegarde iCloud Drive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .fileImporter(isPresented: $isPickingFolder, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url):
                    pickerError = nil
                    restoredCount = nil
                    backup.setFolder(url)
                case .failure(let error):
                    pickerError = "Dossier inaccessible : \(error.localizedDescription)"
                }
            }
            .alert("Restaurer la sauvegarde ?", isPresented: $isConfirmingRestore) {
                Button("Remplacer mes données", role: .destructive, action: restore)
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Les morceaux, listes, historique et réglages actuels seront remplacés par ceux de la sauvegarde\(backupDate). Cette action ne peut pas être annulée.")
            }
            .alert("Remplacer la sauvegarde\(backupDate) par les données de cet iPhone ?", isPresented: $isConfirmingSave) {
                Button("Remplacer la sauvegarde", role: .destructive, action: save)
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("La sauvegarde du dossier sera perdue. Cette action ne peut pas être annulée.")
            }
        }
    }

    private var backupDate: String {
        backup.lastSave.map { " du " + $0.formatted(date: .abbreviated, time: .shortened) } ?? ""
    }

    private func save() {
        pickerError = nil
        restoredCount = nil
        backup.saveNow()
    }

    private func restore() {
        pickerError = nil
        do {
            restoredCount = try backup.restore()
            onRestored()
        } catch {
            // Le message lisible est déjà dans backup.lastError, affiché plus haut.
            restoredCount = nil
        }
    }

    private func status(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Palette.chord)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Text(value).font(.headline)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func bigButton(_ title: String, icon: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(filled ? Palette.button : Palette.panel, in: .rect(cornerRadius: 14))
                .foregroundStyle(filled ? Color.black : Palette.chord)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

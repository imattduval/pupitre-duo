import Foundation
import Observation

/// Sauvegarde dans un dossier choisi dans Fichiers (iCloud Drive) : le compte Apple gratuit n'ouvre pas CloudKit.
/// shortcut: lectures et écritures sur le fil principal (quelques Mo de JSON) ; passer en tâche détachée si l'interface gèle.
@MainActor @Observable
final class Backup {
    private(set) var folderName: String? = nil
    private(set) var lastSave: Date? = nil
    private(set) var lastError: String? = nil
    /// Vrai quand une sauvegarde trouvée dans le dossier attend d'être restaurée ou remplacée : l'automatique est en pause.
    private(set) var awaitsChoice = false

    static let fileName = "Pupitre-sauvegarde.json"
    private static let bookmarkKey = "sauvegarde.dossier"
    /// Faux tant qu'une sauvegarde déjà présente dans le dossier n'a été ni restaurée ni remplacée à la main.
    private static let autoKey = "sauvegarde.auto"
    /// Date du fichier juste après notre dernière écriture ou restauration : l'automatique n'écrase qu'un fichier resté tel quel.
    private static let dateKey = "sauvegarde.date"
    private static let defaultsKeys = ["playlists.favorites", "playlist.ouverte"]

    private struct Archive: Codable {
        var version: Int
        var date: Date
        var files: [String: String]
        var defaults: [String: String]
    }

    private enum Failure: LocalizedError {
        case noFolder, unreadable, newerVersion

        var errorDescription: String? {
            switch self {
            case .noFolder: "aucun dossier de sauvegarde choisi."
            case .unreadable: "le fichier de sauvegarde est abîmé ou illisible."
            case .newerVersion: "cette sauvegarde vient d'une version plus récente de Pupitre."
            }
        }
    }

    @ObservationIgnored private var folder: URL?
    private let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale)
            folder = url
            folderName = url.lastPathComponent
            awaitsChoice = !UserDefaults.standard.bool(forKey: Self.autoKey)
            // Signet périmé (dossier déplacé, renommé) : on le refait tant que l'accès marche encore.
            if isStale { try? withFolder { try remember($0) } }
            lastSave = try? withFolder { try fileDate(in: $0) }
        } catch {
            lastError = "Le dossier de sauvegarde n'est plus accessible. Choisissez-le de nouveau."
        }
    }

    func setFolder(_ url: URL) {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        do {
            try remember(url)
        } catch {
            lastError = "Impossible de retenir ce dossier : \(error.localizedDescription)"
            return
        }
        folder = url
        folderName = url.lastPathComponent
        lastError = nil
        do {
            lastSave = try withFolder { try fileDate(in: $0) }
        } catch let error as CocoaError where [.fileReadNoSuchFile, .fileNoSuchFile].contains(error.code) {
            lastSave = nil
        } catch {
            // Lecture ratée (accès, iCloud pas prêt) : une sauvegarde est peut-être là, on n'écrit rien.
            lastSave = nil
            setAuto(false)
            lastError = "Impossible de lire ce dossier : \(Self.message(for: error))"
            return
        }
        // Une sauvegarde existe déjà (réinstallation) : rien d'automatique ne l'écrase avant restauration ou sauvegarde voulue.
        if lastSave != nil {
            setAuto(false)
        } else {
            setAuto(true)
            // Sans .atomic : Foundation refuse .withoutOverwriting avec .atomic ; ici il protège un fichier apparu entre-temps.
            save(options: .withoutOverwriting)
        }
    }

    func saveNow() { save(options: .atomic) }

    private func save(options: Data.WritingOptions) {
        do {
            let files = try documentFiles()
            // Dossier Documents vide : on garde la bonne sauvegarde plutôt que d'y écrire du vide.
            guard !files.isEmpty else {
                lastError = "Rien à sauvegarder pour l'instant : la sauvegarde existante est conservée."
                return
            }
            var defaults: [String: String] = [:]
            for key in Self.defaultsKeys {
                if let value = UserDefaults.standard.string(forKey: key) { defaults[key] = value }
            }
            let archive = Archive(version: 1, date: .now, files: files, defaults: defaults)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(archive)
            try withFolder { folder in
                try coordinatedWrite(folder.appending(path: Self.fileName)) { try data.write(to: $0, options: options) }
            }
            lastSave = archive.date
            lastError = nil
            noteFileDate()
            setAuto(true)
        } catch {
            if (error as? CocoaError)?.code == .fileWriteFileExists {
                // Une sauvegarde est arrivée pendant le choix du dossier : elle aussi attend restauration ou remplacement.
                setAuto(false)
                lastSave = try? withFolder { try fileDate(in: $0) }
            }
            lastError = "Sauvegarde impossible : \(Self.message(for: error))"
        }
    }

    func saveIfConfigured() {
        guard folder != nil, UserDefaults.standard.bool(forKey: Self.autoKey) else { return }
        do {
            let date = try withFolder { try fileDate(in: $0) }
            // Changé depuis notre dernière écriture (autre appareil, téléphone restauré, Drive en retard) : on ne l'écrase pas.
            guard date == UserDefaults.standard.object(forKey: Self.dateKey) as? Date else {
                setAuto(false)
                lastSave = date
                lastError = "La sauvegarde du dossier a changé ailleurs : restaurez-la ou remplacez-la."
                return
            }
        } catch let error as CocoaError where [.fileReadNoSuchFile, .fileNoSuchFile].contains(error.code) {
            // Fichier supprimé du dossier : rien à écraser.
        } catch {
            lastError = "Sauvegarde impossible : \(Self.message(for: error))"
            return
        }
        saveNow()
    }

    func restore() throws -> Int {
        var wrote = false
        do {
            let data = try withFolder { folder in
                try coordinatedRead(folder.appending(path: Self.fileName)) { try Data(contentsOf: $0) }
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let archive = try? decoder.decode(Archive.self, from: data) else { throw Failure.unreadable }
            guard archive.version <= 1 else { throw Failure.newerVersion }
            let files = archive.files.filter { Self.isSafeName($0.key) }
            // Une sauvegarde sans fichier viderait tout le téléphone, maintenant que l'absent est effacé.
            guard !files.isEmpty else { throw Failure.unreadable }
            // Tout vérifier avant d'écrire : un fichier abîmé ferait repartir un store à vide.
            for text in files.values {
                guard (try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)) != nil else {
                    throw Failure.unreadable
                }
            }
            for (name, text) in files {
                try Data(text.utf8).write(to: documents.appending(path: name), options: .atomic)
                wrote = true
            }
            // Tout est remplacé : un fichier ou un réglage absent de la sauvegarde n'existait pas encore, il part aussi.
            for url in try FileManager.default.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil)
            where url.pathExtension == "json" && files[url.lastPathComponent] == nil {
                try FileManager.default.removeItem(at: url)
            }
            for key in Self.defaultsKeys {
                if let value = archive.defaults[key] {
                    UserDefaults.standard.set(value, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
            lastSave = archive.date
            lastError = nil
            noteFileDate()
            setAuto(true)
            return files.count
        } catch {
            // Restauration à moitié écrite : ce mélange ne part pas dans le dossier, la sauvegarde y reste à restaurer.
            if wrote { setAuto(false) }
            lastError = "Restauration impossible : \(Self.message(for: error))"
            throw error
        }
    }

    /// Nom de fichier simple seulement : la sauvegarde vient d'un dossier partagé, elle ne doit rien écrire ailleurs.
    static func isSafeName(_ name: String) -> Bool {
        name.hasSuffix(".json") && !name.hasPrefix(".")
            && !name.contains("/") && !name.contains("\\") && !name.contains("\0")
    }

    // MARK: - Fichiers

    private func documentFiles() throws -> [String: String] {
        var files: [String: String] = [:]
        for url in try FileManager.default.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil)
        where url.pathExtension == "json" {
            if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
                files[url.lastPathComponent] = text
            }
        }
        return files
    }

    /// L'état affiché et l'état relu au prochain lancement restent toujours d'accord.
    private func setAuto(_ on: Bool) {
        awaitsChoice = !on
        UserDefaults.standard.set(on, forKey: Self.autoKey)
    }

    /// Sans date relue, rien n'est retenu : l'automatique s'arrêtera plutôt que d'écraser à l'aveugle.
    private func noteFileDate() {
        UserDefaults.standard.set(try? withFolder { try fileDate(in: $0) }, forKey: Self.dateKey)
    }

    private func remember(_ url: URL) throws {
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
    }

    /// Date de la sauvegarde présente dans le dossier, sans la télécharger depuis iCloud.
    private func fileDate(in folder: URL) throws -> Date? {
        try coordinatedRead(folder.appending(path: Self.fileName), options: .immediatelyAvailableMetadataOnly) {
            try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
    }

    /// L'accès au dossier choisi n'est ouvert que le temps d'une lecture ou d'une écriture.
    private func withFolder<T>(_ body: (URL) throws -> T) throws -> T {
        guard let folder else { throw Failure.noFolder }
        let granted = folder.startAccessingSecurityScopedResource()
        defer { if granted { folder.stopAccessingSecurityScopedResource() } }
        return try body(folder)
    }

    /// iCloud Drive peut synchroniser le fichier au même moment : la coordination évite de lire ou d'écrire à moitié.
    private func coordinatedRead<T>(_ url: URL, options: NSFileCoordinator.ReadingOptions = [],
                                    _ body: (URL) throws -> T) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: options, error: &coordinationError) { url in
            result = Result { try body(url) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }

    private func coordinatedWrite(_ url: URL, _ body: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { url in
            result = Result { try body(url) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        try result.get()
    }

    private static func message(for error: Error) -> String {
        if let error = error as? CocoaError, [.fileReadNoSuchFile, .fileNoSuchFile].contains(error.code) {
            return "aucune sauvegarde dans ce dossier."
        }
        if let error = error as? CocoaError, error.code == .fileWriteFileExists {
            return "une sauvegarde est apparue dans ce dossier entre-temps : restaurez-la ou remplacez-la."
        }
        if let error = error as? CocoaError, error.code == .fileWriteOutOfSpace {
            return "plus de place dans iCloud Drive."
        }
        return error.localizedDescription
    }
}

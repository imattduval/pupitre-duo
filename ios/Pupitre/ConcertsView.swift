import SwiftUI

/// Les programmes de concert : morceaux dans l'ordre de la soirée, lancés d'un seul geste.
struct ConcertsView: View {
    @Environment(Concerts.self) private var concerts
    @Environment(\.dismiss) private var dismiss
    let onStart: (Concert) -> Void

    @State private var path: [UUID] = []
    @State private var isCreating = false
    @State private var name = ""

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(concerts.all) { concert in
                    NavigationLink(value: concert.id) {
                        HStack {
                            Text(concert.name).font(.headline)
                            Spacer()
                            Text("\(concert.urls.count)").foregroundStyle(.secondary).monospacedDigit()
                        }
                        .frame(minHeight: 52)
                    }
                }
                .onDelete { offsets in
                    offsets.map { concerts.all[$0].id }.forEach(concerts.delete)
                }
            }
            .overlay {
                if concerts.all.isEmpty {
                    ContentUnavailableView("Aucun concert",
                                           systemImage: "list.number",
                                           description: Text("Crée un concert, ajoute ses morceaux dans l'ordre de la soirée, puis lance-le."))
                }
            }
            .navigationTitle("Concerts")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { ConcertDetail(id: $0, onStart: onStart) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Nouveau concert", systemImage: "plus") {
                        name = ""
                        isCreating = true
                    }
                }
            }
            .alert("Nouveau concert", isPresented: $isCreating) {
                TextField("Nom du concert", text: $name)
                // On entre tout de suite dans le concert créé pour y ajouter les morceaux.
                Button("Créer") { path.append(concerts.create(name: concerts.uniqueName(name)).id) }
                Button("Annuler", role: .cancel) {}
            }
        }
    }
}

private struct ConcertDetail: View {
    @Environment(Library.self) private var library
    @Environment(Concerts.self) private var concerts
    let id: UUID
    let onStart: (Concert) -> Void

    @State private var isAdding = false
    @State private var isRenaming = false
    @State private var name = ""

    var body: some View {
        if let concert = concerts.all.first(where: { $0.id == id }) {
            // Un dictionnaire par affichage plutôt qu'une recherche dans toute la bibliothèque par ligne.
            let byURL = Dictionary(library.songs.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
            List {
                Section {
                    Button {
                        onStart(concert)
                    } label: {
                        Label("Commencer le concert", systemImage: "play.fill")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .background(Palette.button, in: .rect(cornerRadius: 14))
                            .foregroundStyle(.black)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(!concert.urls.contains { byURL[$0] != nil })
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                Section {
                    // Les positions suivent concert.urls, comme remove(at:) et move(from:) les attendent.
                    ForEach(Array(concert.urls.enumerated()), id: \.element) { index, url in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.title3.bold()).monospacedDigit()
                                .foregroundStyle(Palette.chord)
                                .frame(minWidth: 32, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(byURL[url]?.title ?? "Retiré de la bibliothèque").font(.headline)
                                if let artist = byURL[url]?.artist, !artist.isEmpty {
                                    Text(artist).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(minHeight: 52)
                    }
                    .onMove { concerts.move(from: $0, to: $1, in: id) }
                    .onDelete { concerts.remove(at: $0, from: id) }
                    Button {
                        isAdding = true
                    } label: {
                        Label("Morceau", systemImage: "plus")
                            .font(.headline)
                            .foregroundStyle(Palette.chord)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(concert.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) { EditButton() }
                ToolbarItem(placement: .primaryAction) {
                    Button("Renommer", systemImage: "pencil") {
                        name = concert.name
                        isRenaming = true
                    }
                }
            }
            .alert("Renommer le concert", isPresented: $isRenaming) {
                TextField("Nom du concert", text: $name)
                Button("Renommer") { concerts.rename(id, to: concerts.uniqueName(name, except: id)) }
                Button("Annuler", role: .cancel) {}
            }
            .sheet(isPresented: $isAdding) { SongPicker(id: id) }
        }
    }
}

/// Toute la bibliothèque, cherchable ; on ajoute plusieurs morceaux d'affilée sans refermer.
private struct SongPicker: View {
    @Environment(Library.self) private var library
    @Environment(Concerts.self) private var concerts
    @Environment(\.dismiss) private var dismiss
    let id: UUID

    @State private var query = ""

    var body: some View {
        let added = Set(concerts.all.first { $0.id == id }?.urls ?? [])
        let songs = query.isEmpty ? library.alphabetical
            : library.alphabetical.filter { ($0.title + " " + $0.artist).localizedStandardContains(query) }
        NavigationStack {
            List(songs) { song in
                let isAdded = added.contains(song.url)
                Button {
                    concerts.add(song.url, to: id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title).font(.headline)
                            if !song.artist.isEmpty {
                                Text(song.artist).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                            .font(.title2)
                            .foregroundStyle(Palette.chord)
                            .accessibilityLabel(isAdded ? "Dans le concert" : "Ajouter")
                    }
                    .frame(minHeight: 52)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Titre ou artiste")
            .navigationTitle("Ajouter au concert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }
}

extension Concerts {
    /// Deux concerts du même nom se confondraient dans les playlists : on les numérote.
    fileprivate func uniqueName(_ raw: String, except id: UUID? = nil) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Concert" : trimmed
        let taken = Set(all.filter { $0.id != id }.map(\.name))
        var candidate = base
        var number = 2
        while taken.contains(candidate) {
            candidate = "\(base) \(number)"
            number += 1
        }
        return candidate
    }
}

import Observation
import UIKit
import WebKit

struct SearchResult: Decodable, Identifiable {
    let url: String
    let title: String
    let artist: String
    let version: Int?
    let rating: Double?
    let votes: Int?

    var id: String { url }
}

struct LoadedSong: Decodable {
    let url: String
    let title: String
    let artist: String
    let text: String
}

enum LoadError: Error {
    /// UG demande une vérification : on montre la page, on ne la contourne pas.
    case needsBrowser
    case failed
}

/// Page web cachée qui charge, à la demande de l'utilisateur, la recherche ou le morceau qu'il a choisi.
/// Elle partage la session du navigateur intégré, donc le compte UG connecté.
@MainActor
@Observable
final class UGLoader {
    private(set) var isBusy = false

    // Très large : UG coupe ses lignes selon la largeur disponible, ce qui décalerait les accords.
    private let webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        return WKWebView(frame: CGRect(x: -3000, y: 0, width: 1500, height: 1000), configuration: configuration)
    }()

    @ObservationIgnored private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Une seule page web : un chargement attend la fin du précédent, sinon il l'interromprait.
    private func oneAtATime<T>(_ work: () async throws -> T) async throws -> T {
        if isBusy { await withCheckedContinuation { waiting.append($0) } }
        isBusy = true
        // isBusy reste vrai pendant la passation : personne ne double la file.
        defer { if waiting.isEmpty { isBusy = false } else { waiting.removeFirst().resume() } }
        try Task.checkCancellation()
        attachIfNeeded()
        return try await work()
    }

    func search(_ query: String) async throws -> [SearchResult] {
        try await oneAtATime {
            try await openSearchOrigin()
            var found = try await searchPages(query)
            // UG exige tous les mots : « La foule sentimentale » trouve mieux sans son article.
            let short = query.replacing(/^(?i)(la|le|les|l'|un|une|the)\s*/, with: "")
            if found.count < 5, short != query, !short.isEmpty {
                let more = try await searchPages(short)
                found += more.filter { item in !found.contains { $0.url == item.url } }
            }
            return found
        }
    }

    private func searchPages(_ query: String) async throws -> [SearchResult] {
        var found: [SearchResult] = []
        for page in 1...2 {
            // Une recherche dépassée par la frappe libère vite la page pour la suivante.
            try Task.checkCancellation()
            let answer = try await webView.callAsyncJavaScript(Self.searchScript,
                                                               arguments: ["q": query, "page": page],
                                                               contentWorld: .page) as? String
            if answer == "blocked" { throw LoadError.needsBrowser }
            guard let answer else { throw LoadError.failed }
            let result = try JSONDecoder().decode(SearchPage.self, from: Data(answer.utf8))
            found += result.results
            if page >= result.pages || found.count >= 25 { break }
        }
        return found
    }

    /// La recherche se fait depuis une page d'UG : ses données disparaissent de la page affichée,
    /// il faut donc relire le document d'origine.
    private func openSearchOrigin() async throws {
        guard webView.url?.host != "www.ultimate-guitar.com" else { return }
        webView.load(URLRequest(url: URL(string: "https://www.ultimate-guitar.com/search.php?search_type=title&value=a")!))
        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(500))
            if webView.url?.host == "www.ultimate-guitar.com", !webView.isLoading { return }
        }
        throw LoadError.failed
    }

    private struct SearchPage: Decodable {
        let pages: Int
        let results: [SearchResult]
    }

    func song(at url: String) async throws -> LoadedSong {
        guard let address = URL(string: url) else { throw LoadError.failed }
        let json = try await oneAtATime { try await run(url: address, script: Self.songScript) }
        return try JSONDecoder().decode(LoadedSong.self, from: Data(json.utf8))
    }

    private func run(url: URL, script: String) async throws -> String {
        webView.load(URLRequest(url: url))
        try await Task.sleep(for: .seconds(1))
        var previous: String?
        for _ in 0..<50 {
            let answer = try? await webView.evaluateJavaScript(script) as? String
            if answer == "blocked" { throw LoadError.needsBrowser }
            // Le texte s'affiche par étapes : on attend qu'il ne bouge plus.
            if let answer, answer == previous { return answer }
            previous = answer
            try await Task.sleep(for: .milliseconds(500))
        }
        throw LoadError.failed
    }

    private func attachIfNeeded() {
        guard webView.superview == nil else { return }
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        window?.addSubview(webView)
    }

    private static let blockCheck = #"if(/just a moment|verify you are human|captcha/i.test(document.title+' '+(document.body?document.body.innerText.slice(0,300):'')))return 'blocked';"#

    private static let searchScript = #"""
    const response = await fetch('/search.php?search_type=title&value=' + encodeURIComponent(q) + '&page=' + page, {credentials: 'include'});
    const html = await response.text();
    const store = new DOMParser().parseFromString(html, 'text/html').querySelector('.js-store');
    if (!store) return /just a moment|verify you are human|captcha/i.test(html) ? 'blocked' : null;
    const data = JSON.parse(store.dataset.content).store.page.data;
    const results = (data.results || []).filter(r => r.type === 'Chords' && r.tab_url).map(r => ({
      url: r.tab_url, title: r.song_name || '', artist: r.artist_name || '',
      version: r.version || null, rating: r.rating || null, votes: r.votes || null
    }));
    return JSON.stringify({pages: (data.pagination && data.pagination.total) || 1, results});
    """#

    private static let songScript = #"""
    (function(){
      \#(blockCheck)
      var m=document.title.match(/^(.*?)\s+(?:CHORDS|TAB)\b.*?\bby\s+(.*?)\s+@/i);
      var info={url:location.href.split('?')[0],title:m?m[1]:document.title,artist:m?m[2]:''};
      var store=document.querySelector('.js-store');
      if(store){try{
        var c=JSON.parse(store.dataset.content).store.page.data.tab_view.wiki_tab.content;
        if(c){info.text=c.replace(/\[\/?(?:ch|tab)\]/g,'').replace(/\r/g,'');return JSON.stringify(info)}
      }catch(e){}}
      var pre=[].slice.call(document.querySelectorAll('pre')).sort(function(a,b){return b.innerText.length-a.innerText.length})[0];
      if(!pre||pre.innerText.trim().length<20)return null;
      info.text=pre.innerText.replace(/\r/g,'');
      return JSON.stringify(info);
    })()
    """#
}

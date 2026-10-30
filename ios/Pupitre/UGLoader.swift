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

    func search(_ query: String) async throws -> [SearchResult] {
        var parts = URLComponents(string: "https://www.ultimate-guitar.com/search.php")!
        parts.queryItems = [
            URLQueryItem(name: "search_type", value: "title"),
            URLQueryItem(name: "value", value: query),
        ]
        let json = try await run(url: parts.url!, script: Self.searchScript)
        return try JSONDecoder().decode([SearchResult].self, from: Data(json.utf8))
    }

    func song(at url: String) async throws -> LoadedSong {
        guard let address = URL(string: url) else { throw LoadError.failed }
        let json = try await run(url: address, script: Self.songScript)
        return try JSONDecoder().decode(LoadedSong.self, from: Data(json.utf8))
    }

    private func run(url: URL, script: String) async throws -> String {
        isBusy = true
        defer { isBusy = false }
        attachIfNeeded()
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
    (function(){
      \#(blockCheck)
      var out=[];
      var store=document.querySelector('.js-store');
      if(store){try{
        var results=JSON.parse(store.dataset.content).store.page.data.results||[];
        results.forEach(function(r){
          if(r.type==='Chords'&&r.tab_url)out.push({url:r.tab_url,title:r.song_name||'',artist:r.artist_name||'',version:r.version||null,rating:r.rating||null,votes:r.votes||null});
        });
        return JSON.stringify(out);
      }catch(e){}}
      var seen={};
      [].slice.call(document.querySelectorAll('a[href*="tabs.ultimate-guitar.com/tab/"]')).forEach(function(a){
        var u=a.href.split('?')[0];
        if(seen[u]||!/-chords-\d+$/.test(u))return;seen[u]=1;
        var slug=(u.split('/tab/')[1]||'').split('/')[0].replace(/-/g,' ').replace(/\b\w/g,function(c){return c.toUpperCase()});
        out.push({url:u,title:a.innerText.trim(),artist:slug,version:null,rating:null,votes:null});
      });
      return out.length?JSON.stringify(out):null;
    })()
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

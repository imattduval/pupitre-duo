import SwiftUI
import WebKit

struct ImportedLink: Decodable {
    let url: String
    let title: String
    let artist: String
}

/// Navigateur intégré : l'import lit seulement la page que l'utilisateur a ouverte, quand il touche le bouton.
struct BrowserView: View {
    @Environment(Library.self) private var library
    @Environment(UGLoader.self) private var loader
    @Environment(\.dismiss) private var dismiss
    let start: URL

    @State private var page = PageController()
    @State private var message: String?
    @State private var lastImported: String?

    var body: some View {
        NavigationStack {
            WebContainer(page: page, start: start)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Ultimate Guitar")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button("Retour", systemImage: "chevron.left") { page.webView.goBack() }
                        Spacer()
                        if let next = library.nextToImport(after: lastImported), lastImported != nil {
                            Button("Suivant") {
                                if let url = URL(string: next.url) { page.webView.load(URLRequest(url: url)) }
                            }
                        }
                        Button("Importer") { Task { await importPage() } }
                            .buttonStyle(.borderedProminent)
                            .foregroundStyle(.black)
                    }
                }
                .overlay(alignment: .top) {
                    if let message {
                        Text(message)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(.black, in: .rect(cornerRadius: 12))
                            .padding(.top, 8)
                    }
                }
        }
    }

    private func importPage() async {
        guard let result = try? await page.webView.evaluateJavaScript(Self.reader) as? String,
              let data = result.data(using: .utf8),
              let page = try? JSONDecoder().decode(ReadPage.self, from: data) else {
            show("Ouvre un morceau ou une playlist.")
            return
        }
        if let text = page.text, !text.isEmpty, let url = page.url {
            // Relu dans la vue large : ici, la page est étroite et ses lignes sont coupées.
            guard let loaded = try? await loader.song(at: url) else {
                show("Chargement impossible. Réessaie.")
                return
            }
            library.store(url: url, title: loaded.title, artist: loaded.artist, text: loaded.text)
            lastImported = url
            show("« \(loaded.title) » importé")
        } else if let list = page.list, !list.isEmpty {
            let added = library.addList(list)
            show("\(added) morceaux ajoutés à la liste")
        } else {
            show("Rien à importer sur cette page.")
        }
    }

    private func show(_ text: String) {
        message = text
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if message == text { message = nil }
        }
    }

    private struct ReadPage: Decodable {
        let url: String?
        let title: String?
        let artist: String?
        let text: String?
        let list: [ImportedLink]?
    }

    private static let reader = #"""
    (function(){
      var links=[].slice.call(document.querySelectorAll('a[href*="tabs.ultimate-guitar.com/tab/"]'));
      var pre=[].slice.call(document.querySelectorAll('pre')).sort(function(a,b){return b.innerText.length-a.innerText.length})[0];
      if(/\/tab\//.test(location.pathname)&&pre){
        var m=document.title.match(/^(.*?)\s+(?:CHORDS|TAB)\b.*?\bby\s+(.*?)\s+@/i);
        return JSON.stringify({url:location.href.split('?')[0],title:m?m[1]:document.title,artist:m?m[2]:'',text:pre.innerText.replace(/\r/g,'')});
      }
      var seen={},list=[];
      links.forEach(function(a){
        var u=a.href.split('?')[0];if(seen[u])return;seen[u]=1;
        var t=a.innerText.trim(),artist='',p=a.parentElement;
        while(p&&p!==document.body&&!artist){
          var x=p.innerText.split('\n').map(function(s){return s.trim()}).filter(Boolean);
          if(x.length>1&&x.indexOf(t)>0)artist=x[x.indexOf(t)-1];
          p=p.parentElement;
          if(p&&p.querySelectorAll('a[href*="/tab/"]').length>1)break;
        }
        list.push({url:u,title:t,artist:artist});
      });
      return JSON.stringify({list:list});
    })()
    """#
}

@Observable
final class PageController {
    let webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        return WKWebView(frame: .zero, configuration: configuration)
    }()
}

private struct WebContainer: UIViewRepresentable {
    let page: PageController
    let start: URL

    func makeUIView(context: Context) -> WKWebView {
        page.webView.allowsBackForwardNavigationGestures = true
        page.webView.load(URLRequest(url: start))
        return page.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

import SwiftUI
import WebKit
import Combine

private let safariTestUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Mobile/15E148 Safari/604.1"

struct BrowserBookmark: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var url: String
}

struct BrowserHistoryItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var url: String
    var date: Date = Date()
}

final class BrowserTab: ObservableObject, Identifiable {
    let id = UUID()
    let webView: WKWebView
    @Published var urlString = ""
    @Published var title = "Start Page"
    @Published var isLoading = false
    @Published var progress = 0.0
    @Published var canGoBack = false
    @Published var canGoForward = false

    init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = safariTestUserAgent
    }
}

final class SafariViewModel: ObservableObject {
    @Published var tabs: [BrowserTab] = []
    @Published var selectedTabID: UUID?
    @Published var bookmarks: [BrowserBookmark] = []
    @Published var history: [BrowserHistoryItem] = []
    @Published var downloadedFiles: [String] = []
    @Published var showingLibrary = false
    @Published var libraryMode: LibraryMode = .bookmarks

    enum LibraryMode: String, CaseIterable { case bookmarks = "Bookmarks", history = "History", downloads = "Downloads", tabs = "Tabs" }

    var currentTab: BrowserTab? { tabs.first { $0.id == selectedTabID } }

    init() {
        if let data = UserDefaults.standard.data(forKey: "browser.bookmarks"), let saved = try? JSONDecoder().decode([BrowserBookmark].self, from: data) { bookmarks = saved }
        if let data = UserDefaults.standard.data(forKey: "browser.history"), let saved = try? JSONDecoder().decode([BrowserHistoryItem].self, from: data) { history = saved }
        newTab()
    }

    func newTab(url: String? = nil) {
        let tab = BrowserTab()
        tabs.append(tab)
        selectedTabID = tab.id
        if let url { load(url, in: tab) }
    }
    func select(_ tab: BrowserTab) { selectedTabID = tab.id; showingLibrary = false }
    func close(_ tab: BrowserTab) {
        tabs.removeAll { $0.id == tab.id }
        if selectedTabID == tab.id { selectedTabID = tabs.last?.id }
        if tabs.isEmpty { newTab() }
    }
    func load(_ input: String, in tab: BrowserTab? = nil) {
        guard let tab = tab ?? currentTab else { return }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let destination: URL?
        if text.contains("://") { destination = URL(string: text) }
        else if text.contains(".") && !text.contains(" ") { destination = URL(string: "https://" + text) }
        else {
            var c = URLComponents(string: "https://www.google.com/search")
            c?.queryItems = [URLQueryItem(name: "q", value: text)]
            destination = c?.url
        }
        guard let url = destination else { return }
        tab.urlString = url.absoluteString
        tab.webView.customUserAgent = safariTestUserAgent
        tab.webView.load(URLRequest(url: url))
        showingLibrary = false
    }
    func goBack() { currentTab?.webView.goBack() }
    func goForward() { currentTab?.webView.goForward() }
    func reload() { currentTab?.webView.reload() }
    func stop() { currentTab?.webView.stopLoading() }
    func addBookmark() {
        guard let tab = currentTab, let url = tab.webView.url?.absoluteString else { return }
        if !bookmarks.contains(where: { $0.url == url }) {
            bookmarks.insert(BrowserBookmark(title: tab.title.isEmpty ? url : tab.title, url: url), at: 0)
            save(bookmarks, key: "browser.bookmarks")
        }
    }
    func removeBookmark(_ item: BrowserBookmark) { bookmarks.removeAll { $0.id == item.id }; save(bookmarks, key: "browser.bookmarks") }
    func record(_ tab: BrowserTab) {
        guard let url = tab.webView.url?.absoluteString, url != "about:blank" else { return }
        history.removeAll { $0.url == url }
        history.insert(BrowserHistoryItem(title: tab.webView.title ?? url, url: url), at: 0)
        if history.count > 300 { history = Array(history.prefix(300)) }
        save(history, key: "browser.history")
        tab.urlString = url
        tab.title = tab.webView.title ?? url
        tab.canGoBack = tab.webView.canGoBack
        tab.canGoForward = tab.webView.canGoForward
    }
    func save<T: Encodable>(_ value: T, key: String) { if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) } }
}

struct SafariView: View {
    @StateObject private var model = SafariViewModel()
    @State private var addressText = ""
    @State private var editingAddress = false
    @State private var showShare = false
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "textformat.size").foregroundStyle(.secondary)
                if editingAddress {
                    TextField("Search or enter website", text: $addressText)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.go).focused($addressFocused)
                        .onSubmit { model.load(addressText); editingAddress = false; addressFocused = false }
                } else {
                    Button { addressText = model.currentTab?.urlString ?? ""; editingAddress = true; addressFocused = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: model.currentTab?.webView.url == nil ? "magnifyingglass" : "lock.fill").font(.caption2)
                            Text(addressLabel).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .center)
                    }.buttonStyle(.plain)
                }
                Button { model.currentTab?.isLoading == true ? model.stop() : model.reload() } label: {
                    Image(systemName: model.currentTab?.isLoading == true ? "xmark" : "arrow.clockwise")
                }
            }
            .font(.system(size: 16)).padding(.horizontal, 14).frame(height: 46)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 12).padding(.vertical, 7)

            if let tab = model.currentTab, tab.isLoading {
                ProgressView(value: tab.progress).tint(.blue).padding(.horizontal, 12)
            }

            ZStack {
                if model.showingLibrary { libraryView }
                else if let tab = model.currentTab {
                    SafariWebViewRepresentable(tab: tab, onFinish: { model.record(tab) })
                } else { startPage }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)

            if !editingAddress {
                HStack {
                    Button { model.goBack() } label: { Image(systemName: "chevron.backward") }
                        .disabled(!(model.currentTab?.canGoBack ?? false))
                    Spacer()
                    Button { model.goForward() } label: { Image(systemName: "chevron.forward") }
                        .disabled(!(model.currentTab?.canGoForward ?? false))
                    Spacer()
                    Button { showShare = true } label: { Image(systemName: "square.and.arrow.up") }
                    Spacer()
                    Button { model.addBookmark() } label: { Image(systemName: "book") }
                    Spacer()
                    Button { model.libraryMode = .tabs; model.showingLibrary = true } label: {
                        ZStack { RoundedRectangle(cornerRadius: 5).stroke(lineWidth: 1.5).frame(width: 23, height: 22); Text("\(model.tabs.count)").font(.system(size: 11, weight: .semibold)) }
                    }
                }
                .font(.system(size: 20, weight: .medium)).buttonStyle(.plain).foregroundStyle(.blue)
                .padding(.horizontal, 24).padding(.vertical, 12).background(.ultraThinMaterial)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showShare) {
            if let url = model.currentTab?.webView.url { ShareSheet(items: [url]) }
        }
        // Handles an incoming HTTP/HTTPS URL when iOS routes one to this app.
        // This handler does not grant the restricted default-browser entitlement.
        .onOpenURL { url in
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
            if model.currentTab == nil {
                model.newTab(url: url.absoluteString)
            } else {
                model.load(url.absoluteString, in: model.currentTab)
            }
            addressText = url.absoluteString
            editingAddress = false
        }
    }

    private var addressLabel: String {
        guard let tab = model.currentTab, !tab.urlString.isEmpty, let url = URL(string: tab.urlString) else { return "Search or enter website" }
        return url.host ?? tab.urlString
    }

    private var startPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("Start Page").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Button { } label: { Image(systemName: "ellipsis.circle").foregroundStyle(.secondary) }
                }.padding(.horizontal, 18).padding(.top, 12)

                VStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.22, green: 0.22, blue: 0.25))
                        HStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.93, green: 0.45, blue: 0.47)).frame(width: 52, height: 78).rotationEffect(.degrees(-8)).offset(x: 9, y: 4)
                            RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.42, green: 0.47, blue: 0.95)).frame(width: 58, height: 90).offset(y: -2)
                            RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.95, green: 0.64, blue: 0.67)).frame(width: 52, height: 78).rotationEffect(.degrees(8)).offset(x: -9, y: 4)
                        }
                        VStack {
                            Spacer()
                            Text("Favourites").font(.system(size: 10, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 4).background(.ultraThinMaterial, in: Capsule())
                            Text("Suggestions").font(.system(size: 10)).padding(.horizontal, 8).padding(.vertical, 4).background(.ultraThinMaterial, in: Capsule())
                        }.padding(.bottom, 7)
                    }.frame(height: 112)
                    Text("Customise your wallpaper and sections that appear when creating new tabs.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button { } label: {
                        Text("Customise Start Page").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 34).background(Color.blue, in: Capsule())
                    }
                }.padding(14).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22)).padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("Favourites").font(.system(size: 19, weight: .bold)); Spacer(); Button("Show All ›") { model.libraryMode = .bookmarks; model.showingLibrary = true }.font(.system(size: 12)).foregroundStyle(.blue) }.padding(.horizontal, 18)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 18) {
                        ForEach(FavoritesData.list) { item in
                            Button { model.load(item.url) } label: {
                                VStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 13).fill(Color(uiColor: .secondarySystemBackground)).frame(width: 52, height: 52)
                                        .overlay(Image(systemName: item.icon).font(.system(size: 25, weight: .medium)).foregroundStyle(item.color))
                                    Text(item.name).font(.system(size: 11)).foregroundStyle(.primary).lineLimit(1)
                                }.frame(maxWidth: .infinity)
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 12)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Privacy Report").font(.system(size: 19, weight: .bold))
                    HStack(spacing: 12) {
                        Image(systemName: "hand.raised.fill").font(.system(size: 22)).foregroundStyle(.secondary)
                        Text("Safari helps prevent trackers from profiling you as you browse.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }.padding(14).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                }.padding(.horizontal, 16)
                Spacer(minLength: 22)
            }.padding(.bottom, 18)
        }
        .background(Color(uiColor: .systemBackground))
    }

    private func quickButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { VStack(spacing: 8) { Image(systemName: icon).font(.title2); Text(title).font(.caption) }.frame(maxWidth: .infinity).padding(.vertical, 14).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14)) }.buttonStyle(.plain)
    }

    private var libraryView: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Done") { model.showingLibrary = false }
                Spacer()
                Text(model.libraryMode.rawValue).font(.headline)
                Spacer()
                if model.libraryMode == .tabs { Button { model.newTab(); model.showingLibrary = false } label: { Image(systemName: "plus") } }
                else { Button { model.showingLibrary = false } label: { Image(systemName: "xmark") } }
            }.padding()
            Picker("Library", selection: $model.libraryMode) {
                Text("Bookmarks").tag(SafariViewModel.LibraryMode.bookmarks)
                Text("History").tag(SafariViewModel.LibraryMode.history)
                Text("Downloads").tag(SafariViewModel.LibraryMode.downloads)
                Text("Tabs").tag(SafariViewModel.LibraryMode.tabs)
            }.pickerStyle(.segmented).padding(.horizontal)
            List {
                switch model.libraryMode {
                case .bookmarks:
                    ForEach(model.bookmarks) { item in
                        Button { model.load(item.url); model.showingLibrary = false } label: { VStack(alignment: .leading) { Text(item.title).foregroundStyle(.primary); Text(item.url).font(.caption).foregroundStyle(.secondary).lineLimit(1) } }
                            .swipeActions { Button(role: .destructive) { model.removeBookmark(item) } label: { Label("Delete", systemImage: "trash") } }
                    }
                case .history:
                    ForEach(model.history) { item in
                        Button { model.load(item.url); model.showingLibrary = false } label: { VStack(alignment: .leading) { Text(item.title).foregroundStyle(.primary); Text(item.url).font(.caption).foregroundStyle(.secondary).lineLimit(1) } }
                    }
                case .downloads:
                    if model.downloadedFiles.isEmpty { Text("Downloads started from websites will appear here.").foregroundStyle(.secondary) }
                    ForEach(model.downloadedFiles, id: \.self) { Text($0) }
                case .tabs:
                    ForEach(model.tabs) { tab in
                        HStack {
                            Button { model.select(tab) } label: { VStack(alignment: .leading) { Text(tab.title).foregroundStyle(.primary); Text(tab.urlString.isEmpty ? "Start Page" : tab.urlString).font(.caption).foregroundStyle(.secondary).lineLimit(1) } }
                            Spacer()
                            Button { model.close(tab) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        }
                    }
                }
            }.listStyle(.plain)
        }
    }
}

struct SafariWebViewRepresentable: UIViewRepresentable {
    @ObservedObject var tab: BrowserTab
    var onFinish: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(tab: tab, onFinish: onFinish) }
    func makeUIView(context: Context) -> WKWebView {
        let webView = tab.webView
        webView.customUserAgent = safariTestUserAgent
        webView.navigationDelegate = context.coordinator
        webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
        return webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    final class Coordinator: NSObject, WKNavigationDelegate {
        let tab: BrowserTab
        let onFinish: () -> Void
        init(tab: BrowserTab, onFinish: @escaping () -> Void) { self.tab = tab; self.onFinish = onFinish }
        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
            if keyPath == "estimatedProgress" { DispatchQueue.main.async { self.tab.progress = self.tab.webView.estimatedProgress } }
        }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { self.tab.isLoading = true; self.tab.urlString = webView.url?.absoluteString ?? self.tab.urlString }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.tab.isLoading = false; self.tab.title = webView.title ?? webView.url?.host ?? "Website"
                self.tab.urlString = webView.url?.absoluteString ?? self.tab.urlString
                self.tab.canGoBack = webView.canGoBack; self.tab.canGoForward = webView.canGoForward
                self.onFinish()
            }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { DispatchQueue.main.async { self.tab.isLoading = false } }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { DispatchQueue.main.async { self.tab.isLoading = false } }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct FavoriteItem: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let color: Color
    let url: String
}
struct FavoritesData {
    static let list = [
        FavoriteItem(name: "Apple", icon: "apple.logo", color: .gray, url: "apple.com"),
        FavoriteItem(name: "Yandex", icon: "y.circle.fill", color: .red, url: "yandex.com"),
        FavoriteItem(name: "Bing", icon: "b.circle.fill", color: .cyan, url: "bing.com"),
        FavoriteItem(name: "Google", icon: "g.circle.fill", color: .blue, url: "google.com"),
        FavoriteItem(name: "Wikipedia", icon: "w.circle.fill", color: .gray, url: "wikipedia.org"),
        FavoriteItem(name: "YouTube", icon: "play.rectangle.fill", color: .red, url: "youtube.com"),
        FavoriteItem(name: "Reddit", icon: "r.circle.fill", color: .orange, url: "reddit.com"),
        FavoriteItem(name: "X", icon: "xmark", color: .white, url: "x.com")
    ]
}

#Preview { SafariView() }

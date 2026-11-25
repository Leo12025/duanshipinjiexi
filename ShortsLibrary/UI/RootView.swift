import SwiftUI
import SwiftData
import UIKit

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("shorts.lastClipboardChangeCount") private var lastClipboardChangeCount = 0
    @AppStorage("shorts.lastPromptedLink") private var lastPromptedLink = ""

    @ObservedObject private var login = LoginSessionManager.shared

    @State private var selectedTab = 0
    @State private var homeInput: URL?
    @State private var loginPlatform: PlatformLogin?
    @State private var alertMessage: String?
    @State private var detectedLink: URL?
    @State private var detectedPlatform = ""

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(externalInput: $homeInput, selectedTab: $selectedTab)
                .tabItem {
                    Label("首页", systemImage: "house")
                }
                .tag(0)

            LibraryListView()
                .tabItem {
                    Label("资源库", systemImage: "square.stack.3d.up")
                }
                .tag(1)

            ProfileView()
                .tabItem {
                    Label("我的", systemImage: "person.crop.circle")
                }
                .tag(2)
        }
        .tint(.accentColor)
        .sheet(item: $loginPlatform) { platform in
            PlatformLoginView(platform: platform)
        }
        .alert("提示", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .alert("检测到\(detectedPlatform)链接", isPresented: Binding(
            get: { detectedLink != nil },
            set: { if !$0 { detectedLink = nil } }
        )) {
            Button("忽略", role: .cancel) {}
            Button("去解析") {
                guard let link = detectedLink else { return }
                detectedLink = nil
                homeInput = link
                selectedTab = 0
            }
        } message: {
            Text(detectedLink?.absoluteString ?? "")
        }
        .task {
            LibraryRepository.shared.purgeExpiredTrash(in: modelContext)
            await NotificationService.shared.requestAuthorization()
            await login.refresh()
            checkClipboard()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await login.refresh() }
                checkClipboard()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPlatformLogin)) { output in
            if let platform = output.object as? PlatformLogin {
                loginPlatform = platform
            }
        }
        .onOpenURL { url in
            if let target = Self.extractURL(from: url) {
                homeInput = target
                selectedTab = 0
            } else {
                alertMessage = "无法识别打开的链接"
            }
        }
    }

    private func checkClipboard() {
        let pasteboard = UIPasteboard.general
        guard pasteboard.changeCount != lastClipboardChangeCount else { return }
        lastClipboardChangeCount = pasteboard.changeCount

        guard let text = pasteboard.string,
              let url = LinkExtractor.firstURL(in: text),
              let parser = ParserRegistry.parser(for: url),
              url.absoluteString != lastPromptedLink else { return }

        detectedLink = url
        detectedPlatform = parser.source.displayName
        lastPromptedLink = url.absoluteString
    }

    private static func extractURL(from url: URL) -> URL? {
        if url.scheme?.lowercased() == "shortsaver" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            guard let value = components?.queryItems?.first(where: { $0.name == "url" })?.value,
                  let target = URL(string: value),
                  ["http", "https"].contains(target.scheme?.lowercased() ?? "") else {
                return nil
            }
            return target
        }
        if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            return url
        }
        return nil
    }
}

import SwiftUI
import WebKit

struct PlatformLoginView: View {
    let platform: PlatformLogin

    @ObservedObject private var login = LoginSessionManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if login.states[platform] == true {
                    Label("已检测到登录态", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 6)
                }

                Text("请在此页面手动登录，完成后点“完成”。App 不保存密码，只复用 WebKit Cookie。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                PlatformLoginWebView(url: platform.loginURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                HStack {
                    Button("退出登录") {
                        Task {
                            isBusy = true
                            await login.logout(platform)
                            isBusy = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)

                    Spacer()

                    Button("完成") {
                        Task {
                            await login.refresh()
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("\(platform.displayName)登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

private struct PlatformLoginWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

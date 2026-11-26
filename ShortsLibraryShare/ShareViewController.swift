import UIKit
import Social
import UniformTypeIdentifiers

final class ShareViewController: SLComposeServiceViewController {
    private var incomingText: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "短视频资料库"
        placeholder = "粘贴分享文案或链接"
        loadIncomingContent()
    }

    override func isContentValid() -> Bool {
        let text = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty || !(incomingText ?? "").isEmpty
    }

    override func didSelectPost() {
        let typed = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = typed.isEmpty ? (incomingText ?? "") : typed
        guard !text.isEmpty else {
            finish()
            return
        }

        if let url = LinkExtractor.firstURL(in: text),
           let hostURL = Self.hostURL(for: url) {
            extensionContext?.open(hostURL) { [weak self] opened in
                if !opened { SharedLinkStore.enqueue(text) }
                self?.finish()
            }
        } else {
            SharedLinkStore.enqueue(text)
            finish()
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private static func hostURL(for url: URL) -> URL? {
        var components = URLComponents(string: "shortsaver://")
        components?.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        return components?.url
    }

    override func configurationItems() -> [Any]! {
        []
    }

    private func loadIncomingContent() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }
        for item in items {
            for attachment in item.attachments ?? [] {
                if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] object, _ in
                        let value: String?
                        if let url = object as? URL {
                            value = url.absoluteString
                        } else if let url = object as? NSURL {
                            value = url.absoluteString
                        } else {
                            value = object as? String
                        }
                        DispatchQueue.main.async { self?.applyIncoming(value) }
                    }
                } else if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] object, _ in
                        DispatchQueue.main.async { self?.applyIncoming(object as? String) }
                    }
                }
            }
        }
    }

    private func applyIncoming(_ value: String?) {
        guard let value, !value.isEmpty else { return }
        incomingText = value
        if textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            textView.text = value
        }
        validateContent()
    }
}

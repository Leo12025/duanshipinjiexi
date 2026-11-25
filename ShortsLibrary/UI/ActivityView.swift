import SwiftUI
import UIKit

enum SharePayload {
    static func textAndLink(for item: LibraryItem) -> String {
        let caption = item.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = caption.isEmpty ? title : caption
        guard let link = item.pageURL?.absoluteString, !link.isEmpty else { return text }
        return "\(text)\n\(link)"
    }

    static func textAndLinkItems(for item: LibraryItem) -> [Any] {
        [textAndLink(for: item)]
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        configurePopover(for: controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

    private func configurePopover(for controller: UIActivityViewController) {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }),
              let root = window.rootViewController else { return }

        controller.popoverPresentationController?.sourceView = root.view
        controller.popoverPresentationController?.sourceRect = CGRect(
            x: window.bounds.midX,
            y: window.bounds.midY,
            width: 1,
            height: 1
        )
    }
}

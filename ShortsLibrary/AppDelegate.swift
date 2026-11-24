import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    static weak var shared: AppDelegate?

    var backgroundCompletionHandler: (() -> Void)?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        backgroundCompletionHandler = completionHandler
    }
}

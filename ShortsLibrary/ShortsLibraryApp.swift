import SwiftUI
import SwiftData

@main
struct ShortsLibraryApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [LibraryItem.self, MediaFile.self])
    }
}

import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        Task { @MainActor in Downloads.shared.backgroundCompletion = completionHandler }
    }
}
@main struct WanyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var phase
    init() { RanyTypography.registerFont() }
    var body: some Scene {
        WindowGroup {
            RanyExperience().environment(store).environment(store.downloads)
                .environment(\.layoutDirection,.rightToLeft).preferredColorScheme(.dark).tint(Theme.accent)
                .task { await store.refresh() }
                .onChange(of:phase) { _,phase in
                    if phase == .active { Task { await store.refresh() }; store.downloads.updateNetwork() }
                    else { store.persistNow(); store.downloads.persist() }
                }
        }
    }
}

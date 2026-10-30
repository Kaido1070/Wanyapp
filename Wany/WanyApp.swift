import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        Task { @MainActor in Downloads.shared.backgroundCompletion = completionHandler }
    }
}
@main struct WanyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var store: AppStore
    @Environment(\.scenePhase) private var phase
    init() {
        RanyTypography.registerFont()
        _store=State(initialValue:Self.makeStore())
    }
    private static func makeStore() -> AppStore {
        let preview=ProcessInfo.processInfo.arguments.contains("--rany-cinematic-preview")
        var fixture=ProcessInfo.processInfo.arguments.contains("--rany-opening-fixture")
        #if DEBUG
        fixture = fixture || ProcessInfo.processInfo.arguments.contains("--rany-chapter-controls-fixture") || ProcessInfo.processInfo.arguments.contains("--rany-image-quality-fixture")
        #endif
        let account=AppStore(startServices:!preview && !fixture)
        if preview || fixture {
            account.online=false
            if ProcessInfo.processInfo.arguments.contains("--rany-cinematic-signed-in") {
                account.state=AccountState(user:Account(id:"cinematic-preview-fixture",name:"قارئ Rany",username:"preview"))
            }
        }
        return account
    }
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--rany-image-quality-fixture") { ImageQualityFixture() }
            else if ProcessInfo.processInfo.arguments.contains("--rany-chapter-controls-fixture") { ChapterControlsFixture() }
            else { applicationContent }
            #else
            applicationContent
            #endif
        }
    }
    private var applicationContent: some View {
            Group {
                if ProcessInfo.processInfo.arguments.contains("--rany-cinematic-preview") { CinematicPreview().environment(store) }
                else { RanyExperience().environment(store).environment(store.downloads)
                .environment(\.layoutDirection,.rightToLeft).preferredColorScheme(.dark).tint(Theme.accent)
                .task { if !ProcessInfo.processInfo.arguments.contains("--rany-opening-fixture") { await store.refresh() } }
                .onChange(of:phase) { _,phase in
                    if phase == .active && !ProcessInfo.processInfo.arguments.contains("--rany-opening-fixture") { Task { await store.refresh() }; store.downloads.updateNetwork() }
                    else { store.persistNow(); store.downloads.persist() }
                }
                }
            }
    }
}

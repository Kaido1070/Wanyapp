import Foundation
import UIKit
import UserNotifications
import BackgroundTasks

// Local alerts for new chapters of followed stories. What counts is exactly the
// «أتابعها» list of the New feed: unread chapters released after the story was
// followed. iOS decides when the background check runs, so an alert can arrive
// some time after the chapter is released; nothing is sent while the app shows it.
@MainActor final class NewChapterAlerts: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NewChapterAlerts()
    static let taskIdentifier = "site.wany.reader.new-chapters"
    weak var store: AppStore?
    private let defaults = UserDefaults.standard
    private let enabledKey = "rany.alerts.newChapters"
    private func seenKey(_ owner: String) -> String { "rany.alerts.seen." + owner }
    private func baselineKey(_ owner: String) -> String { "rany.alerts.baseline." + owner }

    var enabled: Bool { defaults.bool(forKey:enabledKey) }

    // Returns false when iOS permission is refused.
    func setEnabled(_ on: Bool) async -> Bool {
        guard on else {
            defaults.set(false,forKey:enabledKey)
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier:Self.taskIdentifier)
            return true
        }
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound,.badge])) ?? false
        guard granted else { defaults.set(false,forKey:enabledKey); return false }
        defaults.set(true,forKey:enabledKey)
        // Chapters already waiting when alerts are switched on are not announced.
        if let owner = store?.state?.user.id { markBaseline(owner:owner) }
        schedule()
        return true
    }
    func permissionDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    func schedule() {
        guard enabled else { return }
        let request = BGAppRefreshTaskRequest(identifier:Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow:20*60)
        try? BGTaskScheduler.shared.submit(request)
    }

    func runBackgroundCheck() async {
        guard enabled else { return }
        schedule()
        guard let store, let owner = store.state?.user.id, store.online, !store.loginRequired else { return }
        guard let feed = try? await store.fetchNewFeedForAlerts(), store.state?.user.id == owner else { return }
        await record(feed,owner:owner,notify:true)
    }
    // The New page was shown in the app: what it lists is already seen.
    func feedShown(_ feed: NewFeed,owner: String) {
        guard enabled else { return }
        Task { await record(feed,owner:owner,notify:false) }
    }

    func markBaseline(owner: String) { defaults.set(true,forKey:baselineKey(owner)) }
    func forget(owner: String) { defaults.removeObject(forKey:seenKey(owner)); defaults.removeObject(forKey:baselineKey(owner)) }
    // Returns how many chapters were announced.
    @discardableResult func record(_ feed: NewFeed,owner: String,notify: Bool) async -> Int {
        var seen = defaults.stringArray(forKey:seenKey(owner)) ?? []
        let known = Set(seen)
        let fresh = feed.followed.flatMap { group in group.chapters.filter { !$0.read && !known.contains(group.id+"|"+$0.id) }.map { (group,$0) } }
        let baseline = defaults.bool(forKey:baselineKey(owner))
        seen += fresh.map { $0.0.id+"|"+$0.1.id }
        defaults.set(Array(seen.suffix(3000)),forKey:seenKey(owner))
        defaults.set(false,forKey:baselineKey(owner))
        guard notify, !baseline, !fresh.isEmpty else { return 0 }
        let center = UNUserNotificationCenter.current()
        for (group,chapter) in fresh.prefix(4) {
            let content = UNMutableNotificationContent()
            content.title = group.item.title
            content.body = "فصل جديد: الفصل \(chapterNumber(chapter.number)) · \(chapter.sourceLabel)"
            content.sound = .default
            content.threadIdentifier = group.id
            content.userInfo = ["storyKey":group.item.key]
            try? await center.add(UNNotificationRequest(identifier:owner+"|"+group.id+"|"+chapter.id,content:content,trigger:nil))
        }
        if fresh.count > 4 {
            let content = UNMutableNotificationContent()
            content.title = "فصول جديدة"
            content.body = "و\(fresh.count-4) فصول أخرى جديدة لقصص تتابعها."
            content.userInfo = ["tab":"new"]
            try? await center.add(UNNotificationRequest(identifier:owner+"|summary|"+UUID().uuidString,content:content,trigger:nil))
        }
        return fresh.count
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner,.list,.sound]
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,didReceive response: UNNotificationResponse) async {
        let key = response.notification.request.content.userInfo["storyKey"] as? String
        await MainActor.run { NewChapterAlerts.shared.store?.alertDestination = key ?? "" }
    }
}

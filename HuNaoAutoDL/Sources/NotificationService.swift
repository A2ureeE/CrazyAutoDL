import AppKit
import Foundation
import UserNotifications

@MainActor
final class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var alertsEnabled = true

    private let center = UNUserNotificationCenter.current()
    private var isActivated = false

    func activate() {
        guard !isActivated else { return }
        isActivated = true
        center.delegate = self
        Task {
            await refreshAuthorizationStatus()
            let settings = await center.notificationSettings()
            NSLog(
                "HuNaoAutoDL notification settings: auth=%ld alert=%ld center=%ld sound=%ld badge=%ld style=%ld",
                settings.authorizationStatus.rawValue,
                settings.alertSetting.rawValue,
                settings.notificationCenterSetting.rawValue,
                settings.soundSetting.rawValue,
                settings.badgeSetting.rawValue,
                settings.alertStyle.rawValue
            )
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        alertsEnabled = settings.alertSetting == .enabled
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            await refreshAuthorizationStatus()
            return false
        }
    }

    @discardableResult
    func send(
        title: String,
        body: String,
        identifier: String = UUID().uuidString,
        threadIdentifier: String = "hunao.autodl.monitor",
        trigger: UNNotificationTrigger? = nil
    ) async -> Bool {
        if authorizationStatus != .authorized && authorizationStatus != .provisional {
            await refreshAuthorizationStatus()
        }
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else {
            NSLog("HuNaoAutoDL notification skipped: authorization=%ld", authorizationStatus.rawValue)
            return false
        }
        return await deliver(
            title: title,
            body: body,
            identifier: identifier,
            threadIdentifier: threadIdentifier,
            trigger: trigger
        )
    }

    @discardableResult
    func sendTestNotification() async -> Bool {
        await send(
            title: "胡闹AutoDL 通知已就绪",
            body: "发现空闲显卡、自动开机成功时，我都会在这里提醒你。",
            identifier: "hunao.test.\(UUID().uuidString)",
            threadIdentifier: "",
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
    }

    private func deliver(
        title: String,
        body: String,
        identifier: String,
        threadIdentifier: String,
        trigger: UNNotificationTrigger?
    ) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if !threadIdentifier.isEmpty {
            content.threadIdentifier = threadIdentifier
        }

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
            return true
        } catch {
            NSLog("HuNaoAutoDL notification error: %@", String(describing: error))
            return false
        }
    }

    func openSystemNotificationSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        NSLog("HuNaoAutoDL willPresent: %@", notification.request.identifier)
        completionHandler([.banner, .sound, .list])
    }
}

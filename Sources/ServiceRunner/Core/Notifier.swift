import Foundation
import UserNotifications

/// System notifications about crashed services. Tapping one selects the service.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let serviceIDKey = "serviceID"

    var onOpen: ((UUID) -> Void)?

    /// UNUserNotificationCenter requires a real app bundle (not `swift run`).
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func setUp() {
        guard let center else { return }
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyCrash(name: String, id: UUID, reason: ExitReason, restarting: Bool) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(name) упал"
        content.body = "Процесс завершился: \(reason.description)" + (restarting ? ". Перезапускаю…" : "")
        content.sound = .default
        content.userInfo = [Self.serviceIDKey: id.uuidString]
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let raw = response.notification.request.content.userInfo[Self.serviceIDKey] as? String,
           let id = UUID(uuidString: raw) {
            DispatchQueue.main.async { self.onOpen?(id) }
        }
        completionHandler()
    }
}

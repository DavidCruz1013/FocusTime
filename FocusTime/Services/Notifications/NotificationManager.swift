import Foundation
import UserNotifications

struct ScheduledNotice {
    let id: String
    let title: String
    let body: String
    let deadline: Date
}

enum NotificationID {
    static let sessionEnd = "focustime.session.end"
    static let breakReminder = "focustime.break.reminder"
    static let breakEnd = "focustime.break.end"
    static let all = [sessionEnd, breakReminder, breakEnd]
}

/// Solo solicita permiso desde una acción explícita del usuario en Configuración.
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var revision = 0
    private var pendingSync: Task<Void, Never>?
    var onError: ((String) -> Void)?

    override init() {
        super.init()
        center.delegate = self
    }

    func isAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    func requestAuthorizationIfNeeded() async throws -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            return try await center.requestAuthorization(options: [.alert, .sound])
        }
        return await isAuthorized()
    }

    /// Serializa las escrituras al centro de notificaciones: una solicitud antigua
    /// nunca puede sobrescribir los avisos de una pausa o de una nueva configuración.
    func replace(with notices: [ScheduledNotice]) {
        revision += 1
        let requestedRevision = revision
        let previous = pendingSync
        pendingSync = Task { [weak self] in
            await previous?.value
            guard let self, self.revision == requestedRevision else { return }
            let authorized = await self.isAuthorized()
            guard self.revision == requestedRevision else { return }
            self.center.removePendingNotificationRequests(withIdentifiers: NotificationID.all)
            guard authorized else { return }
            for notice in notices {
                guard self.revision == requestedRevision else { return }
                let seconds = notice.deadline.timeIntervalSinceNow
                guard seconds > 0 else { continue }
                let content = UNMutableNotificationContent()
                content.title = notice.title
                content.body = notice.body
                content.sound = .default
                let request = UNNotificationRequest(
                    identifier: notice.id, content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false))
                do { try await self.center.add(request) }
                catch {
                    if self.revision == requestedRevision {
                        self.onError?("No se pudo programar el aviso: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

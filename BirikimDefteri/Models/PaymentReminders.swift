import Foundation
import UserNotifications

/// Kredi kartı son ödeme ve kredi taksit günleri için yerel bildirimler. İnternet gerektirmez.
@MainActor
enum PaymentReminders {
    static let enabledKey = "paymentReminders"
    private static let prefix = "odeme-"

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Bekleyen hatırlatmaları siler ve borçlara göre yeniden kurar.
    static func reschedule(_ debts: [Debt], calendar: Calendar = .current) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        guard UserDefaults.standard.bool(forKey: enabledKey) else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        for debt in debts where debt.remaining > 0 {
            let name = debt.institution.isEmpty ? debt.kind.title : "\(debt.institution) · \(debt.title.isEmpty ? debt.kind.title : debt.title)"
            if debt.kind == .creditCard, let dueDate = debt.dueDate {
                for (offset, text) in [(-2, "Son ödeme 2 gün sonra"), (0, "Son ödeme günü bugün")] {
                    guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: dueDate)),
                          let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day), fire > .now
                    else { continue }
                    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                    add(id: "\(prefix)\(debt.id)\(offset)", title: name, body: text + amount(debt.remaining),
                        trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
                }
            }
            if let paymentDay = debt.paymentDay {
                var components = DateComponents()
                components.day = paymentDay
                components.hour = 9
                add(id: "\(prefix)\(debt.id)-taksit", title: name, body: "Bugün taksit günü" + amount(debt.monthlyInstallment),
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true))
            }
        }
    }

    /// Tutarları gizle açıksa bildirimde tutar gösterilmez.
    private static func amount(_ value: Decimal?) -> String {
        guard let value, !Format.hidesAmounts else { return "" }
        return " · \(Format.plainLira(value))"
    }

    private static func add(id: String, title: String, body: String, trigger: UNNotificationTrigger) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}

import Foundation
import UserNotifications

/// Ücretsiz Apple hesabıyla imza 7 gün geçerlidir; Mac'teki görev (`scripts/auto-install.sh`) süresi dolmadan yeniler.
/// Yenileme bir sebeple hiç olamazsa son çare olarak imzanın dolmasına 24 saat kala bildirim gösterir ve Özet'te uyarır.
/// Bitiş tarihi uygulamanın kendi profilinden okunur (`embedded.mobileprovision`); simülatörde profil olmadığı için kapalıdır.
@MainActor
enum SigningReminder {
    static let identifier = "imza-suresi"
    /// Özet'teki uyarının görüneceği süre.
    static let bannerLead: TimeInterval = 48 * 3600
    /// Bildirimin imza dolmadan ne kadar önce geleceği.
    static let notificationLead: TimeInterval = 24 * 3600

    /// Bu derlemenin imzasının bitiş tarihi.
    static let expirationDate: Date? = {
        #if DEBUG
        // Simülatörde uyarıyı görmek için: -signingExpiresInHours 30
        let hours = UserDefaults.standard.double(forKey: "signingExpiresInHours")
        if hours > 0 { return Date.now.addingTimeInterval(hours * 3600) }
        #endif
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return expirationDate(fromProvision: data)
    }()

    /// Profil, imzalı (CMS) bir kabın içinde düz metin bir plist taşır; imzayı doğrulamaya gerek yok, plist ayıklanır.
    nonisolated static func expirationDate(fromProvision data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }
        let plist = data.subdata(in: start.lowerBound..<end.upperBound)
        let object = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        return object?["ExpirationDate"] as? Date
    }

    /// İmza yakında doluyorsa bitiş tarihi (Özet'teki uyarı için).
    static func expiringSoon(now: Date = .now) -> Date? {
        guard let expiry = expirationDate, expiry > now, expiry.timeIntervalSince(now) < bannerLead else { return nil }
        return expiry
    }

    /// Bekleyen uyarıyı bu derlemenin bitiş tarihine göre yeniden kurar. Uygulama her öne geldiğinde çağrılır;
    /// Mac imzayı yenileyip uygulama açılınca eski uyarı silinir.
    static func refresh() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard let expiry = expirationDate else { return }
        let fireIn = expiry.timeIntervalSinceNow - notificationLead
        guard fireIn > 60 else { return }

        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "Uygulamanın imzası yarın doluyor"
        content.body = "Mac yenileyemezse Birikim Defteri yarın bu saatten sonra açılmaz. Mac'i açık, iPhone'u aynı Wi-Fi'de "
            + "tutun. İmza bu arada yenilendiyse bu uyarıyı yok sayın."
        content.sound = .default
        try? await center.add(UNNotificationRequest(
            identifier: identifier, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: fireIn, repeats: false)
        ))
    }
}

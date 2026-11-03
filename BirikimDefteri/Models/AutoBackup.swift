import CryptoKit
import Foundation

/// Veriler değiştikçe uygulamanın kendi klasörüne (Documents/Yedekler) tarihli JSON yedeği yazar.
/// Mac'teki zamanlanmış görev bu yedekleri iCloud Drive'a çeker (scripts/auto-install.sh).
@MainActor
enum AutoBackup {
    static let folderName = "Yedekler"
    private static let hashKey = "autoBackupHash"
    private static let keepCount = 30

    static var folder: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(folderName, isDirectory: true)
    }

    /// Son yedekten beri veri değiştiyse yeni bir yedek dosyası yazar, en eski fazlalıkları siler.
    static func saveIfChanged(_ ledger: Ledger) {
        guard let folder, !ledger.assets.isEmpty else { return }
        var backup = BackupService.makeBackup(from: ledger)
        let exportedAt = backup.exportedAt
        backup.exportedAt = .distantPast
        guard let canonical = try? BackupService.encode(backup) else { return }
        let hash = SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
        guard hash != UserDefaults.standard.string(forKey: hashKey) else { return }

        backup.exportedAt = exportedAt
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("BirikimDefteri-\(fileStamp(exportedAt)).json")
            try BackupService.encode(backup).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            UserDefaults.standard.set(hash, forKey: hashKey)
            prune(folder)
        } catch {
            // Yedek yazılamazsa bir sonraki değişiklikte yeniden denenir; uygulamanın akışını bozmaz.
        }
    }

    private static func prune(_ folder: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let backups = files.filter { $0.hasPrefix("BirikimDefteri-") && $0.hasSuffix(".json") }.sorted(by: >)
        for name in backups.dropFirst(keepCount) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    private static func fileStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }
}

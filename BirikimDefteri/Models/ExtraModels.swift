import Foundation
import SwiftData

@Model
final class DebtPayment {
    var id: UUID = UUID()
    var debtID: UUID = UUID()
    var amountText: String = "0"
    var date: Date = Date.now
    var note: String = ""
    var createdAt: Date = Date.now

    init(id: UUID = UUID(), debtID: UUID, amount: Decimal, date: Date, note: String = "", createdAt: Date = .now) {
        self.id = id
        self.debtID = debtID
        self.amountText = amount.storageText
        self.date = date
        self.note = note
        self.createdAt = createdAt
    }

    var amount: Decimal { Decimal(storageText: amountText) ?? 0 }
}

@Model
final class Goal {
    var id: UUID = UUID()
    var title: String = ""
    var kindRaw: String = "netWorth"
    var targetText: String = "0"
    var assetID: UUID?
    var personID: UUID?
    var createdAt: Date = Date.now

    init(id: UUID = UUID(), title: String, kind: GoalKind, target: Decimal, assetID: UUID?, personID: UUID?, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.kindRaw = kind.rawValue
        self.targetText = target.storageText
        self.assetID = assetID
        self.personID = personID
        self.createdAt = createdAt
    }

    var kind: GoalKind {
        get { GoalKind(rawValue: kindRaw) ?? .netWorth }
        set { kindRaw = newValue.rawValue }
    }

    var target: Decimal {
        get { Decimal(storageText: targetText) ?? 0 }
        set { targetText = newValue.storageText }
    }

    var info: GoalInfo {
        GoalInfo(id: id, title: title, kind: kind, target: target, assetID: assetID, personID: personID)
    }
}

/// İşlem geçmişi: her değişiklikten önceki ve sonraki hâl JSON olarak tutulur, geri alma bunlardan yapılır.
@Model
final class JournalEntry {
    var id: UUID = UUID()
    var date: Date = Date.now
    var actionRaw: String = "added"
    var entityRaw: String = "transaction"
    var summary: String = ""
    var beforeJSON: String?
    var afterJSON: String?
    var isUndone: Bool = false

    init(action: JournalAction, entity: JournalEntity, summary: String, before: String?, after: String?, date: Date = .now) {
        self.id = UUID()
        self.date = date
        self.actionRaw = action.rawValue
        self.entityRaw = entity.rawValue
        self.summary = summary
        self.beforeJSON = before
        self.afterJSON = after
    }

    var action: JournalAction { JournalAction(rawValue: actionRaw) ?? .edited }
    var entity: JournalEntity { JournalEntity(rawValue: entityRaw) ?? .transaction }
}

enum JournalAction: String, Codable, Sendable {
    case added, edited, deleted, restored

    var title: String {
        switch self {
        case .added: "Eklendi"
        case .edited: "Düzenlendi"
        case .deleted: "Silindi"
        case .restored: "Yedekten geri yüklendi"
        }
    }

    var symbol: String {
        switch self {
        case .added: "plus.circle.fill"
        case .edited: "pencil.circle.fill"
        case .deleted: "trash.circle.fill"
        case .restored: "arrow.counterclockwise.circle.fill"
        }
    }

    /// Bu kayıtlar geçmişten hiç budanmaz; silinen veri her zaman geri getirilebilir.
    var isKeptForever: Bool { self == .deleted || self == .restored }
}

enum JournalEntity: String, Codable, Sendable {
    case transaction, transfer, debt, payment
    case goal, person, location, asset
    /// Yedekten geri yüklemeden önceki verilerin tamamı.
    case backup
}

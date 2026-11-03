import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// JSON yedeğinin biçimi. Decimal değerler kayıpsız kalsın diye metin olarak yazılır.
struct BackupFile: Codable {
    static let formatName = "birikim-defteri-yedek"

    var format = BackupFile.formatName
    var version = 1
    var exportedAt: Date
    var people: [PersonEntry]
    var locations: [LocationEntry]
    var assets: [AssetEntry]
    var prices: [PriceEntry]
    var transactions: [TransactionEntry]
    var debts: [DebtEntry]
    var debtPayments: [DebtPaymentEntry]?
    var goals: [GoalEntry]?

    struct PersonEntry: Codable {
        var id: UUID
        var name: String
        var createdAt: Date
    }

    struct LocationEntry: Codable {
        var id: UUID
        var name: String
        var kind: LocationKind
        var createdAt: Date
    }

    struct AssetEntry: Codable {
        var id: UUID
        var name: String
        var unit: AssetUnit
        var category: AssetCategory
        var sortOrder: Int
        var createdAt: Date
    }

    struct PriceEntry: Codable {
        var id: UUID
        var assetID: UUID
        var price: String
        var date: Date
    }

    struct TransactionEntry: Codable {
        var id: UUID
        var kind: TransactionKind
        var personID: UUID
        var assetID: UUID
        var locationID: UUID
        var quantity: String
        var unitPrice: String
        var date: Date
        var note: String
        var createdAt: Date
        var transferID: UUID?
    }

    struct DebtEntry: Codable {
        var id: UUID
        var personID: UUID
        var institution: String
        var kind: DebtKind
        var title: String
        var remaining: String
        var monthlyInstallment: String?
        var dueDate: Date?
        var note: String
        var updatedAt: Date
        var paymentDay: Int?
    }

    struct DebtPaymentEntry: Codable {
        var id: UUID
        var debtID: UUID
        var amount: String
        var date: Date
        var note: String
        var createdAt: Date
    }

    struct GoalEntry: Codable {
        var id: UUID
        var title: String
        var kind: GoalKind
        var target: String
        var assetID: UUID?
        var personID: UUID?
        var createdAt: Date
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum BackupError: LocalizedError {
    case notABackup
    case unsupportedVersion(Int)
    case invalidNumber(String)

    var errorDescription: String? {
        switch self {
        case .notABackup: "Bu dosya bir Birikim Defteri yedeği değil."
        case .unsupportedVersion(let version): "Bu yedek daha yeni bir sürümle (\(version)) oluşturulmuş."
        case .invalidNumber(let text): "Yedekte geçersiz bir sayı var: \(text)"
        }
    }
}

@MainActor
enum BackupService {
    nonisolated private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    /// Kayıtlar kimliğe göre sıralanır; aynı veri her seferinde aynı dosyayı üretsin.
    static func makeBackup(from ledger: Ledger) -> BackupFile {
        var backup = BackupFile(
            exportedAt: .now,
            people: ledger.people.map { .init(id: $0.id, name: $0.name, createdAt: $0.createdAt) },
            locations: ledger.locations.map { .init(id: $0.id, name: $0.name, kind: $0.kind, createdAt: $0.createdAt) },
            assets: ledger.assets.map {
                .init(id: $0.id, name: $0.name, unit: $0.unit, category: $0.category, sortOrder: $0.sortOrder, createdAt: $0.createdAt)
            },
            prices: ledger.prices.map { .init(id: $0.id, assetID: $0.assetID, price: $0.priceText, date: $0.date) },
            transactions: ledger.transactions.map {
                .init(
                    id: $0.id, kind: $0.kind, personID: $0.personID, assetID: $0.assetID, locationID: $0.locationID,
                    quantity: $0.quantityText, unitPrice: $0.unitPriceText, date: $0.date, note: $0.note, createdAt: $0.createdAt,
                    transferID: $0.transferID
                )
            },
            debts: ledger.debts.map {
                .init(
                    id: $0.id, personID: $0.personID, institution: $0.institution, kind: $0.kind, title: $0.title,
                    remaining: $0.remainingText, monthlyInstallment: $0.monthlyInstallmentText, dueDate: $0.dueDate,
                    note: $0.note, updatedAt: $0.updatedAt, paymentDay: $0.paymentDay
                )
            },
            debtPayments: ledger.payments.map {
                .init(id: $0.id, debtID: $0.debtID, amount: $0.amountText, date: $0.date, note: $0.note, createdAt: $0.createdAt)
            },
            goals: ledger.goals.map {
                .init(id: $0.id, title: $0.title, kind: $0.kind, target: $0.targetText, assetID: $0.assetID,
                      personID: $0.personID, createdAt: $0.createdAt)
            }
        )
        backup.people.sort { $0.id.uuidString < $1.id.uuidString }
        backup.locations.sort { $0.id.uuidString < $1.id.uuidString }
        backup.assets.sort { $0.id.uuidString < $1.id.uuidString }
        backup.prices.sort { $0.id.uuidString < $1.id.uuidString }
        backup.transactions.sort { $0.id.uuidString < $1.id.uuidString }
        backup.debts.sort { $0.id.uuidString < $1.id.uuidString }
        backup.debtPayments?.sort { $0.id.uuidString < $1.id.uuidString }
        backup.goals?.sort { $0.id.uuidString < $1.id.uuidString }
        return backup
    }

    static func encode(_ backup: BackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(dateStyle))
        }
        return try encoder.encode(backup)
    }

    static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = try? Date(text, strategy: dateStyle) { return date }
            if let date = try? Date(text, strategy: .iso8601) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Geçersiz tarih: \(text)")
        }
        let backup: BackupFile
        do {
            backup = try decoder.decode(BackupFile.self, from: data)
        } catch {
            throw BackupError.notABackup
        }
        guard backup.format == BackupFile.formatName else { throw BackupError.notABackup }
        guard backup.version <= 1 else { throw BackupError.unsupportedVersion(backup.version) }

        let numbers = backup.prices.map(\.price)
            + backup.transactions.flatMap { [$0.quantity, $0.unitPrice] }
            + backup.debts.flatMap { [$0.remaining] + ($0.monthlyInstallment.map { [$0] } ?? []) }
        if let invalid = numbers.first(where: { Decimal(storageText: $0) == nil }) {
            throw BackupError.invalidNumber(invalid)
        }
        return backup
    }

    static func read(from url: URL) throws -> BackupFile {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try decode(Data(contentsOf: url))
    }

    /// Mevcut tüm verileri siler ve yedektekilerle değiştirir.
    static func restore(_ backup: BackupFile, into context: ModelContext) throws {
        try deleteAll(TransactionRecord.self, in: context)
        try deleteAll(PricePoint.self, in: context)
        try deleteAll(Debt.self, in: context)
        try deleteAll(Asset.self, in: context)
        try deleteAll(Location.self, in: context)
        try deleteAll(Person.self, in: context)
        try deleteAll(DebtPayment.self, in: context)
        try deleteAll(Goal.self, in: context)

        for entry in backup.people {
            context.insert(Person(id: entry.id, name: entry.name, createdAt: entry.createdAt))
        }
        for entry in backup.locations {
            context.insert(Location(id: entry.id, name: entry.name, kind: entry.kind, createdAt: entry.createdAt))
        }
        for entry in backup.assets {
            context.insert(Asset(
                id: entry.id, name: entry.name, unit: entry.unit, category: entry.category,
                sortOrder: entry.sortOrder, createdAt: entry.createdAt
            ))
        }
        if !backup.assets.contains(where: { $0.id == AssetInfo.liraID }) {
            Store.insertLira(in: context)
        }
        for entry in backup.prices {
            context.insert(PricePoint(id: entry.id, assetID: entry.assetID, price: Decimal(storageText: entry.price) ?? 0, date: entry.date))
        }
        for entry in backup.transactions {
            let info = TransactionInfo(
                id: entry.id, kind: entry.kind, personID: entry.personID, assetID: entry.assetID,
                locationID: entry.locationID, quantity: Decimal(storageText: entry.quantity) ?? 0,
                unitPrice: Decimal(storageText: entry.unitPrice) ?? 0, date: entry.date, createdAt: entry.createdAt,
                transferID: entry.transferID
            )
            context.insert(TransactionRecord(info: info, note: entry.note))
        }
        for entry in backup.debts {
            context.insert(Debt(
                id: entry.id, personID: entry.personID, institution: entry.institution, kind: entry.kind,
                title: entry.title, remaining: Decimal(storageText: entry.remaining) ?? 0,
                monthlyInstallment: entry.monthlyInstallment.flatMap { Decimal(storageText: $0) },
                dueDate: entry.dueDate, note: entry.note, updatedAt: entry.updatedAt, paymentDay: entry.paymentDay
            ))
        }
        for entry in backup.debtPayments ?? [] {
            context.insert(DebtPayment(
                id: entry.id, debtID: entry.debtID, amount: Decimal(storageText: entry.amount) ?? 0,
                date: entry.date, note: entry.note, createdAt: entry.createdAt
            ))
        }
        for entry in backup.goals ?? [] {
            context.insert(Goal(
                id: entry.id, title: entry.title, kind: entry.kind, target: Decimal(storageText: entry.target) ?? 0,
                assetID: entry.assetID, personID: entry.personID, createdAt: entry.createdAt
            ))
        }
        try context.save()
    }

    struct MergeResult: Equatable {
        var added = 0
        var updated = 0
    }

    /// Yedektekileri mevcut verilere ekler, hiçbir şeyi silmez. Kişi, yer ve ürünler adla eşleştirilir.
    /// Aynı kimlikli işlem ve borçlar yedekteki hâliyle güncellenir, aynı kimlikli fiyatlar atlanır.
    @discardableResult
    static func merge(_ backup: BackupFile, into context: ModelContext) throws -> MergeResult {
        func key(_ name: String) -> String { name.trimmed.lowercased(with: Format.locale) }

        let people = try context.fetch(FetchDescriptor<Person>())
        var personIDs: [UUID: UUID] = [:]
        for entry in backup.people {
            if let existing = people.first(where: { key($0.name) == key(entry.name) }) {
                personIDs[entry.id] = existing.id
            } else {
                context.insert(Person(id: entry.id, name: entry.name.trimmed, createdAt: entry.createdAt))
                personIDs[entry.id] = entry.id
            }
        }

        let locations = try context.fetch(FetchDescriptor<Location>())
        var locationIDs: [UUID: UUID] = [:]
        for entry in backup.locations {
            if let existing = locations.first(where: { key($0.name) == key(entry.name) }) {
                locationIDs[entry.id] = existing.id
            } else {
                context.insert(Location(id: entry.id, name: entry.name.trimmed, kind: entry.kind, createdAt: entry.createdAt))
                locationIDs[entry.id] = entry.id
            }
        }

        let assets = try context.fetch(FetchDescriptor<Asset>())
        var nextSortOrder = (assets.map(\.sortOrder).max() ?? 0) + 1
        var assetIDs: [UUID: UUID] = [:]
        for entry in backup.assets {
            if let existing = assets.first(where: { $0.id == entry.id || key($0.name) == key(entry.name) }) {
                assetIDs[entry.id] = existing.id
            } else {
                context.insert(Asset(
                    id: entry.id, name: entry.name.trimmed, unit: entry.unit, category: entry.category,
                    sortOrder: nextSortOrder, createdAt: entry.createdAt
                ))
                assetIDs[entry.id] = entry.id
                nextSortOrder += 1
            }
        }

        let existingPrices = Set(try context.fetch(FetchDescriptor<PricePoint>()).map(\.id))
        for entry in backup.prices where !existingPrices.contains(entry.id) {
            guard let assetID = assetIDs[entry.assetID], let price = Decimal(storageText: entry.price) else { continue }
            context.insert(PricePoint(id: entry.id, assetID: assetID, price: price, date: entry.date))
        }

        let existingTransactions = Dictionary(
            try context.fetch(FetchDescriptor<TransactionRecord>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        var result = MergeResult()
        for entry in backup.transactions {
            guard let personID = personIDs[entry.personID],
                  let assetID = assetIDs[entry.assetID],
                  let locationID = locationIDs[entry.locationID],
                  let quantity = Decimal(storageText: entry.quantity),
                  let unitPrice = Decimal(storageText: entry.unitPrice)
            else { continue }
            let existing = existingTransactions[entry.id]
            let info = TransactionInfo(
                id: entry.id, kind: entry.kind, personID: personID, assetID: assetID, locationID: locationID,
                quantity: quantity, unitPrice: unitPrice, date: entry.date, createdAt: existing?.createdAt ?? entry.createdAt,
                transferID: entry.transferID
            )
            if let existing {
                if existing.info != info || existing.note != entry.note {
                    existing.update(from: info, note: entry.note)
                    result.updated += 1
                }
            } else {
                context.insert(TransactionRecord(info: info, note: entry.note))
                result.added += 1
            }
        }

        let existingDebts = Dictionary(
            try context.fetch(FetchDescriptor<Debt>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        for entry in backup.debts {
            guard let personID = personIDs[entry.personID], let remaining = Decimal(storageText: entry.remaining) else { continue }
            if let debt = existingDebts[entry.id] {
                debt.personID = personID
                debt.institution = entry.institution
                debt.kind = entry.kind
                debt.title = entry.title
                debt.remaining = remaining
                debt.monthlyInstallment = entry.monthlyInstallment.flatMap { Decimal(storageText: $0) }
                debt.dueDate = entry.dueDate
                debt.note = entry.note
                debt.updatedAt = entry.updatedAt
                continue
            }
            context.insert(Debt(
                id: entry.id, personID: personID, institution: entry.institution, kind: entry.kind,
                title: entry.title, remaining: remaining,
                monthlyInstallment: entry.monthlyInstallment.flatMap { Decimal(storageText: $0) },
                dueDate: entry.dueDate, note: entry.note, updatedAt: entry.updatedAt
            ))
        }
        try context.save()
        return result
    }

    static func defaultFilename() -> String {
        "BirikimDefteri-\(Date.now.formatted(.iso8601.year().month().day()))"
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws {
        for object in try context.fetch(FetchDescriptor<T>()) {
            context.delete(object)
        }
    }
}

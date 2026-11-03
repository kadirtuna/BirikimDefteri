import Foundation
import SwiftData

/// İşlem geçmişi ve geri alma. Değişiklikten önceki ve sonraki hâl, yedek biçimindeki kayıtlar olarak saklanır.
@MainActor
enum Journal {
    private static let keepCount = 500

    struct PaymentSnapshot: Codable {
        var payment: BackupFile.DebtPaymentEntry?
        var debt: BackupFile.DebtEntry
    }

    /// Silinen hedef, kişi, yer ya da ürünün (fiyat kayıtlarıyla birlikte) anlık görüntüsü.
    struct RecordSnapshot: Codable {
        var people: [BackupFile.PersonEntry] = []
        var locations: [BackupFile.LocationEntry] = []
        var assets: [BackupFile.AssetEntry] = []
        var prices: [BackupFile.PriceEntry] = []
        var goals: [BackupFile.GoalEntry] = []
    }

    enum UndoError: LocalizedError {
        case conflict(String)
        case unreadable

        var errorDescription: String? {
            switch self {
            case .conflict(let message): message
            case .unreadable: "Bu kaydın eski hâli okunamadı."
            }
        }
    }

    // MARK: Kaydetme

    @discardableResult
    static func recordTransactions(
        _ action: JournalAction, summary: String,
        before: [TransactionRecord], after: [TransactionRecord], in context: ModelContext
    ) -> JournalEntry {
        let entity: JournalEntity = (before + after).contains { $0.transferID != nil } ? .transfer : .transaction
        return save(JournalEntry(
            action: action, entity: entity, summary: summary,
            before: before.isEmpty ? nil : encode(before.map(entry)),
            after: after.isEmpty ? nil : encode(after.map(entry))
        ), in: context)
    }

    /// Önceki hâli değişiklikten önce, sonrakini değişiklikten sonra alan sürüm (düzenlemeler için).
    @discardableResult
    static func recordTransactions(
        _ action: JournalAction, summary: String,
        before: [BackupFile.TransactionEntry], after: [TransactionRecord], in context: ModelContext
    ) -> JournalEntry {
        let entity: JournalEntity = before.contains { $0.transferID != nil } || after.contains { $0.transferID != nil }
            ? .transfer : .transaction
        return save(JournalEntry(
            action: action, entity: entity, summary: summary,
            before: before.isEmpty ? nil : encode(before),
            after: after.isEmpty ? nil : encode(after.map(entry))
        ), in: context)
    }

    @discardableResult
    static func recordDebt(
        _ action: JournalAction, summary: String,
        before: BackupFile.DebtEntry?, after: Debt?, in context: ModelContext
    ) -> JournalEntry {
        return save(JournalEntry(
            action: action, entity: .debt, summary: summary,
            before: before.flatMap(encode), after: after.map(entry).flatMap(encode)
        ), in: context)
    }

    @discardableResult
    static func recordPayment(
        _ action: JournalAction, summary: String,
        before: PaymentSnapshot, after: PaymentSnapshot, in context: ModelContext
    ) -> JournalEntry {
        return save(JournalEntry(action: action, entity: .payment, summary: summary, before: encode(before), after: encode(after)), in: context)
    }

    /// Silinmeden hemen önce çağrılır.
    @discardableResult
    static func recordDeletion(_ entity: JournalEntity, summary: String, snapshot: RecordSnapshot, in context: ModelContext) -> JournalEntry {
        save(JournalEntry(action: .deleted, entity: entity, summary: summary, before: encode(snapshot), after: nil), in: context)
    }

    /// Yedekten geri yüklemeden hemen önce, o anki verilerin tamamıyla çağrılır.
    @discardableResult
    static func recordRestore(replacing current: BackupFile, summary: String, in context: ModelContext) -> JournalEntry {
        let before = (try? BackupService.encode(current)).flatMap { String(data: $0, encoding: .utf8) }
        return save(JournalEntry(action: .restored, entity: .backup, summary: summary, before: before, after: nil), in: context)
    }

    private static func save(_ entry: JournalEntry, in context: ModelContext) -> JournalEntry {
        context.insert(entry)
        // Silme ve geri yükleme kayıtları budanmaz; sınır yalnızca ekleme ve düzenlemeler içindir.
        let deleted = JournalAction.deleted.rawValue
        let restored = JournalAction.restored.rawValue
        var descriptor = FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.actionRaw != deleted && $0.actionRaw != restored },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        // Kaydedilmemiş kayıtlara fetchOffset uygulanmıyor; dahil edilseler yeni kayıt daha kaydedilmeden silinirdi.
        // Yeni kayıt sayılmadığı için sınırın bir eksiği atlanır.
        descriptor.includePendingChanges = false
        descriptor.fetchOffset = keepCount - 1
        for old in (try? context.fetch(descriptor)) ?? [] { context.delete(old) }
        return entry
    }

    // MARK: Özetler

    static func describe(_ info: TransactionInfo, ledger: Ledger, destination: UUID? = nil) -> String {
        let asset = ledger.calculator.assets[info.assetID]
        let amount = Format.plainQuantity(info.quantity, unit: asset?.unit ?? .piece)
        let name = asset?.name ?? "Bilinmeyen ürün"
        if let destination {
            return "Aktarım · \(name) · \(amount) · \(ledger.locationName(info.locationID)) → \(ledger.locationName(destination))"
        }
        return "\(info.kind.title) · \(name) · \(amount) · \(ledger.personName(info.personID)) · \(ledger.locationName(info.locationID))"
    }

    static func describe(_ debt: Debt) -> String {
        let institution = debt.institution.isEmpty ? debt.kind.title : debt.institution
        return "Borç · \(institution) · \(debt.title.isEmpty ? debt.kind.title : debt.title) · \(Format.plainLira(debt.remaining))"
    }

    static func describe(_ goal: Goal) -> String { "Hedef · \(goal.title)" }
    static func describe(_ person: Person) -> String { "Kişi · \(person.name)" }
    static func describe(_ location: Location) -> String { "Saklama yeri · \(location.name)" }

    static func describe(_ asset: Asset, priceCount: Int) -> String {
        "Ürün · \(asset.name)" + (priceCount > 0 ? " · \(priceCount) fiyat kaydıyla" : "")
    }

    // MARK: Geri alma

    static func undo(_ journalEntry: JournalEntry, ledger: Ledger, context: ModelContext) throws {
        switch journalEntry.entity {
        case .transaction, .transfer:
            try undoTransactions(journalEntry, ledger: ledger, context: context)
        case .debt:
            try undoDebt(journalEntry, ledger: ledger, context: context)
        case .payment:
            try undoPayment(journalEntry, ledger: ledger, context: context)
        case .goal, .person, .location, .asset:
            try undoSnapshot(journalEntry, ledger: ledger, context: context)
        case .backup:
            try undoRestore(journalEntry, ledger: ledger, context: context)
        }
        journalEntry.isUndone = true
        try context.save()
    }

    /// Silinenleri yeniden ekler; aynı kimlikle duran kayda dokunmaz.
    private static func undoSnapshot(_ journalEntry: JournalEntry, ledger: Ledger, context: ModelContext) throws {
        guard let snapshot: RecordSnapshot = try decode(journalEntry.beforeJSON) else { throw UndoError.unreadable }
        for entry in snapshot.people where !ledger.people.contains(where: { $0.id == entry.id }) {
            context.insert(Person(id: entry.id, name: entry.name, createdAt: entry.createdAt))
        }
        for entry in snapshot.locations where !ledger.locations.contains(where: { $0.id == entry.id }) {
            context.insert(Location(id: entry.id, name: entry.name, kind: entry.kind, createdAt: entry.createdAt))
        }
        for entry in snapshot.assets where !ledger.assets.contains(where: { $0.id == entry.id }) {
            context.insert(Asset(id: entry.id, name: entry.name, unit: entry.unit, category: entry.category,
                                 sortOrder: entry.sortOrder, createdAt: entry.createdAt))
        }
        for entry in snapshot.prices where !ledger.prices.contains(where: { $0.id == entry.id }) {
            context.insert(PricePoint(id: entry.id, assetID: entry.assetID, price: Decimal(storageText: entry.price) ?? 0, date: entry.date))
        }
        for entry in snapshot.goals where !ledger.goals.contains(where: { $0.id == entry.id }) {
            context.insert(Goal(id: entry.id, title: entry.title, kind: entry.kind, target: Decimal(storageText: entry.target) ?? 0,
                                assetID: entry.assetID, personID: entry.personID, createdAt: entry.createdAt))
        }
    }

    /// Yedekten geri yüklemeden önceki hâle döner. Dönmeden önce şimdiki hâl de kaydedilir, böylece bu da geri alınabilir.
    private static func undoRestore(_ journalEntry: JournalEntry, ledger: Ledger, context: ModelContext) throws {
        guard let text = journalEntry.beforeJSON, let data = text.data(using: .utf8),
              let previous = try? BackupService.decode(data)
        else { throw UndoError.unreadable }
        recordRestore(replacing: BackupService.makeBackup(from: ledger),
                      summary: "Geri yükleme geri alındı · \(Format.dateTime(journalEntry.date)) öncesine dönüldü", in: context)
        try BackupService.restore(previous, into: context)
    }

    private static func undoTransactions(_ journalEntry: JournalEntry, ledger: Ledger, context: ModelContext) throws {
        let before: [BackupFile.TransactionEntry] = try decode(journalEntry.beforeJSON) ?? []
        let after: [BackupFile.TransactionEntry] = try decode(journalEntry.afterJSON) ?? []
        let restored = before.compactMap(info)
        let removedIDs = Set(after.map(\.id)).subtracting(before.map(\.id))
        if let error = ledger.calculator.validateChange(removing: removedIDs.union(restored.map(\.id)), adding: restored) {
            let unit = restored.first.flatMap { ledger.calculator.assets[$0.assetID]?.unit }
            throw UndoError.conflict("Geri alınamadı: " + error.message(unit: unit))
        }
        for record in ledger.transactions where removedIDs.contains(record.id) {
            context.delete(record)
        }
        for (entry, info) in zip(before, restored) {
            if let record = ledger.transaction(entry.id) {
                record.update(from: info, note: entry.note)
            } else {
                context.insert(TransactionRecord(info: info, note: entry.note))
            }
        }
    }

    private static func undoDebt(_ journalEntry: JournalEntry, ledger: Ledger, context: ModelContext) throws {
        let before: BackupFile.DebtEntry? = try decode(journalEntry.beforeJSON)
        let after: BackupFile.DebtEntry? = try decode(journalEntry.afterJSON)
        if let before {
            restore(before, ledger: ledger, context: context)
        } else if let after, let debt = ledger.debts.first(where: { $0.id == after.id }) {
            for payment in ledger.payments(for: debt) { context.delete(payment) }
            context.delete(debt)
        }
    }

    private static func undoPayment(_ journalEntry: JournalEntry, ledger: Ledger, context: ModelContext) throws {
        guard let before: PaymentSnapshot = try decode(journalEntry.beforeJSON),
              let after: PaymentSnapshot = try decode(journalEntry.afterJSON)
        else { throw UndoError.unreadable }
        restore(before.debt, ledger: ledger, context: context)
        if let added = after.payment, before.payment == nil,
           let payment = ledger.payments.first(where: { $0.id == added.id }) {
            context.delete(payment)
        }
        if let removed = before.payment, !ledger.payments.contains(where: { $0.id == removed.id }) {
            context.insert(DebtPayment(
                id: removed.id, debtID: removed.debtID, amount: Decimal(storageText: removed.amount) ?? 0,
                date: removed.date, note: removed.note, createdAt: removed.createdAt
            ))
        }
    }

    private static func restore(_ entry: BackupFile.DebtEntry, ledger: Ledger, context: ModelContext) {
        let remaining = Decimal(storageText: entry.remaining) ?? 0
        let monthly = entry.monthlyInstallment.flatMap { Decimal(storageText: $0) }
        if let debt = ledger.debts.first(where: { $0.id == entry.id }) {
            debt.personID = entry.personID
            debt.institution = entry.institution
            debt.kind = entry.kind
            debt.title = entry.title
            debt.remaining = remaining
            debt.monthlyInstallment = monthly
            debt.dueDate = entry.dueDate
            debt.note = entry.note
            debt.updatedAt = entry.updatedAt
            debt.paymentDay = entry.paymentDay
        } else {
            context.insert(Debt(
                id: entry.id, personID: entry.personID, institution: entry.institution, kind: entry.kind, title: entry.title,
                remaining: remaining, monthlyInstallment: monthly, dueDate: entry.dueDate, note: entry.note,
                updatedAt: entry.updatedAt, paymentDay: entry.paymentDay
            ))
        }
    }

    // MARK: Anlık görüntüler

    static func entry(_ record: TransactionRecord) -> BackupFile.TransactionEntry {
        .init(
            id: record.id, kind: record.kind, personID: record.personID, assetID: record.assetID, locationID: record.locationID,
            quantity: record.quantityText, unitPrice: record.unitPriceText, date: record.date, note: record.note,
            createdAt: record.createdAt, transferID: record.transferID
        )
    }

    static func entry(_ debt: Debt) -> BackupFile.DebtEntry {
        .init(
            id: debt.id, personID: debt.personID, institution: debt.institution, kind: debt.kind, title: debt.title,
            remaining: debt.remainingText, monthlyInstallment: debt.monthlyInstallmentText, dueDate: debt.dueDate,
            note: debt.note, updatedAt: debt.updatedAt, paymentDay: debt.paymentDay
        )
    }

    static func entry(_ person: Person) -> BackupFile.PersonEntry {
        .init(id: person.id, name: person.name, createdAt: person.createdAt)
    }

    static func entry(_ location: Location) -> BackupFile.LocationEntry {
        .init(id: location.id, name: location.name, kind: location.kind, createdAt: location.createdAt)
    }

    static func entry(_ asset: Asset) -> BackupFile.AssetEntry {
        .init(id: asset.id, name: asset.name, unit: asset.unit, category: asset.category, sortOrder: asset.sortOrder, createdAt: asset.createdAt)
    }

    static func entry(_ price: PricePoint) -> BackupFile.PriceEntry {
        .init(id: price.id, assetID: price.assetID, price: price.priceText, date: price.date)
    }

    static func entry(_ goal: Goal) -> BackupFile.GoalEntry {
        .init(id: goal.id, title: goal.title, kind: goal.kind, target: goal.targetText, assetID: goal.assetID,
              personID: goal.personID, createdAt: goal.createdAt)
    }

    static func entry(_ payment: DebtPayment) -> BackupFile.DebtPaymentEntry {
        .init(id: payment.id, debtID: payment.debtID, amount: payment.amountText, date: payment.date, note: payment.note,
              createdAt: payment.createdAt)
    }

    private static func info(_ entry: BackupFile.TransactionEntry) -> TransactionInfo? {
        guard let quantity = Decimal(storageText: entry.quantity), let unitPrice = Decimal(storageText: entry.unitPrice) else {
            return nil
        }
        return TransactionInfo(
            id: entry.id, kind: entry.kind, personID: entry.personID, assetID: entry.assetID, locationID: entry.locationID,
            quantity: quantity, unitPrice: unitPrice, date: entry.date, createdAt: entry.createdAt, transferID: entry.transferID
        )
    }

    // Tarihler saniyenin altına kadar korunsun diye varsayılan (sayısal) biçim kullanılır.
    private static func encode<T: Encodable>(_ value: T) -> String? {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func decode<T: Decodable>(_ text: String?) throws -> T? {
        guard let text else { return nil }
        guard let data = text.data(using: .utf8), let value = try? JSONDecoder().decode(T.self, from: data) else {
            throw UndoError.unreadable
        }
        return value
    }
}

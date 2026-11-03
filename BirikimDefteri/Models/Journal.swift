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

    private static func save(_ entry: JournalEntry, in context: ModelContext) -> JournalEntry {
        context.insert(entry)
        var descriptor = FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchOffset = keepCount
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

    // MARK: Geri alma

    static func undo(_ journalEntry: JournalEntry, ledger: Ledger, context: ModelContext) throws {
        switch journalEntry.entity {
        case .transaction, .transfer:
            try undoTransactions(journalEntry, ledger: ledger, context: context)
        case .debt:
            try undoDebt(journalEntry, ledger: ledger, context: context)
        case .payment:
            try undoPayment(journalEntry, ledger: ledger, context: context)
        }
        journalEntry.isUndone = true
        try context.save()
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

import Foundation
import SwiftData

// Kayıtlar birbirine UUID ile bağlanır; bakiyeler saklanmaz, her zaman işlemlerden hesaplanır.
// Decimal değerler kayıpsız kalsın diye metin olarak saklanır.

@Model
final class Person {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.now

    init(id: UUID = UUID(), name: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }

    var info: PersonInfo { PersonInfo(id: id, name: name) }
}

@Model
final class Location {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = "physical"
    var createdAt: Date = Date.now

    init(id: UUID = UUID(), name: String, kind: LocationKind, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.createdAt = createdAt
    }

    var kind: LocationKind {
        get { LocationKind(rawValue: kindRaw) ?? .physical }
        set { kindRaw = newValue.rawValue }
    }

    var info: LocationInfo { LocationInfo(id: id, name: name, kind: kind) }
}

@Model
final class Asset {
    var id: UUID = UUID()
    var name: String = ""
    var unitRaw: String = "adet"
    var categoryRaw: String = "other"
    var sortOrder: Int = 0
    var createdAt: Date = Date.now

    init(id: UUID = UUID(), name: String, unit: AssetUnit, category: AssetCategory, sortOrder: Int, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.unitRaw = unit.rawValue
        self.categoryRaw = category.rawValue
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    var unit: AssetUnit {
        get { AssetUnit(rawValue: unitRaw) ?? .piece }
        set { unitRaw = newValue.rawValue }
    }

    var category: AssetCategory {
        get { AssetCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var isLira: Bool { id == AssetInfo.liraID }

    var info: AssetInfo { AssetInfo(id: id, name: name, unit: unit, category: category, sortOrder: sortOrder) }
}

@Model
final class PricePoint {
    var id: UUID = UUID()
    var assetID: UUID = UUID()
    var priceText: String = "0"
    var date: Date = Date.now

    init(id: UUID = UUID(), assetID: UUID, price: Decimal, date: Date = .now) {
        self.id = id
        self.assetID = assetID
        self.priceText = price.storageText
        self.date = date
    }

    var price: Decimal { Decimal(storageText: priceText) ?? 0 }

    var info: PriceInfo { PriceInfo(assetID: assetID, price: price, date: date) }
}

@Model
final class TransactionRecord {
    var id: UUID = UUID()
    var kindRaw: String = "buy"
    var personID: UUID = UUID()
    var assetID: UUID = UUID()
    var locationID: UUID = UUID()
    var quantityText: String = "0"
    var unitPriceText: String = "0"
    var date: Date = Date.now
    var note: String = ""
    var createdAt: Date = Date.now

    init(info: TransactionInfo, note: String) {
        self.id = info.id
        self.kindRaw = info.kind.rawValue
        self.personID = info.personID
        self.assetID = info.assetID
        self.locationID = info.locationID
        self.quantityText = info.quantity.storageText
        self.unitPriceText = info.unitPrice.storageText
        self.date = info.date
        self.note = note
        self.createdAt = info.createdAt
    }

    var kind: TransactionKind { TransactionKind(rawValue: kindRaw) ?? .buy }
    var quantity: Decimal { Decimal(storageText: quantityText) ?? 0 }
    var unitPrice: Decimal { Decimal(storageText: unitPriceText) ?? 0 }

    var info: TransactionInfo {
        TransactionInfo(
            id: id, kind: kind, personID: personID, assetID: assetID, locationID: locationID,
            quantity: quantity, unitPrice: unitPrice, date: date, createdAt: createdAt
        )
    }

    func update(from info: TransactionInfo, note: String) {
        kindRaw = info.kind.rawValue
        personID = info.personID
        assetID = info.assetID
        locationID = info.locationID
        quantityText = info.quantity.storageText
        unitPriceText = info.unitPrice.storageText
        date = info.date
        self.note = note
    }
}

@Model
final class Debt {
    var id: UUID = UUID()
    var personID: UUID = UUID()
    var institution: String = ""
    var kindRaw: String = "loan"
    var title: String = ""
    var remainingText: String = "0"
    var monthlyInstallmentText: String?
    var dueDate: Date?
    var note: String = ""
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(), personID: UUID, institution: String, kind: DebtKind, title: String,
        remaining: Decimal, monthlyInstallment: Decimal?, dueDate: Date?, note: String, updatedAt: Date = .now
    ) {
        self.id = id
        self.personID = personID
        self.institution = institution
        self.kindRaw = kind.rawValue
        self.title = title
        self.remainingText = remaining.storageText
        self.monthlyInstallmentText = monthlyInstallment?.storageText
        self.dueDate = dueDate
        self.note = note
        self.updatedAt = updatedAt
    }

    var kind: DebtKind {
        get { DebtKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var remaining: Decimal {
        get { Decimal(storageText: remainingText) ?? 0 }
        set { remainingText = newValue.storageText }
    }

    var monthlyInstallment: Decimal? {
        get { monthlyInstallmentText.flatMap { Decimal(storageText: $0) } }
        set { monthlyInstallmentText = newValue?.storageText }
    }

    var info: DebtInfo {
        DebtInfo(id: id, personID: personID, kind: kind, remaining: remaining, monthlyInstallment: monthlyInstallment)
    }
}

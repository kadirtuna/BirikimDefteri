import Foundation

// Hesaplama katmanının kullandığı, SwiftUI ve SwiftData'dan bağımsız değer tipleri.

enum TransactionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case buy, sell
    /// Aktarımın iki ayağı: varlık maliyetiyle birlikte bir yerden çıkıp başka bir yere girer.
    case transferOut, transferIn

    var id: Self { self }

    /// Alış/satış formunda seçilebilen türler.
    static let tradeKinds: [TransactionKind] = [.buy, .sell]

    var title: String {
        switch self {
        case .buy: "Alış"
        case .sell: "Satış"
        case .transferOut, .transferIn: "Aktarım"
        }
    }

    var isTransfer: Bool { self == .transferOut || self == .transferIn }
    /// Bakiyeyi artıran türler.
    var addsQuantity: Bool { self == .buy || self == .transferIn }
}

enum AssetUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case gram = "gr"
    case piece = "adet"
    case usd = "$"
    case eur = "€"
    case lira = "₺"

    var id: Self { self }
    var symbol: String { rawValue }

    /// Para birimi olan birimler miktar gösterilirken para biçimiyle yazılır.
    var currencyCode: String? {
        switch self {
        case .usd: "USD"
        case .eur: "EUR"
        case .lira: "TRY"
        case .gram, .piece: nil
        }
    }
}

enum AssetCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case gold, silver, currency, fund, lira, other

    var id: Self { self }

    var title: String {
        switch self {
        case .gold: "Altın"
        case .silver: "Gümüş"
        case .currency: "Döviz"
        case .fund: "Fon"
        case .lira: "TL"
        case .other: "Diğer"
        }
    }
}

enum LocationKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case physical, bank

    var id: Self { self }

    var title: String {
        switch self {
        case .physical: "Fiziki"
        case .bank: "Banka"
        }
    }

    var symbol: String {
        switch self {
        case .physical: "house"
        case .bank: "building.columns"
        }
    }
}

enum DebtKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case loan, creditCard, other

    var id: Self { self }

    var title: String {
        switch self {
        case .loan: "Kredi"
        case .creditCard: "Kredi kartı"
        case .other: "Diğer"
        }
    }

    var dueDateTitle: String {
        self == .creditCard ? "Son ödeme tarihi" : "Bitiş tarihi"
    }
}

struct PersonInfo: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
}

struct LocationInfo: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var kind: LocationKind
}

struct AssetInfo: Identifiable, Hashable, Sendable {
    /// İlk açılışta oluşturulan Türk lirasının sabit kimliği. Silinemez, fiyatı her zaman 1'dir.
    static let liraID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    let id: UUID
    var name: String
    var unit: AssetUnit
    var category: AssetCategory
    var sortOrder: Int = 0
}

struct PriceInfo: Hashable, Sendable {
    let assetID: UUID
    var price: Decimal
    var date: Date
    /// Doluysa bu fiyat yalnızca o yerdeki bakiyeler için geçerlidir (ör. bankanın altın alış fiyatı).
    var locationID: UUID? = nil
}

struct TransactionInfo: Identifiable, Hashable, Sendable {
    let id: UUID
    var kind: TransactionKind
    var personID: UUID
    var assetID: UUID
    var locationID: UUID
    var quantity: Decimal
    var unitPrice: Decimal
    var date: Date
    var createdAt: Date
    /// Aktarımın iki ayağını eşleştirir; alış ve satışta nil.
    var transferID: UUID? = nil

    var key: HoldingKey { HoldingKey(personID: personID, assetID: assetID, locationID: locationID) }
    var total: Decimal { quantity * unitPrice }
}

struct DebtInfo: Identifiable, Hashable, Sendable {
    let id: UUID
    var personID: UUID
    var kind: DebtKind
    var remaining: Decimal
    var monthlyInstallment: Decimal?
}

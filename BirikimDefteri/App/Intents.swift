import AppIntents
import SwiftData

// Kısayollar ve Siri: "Birikim Defteri ile alım ekle". Kayıt uygulamanın deposuna doğrudan yazılır.
// iPhone'un kilidi açık olmalıdır; tutar sesli okunmaz.

struct AssetEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Ürün"
    static var defaultQuery = AssetEntityQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct AssetEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [AssetEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [AssetEntity] {
        all().filter { $0.name.localizedStandardContains(string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [AssetEntity] { all() }

    @MainActor
    private func all() -> [AssetEntity] {
        Ledger.fetch(from: AppContainer.shared.mainContext).assets.map { AssetEntity(id: $0.id, name: $0.name) }
    }
}

struct PlaceEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Saklama yeri"
    static var defaultQuery = PlaceEntityQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct PlaceEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [PlaceEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [PlaceEntity] {
        all().filter { $0.name.localizedStandardContains(string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [PlaceEntity] { all() }

    @MainActor
    private func all() -> [PlaceEntity] {
        Ledger.fetch(from: AppContainer.shared.mainContext).locations.map { PlaceEntity(id: $0.id, name: $0.name) }
    }
}

struct PersonEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Kişi"
    static var defaultQuery = PersonEntityQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct PersonEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [PersonEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [PersonEntity] {
        all().filter { $0.name.localizedStandardContains(string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [PersonEntity] { all() }

    @MainActor
    private func all() -> [PersonEntity] {
        Ledger.fetch(from: AppContainer.shared.mainContext).people.map { PersonEntity(id: $0.id, name: $0.name) }
    }
}

enum TradeKind: String, AppEnum {
    case buy, sell

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "İşlem türü"
    static var caseDisplayRepresentations: [TradeKind: DisplayRepresentation] = [.buy: "Alış", .sell: "Satış"]

    var kind: TransactionKind { self == .buy ? .buy : .sell }
}

/// Kısayolda gösterilen Türkçe hata.
struct IntentMessage: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

struct AddTradeIntent: AppIntent {
    static var title: LocalizedStringResource = "Alım ya da satım ekle"
    static var description = IntentDescription(
        "Birikim Defteri'ne yeni bir alım ya da satım kaydeder. Birim fiyat verilmezse güncel fiyat, yer ve kişi verilmezse son kullanılanlar kullanılır."
    )
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Ürün", requestValueDialog: "Hangi ürün?")
    var asset: AssetEntity

    @Parameter(title: "Miktar", requestValueDialog: "Ne kadar?")
    var quantity: Double

    @Parameter(title: "İşlem", default: .buy)
    var kind: TradeKind

    @Parameter(title: "Birim fiyat (₺)")
    var unitPrice: Double?

    @Parameter(title: "Yer")
    var location: PlaceEntity?

    @Parameter(title: "Kişi")
    var person: PersonEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$quantity) \(\.$asset) \(\.$kind)") {
            \.$unitPrice
            \.$location
            \.$person
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = AppContainer.shared.mainContext
        let ledger = Ledger.fetch(from: context)
        let calculator = ledger.calculator
        guard let info = calculator.assets[asset.id] else { throw IntentMessage(message: "Ürün bulunamadı.") }
        // Double'ın ikili gösterimi yerine yazıldığı gibi (2.5 → 2,5) alınsın.
        guard let amount = Decimal(string: String(quantity)), amount > 0 else {
            throw IntentMessage(message: "Miktar sıfırdan büyük olmalı.")
        }

        let price: Decimal
        if info.unit == .lira {
            price = 1
        } else if let unitPrice {
            guard let given = Decimal(string: String(unitPrice)), given > 0 else {
                throw IntentMessage(message: "Birim fiyat sıfırdan büyük olmalı.")
            }
            price = given
        } else if let current = calculator.price(of: info.id) {
            price = current
        } else {
            throw IntentMessage(message: "\(info.name) için güncel fiyat yok; birim fiyatı da verin.")
        }

        guard let personID = person?.id ?? RecentChoices.person(among: ledger.people.map(\.id)) ?? ledger.people.first?.id,
              let locationID = location?.id ?? RecentChoices.location(among: ledger.locations.map(\.id)) ?? ledger.locations.first?.id
        else { throw IntentMessage(message: "Önce uygulamada bir kişi ve saklama yeri tanımlayın.") }

        let draft = TransactionInfo(
            id: UUID(), kind: kind.kind, personID: personID, assetID: info.id, locationID: locationID,
            quantity: amount, unitPrice: price, date: Calendar.current.startOfDay(for: .now), createdAt: .now
        )
        if let error = calculator.validate(draft) {
            throw IntentMessage(message: error.message(unit: info.unit))
        }

        let record = TransactionRecord(info: draft, note: "Kısayollar ile eklendi")
        context.insert(record)
        Journal.recordTransactions(.added, summary: Journal.describe(draft, ledger: ledger), before: [TransactionRecord](), after: [record], in: context)
        RecentChoices.remember(personID: personID, locationID: locationID)
        try context.save()
        AutoBackup.saveIfChanged(Ledger.fetch(from: context))

        let what = "\(Format.plainQuantity(amount, unit: info.unit)) \(info.name) \(kind == .buy ? "alımı" : "satışı")"
        return .result(dialog: "\(what) eklendi · \(ledger.personName(personID)) · \(ledger.locationName(locationID)).")
    }
}

struct BirikimShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTradeIntent(),
            phrases: [
                "\(.applicationName) ile alım ekle",
                "\(.applicationName) alım ekle",
                "\(.applicationName) ile \(\.$asset) ekle",
                "\(.applicationName) ile \(\.$asset) aldım",
            ],
            shortTitle: "Alım ekle",
            systemImageName: "plus.circle"
        )
    }
}

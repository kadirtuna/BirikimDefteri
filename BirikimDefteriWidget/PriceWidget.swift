import AppIntents
import SwiftUI
import UIKit
import WidgetKit

@main
struct BirikimDefteriWidgets: WidgetBundle {
    var body: some Widget {
        InstitutionPriceWidget()
    }
}

// MARK: - Ayarlar

enum WidgetInstrument: String, AppEnum {
    case gramGold, silver, usd, eur

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Ürün"
    static var caseDisplayRepresentations: [WidgetInstrument: DisplayRepresentation] = [
        .gramGold: "Gram altın", .silver: "Gümüş", .usd: "Dolar", .eur: "Euro",
    ]

    var instrument: BidInstrument { BidInstrument(rawValue: rawValue) ?? .gramGold }
}

/// Widget'ta gösterilebilecek bir kurum (doviz.com kısaltması, Midas ya da kuyumcuların en düşük alışı).
struct InstitutionChoice: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Kurum"
    static var defaultQuery = InstitutionChoiceQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    static var all: [InstitutionChoice] {
        let dealers = ["kapalicarsi": "Kapalıçarşı", "altinkaynak": "Altınkaynak", "harem": "Harem", "odaci": "Odacı", "venus": "Venüs"]
        let banks = BidSource.institutions.map { slug, id in
            InstitutionChoice(id: slug, name: Institution.all.first { $0.id == id }?.name ?? slug)
        }
        return [InstitutionChoice(id: WidgetPlaces.dealersSlug, name: "Kuyumcu (en düşük alış)"),
                InstitutionChoice(id: PriceBoard.midasSlug, name: "Midas (XAUT)")]
            + dealers.map { InstitutionChoice(id: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
            + banks.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
}

struct InstitutionChoiceQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [InstitutionChoice] {
        identifiers.compactMap { id in InstitutionChoice.all.first { $0.id == id } }
    }

    func entities(matching string: String) async throws -> [InstitutionChoice] {
        InstitutionChoice.all.filter { $0.name.localizedStandardContains(string) }
    }

    func suggestedEntities() async throws -> [InstitutionChoice] { InstitutionChoice.all }
}

struct PriceWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Kurum fiyatları"
    static var description = IntentDescription("Kurumların alış ve satış fiyatları. Kurum seçmezseniz varlıklarınızın durduğu yerler gösterilir.")

    @Parameter(title: "Ürün", default: .gramGold)
    var instrument: WidgetInstrument

    @Parameter(title: "Kurumlar")
    var institutions: [InstitutionChoice]?
}

// MARK: - Zaman çizelgesi

struct PriceProvider: AppIntentTimelineProvider {
    /// Kullanıcı kurum seçmediyse ve uygulama henüz kurum listesi yazmadıysa gösterilenler.
    private static let fallback = ["kapalicarsi", "ziraat-bankasi", "garanti-bbva", "isbankasi"]

    func placeholder(in context: Context) -> PriceEntry {
        PriceEntry(date: .now, instrument: .gramGold, rows: [
            PriceRowData(slug: "kapalicarsi", name: "Kapalıçarşı", bid: 6514.22, ask: 6520.55),
            PriceRowData(slug: "ziraat-bankasi", name: "Ziraat Bankası", bid: 6441.31, ask: 6571.36),
        ], priceDate: .now)
    }

    func snapshot(for configuration: PriceWidgetIntent, in context: Context) async -> PriceEntry {
        let board = SharedStore.load(PriceBoard.self, key: SharedStore.boardKey)
        return entry(configuration, board: board) ?? placeholder(in: context)
    }

    func timeline(for configuration: PriceWidgetIntent, in context: Context) async -> Timeline<PriceEntry> {
        var board = SharedStore.load(PriceBoard.self, key: SharedStore.boardKey)
        if let fresh = await PriceBoard.fetch() {
            var merged = board ?? fresh
            merged.date = fresh.date
            merged.tables.merge(fresh.tables) { _, new in new }
            merged.xautPerGram = fresh.xautPerGram ?? merged.xautPerGram
            board = merged
            SharedStore.save(merged, key: SharedStore.boardKey)
        }
        let current = entry(configuration, board: board)
            ?? PriceEntry(date: .now, instrument: configuration.instrument.instrument, rows: [], priceDate: nil)
        return Timeline(entries: [current], policy: .after(.now.addingTimeInterval(30 * 60)))
    }

    private func entry(_ configuration: PriceWidgetIntent, board: PriceBoard?) -> PriceEntry? {
        guard let board else { return nil }
        let instrument = configuration.instrument.instrument
        let saved = SharedStore.load(WidgetPlaces.self, key: SharedStore.placesKey)?.places[instrument] ?? []
        let slugs = configuration.institutions.map { $0.map(\.id) } ?? (saved.isEmpty ? Self.fallback : saved)
        let names = Dictionary(InstitutionChoice.all.map { ($0.id, $0.name.replacingOccurrences(of: " (XAUT)", with: "")) }) { first, _ in first }
        return PriceEntry.make(board: board, instrument: instrument, slugs: slugs, names: names)
    }
}

// MARK: - Görünüm

struct InstitutionPriceWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "InstitutionPrices", intent: PriceWidgetIntent.self, provider: PriceProvider()) { entry in
            FamilyReader { family in
                PriceWidgetView(entry: entry, family: family)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Kurum fiyatları")
        .description("Altın, gümüş, dolar ve euroda kurumların alış ve satış fiyatları. Alış: bozdururken eline geçen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}


/// Widget ailesini ortamdan okuyup görünüme verir; görünüm uygulamadaki önizlemede de kullanılabilsin diye.
private struct FamilyReader<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    @ViewBuilder let content: (WidgetFamily) -> Content

    var body: some View { content(family) }
}

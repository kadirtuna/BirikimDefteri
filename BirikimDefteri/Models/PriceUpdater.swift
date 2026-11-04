import Foundation
import SwiftData
import WidgetKit

/// Güncel fiyatları internetten çeker: altın ve gümüş Truncgil Finans'tan (Kapalıçarşı alış fiyatı),
/// dolar ve euro TCMB döviz alış kurundan, XAUT CoinGecko'dan. Bakiyelerin durduğu yerler için ayrıca
/// o kurumun alış fiyatını doviz.com tablolarından alır (bkz. `BidSource`). Yalnızca herkese açık fiyat verisi
/// indirilir; kişisel veri gönderilmez.
@MainActor
@Observable
final class PriceUpdater {
    static let autoUpdateKey = "autoPriceUpdate"
    private static let lastUpdateKey = "lastPriceUpdate"
    private static let goldURL = URL(string: "https://finans.truncgil.com/today.json")!
    private static let currencyURL = URL(string: "https://www.tcmb.gov.tr/kurlar/today.xml")!

    enum Status: Equatable {
        case idle
        case updating
        case updated(count: Int)
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var lastUpdate: Date? = UserDefaults.standard.object(forKey: PriceUpdater.lastUpdateKey) as? Date
    /// Kurumların son alış ve satış fiyatları (Fiyatlar ekranı ve widget için).
    private(set) var board: PriceBoard? = SharedStore.load(PriceBoard.self, key: SharedStore.boardKey)

    var isUpdating: Bool { status == .updating }

    /// Son başarılı güncellemenin üzerinden `interval` geçtiyse günceller. Henüz hiç yere özel alış fiyatı yoksa
    /// (ör. bu özellik geldikten sonraki ilk açılış) beklemeden günceller.
    func updateIfStale(assets: [Asset], prices: [PricePoint], context: ModelContext, interval: TimeInterval = 3600) async {
        if let lastUpdate, Date.now.timeIntervalSince(lastUpdate) < interval, prices.contains(where: { $0.locationID != nil }) {
            return
        }
        await update(assets: assets, prices: prices, context: context)
    }

    /// Fiyatı çekilebilen ürünler için, son kayıttan farklıysa yeni fiyat kaydı oluşturur.
    func update(assets: [Asset], prices: [PricePoint], context: ModelContext) async {
        guard !isUpdating else { return }
        status = .updating
        async let fetchedQuotes = Self.fetchQuotes()
        async let fetchedBoard = PriceBoard.fetch()
        var (quotes, fetched) = await (fetchedQuotes, fetchedBoard)
        guard !quotes.isEmpty else {
            status = .failed("Fiyatlar alınamadı. İnternet bağlantınızı kontrol edip yeniden deneyin.")
            return
        }
        if let xaut = fetched?.xautPerGram { quotes[.xaut] = xaut }
        let tables = (fetched?.tables ?? [:]).mapValues { $0.mapValues(\.bid) }
        let infos = prices.map(\.info)
        let latest = Dictionary(grouping: infos.filter { $0.locationID == nil }, by: \.assetID)
            .compactMapValues { $0.max { $0.date < $1.date }?.price }
        let now = Date.now
        var count = 0
        var updatedAssets: Set<UUID> = []
        for asset in assets {
            guard let key = QuoteKey.key(for: asset.info), let price = quotes[key], latest[asset.id] != price else { continue }
            context.insert(PricePoint(assetID: asset.id, price: price, date: now))
            updatedAssets.insert(asset.id)
            count += 1
        }

        // Yere özel alış fiyatları: yalnızca işlem kaydı olan ürün × yer çiftleri için. Genel fiyat bu turda
        // değiştiyse alış fiyatı aynı kalsa bile yeniden yazılır, ikisi aynı ana ait olsun diye.
        let ledger = Ledger.fetch(from: context)
        let latestLocal = Dictionary(grouping: infos.filter { $0.locationID != nil }) {
            HoldingPlace(assetID: $0.assetID, locationID: $0.locationID ?? UUID())
        }.compactMapValues { $0.max { $0.date < $1.date }?.price }
        let places = Set(ledger.transactions.map { HoldingPlace(assetID: $0.assetID, locationID: $0.locationID) })
        for place in places {
            guard let asset = ledger.calculator.assets[place.assetID], let location = ledger.calculator.locations[place.locationID],
                  let key = QuoteKey.key(for: asset), let instrument = BidInstrument(key),
                  let bid = BidSource.bid(for: instrument, at: location, tables: tables, xautPerGram: quotes[.xaut]),
                  latestLocal[place] != bid || updatedAssets.contains(place.assetID)
            else { continue }
            context.insert(PricePoint(assetID: place.assetID, price: bid, date: now, locationID: place.locationID))
        }
        if let fetched {
            // Alınamayan tablolar için bir önceki tablo korunur.
            var merged = board ?? fetched
            merged.date = fetched.date
            merged.tables.merge(fetched.tables) { _, new in new }
            merged.xautPerGram = fetched.xautPerGram ?? merged.xautPerGram
            board = merged
            SharedStore.save(merged, key: SharedStore.boardKey)
        }
        Self.saveWidgetPlaces(ledger, reload: false)
        WidgetCenter.shared.reloadAllTimelines()
        try? context.save()
        lastUpdate = now
        UserDefaults.standard.set(now, forKey: Self.lastUpdateKey)
        status = .updated(count: count)
    }

    private nonisolated static func fetchQuotes() async -> [QuoteKey: Decimal] {
        async let gold = fetchGold()
        async let currency = try? fetch(currencyURL)
        var quotes = await gold
        if let data = await currency {
            quotes.merge(QuoteParser.tcmb(data)) { _, official in official }
        }
        return quotes
    }

    /// Widget'ın varsayılan kurumları: her ürün için o ürünün bulunduğu yerler, değere göre büyükten küçüğe.
    /// Değiştiyse kaydeder ve `reload` açıksa widget'ı yeniler.
    static func saveWidgetPlaces(_ ledger: Ledger, reload: Bool = true) {
        let calculator = ledger.calculator
        var places: [BidInstrument: [String]] = [:]
        for holding in calculator.holdings().sorted(by: { ($0.value ?? 0) > ($1.value ?? 0) }) {
            guard let asset = calculator.assets[holding.key.assetID], let key = QuoteKey.key(for: asset),
                  let instrument = BidInstrument(key), let location = calculator.locations[holding.key.locationID],
                  let slug = BidSource.slug(for: location), !(places[instrument] ?? []).contains(slug)
            else { continue }
            places[instrument, default: []].append(slug)
        }
        let new = WidgetPlaces(places: places)
        guard SharedStore.load(WidgetPlaces.self, key: SharedStore.placesKey)?.places != new.places else { return }
        SharedStore.save(new, key: SharedStore.placesKey)
        if reload { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// Truncgil akışı ara sıra yarıda kesildiği için eksik gelirse birkaç kez dener, en dolu yanıtı kullanır.
    private nonisolated static func fetchGold() async -> [QuoteKey: Decimal] {
        var best: [QuoteKey: Decimal] = [:]
        for attempt in 1...3 {
            if let data = try? await fetch(goldURL) {
                let quotes = QuoteParser.truncgil(data)
                if quotes.count > best.count { best = quotes }
                if best.count == QuoteKey.truncgilKeys.count { break }
            }
            try? await Task.sleep(for: .milliseconds(400 * attempt))
        }
        return best
    }

    private nonisolated static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("BirikimDefteri/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}

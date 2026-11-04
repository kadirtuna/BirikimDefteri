import Foundation
import SwiftData

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
    private static let xautURL = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=tether-gold&vs_currencies=try")!

    enum Status: Equatable {
        case idle
        case updating
        case updated(count: Int)
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var lastUpdate: Date? = UserDefaults.standard.object(forKey: PriceUpdater.lastUpdateKey) as? Date

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
        async let fetchedTables = Self.fetchBidTables()
        let (quotes, tables) = await (fetchedQuotes, fetchedTables)
        guard !quotes.isEmpty else {
            status = .failed("Fiyatlar alınamadı. İnternet bağlantınızı kontrol edip yeniden deneyin.")
            return
        }
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
        try? context.save()
        lastUpdate = now
        UserDefaults.standard.set(now, forKey: Self.lastUpdateKey)
        status = .updated(count: count)
    }

    private nonisolated static func fetchQuotes() async -> [QuoteKey: Decimal] {
        async let gold = fetchGold()
        async let currency = try? fetch(currencyURL)
        async let xaut = try? fetch(xautURL)
        var quotes = await gold
        if let data = await currency {
            quotes.merge(QuoteParser.tcmb(data)) { _, official in official }
        }
        if let data = await xaut, let price = QuoteParser.coinGeckoXAUT(data) {
            quotes[.xaut] = price
        }
        return quotes
    }

    /// Yere özel fiyatların karşılaştırma tabloları; alınamayan tablo boş kalır, o yerlerde son fiyat farkı korunur.
    private nonisolated static func fetchBidTables() async -> [BidInstrument: [String: Decimal]] {
        await withTaskGroup(of: (BidInstrument, [String: Decimal]).self) { group in
            for instrument in BidInstrument.allCases {
                group.addTask {
                    let page = instrument.page
                    guard let data = try? await fetch(page.url) else { return (instrument, [:]) }
                    return (instrument, QuoteParser.dovizBids(data, key: page.key))
                }
            }
            var tables: [BidInstrument: [String: Decimal]] = [:]
            for await (instrument, table) in group where !table.isEmpty {
                tables[instrument] = table
            }
            return tables
        }
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

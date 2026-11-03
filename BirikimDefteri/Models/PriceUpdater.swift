import Foundation
import SwiftData

/// Güncel fiyatları internetten çeker: altın ve gümüş Truncgil Finans'tan (Kapalıçarşı alış fiyatı),
/// dolar ve euro TCMB döviz alış kurundan. Yalnızca herkese açık fiyat verisi indirilir; kişisel veri gönderilmez.
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

    var isUpdating: Bool { status == .updating }

    /// Son başarılı güncellemenin üzerinden `interval` geçtiyse günceller.
    func updateIfStale(assets: [Asset], prices: [PricePoint], context: ModelContext, interval: TimeInterval = 3600) async {
        if let lastUpdate, Date.now.timeIntervalSince(lastUpdate) < interval { return }
        await update(assets: assets, prices: prices, context: context)
    }

    /// Fiyatı çekilebilen ürünler için, son kayıttan farklıysa yeni fiyat kaydı oluşturur.
    func update(assets: [Asset], prices: [PricePoint], context: ModelContext) async {
        guard !isUpdating else { return }
        status = .updating
        let quotes = await Self.fetchQuotes()
        guard !quotes.isEmpty else {
            status = .failed("Fiyatlar alınamadı. İnternet bağlantınızı kontrol edip yeniden deneyin.")
            return
        }
        let latest = Dictionary(grouping: prices.map(\.info), by: \.assetID)
            .compactMapValues { $0.max { $0.date < $1.date }?.price }
        let now = Date.now
        var count = 0
        for asset in assets {
            guard let key = QuoteKey.key(for: asset.info), let price = quotes[key], latest[asset.id] != price else { continue }
            context.insert(PricePoint(assetID: asset.id, price: price, date: now))
            count += 1
        }
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

    /// Truncgil akışı ara sıra yarıda kesildiği için eksik gelirse birkaç kez dener, en dolu yanıtı kullanır.
    private nonisolated static func fetchGold() async -> [QuoteKey: Decimal] {
        var best: [QuoteKey: Decimal] = [:]
        for attempt in 1...3 {
            if let data = try? await fetch(goldURL) {
                let quotes = QuoteParser.truncgil(data)
                if quotes.count > best.count { best = quotes }
                if best.count == QuoteKey.allCases.count { break }
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

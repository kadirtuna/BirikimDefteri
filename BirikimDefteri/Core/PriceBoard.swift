import Foundation

/// Bir kurumun bir üründeki alış ve satış fiyatı. Alış: kurumun sizden alacağı (bozdururken eline geçen),
/// satış: kurumun size satacağı fiyat.
struct InstitutionQuote: Codable, Hashable, Sendable {
    let name: String
    let bid: Decimal
    let ask: Decimal?

    /// Alış ile satış arasındaki farkın satışa oranı.
    var spread: Decimal? {
        guard let ask, ask > 0 else { return nil }
        return (ask - bid) / ask
    }
}

/// Kurumların son alış ve satış fiyatları. Uygulama ile widget aynı tabloyu kullanır.
struct PriceBoard: Codable, Sendable {
    /// Midas'ın kimliği; tabloda doviz.com kurumlarının yanında ayrıca gösterilir.
    static let midasSlug = "midas"

    var date: Date
    /// Ürün → kurum adı (doviz.com kısaltması) → fiyat.
    var tables: [BidInstrument: [String: InstitutionQuote]]
    /// XAUT'un gram başına piyasa fiyatı.
    var xautPerGram: Decimal?

    var isEmpty: Bool { tables.isEmpty && xautPerGram == nil }

    func bids(_ instrument: BidInstrument) -> [String: Decimal] {
        (tables[instrument] ?? [:]).mapValues(\.bid)
    }

    /// Ürünün kurum fiyatları; altında Midas da eklenir. Midas fiyat yayımlamadığı için XAUT piyasa fiyatından
    /// tahmin edilir: alış değerlemedeki gibi kesintiler düşülerek, satış aynı oranda eklenerek.
    func quotes(_ instrument: BidInstrument) -> [String: InstitutionQuote] {
        var result = tables[instrument] ?? [:]
        if instrument == .gramGold, let xautPerGram {
            result[Self.midasSlug] = InstitutionQuote(
                name: "Midas (XAUT, tahmini)",
                bid: BidSource.rounded(xautPerGram * BidSource.xautDiscount),
                ask: BidSource.rounded(xautPerGram * (2 - BidSource.xautDiscount))
            )
        }
        return result
    }

    /// Kurum adının listede görünecek hâli.
    static func displayName(_ slug: String, fallback: String) -> String {
        slug == midasSlug ? "Midas" : fallback
    }

    /// Bütün tabloları ve XAUT fiyatını internetten çeker. Alınamayan tablo boş kalır; hiçbiri alınamazsa nil.
    static func fetch() async -> PriceBoard? {
        async let xaut = fetchXAUT()
        let tables = await withTaskGroup(of: (BidInstrument, [String: InstitutionQuote]).self) { group in
            for instrument in BidInstrument.allCases {
                group.addTask {
                    let page = instrument.page
                    guard let data = try? await download(page.url) else { return (instrument, [:]) }
                    return (instrument, QuoteParser.dovizQuotes(data, key: page.key))
                }
            }
            var tables: [BidInstrument: [String: InstitutionQuote]] = [:]
            for await (instrument, table) in group where !table.isEmpty {
                tables[instrument] = table
            }
            return tables
        }
        let board = PriceBoard(date: .now, tables: tables, xautPerGram: await xaut)
        return board.isEmpty ? nil : board
    }

    static let xautURL = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=tether-gold&vs_currencies=try")!

    static func fetchXAUT() async -> Decimal? {
        guard let data = try? await download(xautURL) else { return nil }
        return QuoteParser.coinGeckoXAUT(data)
    }

    static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("BirikimDefteri/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}

/// Widget'ın varsayılan olarak göstereceği kurumlar: kullanıcının o ürünü tuttuğu yerler.
struct WidgetPlaces: Codable, Sendable {
    /// Ürün → sırayla kurum kısaltmaları. Fiziki yerler `dealersSlug` ile gösterilir.
    var places: [BidInstrument: [String]]

    /// Fiziki yer: büyük kuyumcuların en düşük alışı.
    static let dealersSlug = "kuyumcu"
}

extension PriceBoard {
    /// Bir kurumun fiyatı; `kuyumcu` için büyük kuyumcuların en düşük alışı ve en düşük satışı.
    func quote(_ instrument: BidInstrument, slug: String) -> InstitutionQuote? {
        let quotes = quotes(instrument)
        if slug == WidgetPlaces.dealersSlug {
            let dealers = quotes.filter { BidSource.dealers.contains($0.key) }.values
            guard let bid = dealers.map(\.bid).min() else { return nil }
            return InstitutionQuote(name: "Kuyumcu (en düşük alış)", bid: bid, ask: dealers.compactMap(\.ask).min())
        }
        return quotes[slug]
    }
}

/// Uygulama ile widget arasında paylaşılan küçük veriler. Ücretsiz Apple hesabı App Group'a izin vermediği için
/// aynı takımın paylaşılan Anahtar Zinciri grubu kullanılır (bkz. `*.entitlements`).
enum SharedStore {
    private static let service = "com.kadirtuna.birikimdefteri.shared"
    static let boardKey = "price-board"
    static let placesKey = "widget-places"

    static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: key]
        let attributes: [String: Any] = [kSecValueData as String: data,
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
    }

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: key, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

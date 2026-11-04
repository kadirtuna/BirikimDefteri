import Foundation

/// Yere özel alış fiyatı: bir bakiyeyi bozdurduğunuzda eline geçecek birim fiyat.
/// Kaynak doviz.com'un banka ve kuyumcu karşılaştırma tablolarıdır; her tablo bir ürün için bütün kurumların
/// alış fiyatlarını verir. Midas'taki altın XAUT piyasa fiyatından satış kesintileri düşülerek değerlenir.
enum BidInstrument: String, CaseIterable, Sendable {
    case gramGold, silver, usd, eur

    /// Ürünün genel fiyat anahtarından yere özel fiyat türü. Çeyrek, bilezik gibi kuyumcu ürünleri
    /// genel fiyatta zaten kuyumcu alış fiyatıyla tutulduğu için burada yoktur.
    init?(_ key: QuoteKey) {
        switch key {
        case .gramGold: self = .gramGold
        case .silver: self = .silver
        case .usd: self = .usd
        case .eur: self = .eur
        default: return nil
        }
    }

    /// Bütün kurumların bulunduğu karşılaştırma tablosunun sayfası ve tablodaki fiyat anahtarı.
    var page: (url: URL, key: String) {
        switch self {
        case .gramGold: (URL(string: "https://altin.doviz.com/fibabanka/gram-altin")!, "gram-altin")
        case .silver: (URL(string: "https://altin.doviz.com/fibabanka/gumus")!, "gumus")
        case .usd: (URL(string: "https://kur.doviz.com/fibabanka/amerikan-dolari")!, "USD")
        case .eur: (URL(string: "https://kur.doviz.com/fibabanka/euro")!, "EUR")
        }
    }
}

enum BidSource {
    /// Fiziki altını ve dövizi alan büyük kuyumcu ve döviz büroları; aralarındaki en düşük alış kullanılır.
    static let dealers: Set<String> = ["kapalicarsi", "altinkaynak", "harem", "odaci", "venus"]

    /// doviz.com kurum adı → uygulamadaki kurum kimliği.
    static let institutions: [String: String] = [
        "akbank": "akbank", "albaraka-turk": "albaraka", "alternatif-bank": "alternatifbank", "anadolubank": "anadolubank",
        "cepteteb": "teb", "denizbank": "denizbank", "dunya-katilim": "dunyakatilim", "emlak-katilim": "emlakkatilim",
        "enpara": "enpara", "fibabanka": "fibabanka", "garanti-bbva": "garanti", "hadi": "tomkatilim", "halkbank": "halkbank",
        "hayat-finans": "hayatfinans", "hsbc": "hsbc", "ing-bank": "ing", "isbankasi": "isbank", "kuveyt-turk": "kuveytturk",
        "odeabank": "odeabank", "qnb-finansbank": "qnb", "turkiye-finans": "turkiyefinans", "vakifbank": "vakifbank",
        "vakif-katilim": "vakifkatilim", "yapikredi": "yapikredi", "ziraat-bankasi": "ziraat", "ziraat-katilim": "ziraatkatilim",
    ]

    /// Midas'ta kripto satış komisyonunun en yüksek kademesi (%0,20) ve alış-satış farkı için %0,30 pay.
    static let xautDiscount = Decimal(string: "0.995", locale: Locale(identifier: "en_US_POSIX"))!

    /// Bir yerdeki ürünün alış fiyatı. Tanınan bankada o bankanın, fiziki yerde kuyumcuların en düşük alışı;
    /// tanınmayan bankada bütün bankaların en düşük alışı. Midas'taki altın XAUT fiyatından kesintiler düşülerek.
    static func bid(
        for instrument: BidInstrument, at location: LocationInfo, tables: [BidInstrument: [String: Decimal]], xautPerGram: Decimal?
    ) -> Decimal? {
        let table = tables[instrument] ?? [:]
        switch location.kind {
        case .physical:
            return table.filter { dealers.contains($0.key) }.values.min()
        case .bank:
            let institution = Institution.match(location.name)
            if institution?.id == "midas" {
                guard instrument == .gramGold, let xautPerGram else { return nil }
                return rounded(xautPerGram * xautDiscount)
            }
            if let id = institution?.id, let slug = institutions.first(where: { $0.value == id })?.key, let bid = table[slug] {
                return bid
            }
            return table.filter { !dealers.contains($0.key) }.values.min()
        }
    }

    static func rounded(_ value: Decimal) -> Decimal {
        var value = value
        var result = Decimal()
        NSDecimalRound(&result, &value, 2, .plain)
        return result
    }
}

extension QuoteParser {
    /// doviz.com karşılaştırma sayfasındaki ilk tablodan kurum başına alış fiyatlarını okur: [kurum adı: alış].
    static func dovizBids(_ data: Data, key: String) -> [String: Decimal] {
        guard let html = String(data: data, encoding: .utf8),
              let start = html.range(of: "<tbody>"),
              let end = html.range(of: "</tbody>", range: start.upperBound..<html.endIndex)
        else { return [:] }
        let table = String(html[start.upperBound..<end.lowerBound])
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let pattern = "doviz\\.com/([a-z0-9-]+)/[^\"]*\"[\\s\\S]*?data-socket-key=\"\\d+-\(escaped)\" data-socket-attr=\"bid\"[^>]*>\\s*([0-9.,]+)\\s*<"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        var result: [String: Decimal] = [:]
        for row in table.components(separatedBy: "<tr>") {
            let range = NSRange(row.startIndex..., in: row)
            guard let match = regex.firstMatch(in: row, range: range),
                  let slugRange = Range(match.range(at: 1), in: row),
                  let bidRange = Range(match.range(at: 2), in: row),
                  let bid = turkishNumber(String(row[bidRange])), bid > 0
            else { continue }
            result[String(row[slugRange])] = bid
        }
        return result
    }
}

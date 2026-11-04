import Foundation

/// İnternetten fiyatı çekilebilen ürünler. Ham değer, Truncgil Finans akışındaki anahtardır
/// (XAUT'ta CoinGecko kimliği).
enum QuoteKey: String, CaseIterable, Sendable {
    case gramGold = "gram-altin"
    case quarterGold = "ceyrek-altin"
    case halfGold = "yarim-altin"
    case fullGold = "tam-altin"
    case republicGold = "cumhuriyet-altini"
    case ataGold = "ata-altin"
    case resatGold = "resat-altin"
    case bracelet22 = "22-ayar-bilezik"
    case gold18 = "18-ayar-altin"
    case gold14 = "14-ayar-altin"
    case silver = "gumus"
    case usd = "USD"
    case eur = "EUR"
    /// Tether Gold token'ı (ör. Midas'taki altın). 1 XAUT = 1 ons; uygulamada gram olarak tutulur.
    case xaut = "tether-gold"

    /// Truncgil akışında bulunan anahtarlar.
    static let truncgilKeys = allCases.filter { $0 != .xaut }

    /// Ürünü adından ve biriminden tanır. Fon, TL ve tanınmayan ürünlerin fiyatı yalnızca elle girilir.
    static func key(for asset: AssetInfo) -> QuoteKey? {
        switch asset.unit {
        case .usd: return .usd
        case .eur: return .eur
        case .lira: return nil
        case .gram, .piece: break
        }
        guard asset.category != .fund else { return nil }
        let name = asset.name.lowercased(with: Format.locale)
        if name.contains("xaut") || name.contains("tether gold") { return asset.unit == .gram ? .xaut : nil }
        if name.contains("gümüş") { return asset.unit == .gram ? .silver : nil }
        let pieceKeys: [(String, QuoteKey)] = [
            ("çeyrek", .quarterGold), ("yarım", .halfGold), ("cumhuriyet", .republicGold),
            ("reşat", .resatGold), ("ata", .ataGold), ("tam", .fullGold),
        ]
        if asset.unit == .piece {
            return pieceKeys.first { name.contains($0.0) }?.1
        }
        if name.contains("bilezik") || name.contains("22 ayar") { return .bracelet22 }
        if name.contains("18 ayar") { return .gold18 }
        if name.contains("14 ayar") { return .gold14 }
        return name.contains("altın") || asset.category == .gold ? .gramGold : nil
    }
}

enum QuoteParser {
    /// Truncgil Finans `today.json` akışından alış fiyatlarını okur. Akış bazen yarıda kesildiği için
    /// JSON çözülemezse değerler metinden tek tek ayıklanır.
    static func truncgil(_ data: Data) -> [QuoteKey: Decimal] {
        var result: [QuoteKey: Decimal] = [:]
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in QuoteKey.truncgilKeys {
                if let entry = object[key.rawValue] as? [String: Any], let text = entry["Alış"] as? String,
                   let value = turkishNumber(text), value > 0 {
                    result[key] = value
                }
            }
            return result
        }
        guard let text = String(data: data, encoding: .utf8) else { return result }
        for key in QuoteKey.truncgilKeys {
            let pattern = "\"\(NSRegularExpression.escapedPattern(for: key.rawValue))\":\\{[^}]*?\"Alış\":\"([^\"]+)\""
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text),
                  let value = turkishNumber(String(text[range])), value > 0
            else { continue }
            result[key] = value
        }
        return result
    }

    /// TCMB `today.xml` bülteninden ABD doları ve euro döviz alış kurlarını okur.
    static func tcmb(_ data: Data) -> [QuoteKey: Decimal] {
        guard let text = String(data: data, encoding: .utf8) else { return [:] }
        var result: [QuoteKey: Decimal] = [:]
        for key in [QuoteKey.usd, .eur] {
            let pattern = "CurrencyCode=\"\(key.rawValue)\">.*?<ForexBuying>([0-9.]+)</ForexBuying>"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text),
                  let value = Decimal(string: String(text[range]), locale: Locale(identifier: "en_US_POSIX")), value > 0
            else { continue }
            result[key] = value
        }
        return result
    }

    /// Troy onsun gram karşılığı.
    static let gramsPerOunce = Decimal(string: "31.1034768", locale: Locale(identifier: "en_US_POSIX"))!

    /// CoinGecko `simple/price` yanıtından XAUT'un TL fiyatını okur ve 1 gramın fiyatına çevirir (kuruşa yuvarlı).
    static func coinGeckoXAUT(_ data: Data) -> Decimal? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = object[QuoteKey.xaut.rawValue] as? [String: Any],
              let number = entry["try"] as? NSNumber
        else { return nil }
        let perOunce = Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX")) ?? number.decimalValue
        guard perOunce > 0 else { return nil }
        var perGram = perOunce / gramsPerOunce
        var rounded = Decimal()
        NSDecimalRound(&rounded, &perGram, 2, .plain)
        return rounded
    }

    /// "6.287,79" ya da "$3.911,67" gibi Türkçe biçimli sayıyı okur.
    static func turkishNumber(_ text: String) -> Decimal? {
        let cleaned = text.filter { $0.isNumber || $0 == "." || $0 == "," }
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }
}

import Foundation

/// Tüm sayı ve tarih biçimleri tr_TR yerelinde: ₺1.234,50, %12,5, 2 Kas 2026.
enum Format {
    static let locale = Locale(identifier: "tr_TR")
    private static let posix = Locale(identifier: "en_US_POSIX")

    static func lira(_ value: Decimal) -> String {
        value.formatted(.currency(code: "TRY").locale(locale))
    }

    static func signedLira(_ value: Decimal) -> String {
        value.formatted(.currency(code: "TRY").locale(locale).sign(strategy: .always(showZero: false)))
    }

    static func number(_ value: Decimal, maxFractionDigits: Int = 4) -> String {
        value.formatted(.number.locale(locale).precision(.fractionLength(0...maxFractionDigits)))
    }

    /// Miktarı birimiyle yazar: "12,5 gr", "3 adet", "$1.000,00".
    static func quantity(_ value: Decimal, unit: AssetUnit) -> String {
        if let code = unit.currencyCode {
            return value.formatted(.currency(code: code).locale(locale))
        }
        return "\(number(value)) \(unit.symbol)"
    }

    static func percent(_ ratio: Decimal) -> String {
        ratio.formatted(.percent.locale(locale).precision(.fractionLength(0...1)))
    }

    static func signedPercent(_ ratio: Decimal) -> String {
        ratio.formatted(.percent.locale(locale).precision(.fractionLength(0...1)).sign(strategy: .always(includingZero: false)))
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(locale))
    }

    static func month(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year().locale(locale))
    }

    /// Metin alanına yazılacak biçim: binlik ayırıcısız, virgüllü ("2950,5").
    static func editable(_ value: Decimal) -> String {
        value.formatted(.number.locale(locale).grouping(.never).precision(.fractionLength(0...10)))
    }

    /// "1.234,50", "12,5", "0.25" ve "₺2.950" gibi girişleri okur. Geçersizse nil.
    /// Virgül yoksa, ardından tam üç rakam gelen nokta Türkçedeki gibi binlik ayırıcı sayılır.
    static func parseDecimal(_ text: String) -> Decimal? {
        var normalized = text
            .replacingOccurrences(of: "₺", with: "")
            .filter { !$0.isWhitespace }
        guard !normalized.isEmpty else { return nil }

        if normalized.contains(",") {
            normalized = normalized
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: ".")
        } else if let lastDot = normalized.lastIndex(of: "."),
                  normalized.filter({ $0 == "." }).count > 1 || normalized[normalized.index(after: lastDot)...].count == 3 {
            normalized = normalized.replacingOccurrences(of: ".", with: "")
        }

        let digits = Set("0123456789")
        guard normalized.filter({ $0 == "." }).count <= 1,
              normalized.allSatisfy({ digits.contains($0) || $0 == "." }),
              normalized.contains(where: { digits.contains($0) })
        else { return nil }
        return Decimal(string: normalized, locale: posix)
    }
}

extension Decimal {
    /// SwiftData'da kayıpsız saklamak için yerelden bağımsız metin ("1234.5").
    var storageText: String { description }

    init?(storageText: String) {
        guard let value = Decimal(string: storageText, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        self = value
    }

    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

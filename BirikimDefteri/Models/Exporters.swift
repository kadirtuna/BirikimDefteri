import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Excel'de doğrudan açılan CSV dosyaları: Türkçe Excel'e uygun noktalı virgül ayırıcı, virgüllü ondalık ve UTF-8 BOM.
@MainActor
enum CSVExporter {
    enum Kind: String, CaseIterable, Identifiable {
        case transactions, holdings, debts

        var id: Self { self }

        var title: String {
            switch self {
            case .transactions: "İşlemler"
            case .holdings: "Varlıklar"
            case .debts: "Borçlar"
            }
        }

        var filename: String {
            switch self {
            case .transactions: "Islemler"
            case .holdings: "Varliklar"
            case .debts: "Borclar"
            }
        }
    }

    static func make(_ kind: Kind, from ledger: Ledger) -> String {
        switch kind {
        case .transactions: transactions(ledger)
        case .holdings: holdings(ledger)
        case .debts: debts(ledger)
        }
    }

    nonisolated static func csv(_ rows: [[String]]) -> String {
        "\u{FEFF}" + rows.map { $0.map(escape).joined(separator: ";") }.joined(separator: "\r\n") + "\r\n"
    }

    nonisolated static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == ";" || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func number(_ value: Decimal) -> String { Format.editable(value) }

    private static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(Format.locale))
    }

    private static func transactions(_ ledger: Ledger) -> String {
        let calculator = ledger.calculator
        let rows = calculator.transactions.map { transaction -> [String] in
            let asset = calculator.assets[transaction.assetID]
            let kind: String = switch transaction.kind {
            case .buy, .sell: transaction.kind.title
            case .transferOut: "Aktarım (çıkış)"
            case .transferIn: "Aktarım (giriş)"
            }
            return [
                day(transaction.date), kind, ledger.personName(transaction.personID), asset?.name ?? "",
                asset?.unit.symbol ?? "", ledger.locationName(transaction.locationID), number(transaction.quantity),
                number(transaction.unitPrice), number(transaction.total), ledger.transaction(transaction.id)?.note ?? "",
            ]
        }
        return csv([["Tarih", "İşlem", "Kişi", "Ürün", "Birim", "Yer", "Miktar", "Birim fiyat (TL)", "Tutar (TL)", "Not"]] + rows)
    }

    private static func holdings(_ ledger: Ledger) -> String {
        let calculator = ledger.calculator
        let rows = calculator.holdings().sorted { ($0.value ?? 0) > ($1.value ?? 0) }.map { holding -> [String] in
            let asset = calculator.assets[holding.key.assetID]
            return [
                ledger.personName(holding.key.personID), asset?.name ?? "", ledger.locationName(holding.key.locationID),
                number(holding.quantity), asset?.unit.symbol ?? "", number(holding.averageCost), number(holding.cost),
                holding.price.map(number) ?? "", holding.value.map(number) ?? "", holding.value.map { number($0 - holding.cost) } ?? "",
            ]
        }
        return csv([["Kişi", "Ürün", "Yer", "Miktar", "Birim", "Ortalama maliyet (TL)", "Maliyet (TL)", "Güncel fiyat (TL)",
                     "Değer (TL)", "Kâr/Zarar (TL)"]] + rows)
    }

    private static func debts(_ ledger: Ledger) -> String {
        let rows = ledger.debts.map { debt -> [String] in
            [
                ledger.personName(debt.personID), debt.institution, debt.kind.title, debt.title, number(debt.remaining),
                debt.monthlyInstallment.map(number) ?? "", debt.dueDate.map(day) ?? "", debt.paymentDay.map(String.init) ?? "", debt.note,
            ]
        }
        return csv([["Kişi", "Kurum", "Tür", "Açıklama", "Kalan (TL)", "Aylık taksit (TL)", "Son ödeme / bitiş", "Taksit günü", "Not"]] + rows)
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

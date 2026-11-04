import SwiftUI
import UIKit
import WidgetKit

// Widget görünümü. Uygulamanın Debug derlemesindeki önizleme ekranı da bu dosyayı kullanır.

struct PriceRowData: Identifiable, Hashable {
    let slug: String
    let name: String
    let bid: Decimal
    let ask: Decimal?
    var id: String { slug }
}

struct PriceEntry: TimelineEntry {
    let date: Date
    let instrument: BidInstrument
    let rows: [PriceRowData]
    let priceDate: Date?
    /// Büyük widget'ta altta gösterilen, en yüksek alışı veren diğer kurumlar.
    var others: [PriceRowData] = []

    /// Seçili kurumların ve en iyi alış veren diğer kurumların satırları.
    static func make(board: PriceBoard?, instrument: BidInstrument, slugs: [String], names: [String: String] = [:]) -> PriceEntry {
        guard let board else { return PriceEntry(date: .now, instrument: instrument, rows: [], priceDate: nil) }
        func row(_ slug: String, _ quote: InstitutionQuote) -> PriceRowData {
            let name = slug == WidgetPlaces.dealersSlug ? "Kuyumcu" : names[slug] ?? PriceBoard.displayName(slug, fallback: quote.name)
            return PriceRowData(slug: slug, name: name, bid: quote.bid, ask: quote.ask)
        }
        let rows = slugs.compactMap { slug in board.quote(instrument, slug: slug).map { row(slug, $0) } }
        let others = board.quotes(instrument)
            .filter { !slugs.contains($0.key) }
            .sorted { $0.value.bid > $1.value.bid }
            .prefix(8)
            .map { row($0.key, $0.value) }
        return PriceEntry(date: .now, instrument: instrument, rows: rows, priceDate: board.date, others: others)
    }
}

struct PriceWidgetView: View {
    let entry: PriceEntry
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(entry.rows.prefix(2).map { "\(short($0.name)) \(compact($0.bid))" }.joined(separator: " · "))
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("\(entry.instrument.title) alış").font(.caption2.weight(.semibold))
                ForEach(entry.rows.prefix(2)) { row in
                    HStack {
                        Text(short(row.name)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(compact(row.bid)).monospacedDigit()
                    }
                    .font(.caption)
                }
            }
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                header
                ForEach(entry.rows.prefix(2)) { row in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 5) {
                            WidgetLogo(slug: row.slug, size: 16)
                            Text(short(row.name)).font(.caption.weight(.medium)).lineLimit(1)
                        }
                        Text(Format.plainLira(row.bid))
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        if let ask = row.ask {
                            Text("Satış \(Format.plainLira(ask))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                header
                HStack {
                    Spacer()
                    Text("Alış").frame(width: 82, alignment: .trailing)
                    Text("Satış").frame(width: 82, alignment: .trailing)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                let mine = Array(entry.rows.prefix(family == .systemLarge ? 6 : 4))
                ForEach(mine) { row in priceRow(row) }
                if family == .systemLarge, !entry.others.isEmpty {
                    Text("En iyi alış veren diğer kurumlar")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    ForEach(entry.others.prefix(max(10 - mine.count, 3))) { row in priceRow(row) }
                }
                if entry.rows.isEmpty {
                    Text("Fiyatlar alınamadı. Uygulamayı açıp Fiyatlar'da güncelleyin.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func priceRow(_ row: PriceRowData) -> some View {
        HStack(spacing: 8) {
            WidgetLogo(slug: row.slug, size: 20)
            Text(row.name).font(.caption).lineLimit(1)
            Spacer(minLength: 4)
            Text(Format.plainLira(row.bid))
                .font(.caption.weight(.semibold))
                .frame(width: 82, alignment: .trailing)
            Text(row.ask.map(Format.plainLira) ?? "—")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .trailing)
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(entry.instrument.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(red: 0.83, green: 0.63, blue: 0.09))
            Spacer(minLength: 4)
            if let priceDate = entry.priceDate {
                Text(priceDate.formatted(.dateTime.hour().minute().locale(Format.locale)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func short(_ name: String) -> String {
        name.replacingOccurrences(of: " Bankası", with: "").replacingOccurrences(of: " Bank", with: "")
    }

    /// Kilit ekranı için kısa tutar: altında kuruşsuz, dövizde iki basamak.
    private func compact(_ value: Decimal) -> String {
        let digits = value >= 1000 ? 0 : 2
        return value.formatted(.number.locale(Format.locale).precision(.fractionLength(digits)))
    }
}

/// Kurum logosu: kişisel derlemede logo görseli, yoksa kurum renginde baş harf.
private struct WidgetLogo: View {
    let slug: String
    let size: CGFloat

    var body: some View {
        let institution = BidSource.institutions[slug].flatMap { id in Institution.all.first { $0.id == id } }
            ?? (slug == PriceBoard.midasSlug ? Institution.all.first { $0.id == "midas" } : nil)
        Group {
            if let institution, let image = UIImage(named: "inst-\(institution.id)") {
                Image(uiImage: image).resizable().scaledToFill().background(Color.white)
            } else if let institution {
                Circle()
                    .fill(Color(rgb: institution.color))
                    .overlay {
                        Text(institution.monogram)
                            .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.5)
                    }
            } else {
                Circle()
                    .fill(Color(red: 0.83, green: 0.63, blue: 0.09))
                    .overlay {
                        Image(systemName: slug == WidgetPlaces.dealersSlug ? "house.fill" : "storefront.fill")
                            .font(.system(size: size * 0.45))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

private extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}

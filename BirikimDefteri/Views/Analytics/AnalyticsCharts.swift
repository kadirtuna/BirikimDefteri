import Charts
import SwiftUI

extension Format {
    /// Eksen etiketleri için kısa para biçimi: ₺12,5 B, ₺1,2 Mn.
    static func compactLira(_ value: Double) -> String {
        guard !hidesAmounts else { return "₺•••" }
        let magnitude = abs(value)
        let (divisor, suffix): (Double, String) =
            magnitude >= 1e9 ? (1e9, " Mr") : magnitude >= 1e6 ? (1e6, " Mn") : magnitude >= 1e3 ? (1e3, " B") : (1, "")
        let scaled = (magnitude / divisor).formatted(.number.locale(locale).precision(.fractionLength(0...1)))
        return "\(value < 0 ? "-" : "")₺\(scaled)\(suffix)"
    }

    static func shortMonth(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).locale(locale))
    }
}

/// Değer (alan) ve maliyet (kesikli çizgi) geçmişi. Grafiğe dokunup kaydırınca o tarihin değerleri görünür.
struct ValueHistoryChart: View {
    let points: [ValuePoint]
    var height: CGFloat = 230
    @State private var selectedDate: Date?

    var body: some View {
        let selected = selectedDate.flatMap { date in points.last { $0.date <= date } ?? points.first }

        VStack(alignment: .leading, spacing: 10) {
            Chart {
                ForEach(points) { point in
                    AreaMark(x: .value("Tarih", point.date), y: .value("Değer", point.value.doubleValue))
                        .foregroundStyle(LinearGradient(
                            colors: [Theme.green.opacity(0.32), Theme.green.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        ))
                    LineMark(x: .value("Tarih", point.date), y: .value("Değer", point.value.doubleValue), series: .value("Seri", "Değer"))
                        .foregroundStyle(Theme.green)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    LineMark(x: .value("Tarih", point.date), y: .value("Maliyet", point.cost.doubleValue), series: .value("Seri", "Maliyet"))
                        .foregroundStyle(Theme.gold)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                }
                if let selected {
                    RuleMark(x: .value("Seçili", selected.date))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                        .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            SelectionCallout(point: selected)
                        }
                    PointMark(x: .value("Tarih", selected.date), y: .value("Değer", selected.value.doubleValue))
                        .foregroundStyle(Theme.green)
                        .symbolSize(70)
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    AxisValueLabel {
                        if let amount = value.as(Double.self) { Text(Format.compactLira(amount)) }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) { Text(Format.shortMonth(date)) }
                    }
                }
            }
            .frame(height: height)
            .padding(.top, 34)

            HStack(spacing: 16) {
                LegendItem(color: Theme.green, title: "Değer")
                LegendItem(color: Theme.gold, title: "Maliyet", dashed: true)
                Spacer()
                Text("Ayrıntı için grafiğe dokunun")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct SelectionCallout: View {
    let point: ValuePoint

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Format.date(point.date))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(Format.lira(point.value))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            Text("Maliyet \(Format.lira(point.cost))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct LegendItem: View {
    let color: Color
    let title: String
    var dashed = false

    var body: some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(dashed ? Color.clear : color)
                .overlay {
                    if dashed {
                        Capsule().stroke(color, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                    }
                }
                .frame(width: 16, height: 4)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Türlerin toplam içindeki payının zaman içindeki değişimi (yüzde, yığılmış alan).
struct CategoryTrendChart: View {
    let points: [ValuePoint]

    private struct Entry: Identifiable {
        let date: Date
        let category: AssetCategory
        let share: Double
        var id: String { "\(date.timeIntervalSince1970)-\(category.rawValue)" }
    }

    var body: some View {
        let categories = AssetCategory.allCases.filter { category in points.contains { ($0.byCategory[category] ?? 0) > 0 } }
        // Paylar burada hesaplanır: grafiğin kendi normalleştirmesi ekseni ham TL değerlerine göre kurduğu
        // için 0–1 aralığındaki etiketler en alta yığılıyordu.
        let entries = points.flatMap { point -> [Entry] in
            let total = point.byCategory.values.sum { $0 }
            guard total > 0 else { return [] }
            return categories.map { Entry(date: point.date, category: $0, share: ((point.byCategory[$0] ?? 0) / total).doubleValue) }
        }

        Chart(entries) { entry in
            AreaMark(
                x: .value("Tarih", entry.date),
                y: .value("Pay", entry.share),
                stacking: .standard
            )
            .foregroundStyle(by: .value("Tür", entry.category.title))
        }
        .chartYScale(domain: 0...1)
        .chartForegroundStyleScale(
            domain: categories.map(\.title),
            range: categories.map { ChartPalette.palette(for: $0)[0] }
        )
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 0.25, 0.5, 0.75, 1]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                AxisValueLabel {
                    if let ratio = value.as(Double.self) { Text(Format.percent(Decimal(ratio))) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) { Text(Format.shortMonth(date)) }
                }
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 220)
    }
}

/// Aylık alım ve satım tutarları (yan yana sütunlar).
struct MonthlyFlowChart: View {
    let flows: [MonthlyFlow]

    var body: some View {
        Chart {
            ForEach(flows) { flow in
                BarMark(x: .value("Ay", flow.month, unit: .month), y: .value("Tutar", flow.bought.doubleValue))
                    .foregroundStyle(by: .value("Tür", "Alış"))
                    .position(by: .value("Tür", "Alış"))
                    .cornerRadius(3)
                BarMark(x: .value("Ay", flow.month, unit: .month), y: .value("Tutar", flow.sold.doubleValue))
                    .foregroundStyle(by: .value("Tür", "Satış"))
                    .position(by: .value("Tür", "Satış"))
                    .cornerRadius(3)
            }
        }
        .chartForegroundStyleScale(["Alış": Theme.green, "Satış": Color.orange])
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                AxisValueLabel {
                    if let amount = value.as(Double.self) { Text(Format.compactLira(amount)) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month, count: 2)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) { Text(Format.shortMonth(date)) }
                }
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 200)
    }
}

/// Ürün başına getiri (%), yatay çubuklar.
struct PerformanceChart: View {
    let groups: [PortfolioGroup]
    @ScaledMetric private var rowHeight: CGFloat = 34

    var body: some View {
        Chart(groups) { group in
            let ratio = (group.profitRatio ?? 0).doubleValue
            BarMark(x: .value("Getiri", ratio), y: .value("Ürün", group.title))
                .foregroundStyle(ratio >= 0 ? Theme.positive.gradient : Theme.negative.gradient)
                .cornerRadius(4)
                .annotation(position: ratio >= 0 ? .trailing : .leading, spacing: 4) {
                    Text(Format.signedPercent(group.profitRatio ?? 0))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            RuleMark(x: .value("Sıfır", 0))
                .foregroundStyle(Color.secondary.opacity(0.5))
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                AxisValueLabel {
                    if let ratio = value.as(Double.self) { Text(Format.percent(Decimal(ratio))) }
                }
            }
        }
        .chartXScale(range: .plotDimension(padding: 36))
        .frame(height: max(rowHeight * CGFloat(groups.count) + 30, 90))
    }
}

/// Ürün fiyatının geçmişi; alımlar yeşil, satışlar turuncu nokta.
struct PriceHistoryChart: View {
    let prices: [PriceInfo]
    let transactions: [TransactionInfo]

    var body: some View {
        Chart {
            ForEach(Array(prices.enumerated()), id: \.offset) { _, price in
                LineMark(x: .value("Tarih", price.date), y: .value("Fiyat", price.price.doubleValue))
                    .foregroundStyle(Theme.gold)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            ForEach(transactions.filter { !$0.kind.isTransfer }) { transaction in
                PointMark(x: .value("Tarih", transaction.date), y: .value("Fiyat", transaction.unitPrice.doubleValue))
                    .foregroundStyle(by: .value("İşlem", transaction.kind.title))
                    .symbol(by: .value("İşlem", transaction.kind.title))
                    .symbolSize(60)
            }
        }
        .chartForegroundStyleScale(["Alış": Theme.positive, "Satış": Color.orange])
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                AxisValueLabel {
                    if let amount = value.as(Double.self) { Text(Format.compactLira(amount)) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) { Text(Format.shortMonth(date)) }
                }
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 200)
    }
}

/// Dolar ya da gram altın karşılığı değer geçmişi.
struct ConvertedHistoryChart: View {
    let points: [ConvertedPoint]
    let unit: AssetUnit

    var body: some View {
        Chart(points) { point in
            AreaMark(x: .value("Tarih", point.date), y: .value("Değer", point.value.doubleValue))
                .foregroundStyle(LinearGradient(
                    colors: [Theme.gold.opacity(0.3), Theme.gold.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom
                ))
            LineMark(x: .value("Tarih", point.date), y: .value("Değer", point.value.doubleValue))
                .foregroundStyle(Theme.gold)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(unit == .usd ? Format.compactLira(amount).replacingOccurrences(of: "₺", with: "$") : Format.quantity(Decimal(amount.rounded()), unit: unit))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) { Text(Format.shortMonth(date)) }
                }
            }
        }
        .frame(height: 220)
    }
}

struct ConvertedChangeHeader: View {
    let points: [ConvertedPoint]
    let unit: AssetUnit
    let label: String

    var body: some View {
        let first = points.first?.value ?? 0
        let last = points.last?.value ?? 0
        let ratio: Decimal? = first > 0 ? last / first - 1 : nil

        VStack(alignment: .leading, spacing: 4) {
            Text(Format.quantity(last, unit: unit))
                .font(.system(.title, design: .rounded, weight: .bold))
                .monospacedDigit()
            if let ratio {
                Text("\(Format.signedPercent(ratio)) dönem değişimi (\(label) bazında)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ratio >= 0 ? Theme.positive : Theme.negative)
            }
        }
        .padding(.top, 4)
    }
}

/// Ürünün kaydedilen fiyatlara göre piyasa değişimi: 1 hafta, 1 ay, 3 ay, 1 yıl.
struct MarketChangeRow: View {
    let assetID: UUID
    @Environment(\.ledger) private var ledger

    private static let periods: [(title: String, days: Int)] = [("1H", 7), ("1A", 30), ("3A", 91), ("1Y", 365)]

    var body: some View {
        let now = Date.now
        let changes = Self.periods.map { period in
            (period.title, ledger.calculator.marketChange(of: assetID, since: now.addingTimeInterval(-Double(period.days) * 86_400)))
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Piyasa değişimi")
            HStack(spacing: 8) {
                ForEach(changes, id: \.0) { title, change in
                    VStack(spacing: 2) {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(change.map(Format.signedPercent) ?? "—")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(change.map { $0 >= 0 ? Theme.positive : Theme.negative } ?? Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            if changes.allSatisfy({ $0.1 == nil }) {
                Text("Uygulamanın kaydettiği fiyatlardan hesaplanır; fiyat geçmişi biriktikçe dolar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

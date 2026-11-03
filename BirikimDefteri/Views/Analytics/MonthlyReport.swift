import Charts
import SwiftUI

/// Bir ayın özet raporu için hesaplanan değerler.
struct MonthlyReportData {
    struct CategoryValue: Hashable {
        let category: AssetCategory
        let value: Decimal
    }

    let month: Date
    let personTitle: String
    let startValue: Decimal
    let endValue: Decimal
    let bought: Decimal
    let sold: Decimal
    let realized: Decimal
    let debts: Decimal
    let categories: [CategoryValue]
    let history: [ValuePoint]
    let transactions: [TransactionInfo]

    var change: Decimal { endValue - startValue }
    var changeRatio: Decimal? { startValue > 0 ? change / startValue : nil }
    var netWorth: Decimal { endValue - debts }

    @MainActor
    init(ledger: Ledger, filter: PersonFilter, month: Date, now: Date = .now, calendar: Calendar = .current) {
        let calculator = ledger.calculator
        let start = calendar.dateInterval(of: .month, for: month)?.start ?? month
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: start)?.addingTimeInterval(-1) ?? now
        let end = min(monthEnd, now)
        let inMonth = calculator.transactions.filter { filter.includes($0.personID) && $0.date >= start && $0.date <= end }
        let endPoint = calculator.valueHistory(for: filter, since: end, now: end).first

        self.month = start
        if case .person(let id) = filter {
            personTitle = ledger.personName(id)
        } else {
            personTitle = "Herkes"
        }
        startValue = calculator.assetsValue(at: start.addingTimeInterval(-1), for: filter)
        endValue = endPoint?.value ?? 0
        bought = inMonth.filter { $0.kind == .buy }.sum(\.total)
        sold = inMonth.filter { $0.kind == .sell }.sum(\.total)
        realized = calculator.realizedGains(for: filter)
            .filter { $0.date >= start && $0.date <= end && calculator.assets[$0.assetID]?.category != .lira }
            .sum(\.gain)
        debts = calculator.debtSummary(for: filter).total
        categories = (endPoint?.byCategory ?? [:]).filter { $0.value > 0 }.sorted { $0.value > $1.value }.map { CategoryValue(category: $0.key, value: $0.value) }
        history = calculator.valueHistory(for: filter, since: calendar.date(byAdding: .month, value: -11, to: start), now: end)
        transactions = inMonth.filter { $0.kind != .transferIn }.sorted { $0.date < $1.date }
    }
}

/// A4 genişliğinde, PDF'e çizilen rapor sayfası.
struct MonthlyReportView: View {
    let data: MonthlyReportData
    let ledger: Ledger

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image("Logo")
                    .resizable()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Birikim Defteri")
                        .font(.title2.bold())
                    Text("\(Format.month(data.month)) raporu · \(data.personTitle)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Oluşturulma\n\(Format.dateTime(.now))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    tile("Ay başı değer", Format.lira(data.startValue))
                    tile("Ay sonu değer", Format.lira(data.endValue))
                    tile("Aylık değişim", Format.signedLira(data.change) + (data.changeRatio.map { " (\(Format.signedPercent($0)))" } ?? ""))
                }
                GridRow {
                    tile("Ay içinde alım", Format.lira(data.bought))
                    tile("Ay içinde satış", Format.lira(data.sold))
                    tile("Gerçekleşen K/Z", Format.signedLira(data.realized))
                }
                GridRow {
                    tile("Güncel borç", Format.lira(data.debts))
                    tile("Net varlık", Format.lira(data.netWorth))
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                }
            }

            if data.history.count > 1 {
                section("Son 12 ay: değer ve maliyet") {
                    Chart(data.history) { point in
                        LineMark(x: .value("Tarih", point.date), y: .value("Değer", point.value.doubleValue), series: .value("Seri", "Değer"))
                            .foregroundStyle(Theme.green)
                        LineMark(x: .value("Tarih", point.date), y: .value("Maliyet", point.cost.doubleValue), series: .value("Seri", "Maliyet"))
                            .foregroundStyle(Theme.gold)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let amount = value.as(Double.self) { Text(Format.compactLira(amount)) }
                            }
                        }
                    }
                    .frame(height: 170)
                }
            }

            if !data.categories.isEmpty {
                section("Ay sonunda tür dağılımı") {
                    ForEach(data.categories, id: \.category) { item in
                        HStack {
                            Circle().fill(ChartPalette.palette(for: item.category)[0]).frame(width: 10, height: 10)
                            Text(item.category.title)
                            Spacer()
                            Text(Format.lira(item.value)).monospacedDigit()
                            Text(data.endValue > 0 ? Format.percent(item.value / data.endValue) : "—")
                                .foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .trailing)
                        }
                        .font(.callout)
                    }
                }
            }

            section("Ay içindeki işlemler") {
                if data.transactions.isEmpty {
                    Text("Bu ay işlem yok.")
                        .foregroundStyle(.secondary)
                }
                ForEach(data.transactions) { transaction in
                    let asset = ledger.calculator.assets[transaction.assetID]
                    HStack {
                        Text(Format.date(transaction.date)).frame(width: 90, alignment: .leading)
                        Text(transaction.kind.title).frame(width: 60, alignment: .leading)
                        Text(asset?.name ?? "—")
                        Spacer()
                        Text(Format.quantity(transaction.quantity, unit: asset?.unit ?? .piece)).monospacedDigit()
                        Text(transaction.kind.isTransfer ? "—" : Format.lira(transaction.total))
                            .monospacedDigit()
                            .frame(width: 110, alignment: .trailing)
                    }
                    .font(.caption)
                }
            }

            Text("Değerler, her tarihteki son kayıtlı fiyatla hesaplanmıştır. Borç tutarı raporun oluşturulduğu andaki değerdir.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(36)
        .frame(width: 595)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .environment(\.locale, Format.locale)
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
    }
}

struct MonthlyReportSheet: View {
    let filter: PersonFilter

    @Environment(\.ledger) private var ledger
    @Environment(\.dismiss) private var dismiss
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var reportURL: URL?
    @State private var errorMessage: String?

    private var months: [Date] {
        (0..<12).compactMap { Calendar.current.date(byAdding: .month, value: -$0, to: Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Ay", selection: $month) {
                        ForEach(months, id: \.self) { Text(Format.month($0)).tag($0) }
                    }
                } footer: {
                    Text("Rapor; ay sonu değerini, aylık değişimi, alım ve satımları, tür dağılımını ve son 12 ayın grafiğini içerir.")
                }
                Section {
                    Button("PDF oluştur", systemImage: "doc.badge.plus", action: generate)
                    if let reportURL {
                        ShareLink(item: reportURL) {
                            Label("Paylaş ya da kaydet", systemImage: "square.and.arrow.up")
                        }
                    }
                } footer: {
                    if let errorMessage { ErrorLabel(message: errorMessage) }
                }
            }
            .navigationTitle("Aylık rapor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .onChange(of: month) { reportURL = nil }
        }
        .presentationDetents([.medium])
        .lockProtected()
    }

    private func generate() {
        // Rapor, ekranda tutarlar gizli olsa da gerçek rakamlarla çizilir.
        let wasHidden = Format.hidesAmounts
        Format.hidesAmounts = false
        defer { Format.hidesAmounts = wasHidden }

        let data = MonthlyReportData(ledger: ledger, filter: filter, month: month)
        let renderer = ImageRenderer(content: MonthlyReportView(data: data, ledger: ledger))
        let stamp = month.formatted(.iso8601.year().month())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BirikimDefteri-Rapor-\(stamp).pdf")
        var didRender = false
        renderer.render { size, render in
            var box = CGRect(origin: .zero, size: size)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            render(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            didRender = true
        }
        if didRender {
            reportURL = url
            errorMessage = nil
        } else {
            errorMessage = "PDF oluşturulamadı."
        }
    }
}

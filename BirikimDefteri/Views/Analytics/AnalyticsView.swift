import SwiftUI

struct AnalyticsView: View {
    let filter: PersonFilter

    @Environment(\.ledger) private var ledger
    @State private var period: Period = .year
    @State private var denomination: Denomination = .lira
    @State private var isShowingReport = false

    /// Değer grafiğinin birimi: TL, dolar ya da gram altın karşılığı.
    enum Denomination: String, CaseIterable, Identifiable {
        case lira, usd, gold

        var id: Self { self }

        var title: String {
            switch self {
            case .lira: "₺"
            case .usd: "$"
            case .gold: "Gram altın"
            }
        }
    }

    enum Period: String, CaseIterable, Identifiable {
        case threeMonths, sixMonths, year, all

        var id: Self { self }

        var title: String {
            switch self {
            case .threeMonths: "3A"
            case .sixMonths: "6A"
            case .year: "1Y"
            case .all: "Tümü"
            }
        }

        func start(from now: Date) -> Date? {
            let months: Int? = switch self {
            case .threeMonths: 3
            case .sixMonths: 6
            case .year: 12
            case .all: nil
            }
            return months.flatMap { Calendar.current.date(byAdding: .month, value: -$0, to: now) }
        }
    }

    var body: some View {
        let calculator = ledger.calculator
        let now = Date.now
        let history = calculator.valueHistory(for: filter, since: period.start(from: now), now: now)
        let summary = calculator.summary(for: filter)
        // Türk lirası satışı para çekmektir, kâr/zarar doğurmaz. Fon (₺ birimli) zararları sayılır.
        let realized = calculator.realizedGains(for: filter).filter { calculator.assets[$0.assetID]?.category != .lira }
        let flows = calculator.monthlyFlows(for: filter, last: 12, now: now)
        let performance = calculator.groups(by: .asset, for: filter)
            .filter { $0.unit != .lira && $0.cost > 0 }
            .sorted { ($0.profitRatio ?? 0) > ($1.profitRatio ?? 0) }

        List {
            if history.isEmpty {
                ContentUnavailableView(
                    "Analiz için kayıt yok",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Alım ekledikçe değer geçmişi, dağılım ve performans burada görünür.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    Picker("Dönem", selection: $period) {
                        ForEach(Period.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Birim", selection: $denomination) {
                        ForEach(Denomination.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if denomination == .lira {
                        PeriodChangeHeader(points: history)
                        ValueHistoryChart(points: history)
                            .padding(.vertical, 4)
                    } else if let unitAsset = unitAsset(for: denomination, in: calculator) {
                        let converted = calculator.converted(history, into: unitAsset.id)
                        ConvertedChangeHeader(points: converted, unit: unitAsset.unit, label: denomination == .usd ? "dolar" : "gram altın")
                        ConvertedHistoryChart(points: converted, unit: unitAsset.unit)
                            .padding(.vertical, 4)
                    } else {
                        Text(denomination == .usd ? "Dolar ürünü bulunamadı." : "Gram altın ürünü bulunamadı.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(denomination == .lira ? "Değer ve maliyet" : "Değer (\(denomination == .usd ? "dolar" : "gram altın") karşılığı)")
                } footer: {
                    if denomination == .lira {
                        Text("Geçmiş değerler, o tarihteki son fiyat kaydıyla hesaplanır; ilk kayıttan önceki dönem için işlem fiyatı kullanılır.")
                    } else {
                        Text("Varlıklarınızın her tarihteki \(denomination == .usd ? "dolar" : "gram altın") karşılığı. TL değer artarken bu çizgi düşüyorsa birikiminiz \(denomination == .usd ? "dolar" : "altın") karşısında eriyor demektir. Yeni alımlar da dahildir.")
                    }
                }

                Section("Temel göstergeler") {
                    KPIGrid(summary: summary, realized: realized, debts: calculator.debtSummary(for: filter))
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                }

                if history.contains(where: { $0.byCategory.count > 1 }) {
                    Section("Tür dağılımı (zaman içinde)") {
                        CategoryTrendChart(points: history)
                            .padding(.vertical, 4)
                    }
                }

                if flows.contains(where: { $0.bought > 0 || $0.sold > 0 }) {
                    Section {
                        MonthlyFlowChart(flows: flows)
                            .padding(.vertical, 4)
                        LabeledContent("12 ayda alım", value: Format.lira(flows.sum(\.bought)))
                        LabeledContent("12 ayda satış", value: Format.lira(flows.sum(\.sold)))
                    } header: {
                        Text("Aylık alım ve satım")
                    }
                }

                if !performance.isEmpty {
                    Section {
                        PerformanceChart(groups: performance)
                            .padding(.vertical, 4)
                        ForEach(performance) { group in
                            PerformanceRow(group: group)
                        }
                    } header: {
                        Text("Alış maliyetinize göre getiri")
                    } footer: {
                        Text("Her ürünün bugünkü alış fiyatının sizin ortalama alış fiyatınıza göre değişimi. Piyasanın belirli bir dönemdeki değişimi değildir: ürünleri farklı zamanlarda aldığınız için oranlar farklıdır.")
                    }
                }

                Section {
                    LabeledContent("Toplam") {
                        ProfitText(profit: realized.sum(\.gain), ratio: nil)
                            .font(.headline)
                    }
                    if realized.isEmpty {
                        Text("Henüz satış yok.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(realized.suffix(10).reversed()) { gain in
                        RealizedGainRow(gain: gain)
                    }
                } header: {
                    Text("Gerçekleşen kâr/zarar")
                } footer: {
                    if realized.count > 10 {
                        Text("Son 10 satış gösteriliyor.")
                    }
                }
            }
        }
        .navigationTitle("Analiz")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                isShowingReport = true
            } label: {
                Label("Aylık rapor", systemImage: "doc.richtext")
            }
        }
        .sheet(isPresented: $isShowingReport) {
            MonthlyReportSheet(filter: filter)
        }
    }

    private func unitAsset(for denomination: Denomination, in calculator: PortfolioCalculator) -> AssetInfo? {
        let assets = calculator.assets.values.sorted { $0.sortOrder < $1.sortOrder }
        switch denomination {
        case .lira: return nil
        case .usd: return assets.first { $0.unit == .usd }
        case .gold: return assets.first { QuoteKey.key(for: $0) == .gramGold }
        }
    }
}

private struct PeriodChangeHeader: View {
    let points: [ValuePoint]

    var body: some View {
        let first = points.first?.value ?? 0
        let last = points.last?.value ?? 0
        let change = last - first

        VStack(alignment: .leading, spacing: 4) {
            Text(Format.lira(last))
                .font(.system(.title, design: .rounded, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            ProfitText(profit: change, ratio: first > 0 ? change / first : nil)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("Dönem değişimi, yeni alımlar dahil")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }
}

private struct KPIGrid: View {
    let summary: PortfolioSummary
    let realized: [RealizedGain]
    let debts: DebtSummary

    var body: some View {
        let realizedTotal = realized.sum(\.gain)
        let debtRatio = summary.assets > 0 ? summary.debts / summary.assets : nil

        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            KPITile(title: "Toplam değer", value: Format.lira(summary.assets), systemImage: "banknote", tint: Theme.green)
            KPITile(title: "Yatırılan (maliyet)", value: Format.lira(summary.cost), systemImage: "tray.and.arrow.down", tint: Theme.gold)
            KPITile(
                title: "Gerçekleşmemiş K/Z",
                value: Format.signedLira(summary.profit),
                detail: summary.profitRatio.map(Format.signedPercent),
                systemImage: "chart.line.uptrend.xyaxis",
                tint: summary.profit >= 0 ? Theme.positive : Theme.negative
            )
            KPITile(
                title: "Gerçekleşen K/Z",
                value: Format.signedLira(realizedTotal),
                detail: "\(realized.count) satış",
                systemImage: "checkmark.seal",
                tint: realizedTotal >= 0 ? Theme.positive : Theme.negative
            )
            KPITile(
                title: "Borç / varlık",
                value: debtRatio.map(Format.percent) ?? "—",
                detail: Format.lira(summary.debts),
                systemImage: "scalemass",
                tint: .purple
            )
            KPITile(
                title: "Aylık taksit",
                value: Format.lira(debts.monthlyInstallments),
                systemImage: "calendar.badge.clock",
                tint: .blue
            )
        }
    }
}

private struct KPITile: View {
    let title: String
    let value: String
    var detail: String?
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct RealizedGainRow: View {
    let gain: RealizedGain
    @Environment(\.ledger) private var ledger

    var body: some View {
        let asset = ledger.calculator.assets[gain.assetID]

        HStack(spacing: 12) {
            AssetIcon(asset: asset, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(asset?.name ?? "Bilinmeyen ürün")
                Text("\(Format.date(gain.date)) · \(Format.quantity(gain.quantity, unit: asset?.unit ?? .piece))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                ProfitText(profit: gain.gain, ratio: nil)
                    .font(.subheadline.weight(.semibold))
                if let ratio = gain.ratio {
                    Text(Format.signedPercent(ratio))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Getirinin neye göre hesaplandığını gösterir: ortalama alış fiyatı → bugünkü fiyat.
private struct PerformanceRow: View {
    let group: PortfolioGroup
    @Environment(\.ledger) private var ledger

    var body: some View {
        let assetID: UUID? = if case .asset(let id) = group.key { id } else { nil }
        let asset = assetID.flatMap { ledger.calculator.assets[$0] }
        let price = assetID.flatMap(ledger.calculator.price(of:))
        let averageCost = group.quantity.flatMap { $0 > 0 ? group.cost / $0 : nil }

        HStack(spacing: 12) {
            AssetIcon(asset: asset, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.title)
                if let averageCost, let price, let unit = asset?.unit {
                    Text("Ortalama alışınız \(Format.lira(averageCost)) → bugün \(Format.lira(price)) (1 \(unit.symbol))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(group.profitRatio.map(Format.signedPercent) ?? "—")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(group.profit >= 0 ? Theme.positive : Theme.negative)
                ProfitText(profit: group.profit, ratio: nil)
                    .font(.caption)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

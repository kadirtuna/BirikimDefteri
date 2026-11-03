import Charts
import SwiftUI

struct SummaryView: View {
    @Environment(\.ledger) private var ledger
    @Environment(AppRouter.self) private var router
    @State private var selectedFilter: PersonFilter?
    @State private var grouping: Grouping = .asset
    @State private var isAdding = false

    /// Varsayılan görünüm ilk kişidir ("Ben"); başka bir seçim yapılınca o kalır.
    private var filter: PersonFilter {
        selectedFilter ?? ledger.people.first.map { .person($0.id) } ?? .everyone
    }

    var body: some View {
        let calculator = ledger.calculator
        let summary = calculator.summary(for: filter)
        let groups = calculator.groups(by: grouping, for: filter)
        let colors = ChartPalette.colors(for: groups, calculator: calculator)
        let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: .now)
        let trend = calculator.valueHistory(for: filter, since: sixMonthsAgo)

        NavigationStack {
            List {
                if ledger.people.count > 1 {
                    Section {
                        PersonFilterPicker(
                            people: ledger.people,
                            selection: Binding(get: { filter }, set: { selectedFilter = $0 })
                        )
                    }
                }

                Section {
                    NetWorthHeader(summary: summary)
                        .listRowBackground(HeroBackground())
                }

                if !summary.missingPrices.isEmpty {
                    Section {
                        Button {
                            router.tab = .prices
                        } label: {
                            MissingPriceBanner(count: summary.missingPrices.count)
                        }
                    }
                }

                if !calculator.holdings(for: filter).isEmpty {
                    Section {
                        NavigationLink {
                            LocationsOverviewView(filter: filter)
                        } label: {
                            LocationsLinkLabel(breakdown: calculator.locationBreakdown(for: filter))
                        }
                    }
                }

                Section {
                    Picker("Gruplama", selection: $grouping) {
                        ForEach(Grouping.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if groups.isEmpty {
                        ContentUnavailableView {
                            Label("Henüz varlık yok", systemImage: "chart.pie")
                        } description: {
                            Text("Sağ üstteki + ile ilk alımınızı ekleyin.")
                        } actions: {
                            Button("İlk alımı ekle") { isAdding = true }
                                .buttonStyle(.borderedProminent)
                        }
                    } else {
                        AllocationChart(groups: groups, total: summary.assets, colors: colors)
                            .padding(.vertical, 8)
                    }
                }

                if !groups.isEmpty {
                    Section("\(grouping.title) dağılımı") {
                        ForEach(groups) { group in
                            NavigationLink(value: group.key) {
                                GroupRow(group: group, color: colors[group.key] ?? .gray)
                            }
                        }
                    }
                }

                if trend.count > 1 {
                    Section {
                        NavigationLink {
                            AnalyticsView(filter: filter)
                        } label: {
                            TrendCard(points: trend)
                        }
                    } header: {
                        Text("Son 6 ay")
                    }
                }

                if !summary.missingPrices.isEmpty {
                    Section {
                        ForEach(summary.missingPrices) { item in
                            NavigationLink(value: GroupKey.asset(item.asset.id)) {
                                HStack(spacing: 12) {
                                    AssetIcon(asset: item.asset, size: 32)
                                    LabeledContent(item.asset.name, value: Format.quantity(item.quantity, unit: item.asset.unit))
                                }
                            }
                        }
                    } header: {
                        Text("Fiyatı girilmemiş")
                    } footer: {
                        Text("Bu ürünler toplamlara katılmadı.")
                    }
                }
            }
            .navigationTitle("Özet")
            .navigationDestination(for: GroupKey.self) { key in
                GroupDetailView(key: key, filter: filter)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        AnalyticsView(filter: filter)
                    } label: {
                        Label("Analiz", systemImage: "chart.xyaxis.line")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAdding = true
                    } label: {
                        Label("Yeni işlem", systemImage: "plus.circle.fill")
                    }
                    .tint(Theme.gold)
                }
            }
            .sheet(isPresented: $isAdding) {
                TransactionFormView()
            }
        }
    }
}

private struct NetWorthHeader: View {
    let summary: PortfolioSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Net varlık", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(hex: 0xF4D98A))
                Text(Format.lira(summary.netWorth))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                    .animation(.default, value: summary.netWorth)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) { metrics }
                VStack(alignment: .leading, spacing: 10) { metrics }
            }
        }
        .padding(.vertical, 10)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var metrics: some View {
        Metric(title: "Varlıklar", systemImage: "arrow.up.right.circle") {
            Text(Format.lira(summary.assets)).monospacedDigit()
        }
        Metric(title: "Borçlar", systemImage: "arrow.down.right.circle") {
            Text(Format.lira(summary.debts)).monospacedDigit()
        }
        Metric(title: "Kâr/Zarar", systemImage: "chart.line.uptrend.xyaxis") {
            VStack(alignment: .leading, spacing: 0) {
                ProfitText(profit: summary.profit, ratio: nil)
                if let ratio = summary.profitRatio {
                    Text(Format.signedPercent(ratio))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct Metric<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize()
        }
    }
}

private struct MissingPriceBanner: View {
    let count: Int

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count) ürünün fiyatı girilmemiş")
                    .foregroundStyle(.primary)
                Text("Bu ürünler toplamlara katılmadı. Fiyat girmek için dokunun.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

private struct GroupRow: View {
    let group: PortfolioGroup
    let color: Color
    @ScaledMetric private var iconSize: CGFloat = 40

    var body: some View {
        HStack(spacing: 12) {
            GroupIcon(key: group.key, color: color, size: iconSize)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(group.title)
                    Spacer(minLength: 8)
                    Text(Format.lira(group.value))
                        .monospacedDigit()
                }
                HStack(alignment: .firstTextBaseline) {
                    if let quantity = group.quantity, let unit = group.unit {
                        Text(Format.quantity(quantity, unit: unit))
                    } else {
                        ProfitText(profit: group.profit, ratio: group.profitRatio, showsRatio: false)
                    }
                    Spacer(minLength: 8)
                    Text(Format.percent(group.share))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                ProgressView(value: min(max(group.share.doubleValue, 0), 1))
                    .tint(color)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Özet ekranındaki küçük gelişim grafiği; dokununca Analiz açılır.
private struct TrendCard: View {
    let points: [ValuePoint]

    var body: some View {
        let first = points.first?.value ?? 0
        let last = points.last?.value ?? 0
        let change = last - first

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("Varlık değeri", systemImage: "chart.xyaxis.line")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                ProfitText(profit: change, ratio: first > 0 ? change / first : nil)
                    .font(.subheadline)
            }
            Chart(points) { point in
                AreaMark(x: .value("Tarih", point.date), y: .value("Değer", point.value.doubleValue))
                    .foregroundStyle(LinearGradient(
                        colors: [Theme.green.opacity(0.35), Theme.green.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    ))
                LineMark(x: .value("Tarih", point.date), y: .value("Değer", point.value.doubleValue))
                    .foregroundStyle(Theme.green)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 70)
            Text("Ayrıntılı analiz için dokunun")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct LocationsLinkLabel: View {
    let breakdown: [LocationHoldings]

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Varlıklarım nerede?")
                    .foregroundStyle(Color.primary)
                Text(breakdown.prefix(3).map { $0.location?.name ?? "Bilinmeyen yer" }.joined(separator: " · ")
                     + (breakdown.count > 3 ? " +\(breakdown.count - 3)" : ""))
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: "mappin.and.ellipse")
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Theme.green.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

import Charts
import SwiftUI

struct SummaryView: View {
    @Environment(\.ledger) private var ledger
    @Environment(AppRouter.self) private var router
    @Environment(PriceUpdater.self) private var updater: PriceUpdater?
    @Environment(\.modelContext) private var context
    @State private var selectedFilter: PersonFilter?
    @State private var grouping: Grouping = .asset
    @State private var isAdding = false
    @State private var isAddingTransfer = false
    @AppStorage(AmountPrivacy.key) private var hidesAmounts = false

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
        let upcoming = ledger.upcomingPayments(within: 7, for: filter)

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
                    NetWorthHeader(
                        summary: summary,
                        daily: calculator.dailyChange(for: filter),
                        priceDate: calculator.latestPriceDate(for: filter)
                    )
                    .listRowBackground(HeroBackground())
                }

                if !upcoming.isEmpty {
                    Section {
                        Button {
                            router.tab = .debts
                        } label: {
                            UpcomingPaymentsCard(items: upcoming)
                        }
                    }
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
                    NavigationLink {
                        GoalsView()
                    } label: {
                        GoalsCard()
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
            .refreshable {
                await updater?.update(assets: ledger.assets, prices: ledger.prices, context: context)
            }
            .navigationDestination(for: GroupKey.self) { key in
                GroupDetailView(key: key, filter: filter)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    NavigationLink {
                        AnalyticsView(filter: filter)
                    } label: {
                        Label("Analiz", systemImage: "chart.xyaxis.line")
                    }
                    Button {
                        AmountPrivacy.set(!hidesAmounts)
                    } label: {
                        Label(hidesAmounts ? "Tutarları göster" : "Tutarları gizle", systemImage: hidesAmounts ? "eye.slash" : "eye")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    AddTransactionMenu(isAddingTrade: $isAdding, isAddingTransfer: $isAddingTransfer)
                }
            }
            .sheet(isPresented: $isAdding) {
                TransactionFormView()
            }
            .sheet(isPresented: $isAddingTransfer) {
                TransferFormView()
            }
        }
    }
}

private struct NetWorthHeader: View {
    let summary: PortfolioSummary
    let daily: DailyChange?
    let priceDate: Date?

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
                if daily != nil || priceDate != nil {
                    todayLine
                }
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

    /// "Bugün +₺1.240 (%0,4) · Fiyatlar 14:32"
    private var todayLine: some View {
        HStack(spacing: 6) {
            if let daily {
                Text("Bugün \(Format.signedLira(daily.change))" + (daily.ratio.map { " (\(Format.signedPercent($0)))" } ?? ""))
                    .fontWeight(.semibold)
                    .foregroundStyle(daily.change < 0 ? Color(hex: 0xFF9E94) : Color(hex: 0x8FE3B0))
                    .monospacedDigit()
            }
            if let priceDate {
                Text((daily == nil ? "" : "· ") + "Fiyatlar " + Self.priceTime(priceDate))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private static func priceTime(_ date: Date) -> String {
        let time = date.formatted(.dateTime.hour().minute().locale(Format.locale))
        if Calendar.current.isDateInToday(date) { return time }
        if Calendar.current.isDateInYesterday(date) { return "dün \(time)" }
        return Format.dateTime(date)
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
        HStack(spacing: 8) {
            label
            Spacer(minLength: 4)
            HStack(spacing: -8) {
                ForEach(breakdown.prefix(4)) { place in
                    PlaceIcon(location: place.location, size: 26)
                        .background(Circle().fill(Color(.secondarySystemGroupedBackground)).padding(-1.5))
                }
            }
        }
    }

    private var label: some View {
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

/// Önümüzdeki 7 günde ödemesi olan borçlar; dokununca Borçlar açılır.
private struct UpcomingPaymentsCard: View {
    let items: [(debt: Debt, payment: UpcomingPayment)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Yaklaşan ödemeler").foregroundStyle(Color.primary)
            } icon: {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color(hex: 0xC0392B).gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            ForEach(items.prefix(4), id: \.debt.id) { item in
                HStack(spacing: 12) {
                    DebtIcon(kind: item.debt.kind, institution: item.debt.institution, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.debt.title.isEmpty ? item.debt.kind.title : item.debt.title)
                            .foregroundStyle(Color.primary)
                        Text(item.debt.institution.isEmpty ? item.debt.kind.title : item.debt.institution)
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 1) {
                        if let amount = item.payment.amount {
                            Text(Format.lira(amount))
                                .foregroundStyle(Color.primary)
                                .monospacedDigit()
                        }
                        Text(Self.when(item.payment.date))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(item.payment.date < Calendar.current.startOfDay(for: .now) ? Theme.negative : Color.orange)
                    }
                }
                .padding(.leading, 6)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    static func when(_ date: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<0: return "Gecikti · \(Format.date(date))"
        case 0: return "Bugün"
        case 1: return "Yarın"
        default: return "\(days) gün sonra"
        }
    }
}

import Charts
import SwiftData
import SwiftUI

private enum PriceDraftState: Equatable {
    case unchanged, changed(Decimal), invalid
}

struct PricesView: View {
    @Environment(\.ledger) private var ledger
    @Environment(\.modelContext) private var context
    @Environment(PriceUpdater.self) private var updater: PriceUpdater?
    @State private var drafts: [UUID: String] = [:]
    @State private var savedCount: Int?

    var body: some View {
        let changes = pendingChanges

        NavigationStack {
            Form {
                if let updater {
                    Section {
                        UpdateStatusRow(updater: updater) {
                            Task { await refresh() }
                        }
                    } footer: {
                        Text("Altın ve gümüş: Truncgil Finans (Kapalıçarşı alış fiyatı). Dolar ve euro: TCMB döviz alış kuru. XAUT: CoinGecko piyasa fiyatı. Yalnızca fiyat indirilir, verileriniz cihazdan çıkmaz.")
                    }

                    InstitutionPricesSection(board: updater.board)
                }

                Section {
                    ForEach(pricedAssets) { asset in
                        PriceRow(
                            asset: asset,
                            latest: ledger.calculator.latestPrices[asset.id],
                            isAutomatic: QuoteKey.key(for: asset.info) != nil,
                            monthChange: ledger.calculator.marketChange(of: asset.id, since: monthAgo),
                            history: recentPrices(of: asset.id),
                            locationPrices: locationPrices(of: asset.id),
                            state: state(for: asset),
                            text: Binding(
                                get: { drafts[asset.id] ?? "" },
                                set: { drafts[asset.id] = $0; savedCount = nil }
                            )
                        )
                    }
                } footer: {
                    Text("Varlıklarınız, durdukları kurumun alış fiyatıyla değerlenir: bozdurursanız eline geçecek tutar. Bankada o bankanın alışı, fiziki altında büyük kuyumcuların en düşük alışı, Midas'ta XAUT fiyatından %0,5 kesinti düşülmüş hâli. Küçük grafik ve yüzde son 30 günü gösterir. 1 birimin Türk lirası karşılığını girin. Kaydet'e bastığınızda yalnızca değiştirdiğiniz fiyatlar kaydedilir. Otomatik işaretli ürünlerde elle girdiğiniz fiyat bir sonraki internet güncellemesine kadar geçerlidir.")
                }

                if let savedCount {
                    Section {
                        Label(
                            savedCount == 0 ? "Değişen fiyat yok" : "\(savedCount) fiyat güncellendi",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(Theme.positive)
                    }
                }
            }
            .navigationTitle("Fiyatlar")
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await refresh() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save)
                        .disabled(changes.isEmpty || hasInvalidDraft)
                }
            }
            .keyboardDoneButton()
            .onAppear(perform: fillMissingDrafts)
            .onChange(of: ledger.prices.count) {
                drafts = [:]
                fillMissingDrafts()
            }
        }
    }

    private var monthAgo: Date { Date.now.addingTimeInterval(-30 * 86_400) }

    /// Ürünün elde bulunduğu yerlerdeki alış fiyatları; yalnızca yere özel fiyatı olan yerler.
    private func locationPrices(of assetID: UUID) -> [(name: String, price: Decimal)] {
        let calculator = ledger.calculator
        let locations = Set(calculator.holdings().filter { $0.key.assetID == assetID }.map(\.key.locationID))
        return locations.compactMap { locationID -> (name: String, price: Decimal)? in
            guard calculator.locationPriceHistory[HoldingPlace(assetID: assetID, locationID: locationID)] != nil,
                  let price = calculator.price(of: assetID, at: locationID)
            else { return nil }
            return (ledger.locationName(locationID), price)
        }
        .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// Son 30 günün fiyat kayıtları; dönem başındaki fiyat da başlangıç noktası olarak eklenir.
    private func recentPrices(of assetID: UUID) -> [PriceInfo] {
        let history = ledger.calculator.priceHistory[assetID] ?? []
        let start = monthAgo
        let recent = history.filter { $0.date > start }
        guard let base = history.last(where: { $0.date <= start }) else { return recent }
        return [PriceInfo(assetID: assetID, price: base.price, date: start)] + recent
    }

    private var pricedAssets: [Asset] {
        ledger.assets.filter { $0.unit != .lira }
    }

    private func refresh() async {
        savedCount = nil
        await updater?.update(assets: ledger.assets, prices: ledger.prices, context: context)
    }

    private var pendingChanges: [(asset: Asset, price: Decimal)] {
        pricedAssets.compactMap { asset in
            if case .changed(let price) = state(for: asset) { return (asset, price) }
            return nil
        }
    }

    private var hasInvalidDraft: Bool {
        pricedAssets.contains {
            if case .invalid = state(for: $0) { return true }
            return false
        }
    }

    private func state(for asset: Asset) -> PriceDraftState {
        let text = (drafts[asset.id] ?? "").trimmed
        guard !text.isEmpty else { return .unchanged }
        guard let value = Format.parseDecimal(text), value > 0 else { return .invalid }
        return value == ledger.calculator.latestPrices[asset.id]?.price ? .unchanged : .changed(value)
    }

    private func fillMissingDrafts() {
        for asset in pricedAssets where drafts[asset.id] == nil {
            drafts[asset.id] = ledger.calculator.latestPrices[asset.id].map { Format.editable($0.price) } ?? ""
        }
    }

    private func save() {
        let now = Date.now
        let changes = pendingChanges
        for change in changes {
            context.insert(PricePoint(assetID: change.asset.id, price: change.price, date: now))
        }
        try? context.save()
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        savedCount = changes.count
        if !changes.isEmpty { Haptics.success() }
    }
}

private struct PriceRow: View {
    let asset: Asset
    let latest: PriceInfo?
    let isAutomatic: Bool
    let monthChange: Decimal?
    let history: [PriceInfo]
    let locationPrices: [(name: String, price: Decimal)]
    let state: PriceDraftState
    @Binding var text: String
    @ScaledMetric private var iconSize: CGFloat = 38

    var body: some View {
        HStack(spacing: 10) {
            AssetIcon(asset: asset.info, size: iconSize)
            VStack(alignment: .leading, spacing: 3) {
                Text(asset.name)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if history.count > 1 || monthChange != nil {
                    HStack(spacing: 6) {
                        if history.count > 1 {
                            PriceSparkline(points: history, isDown: (monthChange ?? 0) < 0)
                        }
                        if let monthChange {
                            ChangeBadge(change: monthChange)
                        }
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(latest == nil ? Color.orange : Color.secondary)
                ForEach(locationPrices, id: \.name) { item in
                    Text("\(item.name) alışı \(Format.lira(item.price))")
                        .font(.caption)
                        .foregroundStyle(Theme.green)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 8)
            DecimalTextField(placeholder: "₺0,00", text: $text, isInvalid: state == .invalid, accessibilityLabel: "\(asset.name) fiyatı")
                .frame(width: 104)
            Image(systemName: state == .invalid ? "exclamationmark.circle.fill" : "pencil.circle.fill")
                .foregroundStyle(state == .invalid ? Theme.negative : Theme.gold)
                .opacity(state == .unchanged ? 0 : 1)
                .accessibilityHidden(state == .unchanged)
                .accessibilityLabel(state == .invalid ? "Geçersiz" : "Değişti")
        }
    }

    private var subtitle: String {
        let source = isAutomatic ? " · otomatik" : " · elle"
        guard let latest else { return "1 \(asset.unit.symbol) · Fiyat girilmedi\(source)" }
        let date = latest.date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Format.locale))
        return "1 \(asset.unit.symbol) · \(date)\(source)"
    }
}

/// Son 30 günün küçük fiyat grafiği.
private struct PriceSparkline: View {
    let points: [PriceInfo]
    let isDown: Bool

    var body: some View {
        Chart(points, id: \.date) { point in
            LineMark(x: .value("Tarih", point.date), y: .value("Fiyat", point.price.doubleValue))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .foregroundStyle(isDown ? Theme.negative : Theme.positive)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartLegend(.hidden)
        .frame(width: 40, height: 16)
        .accessibilityHidden(true)
    }
}

/// Yeşil (artış) ya da kırmızı (düşüş) yüzde rozeti.
private struct ChangeBadge: View {
    let change: Decimal

    var body: some View {
        let color: Color = change > 0 ? Theme.positive : change < 0 ? Theme.negative : .secondary
        HStack(spacing: 2) {
            Image(systemName: change > 0 ? "arrow.up.right" : change < 0 ? "arrow.down.right" : "equal")
            Text(Format.signedPercent(change))
                .monospacedDigit()
        }
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.14), in: Capsule())
        .accessibilityLabel("30 günde \(Format.signedPercent(change))")
    }
}

private struct UpdateStatusRow: View {
    let updater: PriceUpdater
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Theme.green.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("İnternetten fiyatlar")
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(isFailure ? Theme.negative : Color.secondary)
            }
            Spacer(minLength: 8)
            if updater.isUpdating {
                ProgressView()
            } else {
                Button("Güncelle", action: action)
                    .buttonStyle(.bordered)
            }
        }
    }

    private var isFailure: Bool {
        if case .failed = updater.status { return true }
        return false
    }

    private var detail: String {
        switch updater.status {
        case .updating:
            return "Güncelleniyor…"
        case .failed(let message):
            return message
        case .updated(let count):
            let when = updater.lastUpdate.map(Format.dateTime) ?? ""
            return count == 0 ? "\(when) · fiyatlar zaten güncel" : "\(when) · \(count) fiyat güncellendi"
        case .idle:
            return updater.lastUpdate.map { "Son güncelleme: \(Format.dateTime($0))" } ?? "Henüz güncellenmedi"
        }
    }
}

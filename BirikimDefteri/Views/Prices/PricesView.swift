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
                        Text("Altın ve gümüş: Truncgil Finans (Kapalıçarşı alış fiyatı). Dolar ve euro: TCMB döviz alış kuru. Yalnızca fiyat indirilir, verileriniz cihazdan çıkmaz.")
                    }
                }

                Section {
                    ForEach(pricedAssets) { asset in
                        PriceRow(
                            asset: asset,
                            latest: ledger.calculator.latestPrices[asset.id],
                            isAutomatic: QuoteKey.key(for: asset.info) != nil,
                            monthChange: ledger.calculator.marketChange(of: asset.id, since: Date.now.addingTimeInterval(-30 * 86_400)),
                            state: state(for: asset),
                            text: Binding(
                                get: { drafts[asset.id] ?? "" },
                                set: { drafts[asset.id] = $0; savedCount = nil }
                            )
                        )
                    }
                } footer: {
                    Text("1 birimin Türk lirası karşılığını girin. Kaydet'e bastığınızda yalnızca değiştirdiğiniz fiyatlar kaydedilir. Otomatik işaretli ürünlerde elle girdiğiniz fiyat bir sonraki internet güncellemesine kadar geçerlidir.")
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
    }
}

private struct PriceRow: View {
    let asset: Asset
    let latest: PriceInfo?
    let isAutomatic: Bool
    let monthChange: Decimal?
    let state: PriceDraftState
    @Binding var text: String
    @ScaledMetric private var iconSize: CGFloat = 38

    var body: some View {
        HStack(spacing: 12) {
            AssetIcon(asset: asset.info, size: iconSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.name)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(latest == nil ? Color.orange : Color.secondary)
            }
            Spacer(minLength: 8)
            TextField("₺0,00", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .foregroundStyle(state == .invalid ? Theme.negative : Color.primary)
                .frame(maxWidth: 150)
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
        let change = monthChange.map { " · 1 ayda \(Format.signedPercent($0))" } ?? ""
        return "1 \(asset.unit.symbol) · \(Format.dateTime(latest.date))\(source)\(change)"
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

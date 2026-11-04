import SwiftUI

struct GroupDetailView: View {
    let key: GroupKey
    let filter: PersonFilter

    @Environment(\.ledger) private var ledger
    @Environment(AppRouter.self) private var router
    @State private var editing: TransactionRecord?
    @State private var editingTransfer: TransferRef?

    var body: some View {
        let calculator = ledger.calculator
        let detail = calculator.detail(for: key, filter: filter)
        let history = calculator.valueHistory(for: filter, matching: key)

        List {
            Section {
                HStack(spacing: 14) {
                    GroupIcon(key: key, color: Theme.green, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(detail.title)
                            .font(.title3.weight(.semibold))
                        Text(detail.hasPrice ? Format.lira(detail.value) : "Fiyat girilmedi")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(detail.hasPrice ? Color.primary : Color.orange)
                    }
                }
                .padding(.vertical, 4)

                if case .asset(let assetID) = key, let asset = calculator.assets[assetID] {
                    assetOverview(detail, asset: asset, price: detail.hasMissingPrice || detail.quantity == 0
                                  ? calculator.price(of: assetID) : detail.value / detail.quantity)
                } else {
                    groupOverview(detail)
                }
            }

            if history.count > 1, detail.hasPrice {
                Section("Değer geçmişi") {
                    ValueHistoryChart(points: history, height: 190)
                        .padding(.vertical, 4)
                }
            }

            if case .asset(let assetID) = key, let prices = calculator.priceHistory[assetID], !prices.isEmpty {
                Section("Fiyat geçmişi") {
                    PriceHistoryChart(prices: prices, transactions: detail.transactions)
                        .padding(.vertical, 4)
                }
            }

            if !detail.holdings.isEmpty {
                Section("Nerede, kimde") {
                    ForEach(detail.holdings) { holding in
                        HoldingRow(holding: holding, showsAsset: !isAssetGroup)
                    }
                }
            }

            Section("Alım ve satımlar") {
                if detail.transactions.isEmpty {
                    Text("Kayıt yok").foregroundStyle(.secondary)
                }
                ForEach(detail.transactions) { transaction in
                    Button {
                        if let transferID = transaction.transferID {
                            editingTransfer = TransferRef(id: transferID)
                        } else {
                            editing = ledger.transaction(transaction.id)
                        }
                    } label: {
                        TransactionRow(info: transaction, note: ledger.transaction(transaction.id)?.note)
                    }
                }
            }
        }
        .navigationTitle(detail.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { record in
            TransactionFormView(record: record)
        }
        .sheet(item: $editingTransfer) { reference in
            TransferFormView(transferID: reference.id)
        }
    }

    private var isAssetGroup: Bool {
        if case .asset = key { return true }
        return false
    }

    @ViewBuilder
    private func assetOverview(_ detail: GroupDetail, asset: AssetInfo, price: Decimal?) -> some View {
        LabeledContent("Miktar", value: Format.quantity(detail.quantity, unit: asset.unit))
        if let averageCost = detail.averageCost {
            LabeledContent("Ortalama maliyet (1 \(asset.unit.symbol))", value: Format.lira(averageCost))
        }
        LabeledContent("Bozdurma değeri (1 \(asset.unit.symbol))") {
            if let price {
                Text(Format.lira(price))
            } else {
                Button("Fiyat gir") { router.tab = .prices }
            }
        }
        LabeledContent("Toplam maliyet", value: Format.lira(detail.totalCost))
        if asset.unit != .lira {
            MarketChangeRow(assetID: asset.id)
        }
        if detail.hasPrice {
            LabeledContent("Kâr/Zarar") {
                ProfitText(profit: detail.profit, ratio: detail.profitRatio)
            }
        }
    }

    @ViewBuilder
    private func groupOverview(_ detail: GroupDetail) -> some View {
        LabeledContent("Toplam maliyet", value: Format.lira(detail.pricedCost))
        LabeledContent("Kâr/Zarar") {
            ProfitText(profit: detail.profit, ratio: detail.profitRatio)
        }
        if detail.hasMissingPrice {
            Text("Fiyatı girilmemiş ürünler değer, maliyet ve kâra katılmadı.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct HoldingRow: View {
    let holding: Holding
    let showsAsset: Bool
    @Environment(\.ledger) private var ledger

    var body: some View {
        let asset = ledger.calculator.assets[holding.key.assetID]
        let place = "\(ledger.personName(holding.key.personID)) · \(ledger.locationName(holding.key.locationID))"

        HStack(spacing: 12) {
            if showsAsset {
                AssetIcon(asset: asset, size: 32)
            } else {
                PlaceIcon(location: ledger.calculator.locations[holding.key.locationID], size: 32)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(showsAsset ? asset?.name ?? "Bilinmeyen ürün" : place)
                if showsAsset {
                    Text(place)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.quantity(holding.quantity, unit: asset?.unit ?? .piece))
                    .monospacedDigit()
                Text(holding.value.map(Format.lira) ?? "Fiyat yok")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

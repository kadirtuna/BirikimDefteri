import Charts
import SwiftUI

/// Varlıkların nerede durduğunu tek sayfada gösterir: yer başına toplam, pay ve içindekiler.
struct LocationsOverviewView: View {
    let filter: PersonFilter

    @Environment(\.ledger) private var ledger

    var body: some View {
        let calculator = ledger.calculator
        let breakdown = calculator.locationBreakdown(for: filter)
        let total = breakdown.sum(\.value)
        let showsPerson = filter == .everyone && ledger.people.count > 1

        List {
            if breakdown.isEmpty {
                ContentUnavailableView(
                    "Henüz varlık yok",
                    systemImage: "mappin.slash",
                    description: Text("Alım ekledikçe varlıklarınızın nerede durduğu burada görünür.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Format.lira(total))
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .monospacedDigit()
                        Text("\(breakdown.count) yerde")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    LocationChart(breakdown: breakdown, calculator: calculator)
                        .padding(.vertical, 4)
                } header: {
                    Text("Yerlere göre dağılım")
                }

                ForEach(breakdown) { place in
                    Section {
                        ForEach(place.holdings) { holding in
                            LocationHoldingRow(holding: holding, showsPerson: showsPerson)
                        }
                    } header: {
                        LocationHeader(place: place, share: total > 0 ? place.value / total : 0)
                    } footer: {
                        if place.hasMissingPrice {
                            Text("Fiyatı girilmemiş ürünler toplama katılmadı.")
                        }
                    }
                }
            }
        }
        .navigationTitle("Varlıklarım nerede")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LocationHeader: View {
    let place: LocationHoldings
    let share: Decimal

    var body: some View {
        let kind = place.location?.kind ?? .physical

        HStack(spacing: 10) {
            Image(systemName: "\(kind.symbol).fill")
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    LinearGradient(
                        colors: kind == .bank ? [Color(hex: 0x1E88E5), Color(hex: 0x0D47A1)] : [Color(hex: 0x2E7D32), Color(hex: 0x1B5E20)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    in: Circle()
                )
            VStack(alignment: .leading, spacing: 0) {
                Text(place.location?.name ?? "Bilinmeyen yer")
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                Text(kind.title)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text(Format.lira(place.value))
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .monospacedDigit()
                Text(Format.percent(share))
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
        }
        .textCase(nil)
        .padding(.bottom, 2)
    }
}

private struct LocationHoldingRow: View {
    let holding: Holding
    let showsPerson: Bool
    @Environment(\.ledger) private var ledger
    @ScaledMetric private var iconSize: CGFloat = 34

    var body: some View {
        let asset = ledger.calculator.assets[holding.key.assetID]

        HStack(spacing: 12) {
            AssetIcon(asset: asset, size: iconSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(asset?.name ?? "Bilinmeyen ürün")
                if showsPerson {
                    Text(ledger.personName(holding.key.personID))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(holding.value.map(Format.lira) ?? "Fiyat yok")
                    .monospacedDigit()
                    .foregroundStyle(holding.value == nil ? Color.orange : Color.primary)
                Text(Format.quantity(holding.quantity, unit: asset?.unit ?? .piece))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Her yer için türlere bölünmüş yatay çubuk.
private struct LocationChart: View {
    let breakdown: [LocationHoldings]
    let calculator: PortfolioCalculator
    @ScaledMetric private var rowHeight: CGFloat = 34

    private struct Entry: Identifiable {
        let location: String
        let category: AssetCategory
        let value: Double
        var id: String { "\(location)-\(category.rawValue)" }
    }

    var body: some View {
        let entries = breakdown.flatMap { place in
            Dictionary(grouping: place.holdings) { calculator.assets[$0.key.assetID]?.category ?? .other }
                .map { category, holdings in
                    Entry(location: place.location?.name ?? "Bilinmeyen yer", category: category, value: holdings.sum { $0.value ?? 0 }.doubleValue)
                }
        }
        let categories = AssetCategory.allCases.filter { category in entries.contains { $0.category == category && $0.value > 0 } }

        Chart(entries) { entry in
            BarMark(x: .value("Değer", entry.value), y: .value("Yer", entry.location))
                .foregroundStyle(by: .value("Tür", entry.category.title))
                .cornerRadius(3)
        }
        .chartForegroundStyleScale(domain: categories.map(\.title), range: categories.map { ChartPalette.palette(for: $0)[0] })
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                AxisValueLabel {
                    if let amount = value.as(Double.self) { Text(Format.compactLira(amount)) }
                }
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: rowHeight * CGFloat(breakdown.count) + 60)
    }
}

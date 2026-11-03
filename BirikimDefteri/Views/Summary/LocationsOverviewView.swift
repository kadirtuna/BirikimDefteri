import SwiftUI

/// Varlıkların nerede durduğunu tek sayfada gösterir: yerlerin toplamdaki payı, her yerin içindekiler ve tür dağılımı.
struct LocationsOverviewView: View {
    let filter: PersonFilter

    @Environment(\.ledger) private var ledger

    var body: some View {
        let calculator = ledger.calculator
        let breakdown = calculator.locationBreakdown(for: filter)
        let total = breakdown.sum(\.value)
        let showsPerson = filter == .everyone && ledger.people.count > 1

        ScrollViewReader { proxy in
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
                        LocationShares(breakdown: breakdown, total: total) { id in
                            withAnimation { proxy.scrollTo(id, anchor: .top) }
                        }
                    } footer: {
                        if breakdown.count > 1 {
                            Text("Bir yere dokunarak içindekilere gidin.")
                        }
                    }

                    ForEach(breakdown) { place in
                        Section {
                            LocationHeader(
                                place: place,
                                share: total > 0 ? place.value / total : 0,
                                composition: composition(of: place, calculator: calculator)
                            )
                            .id(place.locationID)
                            .listRowBackground(
                                ZStack {
                                    Color(.secondarySystemGroupedBackground)
                                    PlaceIcon.accent(for: place.location).opacity(0.12)
                                }
                            )
                            ForEach(place.holdings) { holding in
                                LocationHoldingRow(holding: holding, showsPerson: showsPerson)
                            }
                        } footer: {
                            if place.hasMissingPrice {
                                Text("Fiyatı girilmemiş ürünler toplama katılmadı.")
                            }
                        }
                    }
                }
            }
            .listSectionSpacing(.custom(24))
        }
        .navigationTitle("Varlıklarım nerede")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Bir yerdeki türlerin değere göre payı, büyükten küçüğe.
    private func composition(of place: LocationHoldings, calculator: PortfolioCalculator) -> [ShareBar.Part] {
        let total = place.value
        guard total > 0 else { return [] }
        let groups = Dictionary(grouping: place.holdings) { (holding: Holding) -> AssetCategory in
            calculator.assets[holding.key.assetID]?.category ?? .other
        }
        var values: [(category: AssetCategory, value: Decimal)] = []
        for (category, holdings) in groups {
            let value = holdings.sum { $0.value ?? 0 }
            if value > 0 { values.append((category, value)) }
        }
        return values.sorted { $0.value > $1.value }.map { item in
            ShareBar.Part(id: item.category.rawValue, title: item.category.title,
                          color: ChartPalette.palette(for: item.category)[0], share: item.value / total)
        }
    }
}

/// Toplam ve yerlerin paylarını gösteren üst kart; bir yere dokununca onun kartına gider.
private struct LocationShares: View {
    let breakdown: [LocationHoldings]
    let total: Decimal
    let select: (UUID) -> Void
    @ScaledMetric private var iconSize: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.lira(total))
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("\(breakdown.count) yerde")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if total > 0 {
                VStack(spacing: 12) {
                    ForEach(breakdown) { place in
                        Button {
                            select(place.locationID)
                        } label: {
                            shareRow(place)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func shareRow(_ place: LocationHoldings) -> some View {
        let share = place.value / total
        return HStack(spacing: 10) {
            PlaceIcon(location: place.location, size: iconSize)
            VStack(spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name(place))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Format.percent(share))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .font(.subheadline)
                ProgressView(value: min(max(share.doubleValue, 0), 1))
                    .tint(Theme.green)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Bu yerin içindekilere gider")
    }

    private func name(_ place: LocationHoldings) -> String {
        place.location?.name ?? "Bilinmeyen yer"
    }
}

/// Bir yerin kartının başlığı: logo, ad, toplam, pay ve içindeki türlerin dağılımı.
private struct LocationHeader: View {
    let place: LocationHoldings
    let share: Decimal
    let composition: [ShareBar.Part]
    @ScaledMetric private var iconSize: CGFloat = 44

    var body: some View {
        let kind = place.location?.kind ?? .physical
        let productCount = Set(place.holdings.map(\.key.assetID)).count

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                PlaceIcon(location: place.location, size: iconSize)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.location?.name ?? "Bilinmeyen yer")
                        .font(.headline)
                    Text("\(kind.title) · \(productCount) ürün")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(Format.lira(place.value))
                        .font(.headline)
                        .monospacedDigit()
                    Text(Format.percent(share))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
            }

            if !composition.isEmpty {
                ShareBar(parts: composition, height: 6)
                Text(composition.map { "\($0.title) \(Format.percent($0.share))" }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

private struct LocationHoldingRow: View {
    let holding: Holding
    let showsPerson: Bool
    @Environment(\.ledger) private var ledger
    @ScaledMetric private var iconSize: CGFloat = 32

    var body: some View {
        let asset = ledger.calculator.assets[holding.key.assetID]

        HStack(spacing: 12) {
            AssetIcon(asset: asset, size: iconSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(asset?.name ?? "Bilinmeyen ürün")
                if !detail(asset).isEmpty {
                    Text(detail(asset))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 8)
            Text(holding.value.map(Format.lira) ?? "Fiyat yok")
                .monospacedDigit()
                .foregroundStyle(holding.value == nil ? Color.orange : Color.primary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Miktar (TL'de tutarla aynı olduğu için yazılmaz) ve gerekiyorsa kişi.
    private func detail(_ asset: AssetInfo?) -> String {
        var parts: [String] = []
        if let asset, asset.unit != .lira {
            parts.append(Format.quantity(holding.quantity, unit: asset.unit))
        }
        if showsPerson {
            parts.append(ledger.personName(holding.key.personID))
        }
        return parts.joined(separator: " · ")
    }
}

/// Paylara bölünmüş yatay çubuk.
struct ShareBar: View {
    struct Part: Identifiable {
        let id: String
        let title: String
        let color: Color
        let share: Decimal
    }

    let parts: [Part]
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = parts.count > 1 ? 2 : 0
            let available = proxy.size.width - spacing * CGFloat(parts.count - 1)
            HStack(spacing: spacing) {
                ForEach(parts) { part in
                    Rectangle()
                        .fill(part.color)
                        .frame(width: max(available * CGFloat(part.share.doubleValue), 2))
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

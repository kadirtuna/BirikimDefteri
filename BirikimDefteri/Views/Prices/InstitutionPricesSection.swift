import SwiftUI

/// Kurumların alış ve satış fiyatları: önce varlıklarınızın durduğu yerler, altında bütün banka ve kuyumcular.
struct InstitutionPricesSection: View {
    let board: PriceBoard?

    @Environment(\.ledger) private var ledger
    @AppStorage("institutionPricesInstrument") private var instrumentRaw = BidInstrument.gramGold.rawValue
    @State private var showsAll = Self.startsExpanded

    private static var startsExpanded: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "expandInstitutions")
        #else
        false
        #endif
    }

    private var instrument: BidInstrument { BidInstrument(rawValue: instrumentRaw) ?? .gramGold }

    var body: some View {
        Section {
            Picker("Ürün", selection: $instrumentRaw) {
                ForEach(BidInstrument.allCases, id: \.rawValue) { Text($0.shortTitle).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)

            if let board, !board.quotes(instrument).isEmpty {
                let mine = myPlaces(board)
                if !mine.isEmpty {
                    ForEach(mine, id: \.slug) { item in
                        InstitutionQuoteRow(slug: item.slug, title: item.title, quote: item.quote, unit: unit, note: item.note)
                    }
                }
                DisclosureGroup(isExpanded: $showsAll) {
                    ForEach(allQuotes(board), id: \.slug) { item in
                        InstitutionQuoteRow(slug: item.slug, title: item.quote.name, quote: item.quote, unit: unit, isBest: item.isBest)
                    }
                } label: {
                    Text(mine.isEmpty ? "Bütün kurumlar (\(board.quotes(instrument).count))" : "Diğer kurumlar (\(board.quotes(instrument).count))")
                }
            } else {
                Text("Kurum fiyatları henüz alınmadı. Yukarıdaki Güncelle'ye dokunun.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Kurumların alış ve satışı")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Alış: kurumun sizden alacağı fiyat, yani bozdururken eline geçen. Satış: kurumun size satacağı fiyat. Liste en yüksek alıştan sıralıdır.")
                if instrument == .gramGold {
                    Text("Midas kendi fiyatını yayımlamadığı için XAUT piyasa fiyatından tahmin edilir: alışta %0,5 düşülür, satışta %0,5 eklenir.")
                }
                if let board {
                    Text("Kaynak: doviz.com, CoinGecko · \(Format.dateTime(board.date))")
                }
            }
        }
    }

    private var unit: String {
        switch instrument {
        case .gramGold, .silver: "1 gr"
        case .usd: "1 $"
        case .eur: "1 €"
        }
    }

    /// Bu ürünün bulunduğu yerler; aynı kuruma düşen yerler bir kez gösterilir.
    private func myPlaces(_ board: PriceBoard) -> [(slug: String, title: String, quote: InstitutionQuote, note: String?)] {
        let calculator = ledger.calculator
        var seen: Set<String> = []
        var result: [(slug: String, title: String, quote: InstitutionQuote, note: String?)] = []
        for holding in calculator.holdings().sorted(by: { ($0.value ?? 0) > ($1.value ?? 0) }) {
            guard let asset = calculator.assets[holding.key.assetID], let key = QuoteKey.key(for: asset),
                  BidInstrument(key) == instrument, let location = calculator.locations[holding.key.locationID],
                  let slug = BidSource.slug(for: location), seen.insert(slug).inserted,
                  let quote = board.quote(instrument, slug: slug)
            else { continue }
            let note = slug == WidgetPlaces.dealersSlug ? "en düşük kuyumcu" : slug == PriceBoard.midasSlug ? "tahmini" : nil
            result.append((slug, location.name, quote, note))
        }
        return result
    }

    private func allQuotes(_ board: PriceBoard) -> [(slug: String, quote: InstitutionQuote, isBest: Bool)] {
        let sorted = board.quotes(instrument).sorted { $0.value.bid > $1.value.bid }
        let best = sorted.first?.value.bid
        return sorted.map { ($0.key, $0.value, $0.value.bid == best) }
    }
}

private struct InstitutionQuoteRow: View {
    let slug: String
    let title: String
    let quote: InstitutionQuote
    let unit: String
    var note: String? = nil
    var isBest = false
    @ScaledMetric private var iconSize: CGFloat = 30

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let spread = quote.spread {
                        Text(([unit, note].compactMap { $0 } + ["makas \(Format.percent(spread))"]).joined(separator: " · "))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if isBest {
                        Text("En iyi alış")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.positive)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.positive.opacity(0.14), in: Capsule())
                            .fixedSize()
                    }
                }
                .font(.caption)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(Format.plainLira(quote.bid))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if let ask = quote.ask {
                    Text("Satış \(Format.plainLira(ask))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var icon: some View {
        let institution = BidSource.institutions[slug].flatMap { id in Institution.all.first { $0.id == id } }
            ?? (slug == PriceBoard.midasSlug ? Institution.all.first { $0.id == "midas" } : nil)
        if let institution {
            InstitutionLogo(institution: institution, size: iconSize)
        } else {
            Image(systemName: slug == WidgetPlaces.dealersSlug ? "house.fill" : "storefront.fill")
                .font(.system(size: iconSize * 0.42))
                .foregroundStyle(.white)
                .frame(width: iconSize, height: iconSize)
                .background(Theme.gold.gradient, in: Circle())
                .accessibilityHidden(true)
        }
    }
}

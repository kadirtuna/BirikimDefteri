import SwiftUI

struct TransactionRow: View {
    let info: TransactionInfo
    let note: String?
    @Environment(\.ledger) private var ledger
    @ScaledMetric private var iconSize: CGFloat = 40

    var body: some View {
        let asset = ledger.calculator.assets[info.assetID]
        let unit = asset?.unit ?? .piece
        let isBuy = info.kind == .buy

        HStack(alignment: .top, spacing: 12) {
            AssetIcon(asset: asset, size: iconSize)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: isBuy ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: iconSize * 0.4))
                        .foregroundStyle(.white, isBuy ? Theme.positive : Color.orange)
                        .background(Circle().fill(Color(.systemBackground)).padding(-1.5))
                        .offset(x: 4, y: 4)
                }
                .accessibilityLabel(info.kind.title)
            VStack(alignment: .leading, spacing: 2) {
                Text(asset?.name ?? "Bilinmeyen ürün")
                    .foregroundStyle(Color.primary)
                Text("\(info.kind.title) · \(ledger.personName(info.personID)) · \(ledger.locationName(info.locationID))")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                if let note, !note.isEmpty {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text((isBuy ? "+" : "−") + Format.quantity(info.quantity, unit: unit))
                    .foregroundStyle(isBuy ? Theme.positive : Color.orange)
                    .monospacedDigit()
                Text(Format.lira(info.total))
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .monospacedDigit()
                Text(Format.date(info.date))
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

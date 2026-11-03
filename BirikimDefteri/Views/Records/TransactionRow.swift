import SwiftUI

struct TransactionRow: View {
    let info: TransactionInfo
    let note: String?
    @Environment(\.ledger) private var ledger
    @ScaledMetric private var iconSize: CGFloat = 40

    var body: some View {
        let asset = ledger.calculator.assets[info.assetID]
        let unit = asset?.unit ?? .piece

        HStack(alignment: .top, spacing: 12) {
            AssetIcon(asset: asset, size: iconSize)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: badgeSymbol)
                        .font(.system(size: iconSize * 0.4))
                        .foregroundStyle(.white, tint)
                        .background(Circle().fill(Color(.systemBackground)).padding(-1.5))
                        .offset(x: 4, y: 4)
                }
                .accessibilityLabel(info.kind.title)
            VStack(alignment: .leading, spacing: 2) {
                Text(asset?.name ?? "Bilinmeyen ürün")
                    .foregroundStyle(Color.primary)
                Text(subtitle)
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
                Text(sign + Format.quantity(info.quantity, unit: unit))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                Text(info.kind.isTransfer ? "maliyetiyle" : Format.lira(info.total))
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

    private var subtitle: String {
        guard info.kind.isTransfer, let transferID = info.transferID else {
            return "\(info.kind.title) · \(ledger.personName(info.personID)) · \(ledger.locationName(info.locationID))"
        }
        let legs = ledger.transferLegs(transferID)
        let from = legs.out.map { ledger.locationName($0.locationID) } ?? "?"
        let to = legs.in.map { ledger.locationName($0.locationID) } ?? "?"
        return "Aktarım · \(ledger.personName(info.personID)) · \(from) → \(to)"
    }

    private var badgeSymbol: String {
        switch info.kind {
        case .buy: "arrow.down.circle.fill"
        case .sell: "arrow.up.circle.fill"
        case .transferOut, .transferIn: "arrow.left.arrow.right.circle.fill"
        }
    }

    private var tint: Color {
        switch info.kind {
        case .buy: Theme.positive
        case .sell: .orange
        case .transferOut, .transferIn: .blue
        }
    }

    private var sign: String {
        switch info.kind {
        case .buy: "+"
        case .sell: "−"
        case .transferOut, .transferIn: ""
        }
    }
}

/// Silinen bir kaydı birkaç saniye geri almaya izin veren alt şerit.
struct UndoBanner: View {
    let message: String
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
            Spacer(minLength: 8)
            Button("Geri al", action: undo)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

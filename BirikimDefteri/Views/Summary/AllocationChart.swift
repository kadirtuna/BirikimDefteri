import Charts
import SwiftUI

/// Ortasında toplam yazan halka grafik. Bir dilime dokununca ortada o grubun adı, tutarı ve payı görünür;
/// aynı dilime yeniden dokununca toplama döner.
struct AllocationChart: View {
    let groups: [PortfolioGroup]
    let total: Decimal
    let colors: [GroupKey: Color]

    @State private var rawSelection: Double?
    @State private var selectedKey: GroupKey?

    var body: some View {
        let selected = groups.first { $0.key == selectedKey }

        Chart(groups) { group in
            SectorMark(
                angle: .value("Değer", group.value.doubleValue),
                innerRadius: .ratio(selected?.key == group.key ? 0.58 : 0.62),
                angularInset: 1.5
            )
            .cornerRadius(4)
            .foregroundStyle(colors[group.key] ?? .gray)
            .opacity(selected == nil || selected?.key == group.key ? 1 : 0.35)
            .accessibilityLabel(group.title)
            .accessibilityValue("\(Format.lira(group.value)), \(Format.percent(group.share))")
        }
        .chartLegend(.hidden)
        .chartAngleSelection(value: $rawSelection)
        .chartBackground { proxy in
            GeometryReader { geometry in
                if let anchor = proxy.plotFrame {
                    let frame = geometry[anchor]
                    VStack(spacing: 2) {
                        Text(selected?.title ?? "Toplam")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        Text(Format.lira(selected?.value ?? total))
                            .font(.headline)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                        if let selected {
                            Text(Format.percent(selected.share))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(colors[selected.key] ?? .secondary)
                        }
                    }
                    .frame(width: frame.width * 0.5)
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .frame(height: 240)
        .sensoryFeedback(.selection, trigger: selectedKey)
        .onChange(of: rawSelection) { old, new in
            guard let new, let key = group(at: new) else { return }
            withAnimation(.snappy) {
                // Seçili dilime yeni bir dokunuş seçimi kaldırır; parmak kaydırılırken seçim yalnızca değişir.
                selectedKey = old == nil && key == selectedKey ? nil : key
            }
        }
        .onChange(of: groups.map(\.key)) {
            selectedKey = nil
        }
    }

    /// Açı seçiminin (birikimli değer) düştüğü grup.
    private func group(at value: Double) -> GroupKey? {
        var cumulative = 0.0
        for group in groups {
            cumulative += group.value.doubleValue
            if value <= cumulative { return group.key }
        }
        return groups.last?.key
    }
}

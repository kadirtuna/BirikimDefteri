import Charts
import SwiftUI

/// Ortasında toplam yazan halka grafik.
struct AllocationChart: View {
    let groups: [PortfolioGroup]
    let total: Decimal
    let colors: [GroupKey: Color]

    var body: some View {
        Chart(groups) { group in
            SectorMark(
                angle: .value("Değer", group.value.doubleValue),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .cornerRadius(4)
            .foregroundStyle(colors[group.key] ?? .gray)
            .accessibilityLabel(group.title)
            .accessibilityValue("\(Format.lira(group.value)), \(Format.percent(group.share))")
        }
        .chartLegend(.hidden)
        .chartBackground { proxy in
            GeometryReader { geometry in
                if let anchor = proxy.plotFrame {
                    let frame = geometry[anchor]
                    VStack(spacing: 2) {
                        Text("Toplam")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(Format.lira(total))
                            .font(.headline)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                    }
                    .frame(width: frame.width * 0.56)
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .frame(height: 240)
    }
}

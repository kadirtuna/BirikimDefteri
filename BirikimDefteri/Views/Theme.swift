import SwiftUI

enum Theme {
    static let green = Color("AccentColor")
    static let gold = Color("Gold")
    static let positive = Color.green
    static let negative = Color.red
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Grafik renkleri: altınlar sarı tonları, dövizler yeşil ve mavi, TL kırmızı.
enum ChartPalette {
    static let gold: [Color] = [0xD4A017, 0xF0CF5A, 0xB8860B, 0xE6B422, 0x9C7A12, 0xF7E08F, 0xC9A227].map(Color.init(hex:))
    static let currency: [Color] = [0x2E7D32, 0x1E88E5, 0x66BB6A, 0x1565C0, 0x00897B, 0x64B5F6].map(Color.init(hex:))
    static let silver: [Color] = [0x9AA2A9, 0xC5CBD0, 0x6F787F].map(Color.init(hex:))
    static let lira: [Color] = [0xD32F2F, 0xE57373, 0x9A0007].map(Color.init(hex:))
    static let fund: [Color] = [0x7E57C2, 0x26A69A, 0x5C6BC0, 0x00897B].map(Color.init(hex:))
    static let other: [Color] = [0x8D6E63, 0xA1887F, 0x6D4C41, 0xBCAAA4].map(Color.init(hex:))
    static let general: [Color] = [0x1B5E3F, 0xD4A017, 0x1E88E5, 0xD32F2F, 0x8E24AA, 0x00897B, 0xF57C00, 0x546E7A].map(Color.init(hex:))

    static func palette(for category: AssetCategory) -> [Color] {
        switch category {
        case .gold: gold
        case .silver: silver
        case .currency: currency
        case .fund: fund
        case .lira: lira
        case .other: other
        }
    }

    /// Renkler ürünün kendi kategorisindeki sırasına göre verilir, böylece değer değişince renk kaymaz.
    static func colors(for groups: [PortfolioGroup], calculator: PortfolioCalculator) -> [GroupKey: Color] {
        let assetsByCategory = Dictionary(grouping: calculator.assets.values.sorted { $0.sortOrder < $1.sortOrder }, by: \.category)
        let personIDs = calculator.people.values.sorted { $0.name < $1.name }.map(\.id)
        let locationIDs = calculator.locations.values.sorted { $0.name < $1.name }.map(\.id)

        var result: [GroupKey: Color] = [:]
        for group in groups {
            switch group.key {
            case .asset(let id):
                let category = calculator.assets[id]?.category ?? .other
                let index = assetsByCategory[category]?.firstIndex { $0.id == id } ?? 0
                let colors = palette(for: category)
                result[group.key] = colors[index % colors.count]
            case .category(let category):
                result[group.key] = palette(for: category)[0]
            case .person(let id):
                result[group.key] = general[(personIDs.firstIndex(of: id) ?? 0) % general.count]
            case .location(let id):
                result[group.key] = general[(locationIDs.firstIndex(of: id) ?? 0) % general.count]
            }
        }
        return result
    }
}

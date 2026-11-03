import SwiftUI

/// Ürünün türünden ve adından çıkarılan görsel: külçe, sikke, bilezik ya da para birimi rozeti.
enum AssetArtwork: Hashable {
    enum Metal: Hashable {
        case gold, silver
    }

    case bar(Metal)
    case coin(Metal, String)
    case bracelet(Metal)
    case dollar, euro, lira
    case currencies
    case fund
    case generic

    init(asset: AssetInfo) {
        let name = asset.name.lowercased(with: Format.locale)
        if asset.category == .fund {
            self = .fund
            return
        }
        switch asset.unit {
        case .usd:
            self = .dollar
            return
        case .eur:
            self = .euro
            return
        case .lira:
            self = .lira
            return
        case .gram, .piece:
            break
        }
        let metal: Metal?
        switch asset.category {
        case .gold: metal = name.contains("gümüş") ? .silver : .gold
        case .silver: metal = .silver
        case .currency, .fund, .lira, .other: metal = name.contains("altın") ? .gold : name.contains("gümüş") ? .silver : nil
        }
        guard let metal else {
            self = .generic
            return
        }
        if name.contains("bilezik") || name.contains("bileklik") {
            self = .bracelet(metal)
        } else if asset.unit == .piece {
            let letter = asset.name.first.map { String($0).uppercased(with: Format.locale) } ?? "•"
            self = .coin(metal, letter)
        } else {
            self = .bar(metal)
        }
    }

    init(category: AssetCategory) {
        switch category {
        case .gold: self = .bar(.gold)
        case .silver: self = .bar(.silver)
        case .currency: self = .currencies
        case .fund: self = .fund
        case .lira: self = .lira
        case .other: self = .generic
        }
    }
}

struct AssetIcon: View {
    let artwork: AssetArtwork
    var size: CGFloat = 40

    init(artwork: AssetArtwork, size: CGFloat = 40) {
        self.artwork = artwork
        self.size = size
    }

    init(asset: AssetInfo?, size: CGFloat = 40) {
        self.init(artwork: asset.map(AssetArtwork.init(asset:)) ?? .generic, size: size)
    }

    var body: some View {
        content
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch artwork {
        case .bar(let metal):
            ZStack {
                Circle().fill(metal.tint)
                IngotView(metal: metal)
                    .frame(width: size * 0.72, height: size * 0.5)
                    .offset(y: size * 0.04)
            }
        case .coin(let metal, let letter):
            ZStack {
                Circle().fill(metal.gradient)
                Circle()
                    .strokeBorder(metal.rim, lineWidth: max(1, size * 0.05))
                    .padding(size * 0.09)
                Text(letter)
                    .font(.system(size: size * 0.42, weight: .heavy, design: .serif))
                    .foregroundStyle(metal.ink)
                    .shadow(color: .white.opacity(0.55), radius: 0, x: -0.6, y: -0.6)
            }
            .shadow(color: .black.opacity(0.18), radius: size * 0.04, y: size * 0.03)
        case .bracelet(let metal):
            ZStack {
                Circle().fill(metal.tint)
                Circle()
                    .strokeBorder(metal.gradient, lineWidth: size * 0.11)
                    .frame(width: size * 0.56, height: size * 0.56)
                    .offset(x: -size * 0.08, y: size * 0.04)
                Circle()
                    .strokeBorder(metal.gradient, lineWidth: size * 0.11)
                    .frame(width: size * 0.56, height: size * 0.56)
                    .offset(x: size * 0.08, y: -size * 0.04)
            }
        case .dollar:
            badge(symbol: "$", colors: [0x43A047, 0x1B5E20])
        case .lira:
            badge(symbol: "₺", colors: [0xE53935, 0x9A0007])
        case .currencies:
            badge(symbol: "$€", colors: [0x2E7D32, 0x1565C0], scale: 0.36)
        case .fund:
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(hex: 0x7E57C2), Color(hex: 0x00897B)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
            }
        case .euro:
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(hex: 0x2457C5), Color(hex: 0x0B2A6F)], startPoint: .top, endPoint: .bottom))
                ForEach(0..<12, id: \.self) { index in
                    Image(systemName: "star.fill")
                        .font(.system(size: size * 0.09))
                        .foregroundStyle(Color(hex: 0xFFCC00))
                        .offset(y: -size * 0.34)
                        .rotationEffect(.degrees(Double(index) * 30))
                }
                Text("€")
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        case .generic:
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(hex: 0x90A4AE), Color(hex: 0x546E7A)], startPoint: .top, endPoint: .bottom))
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(.white)
            }
        }
    }

    private func badge(symbol: String, colors: [UInt32], scale: CGFloat = 0.5) -> some View {
        ZStack {
            Circle().fill(LinearGradient(colors: colors.map(Color.init(hex:)), startPoint: .top, endPoint: .bottom))
            Circle()
                .strokeBorder(.white.opacity(0.35), lineWidth: max(1, size * 0.03))
                .padding(size * 0.08)
            Text(symbol)
                .font(.system(size: size * scale, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
        }
    }
}

extension AssetArtwork.Metal {
    var gradient: LinearGradient {
        let stops: [UInt32] = switch self {
        case .gold: [0xFFF1B8, 0xF2C94C, 0xC8921F, 0xF7DA7A, 0xA9741A]
        case .silver: [0xFFFFFF, 0xD7DCE0, 0x9AA2A9, 0xE9ECEF, 0x7D858C]
        }
        return LinearGradient(colors: stops.map(Color.init(hex:)), startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var topGradient: LinearGradient {
        let stops: [UInt32] = switch self {
        case .gold: [0xFFF6D0, 0xF2C94C]
        case .silver: [0xFFFFFF, 0xC9CFD4]
        }
        return LinearGradient(colors: stops.map(Color.init(hex:)), startPoint: .top, endPoint: .bottom)
    }

    var rim: Color {
        switch self {
        case .gold: Color(hex: 0x9C6A12).opacity(0.85)
        case .silver: Color(hex: 0x6B737A).opacity(0.85)
        }
    }

    var ink: Color {
        switch self {
        case .gold: Color(hex: 0x7A4E0A)
        case .silver: Color(hex: 0x4A5258)
        }
    }

    var tint: Color {
        switch self {
        case .gold: Color(hex: 0xD4A017).opacity(0.18)
        case .silver: Color(hex: 0x9AA2A9).opacity(0.22)
        }
    }
}

/// Önden ve üstten görünen külçe.
private struct IngotView: View {
    let metal: AssetArtwork.Metal

    var body: some View {
        ZStack {
            IngotFace(isTop: false).fill(metal.gradient)
            IngotFace(isTop: true).fill(metal.topGradient)
        }
        .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
    }
}

private struct IngotFace: Shape {
    let isTop: Bool

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        if isTop {
            path.move(to: CGPoint(x: w * 0.12, y: h * 0.42))
            path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.42))
            path.addLine(to: CGPoint(x: w * 0.76, y: 0))
            path.addLine(to: CGPoint(x: w * 0.24, y: 0))
        } else {
            path.move(to: CGPoint(x: 0, y: h))
            path.addLine(to: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.42))
            path.addLine(to: CGPoint(x: w * 0.12, y: h * 0.42))
        }
        path.closeSubpath()
        return path
    }
}

/// Gruplama satırlarının simgesi: ürün ve türde ürün görseli, kişide baş harfler, yerde yer simgesi.
struct GroupIcon: View {
    let key: GroupKey
    let color: Color
    var size: CGFloat = 40
    @Environment(\.ledger) private var ledger

    var body: some View {
        switch key {
        case .asset(let id):
            AssetIcon(asset: ledger.calculator.assets[id], size: size)
        case .category(let category):
            AssetIcon(artwork: AssetArtwork(category: category), size: size)
        case .person(let id):
            Circle()
                .fill(color.gradient)
                .overlay {
                    Text(initials(ledger.personName(id)))
                        .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)
        case .location(let id):
            PlaceIcon(location: ledger.calculator.locations[id], size: size, color: color)
        }
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2)
            .compactMap(\.first)
            .map { String($0).uppercased(with: Format.locale) }
            .joined()
    }
}

/// Özet ve Borçlar ekranlarının üst kartı için degrade arka plan.
struct HeroBackground: View {
    var colors: [UInt32] = [0x1F7A52, 0x0E3B27]
    var glow: UInt32 = 0xE0B84A

    var body: some View {
        ZStack {
            LinearGradient(colors: colors.map(Color.init(hex:)), startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(
                colors: [Color(hex: glow).opacity(0.35), .clear],
                center: .topTrailing, startRadius: 0, endRadius: 260
            )
            GeometryReader { proxy in
                Circle()
                    .strokeBorder(.white.opacity(0.07), lineWidth: 22)
                    .frame(width: proxy.size.height * 1.3)
                    .position(x: proxy.size.width - proxy.size.height * 0.15, y: proxy.size.height * 0.15)
                Circle()
                    .strokeBorder(.white.opacity(0.05), lineWidth: 14)
                    .frame(width: proxy.size.height * 0.8)
                    .position(x: proxy.size.width - proxy.size.height * 0.15, y: proxy.size.height * 0.15)
            }
        }
    }
}

struct AppLogo: View {
    var size: CGFloat = 88

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: size * 0.08, y: size * 0.04)
            .accessibilityHidden(true)
    }
}

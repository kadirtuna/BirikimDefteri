import SwiftUI
import UIKit

/// Kurumun logosu. Logo görseli yalnızca kişisel derlemede bulunur (`scripts/fetch-logos.py`);
/// yoksa kurumun renginde baş harf rozeti çizilir.
struct InstitutionLogo: View {
    let institution: Institution
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let image = UIImage(named: "inst-\(institution.id)") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .background(Color.white)
            } else {
                Circle()
                    .fill(Color(hex: institution.color).gradient)
                    .overlay {
                        Text(institution.monogram)
                            .font(.system(size: size * (institution.monogram.count > 2 ? 0.3 : 0.4), weight: .bold, design: .rounded))
                            .foregroundStyle(isLight ? Color.black.opacity(0.8) : .white)
                            .minimumScaleFactor(0.5)
                            .padding(size * 0.1)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    private var isLight: Bool {
        let red = Double((institution.color >> 16) & 0xFF) / 255
        let green = Double((institution.color >> 8) & 0xFF) / 255
        let blue = Double(institution.color & 0xFF) / 255
        return 0.299 * red + 0.587 * green + 0.114 * blue > 0.65
    }
}

/// Saklama yerinin simgesi: tanınan kurumda logo, değilse yer türünün simgesi.
struct PlaceIcon: View {
    let location: LocationInfo?
    var size: CGFloat = 40
    /// Tanınmayan yerlerde kullanılacak dolgu; verilmezse yer türünün rengi kullanılır.
    var color: Color?

    var body: some View {
        if let location, location.kind == .bank, let institution = Institution.match(location.name) {
            InstitutionLogo(institution: institution, size: size)
        } else {
            let kind = location?.kind ?? .physical
            Circle()
                .fill(color.map { AnyShapeStyle($0.gradient) } ?? AnyShapeStyle(LinearGradient(
                    colors: kind == .bank ? [Color(hex: 0x1E88E5), Color(hex: 0x0D47A1)] : [Color(hex: 0x2E7D32), Color(hex: 0x1B5E20)],
                    startPoint: .top, endPoint: .bottom
                )))
                .overlay {
                    Image(systemName: location.map { "\($0.kind.symbol).fill" } ?? "mappin")
                        .font(.system(size: size * 0.42))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

/// Borç satırlarının simgesi: tanınan kurumun logosu üzerinde borç türü rozeti.
struct DebtIcon: View {
    let kind: DebtKind
    let institution: String
    var size: CGFloat = 40

    var body: some View {
        if let match = Institution.match(institution) {
            InstitutionLogo(institution: match, size: size)
                .overlay(alignment: .bottomTrailing) {
                    DebtKindIcon(kind: kind, size: size * 0.42)
                        .background(Circle().fill(Color(.systemBackground)).padding(-1.5))
                        .offset(x: 4, y: 4)
                }
        } else {
            DebtKindIcon(kind: kind, size: size)
        }
    }
}

/// Ad yazılırken tanınan kurumu gösteren form satırı.
struct InstitutionMatchRow: View {
    let name: String

    var body: some View {
        if let institution = Institution.match(name) {
            HStack(spacing: 12) {
                InstitutionLogo(institution: institution, size: 30)
                Text("\(institution.name) olarak tanındı")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

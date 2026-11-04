#if DEBUG
import SwiftUI
import WidgetKit

/// Yalnızca Debug derlemede, `-widgetPreview YES` açılış argümanıyla açılır: widget'ın her boyutunu uygulamanın
/// kaydettiği son kurum fiyatlarıyla çizer. Simülatöre widget eklemeden görünümü denetlemek için.
struct WidgetPreviewScreen: View {
    var body: some View {
        let entry = Self.entry()
        ScrollView {
            VStack(spacing: 18) {
                HStack(alignment: .top, spacing: 18) {
                    card(.systemSmall, entry: entry, width: 170, height: 170)
                    VStack(spacing: 12) {
                        card(.accessoryRectangular, entry: entry, width: 172, height: 76, padding: 6)
                        card(.accessoryInline, entry: entry, width: 172, height: 28, padding: 4)
                    }
                }
                card(.systemMedium, entry: entry, width: 364, height: 170)
                card(.systemLarge, entry: entry, width: 364, height: 382)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .background(LinearGradient(colors: [.blue.opacity(0.5), .teal.opacity(0.4)], startPoint: .top, endPoint: .bottom))
    }

    private func card(_ family: WidgetFamily, entry: PriceEntry, width: CGFloat, height: CGFloat, padding: CGFloat = 16) -> some View {
        PriceWidgetView(entry: entry, family: family)
            .padding(padding)
            .frame(width: width, height: height, alignment: .topLeading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: family == .accessoryInline ? 8 : 22, style: .continuous))
    }

    static func entry() -> PriceEntry {
        let board = SharedStore.load(PriceBoard.self, key: SharedStore.boardKey)
        let saved = SharedStore.load(WidgetPlaces.self, key: SharedStore.placesKey)?.places[.gramGold] ?? []
        let slugs = saved.isEmpty ? ["kapalicarsi", "ziraat-bankasi", "garanti-bbva", "isbankasi"] : saved
        return PriceEntry.make(board: board, instrument: .gramGold, slugs: slugs)
    }
}
#endif

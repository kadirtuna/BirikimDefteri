import SwiftData
import SwiftUI

/// Uygulama ve Kısayollar (Siri) aynı veri deposunu kullanır.
@MainActor
enum AppContainer {
    static let shared: ModelContainer = {
        do {
            return try ModelContainer(
                for: Person.self, Location.self, Asset.self, PricePoint.self, TransactionRecord.self, Debt.self,
                DebtPayment.self, Goal.self, JournalEntry.self
            )
        } catch {
            fatalError("Veri deposu açılamadı: \(error)")
        }
    }()
}

@main
struct BirikimDefteriApp: App {
    private let container: ModelContainer

    init() {
        container = AppContainer.shared
        #if DEBUG
        Store.loadDemoDataIfRequested(in: container.mainContext)
        #endif
        Store.seedIfNeeded(in: container.mainContext)
        Store.mergePendingImport(in: container.mainContext)
        Format.hidesAmounts = UserDefaults.standard.bool(forKey: AmountPrivacy.key)
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "widgetPreview") {
                WidgetPreviewScreen()
            } else {
                RootView()
                    .environment(\.locale, Format.locale)
            }
            #else
            RootView()
                .environment(\.locale, Format.locale)
            #endif
        }
        .modelContainer(container)
    }
}

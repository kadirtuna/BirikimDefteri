import SwiftData
import SwiftUI

@main
struct BirikimDefteriApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: Person.self, Location.self, Asset.self, PricePoint.self, TransactionRecord.self, Debt.self
            )
        } catch {
            fatalError("Veri deposu açılamadı: \(error)")
        }
        #if DEBUG
        Store.loadDemoDataIfRequested(in: container.mainContext)
        #endif
        Store.seedIfNeeded(in: container.mainContext)
        Store.mergePendingImport(in: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.locale, Format.locale)
        }
        .modelContainer(container)
    }
}

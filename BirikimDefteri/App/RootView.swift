import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case summary, records, debts, prices, settings
}

@Observable
final class AppRouter {
    var tab: AppTab = .summary
}

extension EnvironmentValues {
    @Entry var ledger = Ledger()
}

struct RootView: View {
    @Query(sort: \Person.createdAt) private var people: [Person]
    @Query(sort: \Location.createdAt) private var locations: [Location]
    @Query(sort: \Asset.sortOrder) private var assets: [Asset]
    @Query(sort: \PricePoint.date) private var prices: [PricePoint]
    @Query(sort: \TransactionRecord.date) private var transactions: [TransactionRecord]
    @Query(sort: \Debt.updatedAt) private var debts: [Debt]

    @State private var router = AppRouter()
    @State private var lock = AppLock()
    @State private var priceUpdater = PriceUpdater()
    @AppStorage(PriceUpdater.autoUpdateKey) private var autoUpdatePrices = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context

    private var ledger: Ledger {
        Ledger(
            people: people, locations: locations, assets: assets,
            prices: prices, transactions: transactions, debts: debts
        )
    }

    var body: some View {
        TabView(selection: $router.tab) {
            SummaryView()
                .tabItem { Label("Özet", systemImage: "chart.pie.fill") }
                .tag(AppTab.summary)
            TransactionsView()
                .tabItem { Label("Kayıtlar", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.records)
            DebtsView()
                .tabItem { Label("Borçlar", systemImage: "creditcard") }
                .tag(AppTab.debts)
            PricesView()
                .tabItem { Label("Fiyatlar", systemImage: "tag") }
                .tag(AppTab.prices)
            SettingsView()
                .tabItem { Label("Ayarlar", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .lockProtected()
        .environment(\.ledger, ledger)
        .environment(router)
        .environment(lock)
        .environment(priceUpdater)
        .onChange(of: scenePhase, initial: true) { _, phase in
            lock.scenePhaseChanged(to: phase)
            if phase == .active || phase == .background {
                AutoBackup.saveIfChanged(ledger)
            }
            if phase == .active, autoUpdatePrices {
                Task { await priceUpdater.updateIfStale(assets: assets, prices: prices, context: context) }
            }
        }
    }
}

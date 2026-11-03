import Foundation
import SwiftData

/// Tüm kayıtların ve onlardan kurulan hesaplayıcının anlık görüntüsü.
/// RootView'da sorgulardan kurulur ve ortam (environment) üzerinden ekranlara iletilir.
struct Ledger {
    var people: [Person] = []
    var locations: [Location] = []
    var assets: [Asset] = []
    var prices: [PricePoint] = []
    var transactions: [TransactionRecord] = []
    var debts: [Debt] = []
    var payments: [DebtPayment] = []
    var goals: [Goal] = []
    var calculator = PortfolioCalculator()

    init() {}

    init(
        people: [Person], locations: [Location], assets: [Asset],
        prices: [PricePoint], transactions: [TransactionRecord], debts: [Debt],
        payments: [DebtPayment] = [], goals: [Goal] = []
    ) {
        self.people = people
        self.locations = locations
        self.assets = assets
        self.prices = prices
        self.transactions = transactions
        self.debts = debts
        self.payments = payments
        self.goals = goals
        self.calculator = PortfolioCalculator(
            people: people.map(\.info),
            locations: locations.map(\.info),
            assets: assets.map(\.info),
            prices: prices.map(\.info),
            transactions: transactions.map(\.info),
            debts: debts.map(\.info)
        )
    }

    /// Depodaki her şeyle kurulan anlık görüntü; arayüz dışından (Kısayollar, testler) erişim için.
    static func fetch(from context: ModelContext) -> Ledger {
        Ledger(
            people: (try? context.fetch(FetchDescriptor<Person>(sortBy: [SortDescriptor(\.createdAt)]))) ?? [],
            locations: (try? context.fetch(FetchDescriptor<Location>(sortBy: [SortDescriptor(\.createdAt)]))) ?? [],
            assets: (try? context.fetch(FetchDescriptor<Asset>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? [],
            prices: (try? context.fetch(FetchDescriptor<PricePoint>(sortBy: [SortDescriptor(\.date)]))) ?? [],
            transactions: (try? context.fetch(FetchDescriptor<TransactionRecord>(sortBy: [SortDescriptor(\.date)]))) ?? [],
            debts: (try? context.fetch(FetchDescriptor<Debt>(sortBy: [SortDescriptor(\.updatedAt)]))) ?? [],
            payments: (try? context.fetch(FetchDescriptor<DebtPayment>(sortBy: [SortDescriptor(\.date)]))) ?? [],
            goals: (try? context.fetch(FetchDescriptor<Goal>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        )
    }

    /// Önümüzdeki günlerde (ve gecikmiş) ödemesi olan borçlar, tarihe göre.
    func upcomingPayments(within days: Int, for filter: PersonFilter = .everyone, now: Date = .now) -> [(debt: Debt, payment: UpcomingPayment)] {
        let calendar = Calendar.current
        guard let limit = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now)) else { return [] }
        return debts
            .filter { filter.includes($0.personID) }
            .compactMap { debt in
                DebtPlan.nextPayment(
                    kind: debt.kind, remaining: debt.remaining, monthly: debt.monthlyInstallment, dueDate: debt.dueDate,
                    paymentDay: debt.paymentDay, lastPayment: payments(for: debt).map(\.date).max(), now: now
                ).map { (debt, $0) }
            }
            .filter { $0.payment.date <= limit }
            .sorted { $0.payment.date < $1.payment.date }
    }

    func transaction(_ id: UUID) -> TransactionRecord? {
        transactions.first { $0.id == id }
    }

    /// Aktarımın iki ayağı.
    func transferLegs(_ transferID: UUID) -> (out: TransactionRecord?, in: TransactionRecord?) {
        let legs = transactions.filter { $0.transferID == transferID }
        return (legs.first { $0.kind == .transferOut }, legs.first { $0.kind == .transferIn })
    }

    func payments(for debt: Debt) -> [DebtPayment] {
        payments.filter { $0.debtID == debt.id }.sorted { $0.date > $1.date }
    }

    func personName(_ id: UUID) -> String {
        calculator.people[id]?.name ?? "Bilinmeyen kişi"
    }

    func locationName(_ id: UUID) -> String {
        calculator.locations[id]?.name ?? "Bilinmeyen yer"
    }

    func isInUse(_ person: Person) -> Bool {
        transactions.contains { $0.personID == person.id } || debts.contains { $0.personID == person.id }
    }

    func isInUse(_ location: Location) -> Bool {
        transactions.contains { $0.locationID == location.id }
    }

    func isInUse(_ asset: Asset) -> Bool {
        transactions.contains { $0.assetID == asset.id }
    }
}

@MainActor
enum Store {
    /// İlk açılışta varsayılan kişi, yer ve ürünleri oluşturur.
    static func seedIfNeeded(in context: ModelContext) {
        guard count(Asset.self, in: context) == 0 else { return }

        if count(Person.self, in: context) == 0 {
            context.insert(Person(name: "Ben"))
        }
        if count(Location.self, in: context) == 0 {
            context.insert(Location(name: "Fiziki (elde)", kind: .physical))
        }
        insertLira(in: context)
        let seeds: [(String, AssetUnit, AssetCategory)] = [
            ("Gram altın", .gram, .gold),
            ("Çeyrek altın", .piece, .gold),
            ("Yarım altın", .piece, .gold),
            ("Tam altın", .piece, .gold),
            ("Cumhuriyet altını", .piece, .gold),
            ("22 ayar bilezik", .gram, .gold),
            ("Gram gümüş", .gram, .silver),
            ("Dolar", .usd, .currency),
            ("Euro", .eur, .currency),
        ]
        for (index, seed) in seeds.enumerated() {
            context.insert(Asset(name: seed.0, unit: seed.1, category: seed.2, sortOrder: index + 1))
        }
        try? context.save()
    }

    static func insertLira(in context: ModelContext) {
        context.insert(Asset(id: AssetInfo.liraID, name: "Türk lirası", unit: .lira, category: .lira, sortOrder: 0))
    }

    /// Uygulama klasörünün Documents dizinine (ör. `xcrun devicectl device copy to` ile) bırakılan
    /// yedeği mevcut verilere ekler (aynı kimlikli kayıtları günceller). Sonucu yanına yazar ve dosyayı siler; bozuksa ".hatali" uzantısıyla kenara alır.
    static func mergePendingImport(in context: ModelContext) {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = documents.appendingPathComponent("BirikimDefteri-ekle.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let report = documents.appendingPathComponent("BirikimDefteri-ekle-sonuc.txt")
        do {
            let backup = try BackupService.decode(Data(contentsOf: url))
            let result = try BackupService.merge(backup, into: context)
            try FileManager.default.removeItem(at: url)
            try? "\(Date.now.formatted(.iso8601)) eklenen işlem: \(result.added), güncellenen: \(result.updated)\n"
                .write(to: report, atomically: true, encoding: .utf8)
        } catch {
            try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("hatali"))
            try? "\(Date.now.formatted(.iso8601)) hata: \(error.localizedDescription)\n".write(to: report, atomically: true, encoding: .utf8)
        }
    }

    @discardableResult
    static func addPerson(named name: String, in context: ModelContext) -> Person? {
        let name = name.trimmed
        guard !name.isEmpty else { return nil }
        let person = Person(name: name)
        context.insert(person)
        try? context.save()
        return person
    }

    private static func count<T: PersistentModel>(_ type: T.Type, in context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<T>())) ?? 0
    }
}

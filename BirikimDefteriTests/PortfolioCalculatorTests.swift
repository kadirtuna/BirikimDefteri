import Foundation
import SwiftData
import Testing
@testable import BirikimDefteri

private func d(_ text: String) -> Decimal {
    Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
}

private enum Fixture {
    static let me = PersonInfo(id: UUID(), name: "Ben")
    static let partner = PersonInfo(id: UUID(), name: "Eşim")
    static let home = LocationInfo(id: UUID(), name: "Fiziki (elde)", kind: .physical)
    static let bank = LocationInfo(id: UUID(), name: "Ziraat", kind: .bank)
    static let lira = AssetInfo(id: AssetInfo.liraID, name: "Türk lirası", unit: .lira, category: .lira, sortOrder: 0)
    static let gram = AssetInfo(id: UUID(), name: "Gram altın", unit: .gram, category: .gold, sortOrder: 1)
    static let quarter = AssetInfo(id: UUID(), name: "Çeyrek altın", unit: .piece, category: .gold, sortOrder: 2)
    static let dollar = AssetInfo(id: UUID(), name: "Dolar", unit: .usd, category: .currency, sortOrder: 7)

    static let start = Date(timeIntervalSince1970: 1_767_225_600)

    static func day(_ number: Int) -> Date {
        start.addingTimeInterval(Double(number) * 86_400)
    }

    static func tx(
        _ kind: TransactionKind, _ asset: AssetInfo, _ quantity: String, at price: String,
        person: PersonInfo = me, location: LocationInfo = home, day number: Int = 0, id: UUID = UUID()
    ) -> TransactionInfo {
        TransactionInfo(
            id: id, kind: kind, personID: person.id, assetID: asset.id, locationID: location.id,
            quantity: d(quantity), unitPrice: d(price), date: day(number), createdAt: day(number)
        )
    }

    static func calculator(
        _ transactions: [TransactionInfo], prices: [UUID: String] = [:], debts: [DebtInfo] = []
    ) -> PortfolioCalculator {
        PortfolioCalculator(
            people: [me, partner],
            locations: [home, bank],
            assets: [lira, gram, quarter, dollar],
            prices: prices.map { PriceInfo(assetID: $0.key, price: d($0.value), date: start) },
            transactions: transactions,
            debts: debts
        )
    }

    /// Ben: 10 gr altın (evde, ₺2.000), 2 çeyrek (evde, ₺3.500), $1.000 (bankada, ₺30), ₺5.000 (bankada).
    /// Eşim: 5 gr altın (bankada, ₺2.400).
    /// Güncel: gram ₺3.000, çeyrek ₺5.000, dolar ₺40 → toplam değer ₺100.000, maliyet ₺74.000.
    static let portfolio: [TransactionInfo] = [
        tx(.buy, gram, "10", at: "2000", day: 0),
        tx(.buy, quarter, "2", at: "3500", day: 1),
        tx(.buy, dollar, "1000", at: "30", location: bank, day: 2),
        tx(.buy, lira, "5000", at: "1", location: bank, day: 3),
        tx(.buy, gram, "5", at: "2400", person: partner, location: bank, day: 4),
    ]

    static let portfolioPrices: [UUID: String] = [gram.id: "3000", quarter.id: "5000", dollar.id: "40"]
}

@Suite("Ortalama maliyet")
struct AverageCostTests {
    @Test("Alışlar ortalama maliyetle birikir")
    func buysAccumulateAtAverageCost() throws {
        let calculator = Fixture.calculator([
            Fixture.tx(.buy, Fixture.gram, "10", at: "2000", day: 0),
            Fixture.tx(.buy, Fixture.gram, "5", at: "2600", day: 1),
        ])
        let holding = try #require(calculator.holdings().first)
        #expect(holding.quantity == 15)
        #expect(holding.cost == 33000)
        #expect(holding.averageCost == 2200)
    }

    @Test("Kısmi satış maliyeti ortalamadan düşer")
    func partialSaleRemovesCostAtAverage() throws {
        let calculator = Fixture.calculator([
            Fixture.tx(.buy, Fixture.gram, "10", at: "2000", day: 0),
            Fixture.tx(.buy, Fixture.gram, "10", at: "3000", day: 1),
            Fixture.tx(.sell, Fixture.gram, "4", at: "4000", day: 2),
        ])
        let holding = try #require(calculator.holdings().first)
        #expect(holding.quantity == 16)
        #expect(holding.cost == 40000)
        #expect(holding.averageCost == 2500)
    }

    @Test("Tam satış bakiyeyi kapatır, sonraki alımda eski maliyet kalmaz")
    func fullSaleClosesHolding() throws {
        let sold = Fixture.calculator([
            Fixture.tx(.buy, Fixture.gram, "3", at: "100", day: 0),
            Fixture.tx(.buy, Fixture.gram, "2", at: "130", day: 1),
            Fixture.tx(.sell, Fixture.gram, "5", at: "200", day: 2),
        ])
        #expect(sold.holdings().isEmpty)
        #expect(sold.summary().cost == 0)

        let rebought = Fixture.calculator(sold.transactions + [Fixture.tx(.buy, Fixture.gram, "1", at: "150", day: 3)])
        let holding = try #require(rebought.holdings().first)
        #expect(holding.quantity == 1)
        #expect(holding.cost == 150)
    }

    @Test("Her yer ayrı bakiye ve ayrı ortalama tutar")
    func locationsKeepSeparateAverages() {
        let calculator = Fixture.calculator([
            Fixture.tx(.buy, Fixture.gram, "10", at: "2000", day: 0),
            Fixture.tx(.buy, Fixture.gram, "10", at: "3000", location: Fixture.bank, day: 1),
            Fixture.tx(.sell, Fixture.gram, "5", at: "3500", day: 2),
        ])
        let byLocation = Dictionary(uniqueKeysWithValues: calculator.holdings().map { ($0.key.locationID, $0) })
        #expect(byLocation[Fixture.home.id]?.quantity == 5)
        #expect(byLocation[Fixture.home.id]?.cost == 10000)
        #expect(byLocation[Fixture.bank.id]?.cost == 30000)
    }
}

@Suite("Satış doğrulama")
struct SaleValidationTests {
    @Test("Eldeki miktardan fazla satış reddedilir")
    func overSellIsRejected() {
        let calculator = Fixture.calculator([Fixture.tx(.buy, Fixture.gram, "5", at: "2000", day: 0)])
        #expect(calculator.validate(Fixture.tx(.sell, Fixture.gram, "6", at: "2500", day: 1)) == .insufficientQuantity(available: 5))
        #expect(calculator.validate(Fixture.tx(.sell, Fixture.gram, "5", at: "2500", day: 1)) == nil)
    }

    @Test("Başka kişi ya da yerdeki miktar satılamaz")
    func saleFromOtherBucketIsRejected() {
        let calculator = Fixture.calculator([Fixture.tx(.buy, Fixture.gram, "5", at: "2000", day: 0)])
        let fromBank = Fixture.tx(.sell, Fixture.gram, "1", at: "2500", location: Fixture.bank, day: 1)
        let byPartner = Fixture.tx(.sell, Fixture.gram, "1", at: "2500", person: Fixture.partner, day: 1)
        #expect(calculator.validate(fromBank) == .insufficientQuantity(available: 0))
        #expect(calculator.validate(byPartner) == .insufficientQuantity(available: 0))
    }

    @Test("Alıştan önceki tarihli satış reddedilir")
    func saleBeforePurchaseIsRejected() {
        let calculator = Fixture.calculator([Fixture.tx(.buy, Fixture.gram, "5", at: "2000", day: 3)])
        #expect(calculator.validate(Fixture.tx(.sell, Fixture.gram, "1", at: "2500", day: 1)) == .insufficientQuantity(available: 0))
    }

    @Test("Sonraki satışı karşılıksız bırakan düzenleme ve silme reddedilir")
    func changesThatBreakLaterSaleAreRejected() {
        let buyID = UUID()
        let calculator = Fixture.calculator([
            Fixture.tx(.buy, Fixture.gram, "10", at: "2000", day: 0, id: buyID),
            Fixture.tx(.sell, Fixture.gram, "8", at: "2500", day: 5),
        ])
        let laterSale = LedgerError.breaksLaterSale(date: Fixture.day(5))
        #expect(calculator.validate(Fixture.tx(.buy, Fixture.gram, "5", at: "2000", day: 0, id: buyID)) == laterSale)
        #expect(calculator.validateDeletion(of: buyID) == laterSale)
        #expect(calculator.validate(Fixture.tx(.sell, Fixture.gram, "5", at: "2100", day: 2)) == laterSale)
        #expect(calculator.validate(Fixture.tx(.sell, Fixture.gram, "2", at: "2100", day: 2)) == nil)
    }

    @Test("Sıfır miktar reddedilir")
    func zeroQuantityIsRejected() {
        let calculator = Fixture.calculator([])
        #expect(calculator.validate(Fixture.tx(.buy, Fixture.gram, "0", at: "2000")) == .nonPositiveQuantity)
    }
}

@Suite("Gruplama")
struct GroupingTests {
    let calculator = Fixture.calculator(Fixture.portfolio, prices: Fixture.portfolioPrices)

    @Test("Ürüne göre: miktar, değer, pay, maliyet ve kâr")
    func byAsset() throws {
        let groups = calculator.groups(by: .asset)
        #expect(groups.map(\.title) == ["Gram altın", "Dolar", "Çeyrek altın", "Türk lirası"])

        let gram = try #require(groups.first)
        #expect(gram.quantity == 15)
        #expect(gram.unit == .gram)
        #expect(gram.value == 45000)
        #expect(gram.cost == 32000)
        #expect(gram.profit == 13000)
        #expect(gram.share == d("0.45"))
        #expect(groups.sum(\.share) == 1)
    }

    @Test("Türe göre")
    func byCategory() {
        let groups = calculator.groups(by: .category)
        #expect(groups.map(\.key) == [.category(.gold), .category(.currency), .category(.lira)])
        #expect(groups.map(\.value) == [55000, 40000, 5000])
        #expect(groups.map(\.cost) == [39000, 30000, 5000])
        #expect(groups.allSatisfy { $0.quantity == nil })
    }

    @Test("Kişiye göre")
    func byPerson() {
        let groups = calculator.groups(by: .person)
        #expect(groups.map(\.key) == [.person(Fixture.me.id), .person(Fixture.partner.id)])
        #expect(groups.map(\.value) == [85000, 15000])
        #expect(groups.map(\.share) == [d("0.85"), d("0.15")])
    }

    @Test("Yere göre")
    func byLocation() {
        let groups = calculator.groups(by: .location)
        #expect(groups.map(\.key) == [.location(Fixture.bank.id), .location(Fixture.home.id)])
        #expect(groups.map(\.value) == [60000, 40000])
    }

    @Test("Özet: değer, maliyet, kâr oranı")
    func summary() throws {
        let summary = calculator.summary()
        #expect(summary.assets == 100000)
        #expect(summary.cost == 74000)
        #expect(summary.profit == 26000)
        let ratio = try #require(summary.profitRatio)
        #expect(abs((ratio - d("0.3513513513")).doubleValue) < 0.000001)
    }

    @Test("Grup detayı: ortalama maliyet ve işlemler")
    func detail() throws {
        let detail = calculator.detail(for: .asset(Fixture.gram.id))
        #expect(detail.quantity == 15)
        let averageCost = try #require(detail.averageCost)
        #expect(abs((averageCost * 15 - 32000).doubleValue) < 0.000001)
        #expect(detail.holdings.count == 2)
        #expect(detail.transactions.count == 2)
        #expect(detail.transactions.first?.personID == Fixture.partner.id)
    }
}

@Suite("Eksik fiyat")
struct MissingPriceTests {
    @Test("Fiyatı olmayan ürün toplamlara katılmaz ve ayrıca listelenir")
    func unpricedAssetsAreExcludedAndListed() {
        var prices = Fixture.portfolioPrices
        prices[Fixture.quarter.id] = nil
        let calculator = Fixture.calculator(Fixture.portfolio, prices: prices)

        let summary = calculator.summary()
        #expect(summary.assets == 90000)
        #expect(summary.cost == 67000)
        #expect(summary.missingPrices.map(\.asset.id) == [Fixture.quarter.id])
        #expect(summary.missingPrices.first?.quantity == 2)
        #expect(!calculator.groups(by: .asset).contains { $0.key == .asset(Fixture.quarter.id) })
        #expect(calculator.groups(by: .category).first?.value == 45000)
    }

    @Test("Türk lirasının fiyatı her zaman 1")
    func liraIsAlwaysPricedAtOne() {
        let calculator = Fixture.calculator([Fixture.tx(.buy, Fixture.lira, "1000", at: "1")])
        #expect(calculator.price(of: AssetInfo.liraID) == 1)
        #expect(calculator.summary().assets == 1000)
        #expect(calculator.summary().missingPrices.isEmpty)
    }
}

@Suite("Kişi filtresi")
struct PersonFilterTests {
    let debts = [
        DebtInfo(id: UUID(), personID: Fixture.me.id, kind: .loan, remaining: 20000, monthlyInstallment: 2000),
        DebtInfo(id: UUID(), personID: Fixture.partner.id, kind: .creditCard, remaining: 5000, monthlyInstallment: nil),
    ]

    @Test("Varlıklar, borçlar ve net varlık filtreye uyar")
    func filterAppliesToEverything() {
        let calculator = Fixture.calculator(Fixture.portfolio, prices: Fixture.portfolioPrices, debts: debts)

        let mine = calculator.summary(for: .person(Fixture.me.id))
        #expect(mine.assets == 85000)
        #expect(mine.debts == 20000)
        #expect(mine.netWorth == 65000)

        let partners = calculator.summary(for: .person(Fixture.partner.id))
        #expect(partners.assets == 15000)
        #expect(partners.netWorth == 10000)

        #expect(calculator.summary(for: .everyone).netWorth == 75000)

        let partnerGroups = calculator.groups(by: .asset, for: .person(Fixture.partner.id))
        #expect(partnerGroups.map(\.title) == ["Gram altın"])
        #expect(partnerGroups.first?.share == 1)
        #expect(calculator.detail(for: .asset(Fixture.gram.id), filter: .person(Fixture.partner.id)).quantity == 5)
    }

    @Test("Borç özeti türe göre ara toplam ve aylık taksit verir")
    func debtSummary() {
        let calculator = Fixture.calculator([], debts: debts)
        let all = calculator.debtSummary()
        #expect(all.total == 25000)
        #expect(all.byKind[.loan] == 20000)
        #expect(all.byKind[.creditCard] == 5000)
        #expect(all.monthlyInstallments == 2000)
        #expect(calculator.debtSummary(for: .person(Fixture.partner.id)).monthlyInstallments == 0)
    }
}

@Suite("Biçimlendirme")
struct FormatTests {
    @Test("tr_TR para ve yüzde biçimi")
    func turkishFormats() {
        #expect(Format.lira(d("1234.5")) == "₺1.234,50")
        #expect(Format.quantity(d("12.5"), unit: .gram) == "12,5 gr")
        #expect(Format.percent(d("0.125")) == "%12,5")
    }

    @Test("Virgüllü ve noktalı girişler okunur", arguments: [
        ("1.234,50", "1234.5"), ("12,5", "12.5"), ("2950", "2950"), ("0,25", "0.25"), ("1.5", "1.5"), ("₺2.950", "2950"),
        ("1.234.567", "1234567"), ("0.25", "0.25"),
    ])
    func parsesDecimals(input: String, expected: String) {
        #expect(Format.parseDecimal(input) == d(expected))
    }

    @Test("Geçersiz girişler reddedilir", arguments: ["", "12a", "1,2,3", "-5", ","])
    func rejectsInvalidInput(input: String) {
        #expect(Format.parseDecimal(input) == nil)
    }
}

@Suite("Analiz")
struct AnalyticsTests {
    @Test("Satışın gerçekleşen kârı ortalama maliyete göre hesaplanır")
    func realizedGainUsesAverageCost() throws {
        let calculator = Fixture.calculator([
            Fixture.tx(.buy, Fixture.gram, "10", at: "2000", day: 0),
            Fixture.tx(.buy, Fixture.gram, "10", at: "3000", day: 1),
            Fixture.tx(.sell, Fixture.gram, "4", at: "4000", day: 2),
        ])
        let gain = try #require(calculator.realizedGains().first)
        #expect(gain.costBasis == 10000)
        #expect(gain.proceeds == 16000)
        #expect(gain.gain == 6000)
        #expect(gain.ratio == d("0.6"))
        #expect(calculator.realizedGains(for: .person(Fixture.partner.id)).isEmpty)
    }

    @Test("Geçmiş fiyat: kayıt varsa kayıt, öncesinde işlem fiyatı, hiç kaydı yoksa yok")
    func historicalPrice() {
        let calculator = PortfolioCalculator(
            assets: [Fixture.lira, Fixture.gram, Fixture.quarter],
            prices: [PriceInfo(assetID: Fixture.gram.id, price: 3000, date: Fixture.day(10))],
            transactions: [
                Fixture.tx(.buy, Fixture.gram, "1", at: "2000", day: 0),
                Fixture.tx(.buy, Fixture.quarter, "1", at: "5000", day: 0),
            ]
        )
        #expect(calculator.price(of: Fixture.gram.id, at: Fixture.day(5)) == 2000)
        #expect(calculator.price(of: Fixture.gram.id, at: Fixture.day(12)) == 3000)
        #expect(calculator.price(of: Fixture.quarter.id, at: Fixture.day(12)) == nil)
        #expect(calculator.price(of: AssetInfo.liraID, at: Fixture.day(0)) == 1)
    }

    @Test("Değer geçmişi işlem fiyatıyla başlar, bugünkü özetle biter")
    func valueHistoryEndsAtSummary() throws {
        let calculator = PortfolioCalculator(
            people: [Fixture.me],
            locations: [Fixture.home],
            assets: [Fixture.lira, Fixture.gram],
            prices: [
                PriceInfo(assetID: Fixture.gram.id, price: 2500, date: Fixture.day(5)),
                PriceInfo(assetID: Fixture.gram.id, price: 3000, date: Fixture.day(20)),
            ],
            transactions: [
                Fixture.tx(.buy, Fixture.gram, "10", at: "2000", day: 0),
                Fixture.tx(.buy, Fixture.lira, "1000", at: "1", day: 10),
            ]
        )
        let history = calculator.valueHistory(now: Fixture.day(30))
        #expect(history.map(\.date) == [Fixture.day(0), Fixture.day(5), Fixture.day(10), Fixture.day(20), Fixture.day(30)])
        #expect(history.map(\.value) == [20000, 25000, 26000, 31000, 31000])
        #expect(history.last?.cost == 21000)
        #expect(history.last?.value == calculator.summary().assets)
        #expect(history.last?.byCategory[.gold] == 30000)

        let recent = calculator.valueHistory(since: Fixture.day(15), now: Fixture.day(30))
        #expect(recent.map(\.value) == [26000, 31000, 31000])
        #expect(calculator.valueHistory(matching: .category(.lira), now: Fixture.day(30)).first?.value == 1000)
    }

    @Test("Aylık akış boş ayları sıfırla doldurur")
    func monthlyFlows() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let calculator = Fixture.calculator([
            Fixture.tx(.buy, Fixture.gram, "2", at: "2000", day: 0),
            Fixture.tx(.buy, Fixture.gram, "1", at: "2100", day: 3),
            Fixture.tx(.sell, Fixture.gram, "1", at: "2500", day: 70),
        ])
        let flows = calculator.monthlyFlows(last: 3, now: Fixture.day(75), calendar: calendar)
        #expect(flows.count == 3)
        #expect(flows.map(\.bought) == [6100, 0, 0])
        #expect(flows.map(\.sold) == [0, 0, 2500])
        #expect(flows.first?.month == Fixture.start)
    }
}

@MainActor
@Suite("Yedekten ekleme")
struct BackupMergeTests {
    @Test("Kişi, yer ve ürünler adla eşleşir; aynı yedek iki kez eklenince çoğalmaz")
    func mergeMatchesByNameAndIsIdempotent() throws {
        let container = try ModelContainer(
            for: Person.self, Location.self, Asset.self, PricePoint.self, TransactionRecord.self, Debt.self,
            DebtPayment.self, Goal.self, JournalEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        Store.seedIfNeeded(in: context)
        let me = try #require(try context.fetch(FetchDescriptor<Person>()).first)
        let gram = try #require(try context.fetch(FetchDescriptor<Asset>()).first { $0.name == "Gram altın" })

        let now = Date.now
        let personID = UUID(), fatherID = UUID(), homeID = UUID(), bankID = UUID(), gramID = UUID(), fundID = UUID()
        let backup = BackupFile(
            exportedAt: now,
            people: [.init(id: personID, name: "ben ", createdAt: now), .init(id: fatherID, name: "Ayşe", createdAt: now)],
            locations: [
                .init(id: homeID, name: "Fiziki (elde)", kind: .physical, createdAt: now),
                .init(id: bankID, name: "Örnek Banka", kind: .bank, createdAt: now),
            ],
            assets: [
                .init(id: gramID, name: "Gram altın", unit: .gram, category: .gold, sortOrder: 1, createdAt: now),
                .init(id: fundID, name: "Örnek Fon", unit: .lira, category: .fund, sortOrder: 1, createdAt: now),
            ],
            prices: [],
            transactions: [
                .init(id: UUID(), kind: .buy, personID: personID, assetID: gramID, locationID: homeID,
                      quantity: "17", unitPrice: "2450", date: now, note: "", createdAt: now),
                .init(id: UUID(), kind: .buy, personID: fatherID, assetID: fundID, locationID: bankID,
                      quantity: "10000", unitPrice: "1", date: now, note: "", createdAt: now),
            ],
            debts: [.init(id: UUID(), personID: personID, institution: "", kind: .creditCard, title: "Kredi kartı",
                          remaining: "2500", monthlyInstallment: nil, dueDate: nil, note: "", updatedAt: now)]
        )

        #expect(try BackupService.merge(backup, into: context) == .init(added: 2, updated: 0))
        #expect(try BackupService.merge(backup, into: context) == .init(added: 0, updated: 0))

        var moved = backup
        moved.transactions[0].locationID = bankID
        moved.transactions[0].note = "Yer düzeltildi"
        #expect(try BackupService.merge(moved, into: context) == .init(added: 0, updated: 1))

        let people = try context.fetch(FetchDescriptor<Person>())
        #expect(people.map(\.name).sorted() == ["Ayşe", "Ben"])
        let records = try context.fetch(FetchDescriptor<TransactionRecord>())
        #expect(records.count == 2)
        let mine = try #require(records.first { $0.quantity == 17 })
        #expect(mine.personID == me.id)
        #expect(mine.assetID == gram.id)
        #expect(mine.note == "Yer düzeltildi")
        #expect(try context.fetch(FetchDescriptor<Location>()).first { $0.id == mine.locationID }?.name == "Örnek Banka")
        #expect(try context.fetch(FetchDescriptor<Debt>()).first?.personID == me.id)
        #expect(try context.fetch(FetchDescriptor<Asset>()).contains { $0.name == "Örnek Fon" && $0.category == .fund })
    }
}

@Suite("Yer dökümü")
struct LocationBreakdownTests {
    @Test("Bakiyeler yere göre toplanır ve değere göre sıralanır")
    func breakdownByLocation() {
        let calculator = Fixture.calculator(Fixture.portfolio, prices: Fixture.portfolioPrices)
        let breakdown = calculator.locationBreakdown()
        #expect(breakdown.map(\.locationID) == [Fixture.bank.id, Fixture.home.id])
        #expect(breakdown.map(\.value) == [60000, 40000])
        #expect(breakdown.first?.holdings.count == 3)
        #expect(breakdown.first?.location?.name == "Ziraat")

        let mine = calculator.locationBreakdown(for: .person(Fixture.me.id))
        #expect(mine.map(\.value) == [45000, 40000])
    }
}

@Suite("İnternetten fiyat")
struct QuoteTests {
    private let truncgil = """
    {"Update_Date":"2026-11-03 10:00:06","USD":{"Alış":"49,9451","Tür":"Döviz","Satış":"50,0491","Değişim":"%0,05"},\
    "gram-altin":{"Alış":"6.287,79","Tür":"Altın","Satış":"6.288,77","Değişim":"%0,10"},\
    "ceyrek-altin":{"Alış":"10.134,56","Tür":"Altın","Satış":"10.366,53","Değişim":"%0,10"},\
    "22-ayar-bilezik":{"Alış":"5.776,70","Tür":"Altın","Satış":"5.782,43","Değişim":"%0,10"},\
    "gumus":{"Alış":"78,81","Tür":"Altın","Satış":"78,91","Değişim":"%-1,0"}}
    """

    @Test("Truncgil akışı alış fiyatlarıyla okunur")
    func parsesTruncgil() {
        let quotes = QuoteParser.truncgil(Data(truncgil.utf8))
        #expect(quotes[.gramGold] == d("6287.79"))
        #expect(quotes[.quarterGold] == d("10134.56"))
        #expect(quotes[.bracelet22] == d("5776.7"))
        #expect(quotes[.silver] == d("78.81"))
        #expect(quotes[.usd] == d("49.9451"))
        #expect(quotes[.halfGold] == nil)
    }

    @Test("Yarıda kesilen akıştan da değerler ayıklanır")
    func parsesTruncatedTruncgil() {
        let truncated = String(truncgil.dropLast(40))
        let quotes = QuoteParser.truncgil(Data(truncated.utf8))
        #expect(quotes[.gramGold] == d("6287.79"))
        #expect(quotes[.bracelet22] == d("5776.7"))
    }

    @Test("TCMB bülteninden dolar ve euro alış kuru okunur")
    func parsesTCMB() {
        let xml = """
        <Tarih_Date Tarih="02.11.2026"><Currency CrossOrder="0" Kod="USD" CurrencyCode="USD"><Unit>1</Unit>
        <ForexBuying>49.8827</ForexBuying><ForexSelling>49.9726</ForexSelling></Currency>
        <Currency CrossOrder="9" Kod="EUR" CurrencyCode="EUR"><Unit>1</Unit>
        <ForexBuying>55.8953</ForexBuying><ForexSelling>55.9960</ForexSelling></Currency></Tarih_Date>
        """
        let quotes = QuoteParser.tcmb(Data(xml.utf8))
        #expect(quotes[.usd] == d("49.8827"))
        #expect(quotes[.eur] == d("55.8953"))
    }

    @Test("Varsayılan ürünler fiyat anahtarlarıyla eşleşir", arguments: [
        ("Gram altın", AssetUnit.gram, AssetCategory.gold, QuoteKey.gramGold),
        ("Çeyrek altın", .piece, .gold, .quarterGold),
        ("Yarım altın", .piece, .gold, .halfGold),
        ("Tam altın", .piece, .gold, .fullGold),
        ("Cumhuriyet altını", .piece, .gold, .republicGold),
        ("22 ayar bilezik", .gram, .gold, .bracelet22),
        ("Gram gümüş", .gram, .silver, .silver),
        ("Dolar", .usd, .currency, .usd),
        ("Euro", .eur, .currency, .eur),
    ])
    func mapsDefaultAssets(name: String, unit: AssetUnit, category: AssetCategory, key: QuoteKey) {
        #expect(QuoteKey.key(for: AssetInfo(id: UUID(), name: name, unit: unit, category: category)) == key)
    }

    @Test("Fon ve TL elle kalır")
    func fundsAreManual() {
        #expect(QuoteKey.key(for: AssetInfo(id: UUID(), name: "Örnek Fon", unit: .lira, category: .fund)) == nil)
        #expect(QuoteKey.key(for: Fixture.lira) == nil)
    }
}

@Suite("Aktarım")
struct TransferTests {
    private func transfer(_ quantity: String, at price: String, from: LocationInfo, to: LocationInfo, day: Int, id: UUID = UUID()) -> [TransactionInfo] {
        let date = Fixture.day(day)
        return [
            TransactionInfo(id: UUID(), kind: .transferOut, personID: Fixture.me.id, assetID: Fixture.gram.id, locationID: from.id,
                            quantity: d(quantity), unitPrice: d(price), date: date, createdAt: date, transferID: id),
            TransactionInfo(id: UUID(), kind: .transferIn, personID: Fixture.me.id, assetID: Fixture.gram.id, locationID: to.id,
                            quantity: d(quantity), unitPrice: d(price), date: date, createdAt: date.addingTimeInterval(0.001), transferID: id),
        ]
    }

    @Test("Aktarım ortalama maliyeti taşır, kâr/zarar ve alım-satım akışı doğurmaz")
    func transferCarriesCost() {
        let calculator = Fixture.calculator(
            [Fixture.tx(.buy, Fixture.gram, "10", at: "2000", day: 0), Fixture.tx(.buy, Fixture.gram, "10", at: "3000", day: 1)]
                + transfer("4", at: "0", from: Fixture.home, to: Fixture.bank, day: 2),
            prices: [Fixture.gram.id: "3000"]
        )
        let byLocation = Dictionary(uniqueKeysWithValues: calculator.holdings().map { ($0.key.locationID, $0) })
        #expect(byLocation[Fixture.home.id]?.quantity == 16)
        #expect(byLocation[Fixture.home.id]?.cost == 40000)
        #expect(byLocation[Fixture.bank.id]?.quantity == 4)
        #expect(byLocation[Fixture.bank.id]?.cost == 10000)
        #expect(calculator.realizedGains().isEmpty)
        #expect(calculator.summary().cost == 50000)
        #expect(calculator.monthlyFlows(last: 1, now: Fixture.day(2)).first?.sold == 0)
    }

    @Test("Eldekinden fazla aktarım ve sonraki aktarımı bozan silme reddedilir")
    func transferValidation() {
        let buyID = UUID()
        let base = [Fixture.tx(.buy, Fixture.gram, "5", at: "2000", day: 0, id: buyID)]
        let calculator = Fixture.calculator(base)
        #expect(calculator.validate(transfer("6", at: "2000", from: Fixture.home, to: Fixture.bank, day: 1)) == .insufficientQuantity(available: 5))
        #expect(calculator.validate(transfer("5", at: "2000", from: Fixture.home, to: Fixture.bank, day: 1)) == nil)

        let moved = Fixture.calculator(base + transfer("5", at: "2000", from: Fixture.home, to: Fixture.bank, day: 1))
        #expect(moved.validateDeletion(of: buyID) == .breaksLaterSale(date: Fixture.day(1)))
        #expect(moved.averageCost(before: Fixture.tx(.sell, Fixture.gram, "1", at: "0", location: Fixture.bank, day: 2)) == 2000)
    }
}

@Suite("Dolar/altın karşılığı ve piyasa değişimi")
struct DenominationTests {
    @Test("Değer geçmişi dolar cinsinden ifade edilir")
    func convertsToDollars() {
        let calculator = PortfolioCalculator(
            assets: [Fixture.lira, Fixture.dollar],
            prices: [
                PriceInfo(assetID: Fixture.dollar.id, price: 40, date: Fixture.day(0)),
                PriceInfo(assetID: Fixture.dollar.id, price: 50, date: Fixture.day(10)),
            ],
            transactions: [Fixture.tx(.buy, Fixture.lira, "100000", at: "1", day: 0)]
        )
        // Elde dolar olmadığı için noktalar başlangıç ve bugündür; her nokta o günkü kurla çevrilir.
        let converted = calculator.converted(calculator.valueHistory(now: Fixture.day(20)), into: Fixture.dollar.id)
        #expect(converted.map(\.value) == [2500, 2000])
    }

    @Test("Piyasa değişimi kayıtlı fiyatlardan hesaplanır, öncesinde kayıt yoksa yoktur")
    func marketChange() {
        let calculator = PortfolioCalculator(
            assets: [Fixture.gram],
            prices: [
                PriceInfo(assetID: Fixture.gram.id, price: 3000, date: Fixture.day(0)),
                PriceInfo(assetID: Fixture.gram.id, price: 3300, date: Fixture.day(30)),
            ]
        )
        #expect(calculator.marketChange(of: Fixture.gram.id, since: Fixture.day(5)) == d("0.1"))
        #expect(calculator.marketChange(of: Fixture.gram.id, since: Fixture.start.addingTimeInterval(-86_400)) == nil)
    }
}

@Suite("Hedefler ve borç planı")
struct GoalAndDebtTests {
    @Test("Miktar hedefi ilerlemesi ve tahmini tarih")
    func quantityGoal() throws {
        let calculator = Fixture.calculator([
            Fixture.tx(.buy, Fixture.gram, "10", at: "2000", day: 0),
            Fixture.tx(.buy, Fixture.gram, "10", at: "2000", day: 100),
        ])
        let goal = GoalInfo(id: UUID(), title: "100 gr", kind: .quantity, target: 100, assetID: Fixture.gram.id, personID: nil)
        let progress = calculator.progress(of: goal, now: Fixture.day(120), lookbackDays: 90)
        #expect(progress.current == 20)
        #expect(progress.ratio == d("0.2"))
        #expect(!progress.isReached)
        let estimate = try #require(progress.estimatedDate)
        // 90 günde 10 gr → kalan 80 gr için 720 gün.
        #expect(abs(estimate.timeIntervalSince(Fixture.day(120)) - 720 * 86_400) < 1)
    }

    @Test("Net varlık hedefi borçları düşer")
    func netWorthGoal() {
        let debts = [DebtInfo(id: UUID(), personID: Fixture.me.id, kind: .loan, remaining: 5000, monthlyInstallment: 1000)]
        let calculator = Fixture.calculator([Fixture.tx(.buy, Fixture.lira, "20000", at: "1")], debts: debts)
        let goal = GoalInfo(id: UUID(), title: "Net", kind: .netWorth, target: 30000, assetID: nil, personID: Fixture.me.id)
        let progress = calculator.progress(of: goal, now: Fixture.day(30))
        #expect(progress.current == 15000)
        #expect(progress.ratio == d("0.5"))
    }

    @Test("Borcun aylık taksitle biteceği ay")
    func debtPayoff() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let plan = try #require(DebtPlan.payoff(remaining: 10500, monthly: 1000, from: Fixture.start, calendar: calendar))
        #expect(plan.months == 11)
        #expect(calendar.component(.month, from: plan.date) == 12)
        #expect(DebtPlan.payoff(remaining: 1000, monthly: nil) == nil)
    }
}

@Suite("Dışa aktarma ve gizleme")
struct ExportAndPrivacyTests {
    @Test("CSV alanları noktalı virgül ve tırnaklara göre kaçışlanır")
    func csvEscaping() {
        let text = CSVExporter.csv([["Tarih", "Not"], ["01.01.2026", "Kuyumcu; 2 adet \"yeni\""]])
        #expect(text.hasPrefix("\u{FEFF}Tarih;Not\r\n"))
        #expect(text.contains("01.01.2026;\"Kuyumcu; 2 adet \"\"yeni\"\"\"\r\n"))
    }

    @Test("Tutarları gizle para ve miktarı maskeler, yüzdeyi bırakır")
    func masksAmounts() {
        Format.hidesAmounts = true
        defer { Format.hidesAmounts = false }
        #expect(Format.lira(1234) == "₺••••")
        #expect(Format.quantity(12, unit: .gram) == "•••• gr")
        #expect(Format.plainLira(d("1234.5")) == "₺1.234,50")
        #expect(Format.percent(d("0.5")) == "%50")
    }
}

@Suite("Kurum tanıma")
struct InstitutionTests {
    @Test("Yer ve borç adları doğru kuruma eşlenir", arguments: [
        ("T.C. Ziraat Bankası", "ziraat"),
        ("Ziraat Katılım", "ziraatkatilim"),
        ("Garanti BBVA", "garanti"),
        ("Türkiye Halk Bankası", "halkbank"),
        ("VakıfBank", "vakifbank"),
        ("Vakıf Katılım", "vakifkatilim"),
        ("ING Bank", "ing"),
        ("Türkiye İş Bankası", "isbank"),
        ("İş Yatırım Menkul Değerler", "isyatirim"),
        ("Türkiye Finans", "turkiyefinans"),
        ("YAPI KREDİ", "yapikredi"),
        ("QNB Finansbank", "qnb"),
        ("CEPTETEB", "teb"),
        ("A&T Bank", "atbank"),
        ("Gedik Yatırım", "gedik"),
        ("ALBARAKATÜRK KATILIM BANKASI A.Ş.", "albaraka"),
        ("Industrial and Commercial Bank of China", "icbc"),
        ("Bank of China Limited", "bankofchina"),
    ])
    func matches(name: String, id: String) {
        #expect(Institution.match(name)?.id == id)
    }

    @Test("Kurum olmayan adlar eşlenmez", arguments: ["Fiziki (elde)", "Kasa", "Ev", "İngiltere hesabı", ""])
    func noMatch(name: String) {
        #expect(Institution.match(name) == nil)
    }

    @Test("Kimlikler ve takma adlar benzersiz")
    func uniqueness() {
        let ids = Institution.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        let aliases = Institution.all.flatMap { $0.aliases.map { Institution.normalizedTokens($0).joined(separator: " ") } }
        #expect(Set(aliases).count == aliases.count)
    }
}

@Suite("Günlük değişim ve yaklaşan ödemeler")
struct DailyAndUpcomingTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    @Test("Bugünkü değişim dünkü son fiyata göre hesaplanır; TL yalnızca oranı etkiler")
    func dailyChangeComparesWithYesterday() {
        let now = date("2026-11-03 15:00")
        let calculator = PortfolioCalculator(
            people: [Fixture.me], locations: [Fixture.home], assets: [Fixture.lira, Fixture.gram],
            prices: [
                PriceInfo(assetID: Fixture.gram.id, price: 2000, date: date("2026-11-02 21:00")),
                PriceInfo(assetID: Fixture.gram.id, price: 2100, date: date("2026-11-03 09:00")),
            ],
            transactions: [
                TransactionInfo(id: UUID(), kind: .buy, personID: Fixture.me.id, assetID: Fixture.gram.id, locationID: Fixture.home.id,
                                quantity: 10, unitPrice: 1900, date: date("2026-10-01 00:00"), createdAt: date("2026-10-01 00:00")),
                TransactionInfo(id: UUID(), kind: .buy, personID: Fixture.me.id, assetID: AssetInfo.liraID, locationID: Fixture.home.id,
                                quantity: 1000, unitPrice: 1, date: date("2026-10-01 00:00"), createdAt: date("2026-10-01 00:00")),
            ]
        )
        let daily = calculator.dailyChange(now: now, calendar: calendar)
        #expect(daily?.change == 1000)
        #expect(daily?.ratio == Decimal(1000) / Decimal(21000))
        #expect(calculator.dailyChange(now: date("2026-11-04 08:00"), calendar: calendar) == nil)
    }

    @Test("Kredi kartında son ödeme tarihi; bir aydan eski gecikme gösterilmez")
    func creditCardUsesDueDate() {
        let now = date("2026-11-03 12:00")
        let soon = DebtPlan.nextPayment(kind: .creditCard, remaining: 4210, monthly: nil, dueDate: date("2026-11-05 00:00"),
                                        paymentDay: nil, lastPayment: nil, now: now, calendar: calendar)
        #expect(soon == UpcomingPayment(date: date("2026-11-05 00:00"), amount: 4210))
        let stale = DebtPlan.nextPayment(kind: .creditCard, remaining: 4210, monthly: nil, dueDate: date("2026-09-20 00:00"),
                                         paymentDay: nil, lastPayment: nil, now: now, calendar: calendar)
        #expect(stale == nil)
        let paidOff = DebtPlan.nextPayment(kind: .creditCard, remaining: 0, monthly: nil, dueDate: date("2026-11-05 00:00"),
                                           paymentDay: nil, lastPayment: nil, now: now, calendar: calendar)
        #expect(paidOff == nil)
    }

    @Test("Taksit günü: bu ay geçtiyse ya da erken ödendiyse sonraki ay; kısa aylarda ayın son günü")
    func installmentDay() {
        func next(_ now: String, day: Int, paid: String? = nil) -> Date? {
            DebtPlan.nextPayment(kind: .loan, remaining: 85_400, monthly: 6250, dueDate: nil, paymentDay: day,
                                 lastPayment: paid.map(date), now: date(now), calendar: calendar)?.date
        }
        #expect(next("2026-11-03 10:00", day: 5) == date("2026-11-05 00:00"))
        #expect(next("2026-11-10 10:00", day: 5) == date("2026-12-05 00:00"))
        #expect(next("2026-11-03 10:00", day: 5, paid: "2026-11-02 10:00") == date("2026-12-05 00:00"))
        #expect(next("2026-11-03 10:00", day: 5, paid: "2026-10-05 10:00") == date("2026-11-05 00:00"))
        #expect(next("2027-02-10 10:00", day: 31) == date("2027-02-28 00:00"))
    }
}

@Suite("Yazarken binlik ayraç")
struct GroupedInputTests {
    @Test("Ayraç eklenir, silmede baştan hesaplanır, nokta ondalık sayılır", arguments: [
        ("1234", "123", "1.234"),
        ("1.2345", "1.234", "12.345"),
        ("1.23", "1.234", "123"),
        ("12.", "12", "12,"),
        ("1.234,5", "1.234,", "1.234,5"),
        ("1234567,25", "", "1.234.567,25"),
        ("12.5", "", "12,5"),
        ("1.234", "", "1.234"),
        ("", "1", ""),
    ])
    func groups(text: String, previous: String, expected: String) {
        #expect(Format.groupedInput(text, previous: previous) == expected)
        #expect(Format.parseDecimal(expected) == Format.parseDecimal(Format.groupedInput(expected, previous: expected)))
    }
}

@MainActor
@Suite("Silinenler ve geri yükleme")
struct DeletionHistoryTests {
    private func makeContainer() throws -> ModelContainer {
        let container = try ModelContainer(
            for: Person.self, Location.self, Asset.self, PricePoint.self, TransactionRecord.self, Debt.self,
            DebtPayment.self, Goal.self, JournalEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        Store.seedIfNeeded(in: container.mainContext)
        return container
    }

    @Test("Silme kayıtları 500 sınırında budanmaz")
    func deletionsAreNeverPruned() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let goal = Goal(title: "Örnek hedef", kind: .netWorth, target: 1000, assetID: nil, personID: nil)
        context.insert(goal)
        Journal.recordDeletion(.goal, summary: Journal.describe(goal), snapshot: .init(goals: [Journal.entry(goal)]), in: context)
        context.delete(goal)
        try context.save()
        for _ in 0..<510 {
            Journal.recordTransactions(.added, summary: "Ekleme", before: [TransactionRecord](), after: [], in: context)
            try context.save()
        }
        let entries = try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(entries.count == 501)
        #expect(entries.contains { $0.action == .deleted && $0.entity == .goal })
    }

    @Test("Silinen ürün fiyat kayıtlarıyla geri getirilir")
    func deletedAssetComesBackWithPrices() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let fund = Asset(name: "Örnek Fon", unit: .lira, category: .fund, sortOrder: 99)
        context.insert(fund)
        context.insert(PricePoint(assetID: fund.id, price: 10, date: .now.addingTimeInterval(-86_400)))
        context.insert(PricePoint(assetID: fund.id, price: 11, date: .now))
        try context.save()

        let prices = Ledger.fetch(from: context).prices.filter { $0.assetID == fund.id }
        let entry = Journal.recordDeletion(.asset, summary: Journal.describe(fund, priceCount: prices.count),
                                           snapshot: .init(assets: [Journal.entry(fund)], prices: prices.map(Journal.entry)), in: context)
        prices.forEach(context.delete)
        context.delete(fund)
        try context.save()
        #expect(!Ledger.fetch(from: context).assets.contains { $0.id == fund.id })

        try Journal.undo(entry, ledger: Ledger.fetch(from: context), context: context)
        let restored = Ledger.fetch(from: context)
        #expect(restored.assets.contains { $0.id == fund.id && $0.name == "Örnek Fon" })
        #expect(restored.prices.filter { $0.assetID == fund.id }.count == 2)
        #expect(entry.isUndone)
    }

    @Test("Yedekten geri yükleme geri alınır; geri alma da geçmişe yazılır")
    func restoreCanBeUndone() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(Person(name: "Ayşe"))
        try context.save()

        let backup = BackupFile(
            exportedAt: .now, people: [.init(id: UUID(), name: "Yeni", createdAt: .now)],
            locations: [], assets: [], prices: [], transactions: [], debts: []
        )
        let entry = Journal.recordRestore(replacing: BackupService.makeBackup(from: Ledger.fetch(from: context)), summary: "Geri yükleme", in: context)
        try BackupService.restore(backup, into: context)
        try context.save()
        #expect(Ledger.fetch(from: context).people.map(\.name) == ["Yeni"])

        try Journal.undo(entry, ledger: Ledger.fetch(from: context), context: context)
        let names = Set(Ledger.fetch(from: context).people.map(\.name))
        #expect(names == ["Ben", "Ayşe"])
        let restores = try context.fetch(FetchDescriptor<JournalEntry>()).filter { $0.action == .restored }
        #expect(restores.count == 2)
    }
}

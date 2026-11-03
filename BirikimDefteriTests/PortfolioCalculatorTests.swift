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

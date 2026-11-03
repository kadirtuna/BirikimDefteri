import Foundation

enum PersonFilter: Hashable, Sendable {
    case everyone
    case person(UUID)

    func includes(_ personID: UUID) -> Bool {
        switch self {
        case .everyone: true
        case .person(let id): id == personID
        }
    }
}

enum Grouping: String, CaseIterable, Identifiable, Sendable {
    case asset, category, person, location

    var id: Self { self }

    var title: String {
        switch self {
        case .asset: "Ürün"
        case .category: "Tür"
        case .person: "Kişi"
        case .location: "Yer"
        }
    }
}

enum GroupKey: Hashable, Sendable {
    case asset(UUID)
    case category(AssetCategory)
    case person(UUID)
    case location(UUID)
}

/// Bakiyelerin tutulduğu kırılım: kişi × ürün × yer.
struct HoldingKey: Hashable, Sendable {
    let personID: UUID
    let assetID: UUID
    let locationID: UUID
}

struct Holding: Identifiable, Hashable, Sendable {
    let key: HoldingKey
    let quantity: Decimal
    let cost: Decimal
    /// 1 birimin güncel TL fiyatı. Fiyat girilmemişse nil.
    let price: Decimal?

    var id: HoldingKey { key }
    var value: Decimal? { price.map { quantity * $0 } }
    var averageCost: Decimal { quantity > 0 ? cost / quantity : 0 }
}

struct PortfolioGroup: Identifiable, Hashable, Sendable {
    let key: GroupKey
    let title: String
    /// Yalnızca ürün gruplamasında dolu.
    let quantity: Decimal?
    let unit: AssetUnit?
    let value: Decimal
    let cost: Decimal
    /// Toplam değer içindeki pay (0...1).
    let share: Decimal

    var id: GroupKey { key }
    var profit: Decimal { value - cost }
    var profitRatio: Decimal? { cost > 0 ? profit / cost : nil }
}

struct MissingPrice: Identifiable, Hashable, Sendable {
    let asset: AssetInfo
    let quantity: Decimal

    var id: UUID { asset.id }
}

struct PortfolioSummary: Hashable, Sendable {
    /// Fiyatı bilinen varlıkların TL değeri.
    let assets: Decimal
    let debts: Decimal
    /// Fiyatı bilinen varlıkların maliyeti.
    let cost: Decimal
    let missingPrices: [MissingPrice]

    var netWorth: Decimal { assets - debts }
    var profit: Decimal { assets - cost }
    var profitRatio: Decimal? { cost > 0 ? profit / cost : nil }
}

struct DebtSummary: Hashable, Sendable {
    let total: Decimal
    let byKind: [DebtKind: Decimal]
    let monthlyInstallments: Decimal
}

struct GroupDetail: Hashable, Sendable {
    let key: GroupKey
    let title: String
    /// Gruptaki tüm bakiyeler (fiyatlı ya da fiyatsız), değere göre sıralı.
    let holdings: [Holding]
    /// Gruptaki tüm alım ve satımlar, en yenisi önce.
    let transactions: [TransactionInfo]

    private var pricedHoldings: [Holding] { holdings.filter { $0.price != nil } }

    var quantity: Decimal { holdings.sum(\.quantity) }
    var totalCost: Decimal { holdings.sum(\.cost) }
    var averageCost: Decimal? { quantity > 0 ? totalCost / quantity : nil }
    var hasPrice: Bool { !pricedHoldings.isEmpty }
    var hasMissingPrice: Bool { holdings.contains { $0.price == nil } }
    var value: Decimal { pricedHoldings.sum { $0.value ?? 0 } }
    var pricedCost: Decimal { pricedHoldings.sum(\.cost) }
    var profit: Decimal { value - pricedCost }
    var profitRatio: Decimal? { pricedCost > 0 ? profit / pricedCost : nil }
}

enum LedgerError: Error, Hashable, Sendable {
    case nonPositiveQuantity
    case negativePrice
    /// Önerilen satış, o tarihte o kişi ve yerdeki miktarı aşıyor.
    case insufficientQuantity(available: Decimal)
    /// Değişiklik, daha sonraki bir satışı karşılıksız bırakıyor.
    case breaksLaterSale(date: Date)

    func message(unit: AssetUnit?) -> String {
        switch self {
        case .nonPositiveQuantity:
            return "Miktar sıfırdan büyük olmalı."
        case .negativePrice:
            return "Birim fiyat negatif olamaz."
        case .insufficientQuantity(let available):
            guard available > 0 else {
                return "Bu kişi ve yerde o tarihte satılacak miktar yok."
            }
            let amount = unit.map { Format.quantity(available, unit: $0) } ?? Format.number(available)
            return "Satış eldeki miktarı aşıyor. Bu kişi ve yerde en fazla \(amount) satılabilir."
        case .breaksLaterSale(let date):
            return "Bu değişiklik \(Format.date(date)) tarihli satışı karşılıksız bırakıyor. Önce o satışı düzenleyin."
        }
    }
}

/// Bakiyeleri her seferinde işlemlerden hesaplayan saf hesaplayıcı.
/// Ortalama maliyet yöntemi: alışlar maliyete eklenir, satışlar ortalama maliyetten düşer.
struct PortfolioCalculator: Sendable {
    let people: [UUID: PersonInfo]
    let locations: [UUID: LocationInfo]
    let assets: [UUID: AssetInfo]
    let latestPrices: [UUID: PriceInfo]
    /// Her ürünün fiyat kayıtları, tarihe göre artan sırada.
    let priceHistory: [UUID: [PriceInfo]]
    /// Kronolojik sırada (tarih, sonra oluşturulma zamanı).
    let transactions: [TransactionInfo]
    let debts: [DebtInfo]
    private let allHoldings: [Holding]
    private let allRealizedGains: [RealizedGain]
    /// Geçmiş değerlemede fiyat kaydı öncesine düşülecek işlem fiyatları, ürün başına kronolojik.
    private let tradePrices: [UUID: [PriceInfo]]

    init(
        people: [PersonInfo] = [],
        locations: [LocationInfo] = [],
        assets: [AssetInfo] = [],
        prices: [PriceInfo] = [],
        transactions: [TransactionInfo] = [],
        debts: [DebtInfo] = []
    ) {
        let assetsByID = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let history = Dictionary(grouping: prices, by: \.assetID).mapValues { $0.sorted { $0.date < $1.date } }
        let latest = history.compactMapValues(\.last)
        let sorted = transactions.sorted(by: Self.isChronological)

        var state: [HoldingKey: Position] = [:]
        var transfers: [UUID: Decimal] = [:]
        var realized: [RealizedGain] = []
        for transaction in sorted {
            if let gain = Self.apply(transaction, to: &state, transfers: &transfers) { realized.append(gain) }
        }

        self.people = Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.locations = Dictionary(locations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.assets = assetsByID
        self.latestPrices = latest
        self.priceHistory = history
        self.transactions = sorted
        self.debts = debts
        self.allRealizedGains = realized
        self.tradePrices = Dictionary(grouping: sorted, by: \.assetID)
            .mapValues { $0.map { PriceInfo(assetID: $0.assetID, price: $0.unitPrice, date: $0.date) } }
        self.allHoldings = state.compactMap { key, position in
            position.quantity > 0
                ? Holding(key: key, quantity: position.quantity, cost: position.cost,
                          price: Self.price(of: assetsByID[key.assetID], latest: latest))
                : nil
        }
    }

    // MARK: Fiyat

    func price(of assetID: UUID) -> Decimal? {
        Self.price(of: assets[assetID], latest: latestPrices)
    }

    private static func price(of asset: AssetInfo?, latest: [UUID: PriceInfo]) -> Decimal? {
        guard let asset else { return nil }
        if asset.unit == .lira { return 1 }
        return latest[asset.id]?.price
    }

    // MARK: Bakiyeler

    func holdings(for filter: PersonFilter = .everyone) -> [Holding] {
        allHoldings.filter { filter.includes($0.key.personID) }
    }

    func summary(for filter: PersonFilter = .everyone) -> PortfolioSummary {
        let holdings = holdings(for: filter)
        let priced = holdings.filter { $0.price != nil }
        return PortfolioSummary(
            assets: priced.sum { $0.value ?? 0 },
            debts: debtSummary(for: filter).total,
            cost: priced.sum(\.cost),
            missingPrices: missingPrices(in: holdings)
        )
    }

    func missingPrices(for filter: PersonFilter = .everyone) -> [MissingPrice] {
        missingPrices(in: holdings(for: filter))
    }

    private func missingPrices(in holdings: [Holding]) -> [MissingPrice] {
        let unpriced = Dictionary(grouping: holdings.filter { $0.price == nil }, by: \.key.assetID)
        return unpriced.compactMap { assetID, items in
            assets[assetID].map { MissingPrice(asset: $0, quantity: items.sum(\.quantity)) }
        }
        .sorted { $0.asset.sortOrder < $1.asset.sortOrder }
    }

    // MARK: Gruplama

    func groups(by grouping: Grouping, for filter: PersonFilter = .everyone) -> [PortfolioGroup] {
        let priced = holdings(for: filter).filter { $0.price != nil }
        let total = priced.sum { $0.value ?? 0 }
        let buckets = Dictionary(grouping: priced) { groupKey(for: $0.key, grouping: grouping) }

        return buckets.map { key, items in
            let value = items.sum { $0.value ?? 0 }
            var unit: AssetUnit?
            if case .asset(let assetID) = key { unit = assets[assetID]?.unit }
            return PortfolioGroup(
                key: key,
                title: title(for: key),
                quantity: grouping == .asset ? items.sum(\.quantity) : nil,
                unit: unit,
                value: value,
                cost: items.sum(\.cost),
                share: total > 0 ? value / total : 0
            )
        }
        .sorted { lhs, rhs in
            lhs.value != rhs.value
                ? lhs.value > rhs.value
                : lhs.title.localizedCompare(rhs.title) == .orderedAscending
        }
    }

    func detail(for group: GroupKey, filter: PersonFilter = .everyone) -> GroupDetail {
        let holdings = holdings(for: filter)
            .filter { contains(group, $0.key) }
            .sorted { ($0.value ?? -1) > ($1.value ?? -1) }
        let transactions = transactions
            .filter { filter.includes($0.personID) && contains(group, $0.key) }
            .reversed()
        return GroupDetail(key: group, title: title(for: group), holdings: holdings, transactions: Array(transactions))
    }

    func groupKey(for key: HoldingKey, grouping: Grouping) -> GroupKey {
        switch grouping {
        case .asset: .asset(key.assetID)
        case .category: .category(assets[key.assetID]?.category ?? .other)
        case .person: .person(key.personID)
        case .location: .location(key.locationID)
        }
    }

    func contains(_ group: GroupKey, _ key: HoldingKey) -> Bool {
        switch group {
        case .asset(let id): key.assetID == id
        case .category(let category): (assets[key.assetID]?.category ?? .other) == category
        case .person(let id): key.personID == id
        case .location(let id): key.locationID == id
        }
    }

    func title(for group: GroupKey) -> String {
        switch group {
        case .asset(let id): assets[id]?.name ?? "Bilinmeyen ürün"
        case .category(let category): category.title
        case .person(let id): people[id]?.name ?? "Bilinmeyen kişi"
        case .location(let id): locations[id]?.name ?? "Bilinmeyen yer"
        }
    }

    // MARK: Borçlar

    func debtSummary(for filter: PersonFilter = .everyone) -> DebtSummary {
        let debts = debts.filter { filter.includes($0.personID) }
        return DebtSummary(
            total: debts.sum(\.remaining),
            byKind: Dictionary(grouping: debts, by: \.kind).mapValues { $0.sum(\.remaining) },
            monthlyInstallments: debts.sum { $0.monthlyInstallment ?? 0 }
        )
    }

    // MARK: Doğrulama

    /// Önerilen işlemi (yeni ya da aynı kimlikli mevcut işlemin yerine) kontrol eder.
    func validate(_ proposed: TransactionInfo) -> LedgerError? {
        validate([proposed])
    }

    /// Birlikte kaydedilecek işlemleri (ör. aktarımın iki ayağı) aynı anda kontrol eder.
    func validate(_ proposals: [TransactionInfo]) -> LedgerError? {
        validateChange(removing: Set(proposals.map(\.id)), adding: proposals)
    }

    /// Bir işlemin silinmesinin sonraki satışları bozup bozmadığını kontrol eder.
    func validateDeletion(of id: UUID) -> LedgerError? {
        validateDeletion(of: [id])
    }

    func validateDeletion(of ids: Set<UUID>) -> LedgerError? {
        validateChange(removing: ids, adding: [])
    }

    /// `removing` kimlikli işlemler çıkarılıp `adding` eklendiğinde bakiyelerin eksiye düşüp düşmediği.
    func validateChange(removing ids: Set<UUID>, adding proposals: [TransactionInfo]) -> LedgerError? {
        for proposed in proposals {
            guard proposed.quantity > 0 else { return .nonPositiveQuantity }
            guard proposed.unitPrice >= 0 else { return .negativePrice }
        }
        var affected = Set(proposals.map(\.key))
        for original in transactions where ids.contains(original.id) {
            affected.insert(original.key)
        }
        guard !affected.isEmpty else { return nil }
        let candidate = transactions.filter { !ids.contains($0.id) } + proposals
        return firstViolation(in: candidate, keys: affected, proposedIDs: Set(proposals.map(\.id)))
    }

    /// Önerilen işlemden hemen önce, aynı kişi, ürün ve yerdeki miktar.
    func availableQuantity(before proposed: TransactionInfo) -> Decimal {
        max(position(before: proposed).quantity, 0)
    }

    /// Önerilen işlemden hemen önceki ortalama birim maliyet; aktarımda maliyet bununla taşınır.
    func averageCost(before proposed: TransactionInfo) -> Decimal? {
        let position = position(before: proposed)
        return position.quantity > 0 ? position.cost / position.quantity : nil
    }

    private func position(before proposed: TransactionInfo) -> Position {
        var state: [HoldingKey: Position] = [:]
        var transfers: [UUID: Decimal] = [:]
        for transaction in transactions
        where transaction.id != proposed.id && Self.isChronological(transaction, proposed) {
            Self.apply(transaction, to: &state, transfers: &transfers)
        }
        return state[proposed.key] ?? Position()
    }

    private func firstViolation(in list: [TransactionInfo], keys: Set<HoldingKey>, proposedIDs: Set<UUID>) -> LedgerError? {
        var balances: [HoldingKey: Decimal] = [:]
        for transaction in list.sorted(by: Self.isChronological) where keys.contains(transaction.key) {
            let balance = balances[transaction.key, default: 0]
            if transaction.kind.addsQuantity {
                balances[transaction.key] = balance + transaction.quantity
                continue
            }
            if transaction.quantity > balance {
                return proposedIDs.contains(transaction.id)
                    ? .insufficientQuantity(available: balance)
                    : .breaksLaterSale(date: transaction.date)
            }
            balances[transaction.key] = balance - transaction.quantity
        }
        return nil
    }

    // MARK: Yardımcılar

    static func isChronological(_ lhs: TransactionInfo, _ rhs: TransactionInfo) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private struct Position {
        var quantity: Decimal = 0
        var cost: Decimal = 0
    }

    /// İşlemi pozisyona ortalama maliyet yöntemiyle uygular. Satışsa gerçekleşen kârı döndürür.
    /// Aktarımın çıkış ayağı ortalama maliyetle düşer ve maliyetini `transfers`'a bırakır; giriş ayağı onu alır.
    @discardableResult
    private static func apply(
        _ transaction: TransactionInfo, to state: inout [HoldingKey: Position], transfers: inout [UUID: Decimal]
    ) -> RealizedGain? {
        var position = state[transaction.key] ?? Position()
        var realized: RealizedGain?
        switch transaction.kind {
        case .buy:
            position.quantity += transaction.quantity
            position.cost += transaction.quantity * transaction.unitPrice
        case .transferIn:
            position.quantity += transaction.quantity
            position.cost += transaction.transferID.flatMap { transfers.removeValue(forKey: $0) }
                ?? transaction.quantity * transaction.unitPrice
        case .sell, .transferOut:
            let sold = min(transaction.quantity, position.quantity)
            let costBasis: Decimal
            if sold >= position.quantity {
                costBasis = position.cost
                position = Position()
            } else {
                let remaining = position.cost * (position.quantity - sold) / position.quantity
                costBasis = position.cost - remaining
                position.cost = remaining
                position.quantity -= sold
            }
            if transaction.kind == .sell {
                realized = RealizedGain(
                    transactionID: transaction.id, date: transaction.date, personID: transaction.personID,
                    assetID: transaction.assetID, quantity: sold, proceeds: sold * transaction.unitPrice, costBasis: costBasis
                )
            } else if let transferID = transaction.transferID {
                transfers[transferID, default: 0] += costBasis
            }
        }
        state[transaction.key] = position
        return realized
    }
}

// MARK: - Analiz (BI)

struct RealizedGain: Identifiable, Hashable, Sendable {
    let transactionID: UUID
    let date: Date
    let personID: UUID
    let assetID: UUID
    let quantity: Decimal
    let proceeds: Decimal
    let costBasis: Decimal

    var id: UUID { transactionID }
    var gain: Decimal { proceeds - costBasis }
    var ratio: Decimal? { costBasis > 0 ? gain / costBasis : nil }
}

struct ValuePoint: Identifiable, Hashable, Sendable {
    let date: Date
    let value: Decimal
    let cost: Decimal
    let byCategory: [AssetCategory: Decimal]

    var id: Date { date }
    var profit: Decimal { value - cost }
}

struct MonthlyFlow: Identifiable, Hashable, Sendable {
    let month: Date
    let bought: Decimal
    let sold: Decimal

    var id: Date { month }
    var net: Decimal { bought - sold }
}

extension PortfolioCalculator {
    func realizedGains(for filter: PersonFilter = .everyone) -> [RealizedGain] {
        allRealizedGains.filter { filter.includes($0.personID) }
    }

    /// Geçmiş bir tarihteki birim fiyat: o tarihe kadarki son fiyat kaydı; ilk kayıttan öncesi için
    /// son işlem fiyatı. Hiç fiyat kaydı olmayan ürün, güncel toplamlarla tutarlı olsun diye dışarıda kalır.
    func price(of assetID: UUID, at date: Date) -> Decimal? {
        guard let asset = assets[assetID] else { return nil }
        if asset.unit == .lira { return 1 }
        guard let history = priceHistory[assetID], let earliest = history.first else { return nil }
        if let recorded = Self.last(in: history, atOrBefore: date) { return recorded.price }
        return tradePrices[assetID].flatMap { Self.last(in: $0, atOrBefore: date) }?.price ?? earliest.price
    }

    /// Değer ve maliyetin zaman içindeki seyri. Noktalar başlangıçta, her işlem ve fiyat değişiminde ve bugün alınır.
    func valueHistory(
        for filter: PersonFilter = .everyone, matching group: GroupKey? = nil, since start: Date? = nil, now: Date = .now
    ) -> [ValuePoint] {
        let relevant = transactions.filter { transaction in
            filter.includes(transaction.personID) && (group.map { contains($0, transaction.key) } ?? true)
        }
        guard let first = relevant.first, first.date <= now else { return [] }

        let begin = max(start ?? first.date, first.date)
        var dates: Set<Date> = [begin, now]
        for transaction in relevant where transaction.date > begin && transaction.date <= now {
            dates.insert(transaction.date)
        }
        for assetID in Set(relevant.map(\.assetID)) {
            for point in priceHistory[assetID] ?? [] where point.date > begin && point.date <= now {
                dates.insert(point.date)
            }
        }

        var state: [HoldingKey: Position] = [:]
        var transfers: [UUID: Decimal] = [:]
        var next = 0
        return dates.sorted().map { date in
            while next < relevant.count, relevant[next].date <= date {
                Self.apply(relevant[next], to: &state, transfers: &transfers)
                next += 1
            }
            var value: Decimal = 0
            var cost: Decimal = 0
            var byCategory: [AssetCategory: Decimal] = [:]
            for (key, position) in state where position.quantity > 0 {
                guard let price = price(of: key.assetID, at: date) else { continue }
                let holdingValue = position.quantity * price
                value += holdingValue
                cost += position.cost
                byCategory[assets[key.assetID]?.category ?? .other, default: 0] += holdingValue
            }
            return ValuePoint(date: date, value: value, cost: cost, byCategory: byCategory)
        }
    }

    /// Son `count` ayın alım ve satım tutarları; işlem olmayan aylar sıfırla gelir.
    func monthlyFlows(
        for filter: PersonFilter = .everyone, last count: Int = 12, now: Date = .now, calendar: Calendar = .current
    ) -> [MonthlyFlow] {
        guard let currentMonth = calendar.dateInterval(of: .month, for: now)?.start else { return [] }
        let months = (0..<count).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: currentMonth) }
        var totals: [Date: (bought: Decimal, sold: Decimal)] = [:]
        for transaction in transactions where filter.includes(transaction.personID) {
            guard let month = calendar.dateInterval(of: .month, for: transaction.date)?.start else { continue }
            var entry = totals[month] ?? (0, 0)
            switch transaction.kind {
            case .buy: entry.bought += transaction.total
            case .sell: entry.sold += transaction.total
            case .transferOut, .transferIn: continue
            }
            totals[month] = entry
        }
        return months.map { MonthlyFlow(month: $0, bought: totals[$0]?.bought ?? 0, sold: totals[$0]?.sold ?? 0) }
    }

    private static func last(in points: [PriceInfo], atOrBefore date: Date) -> PriceInfo? {
        var low = 0
        var high = points.count
        while low < high {
            let middle = (low + high) / 2
            if points[middle].date <= date { low = middle + 1 } else { high = middle }
        }
        return low > 0 ? points[low - 1] : nil
    }
}

extension Sequence {
    func sum(_ transform: (Element) -> Decimal) -> Decimal {
        reduce(0) { $0 + transform($1) }
    }
}

// MARK: - Yer dökümü

struct LocationHoldings: Identifiable, Hashable, Sendable {
    let locationID: UUID
    let location: LocationInfo?
    /// Bu yerdeki bakiyeler, değere göre sıralı; fiyatı olmayanlar sonda.
    let holdings: [Holding]

    var id: UUID { locationID }
    var value: Decimal { holdings.sum { $0.value ?? 0 } }
    var cost: Decimal { holdings.filter { $0.price != nil }.sum(\.cost) }
    var hasMissingPrice: Bool { holdings.contains { $0.price == nil } }
}

extension PortfolioCalculator {
    /// Varlıkların hangi yerde durduğu, yer başına toplam değerle.
    func locationBreakdown(for filter: PersonFilter = .everyone) -> [LocationHoldings] {
        Dictionary(grouping: holdings(for: filter), by: \.key.locationID)
            .map { locationID, items in
                LocationHoldings(
                    locationID: locationID,
                    location: locations[locationID],
                    holdings: items.sorted { ($0.value ?? -1) > ($1.value ?? -1) }
                )
            }
            .sorted { lhs, rhs in
                lhs.value != rhs.value
                    ? lhs.value > rhs.value
                    : (lhs.location?.name ?? "").localizedCompare(rhs.location?.name ?? "") == .orderedAscending
            }
    }
}

// MARK: - Para birimi karşılığı, piyasa değişimi, hedefler

struct ConvertedPoint: Identifiable, Hashable, Sendable {
    let date: Date
    let value: Decimal
    var id: Date { date }
}

enum GoalKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case netWorth, quantity

    var id: Self { self }

    var title: String {
        switch self {
        case .netWorth: "Net varlık"
        case .quantity: "Ürün miktarı"
        }
    }
}

struct GoalInfo: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var kind: GoalKind
    var target: Decimal
    var assetID: UUID?
    var personID: UUID?
}

struct GoalProgress: Hashable, Sendable {
    let current: Decimal
    let target: Decimal
    /// Son dönemdeki hızla hedefe ulaşılacak tahmini tarih; ilerleme yoksa nil.
    let estimatedDate: Date?

    var ratio: Decimal { target > 0 ? min(max(current / target, 0), 1) : 0 }
    var isReached: Bool { current >= target }
}

extension PortfolioCalculator {
    /// Değer geçmişini başka bir ürün cinsinden (ör. dolar, gram altın) ifade eder.
    func converted(_ points: [ValuePoint], into assetID: UUID) -> [ConvertedPoint] {
        points.compactMap { point in
            guard let price = price(of: assetID, at: point.date), price > 0 else { return nil }
            return ConvertedPoint(date: point.date, value: point.value / price)
        }
    }

    /// Kaydedilen fiyatlara göre ürünün piyasa değişimi. O tarihte ya da öncesinde fiyat kaydı yoksa nil.
    func marketChange(of assetID: UUID, since date: Date) -> Decimal? {
        guard let history = priceHistory[assetID], let latest = history.last,
              let base = Self.last(in: history, atOrBefore: date), base.price > 0, latest.date > base.date
        else { return nil }
        return latest.price / base.price - 1
    }

    /// Bir tarihteki toplam varlık değeri.
    func assetsValue(at date: Date, for filter: PersonFilter = .everyone) -> Decimal {
        valueHistory(for: filter, since: date, now: date).first?.value ?? 0
    }

    /// Bir tarihte bir ürünün toplam miktarı.
    func quantity(of assetID: UUID, for filter: PersonFilter = .everyone, at date: Date) -> Decimal {
        var state: [HoldingKey: Position] = [:]
        var transfers: [UUID: Decimal] = [:]
        for transaction in transactions where transaction.date <= date {
            Self.apply(transaction, to: &state, transfers: &transfers)
        }
        return state.filter { $0.key.assetID == assetID && filter.includes($0.key.personID) }.values.sum { $0.quantity }
    }

    /// Hedefin bugünkü durumu; tahmini tarih son `lookbackDays` gündeki ilerleme hızından hesaplanır.
    func progress(of goal: GoalInfo, now: Date = .now, lookbackDays: Int = 90) -> GoalProgress {
        let filter = goal.personID.map(PersonFilter.person) ?? .everyone
        let past = now.addingTimeInterval(-Double(lookbackDays) * 86_400)
        let current: Decimal
        let previous: Decimal
        switch goal.kind {
        case .netWorth:
            current = summary(for: filter).netWorth
            previous = assetsValue(at: past, for: filter) - debtSummary(for: filter).total
        case .quantity:
            guard let assetID = goal.assetID else {
                return GoalProgress(current: 0, target: goal.target, estimatedDate: nil)
            }
            current = holdings(for: filter).filter { $0.key.assetID == assetID }.sum(\.quantity)
            previous = quantity(of: assetID, for: filter, at: past)
        }
        var estimate: Date?
        let gainPerDay = (current - previous) / Decimal(lookbackDays)
        if current < goal.target, gainPerDay > 0 {
            let daysLeft = ((goal.target - current) / gainPerDay).doubleValue
            if daysLeft < 365 * 50 { estimate = now.addingTimeInterval(daysLeft * 86_400) }
        }
        return GoalProgress(current: current, target: goal.target, estimatedDate: estimate)
    }
}

enum DebtPlan {
    /// Kalan borcun aylık taksitle kaç ayda biteceği ve tahmini bitiş tarihi.
    static func payoff(
        remaining: Decimal, monthly: Decimal?, from date: Date = .now, calendar: Calendar = .current
    ) -> (months: Int, date: Date)? {
        guard let monthly, monthly > 0, remaining > 0 else { return nil }
        let months = Int((remaining / monthly).doubleValue.rounded(.up))
        guard let end = calendar.date(byAdding: .month, value: months, to: date) else { return nil }
        return (months, end)
    }
}

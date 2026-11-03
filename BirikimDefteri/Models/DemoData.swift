#if DEBUG
import Foundation
import SwiftData

extension Store {
    /// Yalnızca hata ayıklama derlemesinde ve `-demoData` argümanıyla açılınca mevcut veriyi silip
    /// 18 aylık örnek işlem, fiyat geçmişi ve borç yükler. Ekranları simülatörde denemek içindir.
    static func loadDemoDataIfRequested(in context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("-demoData") else { return }

        for object in (try? context.fetch(FetchDescriptor<TransactionRecord>())) ?? [] { context.delete(object) }
        for object in (try? context.fetch(FetchDescriptor<PricePoint>())) ?? [] { context.delete(object) }
        for object in (try? context.fetch(FetchDescriptor<Debt>())) ?? [] { context.delete(object) }
        for object in (try? context.fetch(FetchDescriptor<Asset>())) ?? [] { context.delete(object) }
        for object in (try? context.fetch(FetchDescriptor<Location>())) ?? [] { context.delete(object) }
        for object in (try? context.fetch(FetchDescriptor<Person>())) ?? [] { context.delete(object) }
        for object in (try? context.fetch(FetchDescriptor<DebtPayment>())) ?? [] { context.delete(object) }
        for object in (try? context.fetch(FetchDescriptor<Goal>())) ?? [] { context.delete(object) }
        for object in (try? context.fetch(FetchDescriptor<JournalEntry>())) ?? [] { context.delete(object) }
        try? context.save()
        seedIfNeeded(in: context)

        let assets = (try? context.fetch(FetchDescriptor<Asset>())) ?? []
        guard let me = (try? context.fetch(FetchDescriptor<Person>()))?.first,
              let home = (try? context.fetch(FetchDescriptor<Location>()))?.first
        else { return }
        let partner = Person(name: "Eşim", createdAt: me.createdAt.addingTimeInterval(1))
        let bank = Location(name: "Ziraat Bankası", kind: .bank, createdAt: home.createdAt.addingTimeInterval(1))
        context.insert(partner)
        context.insert(bank)

        func asset(_ name: String) -> Asset? { assets.first { $0.name == name } }

        let curves: [String: (start: Double, end: Double, phase: Double)] = [
            "Gram altın": (2250, 3450, 0.0),
            "Çeyrek altın": (3700, 5650, 0.3),
            "Yarım altın": (7400, 11300, 0.6),
            "Tam altın": (14800, 22500, 0.9),
            "Cumhuriyet altını": (15200, 23100, 1.2),
            "22 ayar bilezik": (2050, 3150, 1.5),
            "Gram gümüş": (28, 41.5, 2.1),
            "Dolar": (32.4, 41.8, 2.7),
            "Euro": (35.1, 48.6, 3.3),
        ]
        let months = 18
        let calendar = Calendar.current
        guard let thisMonth = calendar.dateInterval(of: .month, for: .now)?.start else { return }

        func monthStart(_ month: Int) -> Date {
            calendar.date(byAdding: .month, value: month - (months - 1), to: thisMonth) ?? thisMonth
        }

        func price(_ name: String, _ month: Int) -> Decimal {
            guard let curve = curves[name] else { return 1 }
            let progress = Double(month) / Double(months - 1)
            let value = curve.start * pow(curve.end / curve.start, progress) * (1 + 0.03 * sin(Double(month) * 1.3 + curve.phase))
            return Decimal(string: String(format: "%.2f", value)) ?? 1
        }

        for month in 0..<months {
            for name in curves.keys {
                guard let asset = asset(name) else { continue }
                context.insert(PricePoint(assetID: asset.id, price: price(name, month), date: monthStart(month).addingTimeInterval(36_000)))
            }
        }

        var createdAt = monthStart(0)
        func add(
            _ kind: TransactionKind, _ name: String, _ quantity: Decimal, month: Int, day: Int = 5,
            person: Person? = nil, location: Location? = nil, note: String = ""
        ) {
            guard let asset = asset(name) else { return }
            let date = calendar.startOfDay(for: monthStart(month).addingTimeInterval(Double(day - 1) * 86_400))
            createdAt = max(createdAt, date).addingTimeInterval(60)
            let info = TransactionInfo(
                id: UUID(), kind: kind, personID: (person ?? me).id, assetID: asset.id, locationID: (location ?? home).id,
                quantity: quantity, unitPrice: asset.unit == .lira ? 1 : price(name, month),
                date: date, createdAt: createdAt
            )
            context.insert(TransactionRecord(info: info, note: note))
        }

        add(.buy, "Türk lirası", 50_000, month: 0, day: 2, location: bank, note: "Vadeli hesap")
        for month in 0..<(months - 1) {
            add(.buy, "Gram altın", Decimal(2 + month % 4), month: month, note: month == 0 ? "Aylık birikim" : "")
            if month % 3 == 1 { add(.buy, "Çeyrek altın", 1, month: month, day: 12) }
        }
        add(.buy, "Dolar", 1_500, month: 2, day: 8, location: bank)
        add(.buy, "Euro", 800, month: 4, day: 9, location: bank)
        add(.buy, "22 ayar bilezik", 20, month: 6, day: 14, person: partner, note: "Düğün hediyesi")
        add(.buy, "Gram gümüş", 250, month: 8, day: 10)
        add(.buy, "Dolar", 1_000, month: 9, day: 8, location: bank)
        add(.buy, "Türk lirası", 25_000, month: 10, day: 2, location: bank)
        add(.buy, "Cumhuriyet altını", 1, month: 11, day: 20, person: partner)
        add(.sell, "Dolar", 800, month: 12, day: 15, location: bank, note: "Tatil")
        add(.sell, "Gram altın", 5, month: 13, day: 18)
        add(.sell, "Türk lirası", 20_000, month: 14, day: 3, location: bank)
        add(.sell, "Gram gümüş", 100, month: 15, day: 11)
        add(.buy, "Yarım altın", 1, month: 16, day: 7, person: partner)

        if let gram = asset("Gram altın") {
            let moveDate = calendar.startOfDay(for: monthStart(14).addingTimeInterval(19 * 86_400))
            let moveID = UUID()
            createdAt = max(createdAt, moveDate).addingTimeInterval(60)
            for (kind, location, offset) in [(TransactionKind.transferOut, home, 0.0), (.transferIn, bank, 0.001)] {
                let info = TransactionInfo(
                    id: UUID(), kind: kind, personID: me.id, assetID: gram.id, locationID: location.id, quantity: 5,
                    unitPrice: price("Gram altın", 14), date: moveDate, createdAt: createdAt.addingTimeInterval(offset), transferID: moveID
                )
                context.insert(TransactionRecord(info: info, note: "Banka hesabına taşındı"))
            }
            context.insert(Goal(title: "100 gr altın", kind: .quantity, target: 100, assetID: gram.id, personID: me.id))
        }
        context.insert(Goal(title: "Net varlık hedefi", kind: .netWorth, target: 500_000, assetID: nil, personID: nil))

        let nextMonth = calendar.date(byAdding: .month, value: 1, to: thisMonth) ?? thisMonth
        let loan = Debt(
            personID: me.id, institution: "Ziraat Bankası", kind: .loan, title: "İhtiyaç kredisi",
            remaining: 85_400, monthlyInstallment: 6_250,
            dueDate: calendar.date(byAdding: .month, value: 22, to: thisMonth), note: "", paymentDay: 5
        )
        context.insert(loan)
        for month in [15, 16] {
            context.insert(DebtPayment(debtID: loan.id, amount: 6_250, date: monthStart(month).addingTimeInterval(4 * 86_400)))
        }
        context.insert(Debt(
            personID: me.id, institution: "Garanti BBVA", kind: .creditCard, title: "Bonus",
            remaining: Decimal(string: "12430.75") ?? 0, monthlyInstallment: nil,
            dueDate: calendar.date(byAdding: .day, value: 14, to: nextMonth), note: ""
        ))
        context.insert(Debt(
            personID: partner.id, institution: "Akbank", kind: .creditCard, title: "Axess",
            remaining: 4_210, monthlyInstallment: nil,
            dueDate: calendar.date(byAdding: .day, value: 9, to: nextMonth), note: ""
        ))
        try? context.save()
    }
}
#endif

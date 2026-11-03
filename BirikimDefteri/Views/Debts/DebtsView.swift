import SwiftData
import SwiftUI

struct DebtsView: View {
    @Environment(\.ledger) private var ledger
    @Environment(\.modelContext) private var context
    @State private var filter: PersonFilter = .everyone
    @State private var isAdding = false

    private struct InstitutionGroup: Identifiable {
        let institution: String
        let debts: [Debt]
        var id: String { institution }
        var total: Decimal { debts.sum(\.remaining) }
    }

    var body: some View {
        let debts = ledger.debts.filter { filter.includes($0.personID) }
        let summary = ledger.calculator.debtSummary(for: filter)
        let groups = institutionGroups(debts)

        NavigationStack {
            List {
                if ledger.people.count > 1 {
                    Section {
                        PersonFilterPicker(people: ledger.people, selection: $filter)
                    }
                }

                if !debts.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Toplam borç", systemImage: "creditcard")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color(hex: 0xFFC9B8))
                                Text(Format.lira(summary.total))
                                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                            }
                            Label {
                                Text("Aylık taksit: \(Format.lira(summary.monthlyInstallments))")
                            } icon: {
                                Image(systemName: "calendar.badge.clock")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(.vertical, 10)
                        .listRowBackground(HeroBackground(colors: [0x8E2B2B, 0x3D1010], glow: 0xFF8A65))

                        ForEach(DebtKind.allCases) { kind in
                            if let amount = summary.byKind[kind] {
                                HStack(spacing: 12) {
                                    DebtKindIcon(kind: kind, size: 30)
                                    LabeledContent(kind.title, value: Format.lira(amount))
                                }
                            }
                        }
                    }

                    ForEach(groups) { group in
                        Section {
                            ForEach(group.debts) { debt in
                                NavigationLink {
                                    DebtDetailView(debtID: debt.id)
                                } label: {
                                    DebtRow(debt: debt, showsPerson: ledger.people.count > 1)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button("Sil", systemImage: "trash", role: .destructive) {
                                        Journal.recordDebt(.deleted, summary: Journal.describe(debt), before: Journal.entry(debt), after: nil, in: context)
                                        for payment in ledger.payments(for: debt) { context.delete(payment) }
                                        context.delete(debt)
                                        try? context.save()
                                    }
                                }
                            }
                        } header: {
                            HStack {
                                Text(group.institution)
                                Spacer()
                                Text(Format.lira(group.total)).monospacedDigit()
                            }
                        }
                    }
                }
            }
            .overlay {
                if debts.isEmpty {
                    ContentUnavailableView(
                        "Borç kaydı yok",
                        systemImage: "creditcard",
                        description: Text("Kredi, kredi kartı ve diğer borçlarınızı + ile ekleyin.")
                    )
                }
            }
            .navigationTitle("Borçlar")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAdding = true
                    } label: {
                        Label("Yeni borç", systemImage: "plus.circle.fill")
                    }
                    .tint(Theme.gold)
                }
            }
            .sheet(isPresented: $isAdding) {
                DebtFormView()
            }
        }
    }

    private func institutionGroups(_ debts: [Debt]) -> [InstitutionGroup] {
        Dictionary(grouping: debts) { $0.institution.trimmed.isEmpty ? "Kurum belirtilmemiş" : $0.institution.trimmed }
            .map { InstitutionGroup(institution: $0.key, debts: $0.value.sorted { $0.remaining > $1.remaining }) }
            .sorted { $0.institution.localizedCompare($1.institution) == .orderedAscending }
    }
}

private struct DebtRow: View {
    let debt: Debt
    let showsPerson: Bool
    @Environment(\.ledger) private var ledger

    @ScaledMetric private var iconSize: CGFloat = 40

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DebtKindIcon(kind: debt.kind, size: iconSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(debt.title.isEmpty ? debt.kind.title : debt.title)
                    .foregroundStyle(Color.primary)
                Text(details)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                Text("Güncellendi: \(Format.date(debt.updatedAt))")
                    .font(.caption)
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            Spacer(minLength: 8)
            Text(Format.lira(debt.remaining))
                .foregroundStyle(Color.primary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private var details: String {
        var parts = [debt.kind.title]
        if let monthly = debt.monthlyInstallment {
            parts.append("Aylık \(Format.lira(monthly))")
        }
        if let dueDate = debt.dueDate {
            parts.append("\(debt.kind == .creditCard ? "Son ödeme" : "Bitiş") \(Format.date(dueDate))")
        }
        if showsPerson {
            parts.append(ledger.personName(debt.personID))
        }
        return parts.joined(separator: " · ")
    }
}

struct DebtKindIcon: View {
    let kind: DebtKind
    var size: CGFloat = 40

    var body: some View {
        let style: (symbol: String, colors: [UInt32]) = switch kind {
        case .loan: ("building.columns.fill", [0x1E88E5, 0x0D47A1])
        case .creditCard: ("creditcard.fill", [0xAB47BC, 0x4A148C])
        case .other: ("doc.text.fill", [0x90A4AE, 0x455A64])
        }
        Circle()
            .fill(LinearGradient(colors: style.colors.map(Color.init(hex:)), startPoint: .top, endPoint: .bottom))
            .overlay {
                Image(systemName: style.symbol)
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

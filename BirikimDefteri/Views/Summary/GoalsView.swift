import SwiftData
import SwiftUI

/// Özet ekranındaki hedef kartı.
struct GoalsCard: View {
    @Environment(\.ledger) private var ledger

    var body: some View {
        if ledger.goals.isEmpty {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hedef belirle")
                        .foregroundStyle(Color.primary)
                    Text("Net varlık ya da ürün miktarı için; ilerlemeyi ve tahmini tarihi gösterir.")
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                }
            } icon: {
                GoalIcon()
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text("Hedefler").foregroundStyle(Color.primary)
                } icon: {
                    GoalIcon()
                }
                ForEach(ledger.goals.prefix(3)) { goal in
                    GoalProgressView(goal: goal)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct GoalIcon: View {
    var body: some View {
        Image(systemName: "target")
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Theme.gold.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct GoalProgressView: View {
    let goal: Goal
    @Environment(\.ledger) private var ledger

    var body: some View {
        let progress = ledger.calculator.progress(of: goal.info)

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(goal.title)
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 8)
                Text(Format.percent(progress.ratio))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(progress.isReached ? Theme.positive : Color.primary)
            }
            ProgressView(value: progress.ratio.doubleValue)
                .tint(progress.isReached ? Theme.positive : Theme.gold)
            Text("\(amount(progress.current)) / \(amount(progress.target)) · \(estimate(progress))")
                .font(.caption)
                .foregroundStyle(Color.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func amount(_ value: Decimal) -> String {
        switch goal.kind {
        case .netWorth:
            return Format.lira(value)
        case .quantity:
            return Format.quantity(value, unit: goal.assetID.flatMap { ledger.calculator.assets[$0]?.unit } ?? .piece)
        }
    }

    private func estimate(_ progress: GoalProgress) -> String {
        if progress.isReached { return "Hedefe ulaşıldı" }
        guard let date = progress.estimatedDate else { return "Son 3 ayda ilerleme yok" }
        return "Bu hızla \(Format.month(date))"
    }
}

struct GoalsView: View {
    @Environment(\.ledger) private var ledger
    @Environment(\.modelContext) private var context
    @State private var editing: Goal?
    @State private var isAdding = false

    var body: some View {
        List {
            Section {
                ForEach(ledger.goals) { goal in
                    Button {
                        editing = goal
                    } label: {
                        GoalProgressView(goal: goal)
                            .padding(.vertical, 4)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Sil", systemImage: "trash", role: .destructive) {
                            context.delete(goal)
                            try? context.save()
                        }
                    }
                }
            } footer: {
                if !ledger.goals.isEmpty {
                    Text("Tahmini tarih, son 3 aydaki ilerleme hızıyla hesaplanır.")
                }
            }
        }
        .overlay {
            if ledger.goals.isEmpty {
                ContentUnavailableView(
                    "Henüz hedef yok",
                    systemImage: "target",
                    description: Text("Ör. ₺2.000.000 net varlık ya da 100 gr altın hedefi koyun.")
                )
            }
        }
        .navigationTitle("Hedefler")
        .toolbar {
            Button {
                isAdding = true
            } label: {
                Label("Hedef ekle", systemImage: "plus")
            }
        }
        .sheet(item: $editing) { goal in
            GoalFormView(goal: goal)
        }
        .sheet(isPresented: $isAdding) {
            GoalFormView()
        }
    }
}

struct GoalFormView: View {
    let goal: Goal?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.ledger) private var ledger
    @State private var title: String
    @State private var kind: GoalKind
    @State private var assetID: UUID?
    @State private var personID: UUID?
    @State private var targetText: String

    init(goal: Goal? = nil) {
        self.goal = goal
        _title = State(initialValue: goal?.title ?? "")
        _kind = State(initialValue: goal?.kind ?? .netWorth)
        _assetID = State(initialValue: goal?.assetID)
        _personID = State(initialValue: goal?.personID)
        _targetText = State(initialValue: goal.map { Format.editable($0.target) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tür", selection: $kind) {
                        ForEach(GoalKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if kind == .quantity {
                        Picker("Ürün", selection: $assetID) {
                            if assetID == nil { Text("Seçin").tag(UUID?.none) }
                            ForEach(ledger.assets) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                    DecimalField(title: "Hedef", placeholder: "0", text: $targetText, suffix: suffix)
                    if ledger.people.count > 1 {
                        Picker("Kişi", selection: $personID) {
                            Text("Herkes").tag(UUID?.none)
                            ForEach(ledger.people) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                }
                Section {
                    TextField(defaultTitle, text: $title)
                } header: {
                    Text("Ad")
                }
            }
            .navigationTitle(goal == nil ? "Yeni hedef" : "Hedef")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save).disabled(!canSave)
                }
            }
            .keyboardDoneButton()
        }
        .presentationDetents([.medium, .large])
        .lockProtected()
    }

    private var asset: AssetInfo? { assetID.flatMap { ledger.calculator.assets[$0] } }
    private var target: Decimal? { Format.parseDecimal(targetText) }
    private var suffix: String { kind == .netWorth ? "₺" : asset?.unit.symbol ?? "" }

    private var defaultTitle: String {
        switch kind {
        case .netWorth: return "Net varlık hedefi"
        case .quantity: return asset.map { "\($0.name) hedefi" } ?? "Ürün hedefi"
        }
    }

    private var canSave: Bool {
        guard let target, target > 0 else { return false }
        return kind == .netWorth || assetID != nil
    }

    private func save() {
        guard let target, canSave else { return }
        let name = title.trimmed.isEmpty ? defaultTitle : title.trimmed
        let asset = kind == .quantity ? assetID : nil
        if let goal {
            goal.title = name
            goal.kind = kind
            goal.target = target
            goal.assetID = asset
            goal.personID = personID
        } else {
            context.insert(Goal(title: name, kind: kind, target: target, assetID: asset, personID: personID))
        }
        try? context.save()
        dismiss()
    }
}

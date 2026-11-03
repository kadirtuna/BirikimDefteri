import SwiftData
import SwiftUI

struct TransactionsView: View {
    @Environment(\.ledger) private var ledger
    @Environment(\.modelContext) private var context
    @State private var assetFilter: UUID?
    @State private var locationFilter: UUID?
    @State private var personFilter: UUID?
    @State private var editing: TransactionRecord?
    @State private var editingTransfer: TransferRef?
    @State private var isAdding = false
    @State private var isAddingTransfer = false
    @State private var deleteError: String?
    @State private var undoEntry: JournalEntry?
    @State private var query = ""
    @State private var repeating: TransactionRecord?
    @State private var transferPrefill: TransferPrefill?
    @State private var showsDeleted = false

    private struct TransferPrefill: Identifiable {
        let id = UUID()
        let assetID: UUID
        let personID: UUID
        let fromID: UUID
    }

    private struct MonthSection: Identifiable {
        let month: Date
        let records: [TransactionRecord]
        var id: Date { month }
    }

    var body: some View {
        let sections = monthSections

        NavigationStack {
            List {
                if isFiltering {
                    Section {
                        HStack {
                            Text(filterDescription)
                                .font(.subheadline)
                            Spacer()
                            Button("Temizle", action: clearFilters)
                        }
                    }
                }
                ForEach(sections) { section in
                    Section {
                        ForEach(section.records) { record in
                            Button {
                                open(record)
                            } label: {
                                TransactionRow(info: record.info, note: record.note)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("Sil", systemImage: "trash", role: .destructive) {
                                    delete(record)
                                }
                            }
                            .swipeActions(edge: .leading) {
                                if record.transferID == nil {
                                    Button("Tekrarla", systemImage: "arrow.clockwise") { repeating = record }
                                        .tint(Theme.green)
                                }
                            }
                            .contextMenu { menu(for: record) }
                        }
                    } header: {
                        MonthHeader(month: section.month, records: section.records)
                    }
                }
            }
            .overlay {
                if sections.isEmpty {
                    if !query.trimmed.isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else if isFiltering {
                        ContentUnavailableView("Eşleşen kayıt yok", systemImage: "line.3.horizontal.decrease.circle")
                    } else {
                        ContentUnavailableView(
                            "Henüz kayıt yok",
                            systemImage: "tray",
                            description: Text("Alış, satış ve aktarımlarınızı + ile ekleyin.")
                        )
                    }
                }
            }
            .navigationTitle("Kayıtlar")
            .searchable(text: $query, prompt: "Ürün, yer, kişi ya da not")
            .navigationDestination(isPresented: $showsDeleted) {
                JournalView(filter: .deleted)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { filterMenu }
                ToolbarItem(placement: .primaryAction) {
                    AddTransactionMenu(isAddingTrade: $isAdding, isAddingTransfer: $isAddingTransfer)
                }
            }
            .sheet(item: $editing) { record in
                TransactionFormView(record: record)
            }
            .sheet(item: $editingTransfer) { reference in
                TransferFormView(transferID: reference.id)
            }
            .sheet(isPresented: $isAdding) {
                TransactionFormView(assetID: assetFilter)
            }
            .sheet(isPresented: $isAddingTransfer) {
                TransferFormView()
            }
            .sheet(item: $repeating) { record in
                TransactionFormView(template: record)
            }
            .sheet(item: $transferPrefill) { prefill in
                TransferFormView(assetID: prefill.assetID, personID: prefill.personID, fromID: prefill.fromID)
            }
            .overlay(alignment: .bottom) {
                if undoEntry != nil {
                    UndoBanner(message: "Kayıt silindi", undo: undoLastDeletion)
                }
            }
            .animation(.default, value: undoEntry?.id)
            .task(id: undoEntry?.id) {
                guard undoEntry != nil else { return }
                try? await Task.sleep(for: .seconds(6))
                undoEntry = nil
            }
            .alert("İşlem silinemedi", isPresented: Binding(isPresent: $deleteError)) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Ürün", selection: $assetFilter) {
                Text("Tüm ürünler").tag(UUID?.none)
                ForEach(ledger.assets) { Text($0.name).tag(Optional($0.id)) }
            }
            .pickerStyle(.menu)
            Picker("Yer", selection: $locationFilter) {
                Text("Tüm yerler").tag(UUID?.none)
                ForEach(ledger.locations) { Text($0.name).tag(Optional($0.id)) }
            }
            .pickerStyle(.menu)
            if ledger.people.count > 1 {
                Picker("Kişi", selection: $personFilter) {
                    Text("Herkes").tag(UUID?.none)
                    ForEach(ledger.people) { Text($0.name).tag(Optional($0.id)) }
                }
                .pickerStyle(.menu)
            }
            if isFiltering {
                Button("Filtreleri temizle", systemImage: "xmark.circle", role: .destructive, action: clearFilters)
            }
            Divider()
            Button("Silinenler", systemImage: "trash") { showsDeleted = true }
        } label: {
            Label("Filtrele", systemImage: isFiltering
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
        }
    }

    @ViewBuilder
    private func menu(for record: TransactionRecord) -> some View {
        Button("Düzenle", systemImage: "pencil") { open(record) }
        if record.transferID == nil {
            Button("Tekrarla", systemImage: "arrow.clockwise") { repeating = record }
            Button("Başka yere aktar", systemImage: "arrow.left.arrow.right") {
                transferPrefill = TransferPrefill(assetID: record.assetID, personID: record.personID, fromID: record.locationID)
            }
        }
        Divider()
        Button("Sil", systemImage: "trash", role: .destructive) { delete(record) }
    }

    private func open(_ record: TransactionRecord) {
        if let transferID = record.transferID {
            editingTransfer = TransferRef(id: transferID)
        } else {
            editing = record
        }
    }

    /// Aramada ürün, kişi, yer (aktarımda iki yer de), işlem türü ve not aranır.
    private func matches(_ record: TransactionRecord, _ query: String) -> Bool {
        var fields = [
            ledger.calculator.assets[record.assetID]?.name ?? "", ledger.personName(record.personID),
            ledger.locationName(record.locationID), record.kind.title, record.note,
        ]
        if let transferID = record.transferID {
            let legs = ledger.transferLegs(transferID)
            fields += [legs.out, legs.in].compactMap { $0.map { ledger.locationName($0.locationID) } }
        }
        return fields.contains { $0.localizedStandardContains(query) }
    }

    private var isFiltering: Bool {
        assetFilter != nil || locationFilter != nil || personFilter != nil
    }

    private var filterDescription: String {
        var parts: [String] = []
        if let assetFilter { parts.append(ledger.calculator.title(for: .asset(assetFilter))) }
        if let locationFilter { parts.append(ledger.locationName(locationFilter)) }
        if let personFilter { parts.append(ledger.personName(personFilter)) }
        return parts.joined(separator: " · ")
    }

    private var monthSections: [MonthSection] {
        let calendar = Calendar.current
        let query = query.trimmed
        let records = ledger.transactions
            .filter { record in
                (assetFilter == nil || record.assetID == assetFilter)
                    && (locationFilter == nil || record.locationID == locationFilter)
                    && (personFilter == nil || record.personID == personFilter)
                    && (query.isEmpty || matches(record, query))
            }
            .sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
        // Aktarımın iki ayağından yalnızca biri satır olarak gösterilir.
        var seenTransfers: Set<UUID> = []
        let rows = records.filter { record in
            guard let transferID = record.transferID else { return true }
            return seenTransfers.insert(transferID).inserted
        }
        let grouped = Dictionary(grouping: rows) { record in
            calendar.dateInterval(of: .month, for: record.date)?.start ?? record.date
        }
        return grouped
            .map { month, records in
                MonthSection(month: month, records: records.sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) })
            }
            .sorted { $0.month > $1.month }
    }

    private func clearFilters() {
        assetFilter = nil
        locationFilter = nil
        personFilter = nil
    }

    private func delete(_ record: TransactionRecord) {
        let records: [TransactionRecord]
        let summary: String
        if let transferID = record.transferID {
            let legs = ledger.transferLegs(transferID)
            records = [legs.out, legs.in].compactMap { $0 }
            summary = Journal.describe(legs.out?.info ?? record.info, ledger: ledger, destination: legs.in?.locationID)
        } else {
            records = [record]
            summary = Journal.describe(record.info, ledger: ledger)
        }
        if let error = ledger.calculator.validateDeletion(of: Set(records.map(\.id))) {
            deleteError = error.message(unit: ledger.calculator.assets[record.assetID]?.unit)
            return
        }
        undoEntry = Journal.recordTransactions(.deleted, summary: summary, before: records, after: [], in: context)
        records.forEach(context.delete)
        try? context.save()
        Haptics.warning()
    }

    private func undoLastDeletion() {
        guard let undoEntry else { return }
        self.undoEntry = nil
        do {
            try Journal.undo(undoEntry, ledger: ledger, context: context)
            Haptics.success()
        } catch {
            deleteError = error.localizedDescription
        }
    }
}

/// Ay başlığı ve o ayın toplam alım ile satımı (aktarımlar hariç).
private struct MonthHeader: View {
    let month: Date
    let records: [TransactionRecord]

    var body: some View {
        let trades = records.filter { $0.transferID == nil }
        let bought = trades.filter { $0.kind == .buy }.sum { $0.info.total }
        let sold = trades.filter { $0.kind == .sell }.sum { $0.info.total }
        let parts = [bought > 0 ? "Alım \(Format.lira(bought))" : nil, sold > 0 ? "Satış \(Format.lira(sold))" : nil].compactMap { $0 }

        HStack(alignment: .firstTextBaseline) {
            Text(Format.month(month))
            Spacer(minLength: 8)
            Text(parts.joined(separator: " · "))
                .font(.caption)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// "+" düğmesi: alış/satış ya da aktarım.
struct AddTransactionMenu: View {
    @Binding var isAddingTrade: Bool
    @Binding var isAddingTransfer: Bool

    var body: some View {
        Menu {
            Button("Alış / Satış", systemImage: "plus") { isAddingTrade = true }
            Button("Aktarım", systemImage: "arrow.left.arrow.right") { isAddingTransfer = true }
        } label: {
            Label("Yeni işlem", systemImage: "plus.circle.fill")
        }
        .tint(Theme.gold)
    }
}

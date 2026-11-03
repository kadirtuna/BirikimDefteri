import SwiftData
import SwiftUI

struct TransactionsView: View {
    @Environment(\.ledger) private var ledger
    @Environment(\.modelContext) private var context
    @State private var assetFilter: UUID?
    @State private var locationFilter: UUID?
    @State private var personFilter: UUID?
    @State private var editing: TransactionRecord?
    @State private var isAdding = false
    @State private var deleteError: String?

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
                    Section(Format.month(section.month)) {
                        ForEach(section.records) { record in
                            Button {
                                editing = record
                            } label: {
                                TransactionRow(info: record.info, note: record.note)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("Sil", systemImage: "trash", role: .destructive) {
                                    delete(record)
                                }
                            }
                        }
                    }
                }
            }
            .overlay {
                if sections.isEmpty {
                    if isFiltering {
                        ContentUnavailableView("Eşleşen kayıt yok", systemImage: "line.3.horizontal.decrease.circle")
                    } else {
                        ContentUnavailableView(
                            "Henüz kayıt yok",
                            systemImage: "tray",
                            description: Text("Alış ve satışlarınızı + ile ekleyin.")
                        )
                    }
                }
            }
            .navigationTitle("Kayıtlar")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { filterMenu }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAdding = true
                    } label: {
                        Label("Yeni işlem", systemImage: "plus.circle.fill")
                    }
                    .tint(Theme.gold)
                }
            }
            .sheet(item: $editing) { record in
                TransactionFormView(record: record)
            }
            .sheet(isPresented: $isAdding) {
                TransactionFormView(assetID: assetFilter)
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
        } label: {
            Label("Filtrele", systemImage: isFiltering
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
        }
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
        let records = ledger.transactions
            .filter { record in
                (assetFilter == nil || record.assetID == assetFilter)
                    && (locationFilter == nil || record.locationID == locationFilter)
                    && (personFilter == nil || record.personID == personFilter)
            }
            .sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
        let grouped = Dictionary(grouping: records) { record in
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
        if let error = ledger.calculator.validateDeletion(of: record.id) {
            deleteError = error.message(unit: ledger.calculator.assets[record.assetID]?.unit)
            return
        }
        context.delete(record)
        try? context.save()
    }
}

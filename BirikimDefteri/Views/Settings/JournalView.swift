import SwiftData
import SwiftUI

/// Kayıt, aktarım, borç, ödeme ve tanım değişikliklerinin geçmişi; her değişiklik geri alınabilir.
/// Silmeler ve yedekten geri yüklemeler hiç budanmaz.
struct JournalView: View {
    enum Filter: Hashable {
        case all, deleted
    }

    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]
    @Environment(\.ledger) private var ledger
    @Environment(\.modelContext) private var context
    @State private var filter: Filter
    @State private var undoError: String?
    @State private var pendingRestoreUndo: JournalEntry?

    init(filter: Filter = .all) {
        _filter = State(initialValue: filter)
    }

    private struct Day: Identifiable {
        let date: Date
        let entries: [JournalEntry]
        var id: Date { date }
    }

    var body: some View {
        let visible = filter == .all ? entries : entries.filter { $0.action.isKeptForever }
        let days = Dictionary(grouping: visible) { Calendar.current.startOfDay(for: $0.date) }
            .map { Day(date: $0.key, entries: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.date > $1.date }

        List {
            Section {
                Picker("Göster", selection: $filter) {
                    Text("Tümü").tag(Filter.all)
                    Text("Silinenler").tag(Filter.deleted)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                if filter == .deleted {
                    Text("Silinen kayıtlar ve yedekten geri yüklemeler burada hep kalır; istediğiniz zaman geri getirebilirsiniz.")
                }
            }

            ForEach(days) { day in
                Section(Format.date(day.date)) {
                    ForEach(day.entries) { entry in
                        JournalRow(entry: entry) { requestUndo(entry) }
                    }
                }
            }
        }
        .overlay {
            if visible.isEmpty {
                ContentUnavailableView(
                    filter == .all ? "Henüz değişiklik yok" : "Silinen bir şey yok",
                    systemImage: filter == .all ? "clock.arrow.circlepath" : "trash.slash",
                    description: Text(filter == .all
                        ? "Kayıt, aktarım, borç ve ödemelerde yaptığınız değişiklikler burada listelenir ve geri alınabilir."
                        : "Bir şeyi sildiğinizde burada görünür ve geri getirilebilir.")
                )
            }
        }
        .navigationTitle("İşlem geçmişi")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Geri alınamadı", isPresented: Binding(isPresent: $undoError)) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(undoError ?? "")
        }
        .confirmationDialog(
            "Geri yüklemeden önceki hâle dönülsün mü?",
            isPresented: Binding(isPresent: $pendingRestoreUndo),
            titleVisibility: .visible,
            presenting: pendingRestoreUndo
        ) { entry in
            Button("Önceki hâle dön", role: .destructive) { undo(entry) }
        } message: { _ in
            Text("Veriler geri yüklemeden hemen önceki hâline döner. Şimdiki hâl de geçmişe kaydedilir; istersen ona da dönebilirsin.")
        }
    }

    private func requestUndo(_ entry: JournalEntry) {
        if entry.entity == .backup {
            pendingRestoreUndo = entry
        } else {
            undo(entry)
        }
    }

    private func undo(_ entry: JournalEntry) {
        do {
            try Journal.undo(entry, ledger: ledger, context: context)
            Haptics.success()
        } catch {
            undoError = error.localizedDescription
        }
    }
}

private struct JournalRow: View {
    let entry: JournalEntry
    let undo: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.action.symbol)
                .font(.title3)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.summary)
                    .font(.subheadline)
                    .strikethrough(entry.isUndone)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if !entry.isUndone {
                Button(entry.action == .deleted ? "Geri getir" : "Geri al", action: undo)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    private var detail: String {
        let time = entry.date.formatted(.dateTime.hour().minute().locale(Format.locale))
        return "\(entry.action.title) · \(time)" + (entry.isUndone ? " · geri alındı" : "")
    }

    private var tint: Color {
        switch entry.action {
        case .added: Theme.positive
        case .edited: .blue
        case .deleted: Theme.negative
        case .restored: .orange
        }
    }
}

import SwiftData
import SwiftUI

/// Kayıt, aktarım, borç ve ödeme değişikliklerinin geçmişi; her değişiklik geri alınabilir.
struct JournalView: View {
    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]
    @Environment(\.ledger) private var ledger
    @Environment(\.modelContext) private var context
    @State private var undoError: String?

    private struct Day: Identifiable {
        let date: Date
        let entries: [JournalEntry]
        var id: Date { date }
    }

    var body: some View {
        let days = Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.date) }
            .map { Day(date: $0.key, entries: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.date > $1.date }

        List {
            ForEach(days) { day in
                Section(Format.date(day.date)) {
                    ForEach(day.entries) { entry in
                        JournalRow(entry: entry) { undo(entry) }
                    }
                }
            }
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView(
                    "Henüz değişiklik yok",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Kayıt, aktarım, borç ve ödemelerde yaptığınız değişiklikler burada listelenir ve geri alınabilir.")
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
    }

    private func undo(_ entry: JournalEntry) {
        do {
            try Journal.undo(entry, ledger: ledger, context: context)
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
                Button("Geri al", action: undo)
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
        }
    }
}

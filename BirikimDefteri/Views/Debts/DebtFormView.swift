import SwiftData
import SwiftUI

struct DebtFormView: View {
    let debt: Debt?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.ledger) private var ledger

    @State private var personID: UUID?
    @State private var institution: String
    @State private var kind: DebtKind
    @State private var title: String
    @State private var remainingText: String
    @State private var monthlyText: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var note: String
    @State private var paymentDay: Int?
    @State private var isConfirmingDelete = false

    init(debt: Debt? = nil) {
        self.debt = debt
        _personID = State(initialValue: debt?.personID)
        _institution = State(initialValue: debt?.institution ?? "")
        _kind = State(initialValue: debt?.kind ?? .loan)
        _title = State(initialValue: debt?.title ?? "")
        _remainingText = State(initialValue: debt.map { Format.editable($0.remaining) } ?? "")
        _monthlyText = State(initialValue: debt?.monthlyInstallment.map(Format.editable) ?? "")
        _hasDueDate = State(initialValue: debt?.dueDate != nil)
        _dueDate = State(initialValue: debt?.dueDate ?? .now)
        _note = State(initialValue: debt?.note ?? "")
        _paymentDay = State(initialValue: debt?.paymentDay)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tür", selection: $kind) {
                        ForEach(DebtKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TextField("Kurum (ör. Ziraat Bankası)", text: $institution)
                        .textInputAutocapitalization(.words)
                    TextField("Açıklama (ör. İhtiyaç kredisi)", text: $title)
                    if ledger.people.count > 1 || personID == nil {
                        Picker("Kişi", selection: $personID) {
                            if personID == nil { Text("Seçin").tag(UUID?.none) }
                            ForEach(ledger.people) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                }

                Section {
                    DecimalField(title: "Kalan tutar", placeholder: "₺0,00", text: $remainingText)
                    DecimalField(title: "Aylık taksit", placeholder: "Opsiyonel", text: $monthlyText)
                }

                if kind != .creditCard {
                    Section {
                        Picker("Taksit günü", selection: $paymentDay) {
                            Text("Yok").tag(Int?.none)
                            ForEach(1...28, id: \.self) { Text("Her ayın \($0)'i").tag(Optional($0)) }
                        }
                    } footer: {
                        Text("Ödeme hatırlatmaları açıksa her ay bu gün bildirim gelir.")
                    }
                }

                Section {
                    Toggle(kind.dueDateTitle, isOn: $hasDueDate.animation())
                    if hasDueDate {
                        DatePicker(kind.dueDateTitle, selection: $dueDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                }

                Section {
                    TextField("Not", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                } footer: {
                    if let problem {
                        ErrorLabel(message: problem)
                    }
                }

                if debt != nil {
                    Section {
                        Button("Borcu sil", role: .destructive) { isConfirmingDelete = true }
                    }
                }
            }
            .navigationTitle(debt == nil ? "Yeni borç" : "Borcu düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save).disabled(!canSave)
                }
            }
            .keyboardDoneButton()
            .onAppear {
                if personID == nil { personID = ledger.people.first?.id }
            }
            .confirmationDialog("Bu borç silinsin mi?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Borcu sil", role: .destructive) {
                    if let debt {
                        Journal.recordDebt(.deleted, summary: Journal.describe(debt), before: Journal.entry(debt), after: nil, in: context)
                        for payment in ledger.payments(for: debt) { context.delete(payment) }
                        context.delete(debt)
                        try? context.save()
                    }
                    dismiss()
                }
            }
        }
        .lockProtected()
    }

    private var remaining: Decimal? { Format.parseDecimal(remainingText) }
    private var monthly: Decimal? { Format.parseDecimal(monthlyText) }

    private var problem: String? {
        if !remainingText.trimmed.isEmpty, remaining == nil {
            return "Kalan tutar geçerli bir sayı değil."
        }
        if !monthlyText.trimmed.isEmpty, monthly == nil {
            return "Aylık taksit geçerli bir sayı değil."
        }
        if ledger.people.isEmpty {
            return "Önce Ayarlar'dan bir kişi ekleyin."
        }
        return nil
    }

    private var canSave: Bool {
        personID != nil && remaining != nil && problem == nil
    }

    private func save() {
        guard let personID, let remaining, problem == nil else { return }
        let monthly = monthlyText.trimmed.isEmpty ? nil : monthly
        let dueDate = hasDueDate ? Calendar.current.startOfDay(for: dueDate) : nil
        let day = kind == .creditCard ? nil : paymentDay
        if let debt {
            let before = Journal.entry(debt)
            debt.personID = personID
            debt.institution = institution.trimmed
            debt.kind = kind
            debt.title = title.trimmed
            debt.remaining = remaining
            debt.monthlyInstallment = monthly
            debt.dueDate = dueDate
            debt.note = note.trimmed
            debt.paymentDay = day
            debt.updatedAt = .now
            Journal.recordDebt(.edited, summary: Journal.describe(debt), before: before, after: debt, in: context)
        } else {
            let debt = Debt(
                personID: personID, institution: institution.trimmed, kind: kind, title: title.trimmed,
                remaining: remaining, monthlyInstallment: monthly, dueDate: dueDate, note: note.trimmed, paymentDay: day
            )
            context.insert(debt)
            Journal.recordDebt(.added, summary: Journal.describe(debt), before: nil, after: debt, in: context)
        }
        try? context.save()
        dismiss()
    }
}

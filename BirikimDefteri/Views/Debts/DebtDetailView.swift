import SwiftData
import SwiftUI

/// Borcun ayrıntısı: kalan tutar, taksit planı, tahmini bitiş ve ödeme geçmişi.
struct DebtDetailView: View {
    let debtID: UUID

    @Environment(\.ledger) private var ledger
    @Environment(\.modelContext) private var context
    @State private var isEditing = false
    @State private var isPaying = false

    var body: some View {
        if let debt = ledger.debts.first(where: { $0.id == debtID }) {
            content(debt)
        } else {
            ContentUnavailableView("Borç bulunamadı", systemImage: "creditcard")
        }
    }

    private func content(_ debt: Debt) -> some View {
        let payments = ledger.payments(for: debt)
        let plan = DebtPlan.payoff(remaining: debt.remaining, monthly: debt.monthlyInstallment)

        return List {
            Section {
                HStack(spacing: 14) {
                    DebtIcon(kind: debt.kind, institution: debt.institution, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(debt.title.isEmpty ? debt.kind.title : debt.title)
                            .font(.title3.weight(.semibold))
                        Text(debt.institution.isEmpty ? debt.kind.title : "\(debt.institution) · \(debt.kind.title)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Kalan borç") {
                    Text(Format.lira(debt.remaining))
                        .font(.headline)
                        .monospacedDigit()
                }
                if let monthly = debt.monthlyInstallment {
                    LabeledContent("Aylık taksit", value: Format.lira(monthly))
                }
                if let day = debt.paymentDay {
                    LabeledContent("Taksit günü", value: "Her ayın \(day)'i")
                }
                if let dueDate = debt.dueDate {
                    LabeledContent(debt.kind.dueDateTitle, value: Format.date(dueDate))
                }
                if let plan {
                    LabeledContent("Tahmini bitiş", value: "\(plan.months) taksit · \(Format.month(plan.date))")
                }
                if !payments.isEmpty {
                    LabeledContent("Toplam ödenen", value: Format.lira(payments.sum(\.amount)))
                }
            } footer: {
                if plan != nil {
                    Text("Tahmini bitiş, kalan borcun aylık taksite bölünmesiyle bulunur; faiz hesaba katılmaz.")
                }
            }

            Section {
                Button {
                    isPaying = true
                } label: {
                    Label("Ödeme ekle", systemImage: "checkmark.circle.fill")
                }
                .disabled(debt.remaining <= 0)
            }

            Section("Ödeme geçmişi") {
                if payments.isEmpty {
                    Text("Henüz ödeme yok.")
                        .foregroundStyle(.secondary)
                }
                ForEach(payments) { payment in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Format.date(payment.date))
                            if !payment.note.isEmpty {
                                Text(payment.note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(Format.lira(payment.amount))
                            .monospacedDigit()
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Sil", systemImage: "trash", role: .destructive) {
                            delete(payment, from: debt)
                        }
                    }
                }
            }
        }
        .navigationTitle(debt.institution.isEmpty ? "Borç" : debt.institution)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Düzenle") { isEditing = true }
        }
        .sheet(isPresented: $isEditing) {
            DebtFormView(debt: debt)
        }
        .sheet(isPresented: $isPaying) {
            DebtPaymentFormView(debt: debt)
        }
    }

    /// Ödemeyi siler, tutarı kalan borca geri ekler.
    private func delete(_ payment: DebtPayment, from debt: Debt) {
        let before = Journal.PaymentSnapshot(payment: Journal.entry(payment), debt: Journal.entry(debt))
        debt.remaining += payment.amount
        debt.updatedAt = .now
        context.delete(payment)
        Journal.recordPayment(
            .deleted, summary: "Ödeme · \(debt.institution.isEmpty ? debt.kind.title : debt.institution) · \(Format.plainLira(payment.amount))",
            before: before, after: Journal.PaymentSnapshot(payment: nil, debt: Journal.entry(debt)), in: context
        )
        try? context.save()
    }
}

struct DebtPaymentFormView: View {
    let debt: Debt

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var amountText: String
    @State private var date = Date.now
    @State private var note = ""

    init(debt: Debt) {
        self.debt = debt
        let suggested = debt.kind == .creditCard ? debt.remaining : min(debt.monthlyInstallment ?? debt.remaining, debt.remaining)
        _amountText = State(initialValue: Format.editable(suggested))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DecimalField(title: "Ödenen tutar", placeholder: "₺0,00", text: $amountText)
                    DatePicker("Tarih", selection: $date, displayedComponents: .date)
                    TextField("Not", text: $note)
                } footer: {
                    if let problem {
                        ErrorLabel(message: problem)
                    } else if debt.kind == .creditCard, debt.dueDate != nil {
                        Text("Tutar kalan borçtan düşülür; son ödeme tarihi bir ay ileri alınır.")
                    } else {
                        Text("Tutar kalan borçtan düşülür.")
                    }
                }
            }
            .navigationTitle("Ödeme ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save).disabled(amount == nil || problem != nil)
                }
            }
            .keyboardDoneButton()
        }
        .presentationDetents([.medium, .large])
        .lockProtected()
    }

    private var amount: Decimal? { Format.parseDecimal(amountText) }

    private var problem: String? {
        guard !amountText.trimmed.isEmpty else { return nil }
        guard let amount, amount > 0 else { return "Tutar sıfırdan büyük bir sayı olmalı." }
        return amount > debt.remaining ? "Tutar kalan borçtan (\(Format.lira(debt.remaining))) fazla olamaz." : nil
    }

    private func save() {
        guard let amount, problem == nil else { return }
        let before = Journal.PaymentSnapshot(payment: nil, debt: Journal.entry(debt))
        let payment = DebtPayment(debtID: debt.id, amount: amount, date: Calendar.current.startOfDay(for: date), note: note.trimmed)
        context.insert(payment)
        debt.remaining = max(debt.remaining - amount, 0)
        if debt.kind == .creditCard, let dueDate = debt.dueDate {
            debt.dueDate = Calendar.current.date(byAdding: .month, value: 1, to: dueDate)
        }
        debt.updatedAt = .now
        Journal.recordPayment(
            .added, summary: "Ödeme · \(debt.institution.isEmpty ? debt.kind.title : debt.institution) · \(Format.plainLira(amount))",
            before: before, after: Journal.PaymentSnapshot(payment: Journal.entry(payment), debt: Journal.entry(debt)), in: context
        )
        try? context.save()
        dismiss()
    }
}

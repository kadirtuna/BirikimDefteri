import SwiftData
import SwiftUI

/// Bir aktarımı sayfa (sheet) olarak açmak için kimlik sarmalayıcısı.
struct TransferRef: Identifiable {
    let id: UUID
}

/// Varlığı maliyetiyle birlikte bir yerden başka bir yere taşır. İki kayıt olarak saklanır: çıkış ve giriş.
struct TransferFormView: View {
    let transferID: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.ledger) private var ledger

    @State private var assetID: UUID?
    @State private var personID: UUID?
    @State private var fromID: UUID?
    @State private var toID: UUID?
    @State private var quantityText = ""
    @State private var date = Date.now
    @State private var note = ""
    @State private var outID = UUID()
    @State private var inID = UUID()
    @State private var draftTransferID = UUID()
    @State private var createdAt = Date.now
    @State private var isLoaded = false
    @State private var isConfirmingDelete = false
    @State private var deleteError: String?

    private let prefill: (assetID: UUID?, personID: UUID?, fromID: UUID?)

    /// Yeni aktarım için ürün, kişi ve çıkış yeri önceden seçilebilir (ör. bir kaydın "Aktar" menüsünden).
    init(transferID: UUID? = nil, assetID: UUID? = nil, personID: UUID? = nil, fromID: UUID? = nil) {
        self.transferID = transferID
        self.prefill = (assetID, personID, fromID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Ürün", selection: $assetID) {
                        if assetID == nil { Text("Seçin").tag(UUID?.none) }
                        ForEach(ledger.assets) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Kişi", selection: $personID) {
                        if personID == nil { Text("Seçin").tag(UUID?.none) }
                        ForEach(ledger.people) { Text($0.name).tag(Optional($0.id)) }
                    }
                }

                Section {
                    Picker("Nereden", selection: $fromID) {
                        if fromID == nil { Text("Seçin").tag(UUID?.none) }
                        ForEach(ledger.locations) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Nereye", selection: $toID) {
                        if toID == nil { Text("Seçin").tag(UUID?.none) }
                        ForEach(ledger.locations) { Text($0.name).tag(Optional($0.id)) }
                    }
                } footer: {
                    Text("Aktarım kâr ya da zarar doğurmaz; ürün ortalama maliyetiyle birlikte taşınır. Yeni bir yer için Ayarlar > Saklama yerleri.")
                }

                Section {
                    DecimalField(title: "Miktar", placeholder: "0", text: $quantityText, suffix: asset?.unit.symbol)
                    if let available, available > 0 {
                        Button("Tümünü aktar (\(Format.quantity(available, unit: asset?.unit ?? .piece)))") {
                            quantityText = Format.editable(available)
                        }
                    }
                } footer: {
                    if let available, let asset {
                        Text("Bu kişi ve yerde mevcut: \(Format.quantity(available, unit: asset.unit))")
                    }
                }

                Section {
                    DatePicker("Tarih", selection: $date, displayedComponents: .date)
                    TextField("Not", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                } footer: {
                    if let problem { ErrorLabel(message: problem) }
                }

                if transferID != nil {
                    Section {
                        Button("Aktarımı sil", role: .destructive, action: requestDelete)
                    }
                }
            }
            .navigationTitle(transferID == nil ? "Yeni aktarım" : "Aktarım")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save).disabled(legs == nil || problem != nil)
                }
            }
            .keyboardDoneButton()
            .onAppear(perform: load)
            .confirmationDialog("Bu aktarım silinsin mi?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Aktarımı sil", role: .destructive, action: delete)
            }
            .alert("Aktarım silinemedi", isPresented: Binding(isPresent: $deleteError)) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
        }
        .lockProtected()
    }

    // MARK: Hesaplananlar

    private var calculator: PortfolioCalculator { ledger.calculator }
    private var asset: AssetInfo? { assetID.flatMap { calculator.assets[$0] } }
    private var quantity: Decimal? { Format.parseDecimal(quantityText) }
    private var day: Date { Calendar.current.startOfDay(for: date) }

    private var outProbe: TransactionInfo? {
        guard let assetID, let personID, let fromID else { return nil }
        return TransactionInfo(
            id: outID, kind: .transferOut, personID: personID, assetID: assetID, locationID: fromID,
            quantity: quantity ?? 0, unitPrice: 0, date: day, createdAt: createdAt, transferID: transferID ?? draftTransferID
        )
    }

    private var available: Decimal? {
        outProbe.map { calculator.availableQuantity(before: $0) }
    }

    private var legs: [TransactionInfo]? {
        guard var out = outProbe, let toID, let quantity else { return nil }
        out.unitPrice = calculator.averageCost(before: out) ?? 0
        let incoming = TransactionInfo(
            id: inID, kind: .transferIn, personID: out.personID, assetID: out.assetID, locationID: toID,
            quantity: quantity, unitPrice: out.unitPrice, date: day, createdAt: createdAt.addingTimeInterval(0.001),
            transferID: out.transferID
        )
        return [out, incoming]
    }

    private var problem: String? {
        if !quantityText.trimmed.isEmpty, quantity == nil { return "Miktar geçerli bir sayı değil." }
        if let fromID, fromID == toID { return "Nereden ve nereye aynı yer olamaz." }
        guard let legs else { return nil }
        guard let error = calculator.validate(legs) else { return nil }
        if case .insufficientQuantity = error, let available, let asset {
            return available > 0
                ? "Aktarım eldeki miktarı aşıyor. Bu kişi ve yerde en fazla \(Format.quantity(available, unit: asset.unit)) var."
                : "Bu kişi ve yerde o tarihte aktarılacak miktar yok."
        }
        return error.message(unit: asset?.unit)
    }

    // MARK: Eylemler

    private func load() {
        guard !isLoaded else { return }
        isLoaded = true
        guard let transferID else {
            assetID = prefill.assetID
            personID = prefill.personID ?? RecentChoices.person(among: ledger.people.map(\.id)) ?? ledger.people.first?.id
            fromID = prefill.fromID ?? RecentChoices.location(among: ledger.locations.map(\.id)) ?? ledger.locations.first?.id
            return
        }
        let legs = ledger.transferLegs(transferID)
        guard let out = legs.out else { return }
        assetID = out.assetID
        personID = out.personID
        fromID = out.locationID
        toID = legs.in?.locationID
        quantityText = Format.editable(out.quantity)
        date = out.date
        note = out.note
        outID = out.id
        inID = legs.in?.id ?? UUID()
        createdAt = out.createdAt
    }

    private func save() {
        guard let legs, problem == nil, let destination = toID else { return }
        let summary = Journal.describe(legs[0], ledger: ledger, destination: destination)
        let existing = [ledger.transaction(outID), ledger.transaction(inID)].compactMap { $0 }
        let before = existing.map(Journal.entry)
        var saved: [TransactionRecord] = []
        for info in legs {
            if let record = ledger.transaction(info.id) {
                record.update(from: info, note: note.trimmed)
                saved.append(record)
            } else {
                let record = TransactionRecord(info: info, note: note.trimmed)
                context.insert(record)
                saved.append(record)
            }
        }
        Journal.recordTransactions(existing.isEmpty ? .added : .edited, summary: summary, before: before, after: saved, in: context)
        try? context.save()
        Haptics.success()
        dismiss()
    }

    private func requestDelete() {
        if let error = calculator.validateDeletion(of: [outID, inID]) {
            deleteError = error.message(unit: asset?.unit)
        } else {
            isConfirmingDelete = true
        }
    }

    private func delete() {
        let records = [ledger.transaction(outID), ledger.transaction(inID)].compactMap { $0 }
        if let out = records.first(where: { $0.kind == .transferOut }), let destination = toID {
            Journal.recordTransactions(
                .deleted, summary: Journal.describe(out.info, ledger: ledger, destination: destination),
                before: records, after: [], in: context
            )
        }
        records.forEach(context.delete)
        try? context.save()
        Haptics.warning()
        dismiss()
    }
}

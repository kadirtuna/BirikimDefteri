import SwiftData
import SwiftUI

struct TransactionFormView: View {
    /// Kişi ve yer seçicilerindeki "Yeni…" satırının etiketi.
    private static let addNewID = UUID()

    let record: TransactionRecord?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.ledger) private var ledger

    @State private var kind: TransactionKind
    @State private var assetID: UUID?
    @State private var personID: UUID?
    @State private var locationID: UUID?
    @State private var quantityText: String
    @State private var unitPriceText: String
    @State private var date: Date
    @State private var note: String
    @State private var draftID = UUID()
    @State private var draftCreatedAt = Date.now
    @State private var isAddingPerson = false
    @State private var newPersonName = ""
    @State private var isAddingLocation = false
    @State private var isConfirmingDelete = false
    @State private var deleteError: String?

    init(record: TransactionRecord? = nil, assetID: UUID? = nil) {
        self.record = record
        _kind = State(initialValue: record?.kind ?? .buy)
        _assetID = State(initialValue: record?.assetID ?? assetID)
        _personID = State(initialValue: record?.personID)
        _locationID = State(initialValue: record?.locationID)
        _quantityText = State(initialValue: record.map { Format.editable($0.quantity) } ?? "")
        let editablePrice = record.flatMap { $0.assetID == AssetInfo.liraID ? nil : Format.editable($0.unitPrice) }
        _unitPriceText = State(initialValue: editablePrice ?? "")
        _date = State(initialValue: record?.date ?? .now)
        _note = State(initialValue: record?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("İşlem türü", selection: $kind) {
                        ForEach(TransactionKind.tradeKinds) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Picker("Ürün", selection: $assetID) {
                        if assetID == nil { Text("Seçin").tag(UUID?.none) }
                        ForEach(ledger.assets) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Kişi", selection: $personID) {
                        if personID == nil { Text("Seçin").tag(UUID?.none) }
                        ForEach(ledger.people) { Text($0.name).tag(Optional($0.id)) }
                        Divider()
                        Label("Yeni kişi…", systemImage: "plus").tag(Optional(Self.addNewID))
                    }
                    Picker("Yer", selection: $locationID) {
                        if locationID == nil { Text("Seçin").tag(UUID?.none) }
                        ForEach(ledger.locations) { Text($0.name).tag(Optional($0.id)) }
                        Divider()
                        Label("Yeni saklama yeri…", systemImage: "plus").tag(Optional(Self.addNewID))
                    }
                }

                Section {
                    DecimalField(title: "Miktar", placeholder: "0", text: $quantityText, suffix: asset?.unit.symbol)
                    if !isLira {
                        DecimalField(
                            title: "Birim fiyat",
                            placeholder: currentPrice.map(Format.lira) ?? "₺0,00",
                            text: $unitPriceText
                        )
                    }
                } footer: {
                    if let availableText {
                        Text(availableText)
                    } else if !isLira, currentPrice != nil {
                        Text("Birim fiyatı boş bırakırsanız güncel fiyat kullanılır.")
                    }
                }

                Section {
                    DatePicker("Tarih", selection: $date, displayedComponents: .date)
                    TextField("Not", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section {
                    LabeledContent("Toplam") {
                        Text(total.map(Format.lira) ?? "—")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                } footer: {
                    if let problem {
                        ErrorLabel(message: problem)
                    }
                }

                if record != nil {
                    Section {
                        Button("İşlemi sil", role: .destructive, action: requestDelete)
                    }
                }
            }
            .navigationTitle(record == nil ? "Yeni işlem" : "İşlemi düzenle")
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
                if locationID == nil { locationID = ledger.locations.first?.id }
            }
            .onChange(of: personID) { old, new in
                if new == Self.addNewID {
                    personID = old
                    newPersonName = ""
                    isAddingPerson = true
                }
            }
            .onChange(of: locationID) { old, new in
                if new == Self.addNewID {
                    locationID = old
                    isAddingLocation = true
                }
            }
            .alert("Yeni kişi", isPresented: $isAddingPerson) {
                TextField("Ad", text: $newPersonName)
                Button("Vazgeç", role: .cancel) {}
                Button("Ekle") {
                    if let person = Store.addPerson(named: newPersonName, in: context) {
                        personID = person.id
                    }
                }
            }
            .sheet(isPresented: $isAddingLocation) {
                LocationEditorView { location in
                    locationID = location.id
                }
            }
            .confirmationDialog("Bu işlem silinsin mi?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("İşlemi sil", role: .destructive, action: delete)
            }
            .alert("İşlem silinemedi", isPresented: Binding(isPresent: $deleteError)) {
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
    private var isLira: Bool { asset?.unit == .lira }
    private var currentPrice: Decimal? { assetID.flatMap(calculator.price(of:)) }
    private var quantity: Decimal? { Format.parseDecimal(quantityText) }
    private var enteredUnitPrice: Decimal? { Format.parseDecimal(unitPriceText) }

    private var unitPrice: Decimal? {
        if isLira { return 1 }
        if unitPriceText.trimmed.isEmpty { return currentPrice }
        return enteredUnitPrice
    }

    private var total: Decimal? {
        guard let quantity, let unitPrice else { return nil }
        return quantity * unitPrice
    }

    private var draft: TransactionInfo? {
        guard let assetID, let personID, let locationID, let quantity, let unitPrice,
              personID != Self.addNewID, locationID != Self.addNewID
        else { return nil }
        return TransactionInfo(
            id: record?.id ?? draftID,
            kind: kind,
            personID: personID,
            assetID: assetID,
            locationID: locationID,
            quantity: quantity,
            unitPrice: unitPrice,
            date: Calendar.current.startOfDay(for: date),
            createdAt: record?.createdAt ?? draftCreatedAt
        )
    }

    private var problem: String? {
        if !quantityText.trimmed.isEmpty, quantity == nil {
            return "Miktar geçerli bir sayı değil."
        }
        if !isLira, !unitPriceText.trimmed.isEmpty, enteredUnitPrice == nil {
            return "Birim fiyat geçerli bir sayı değil."
        }
        if asset != nil, !isLira, unitPriceText.trimmed.isEmpty, currentPrice == nil {
            return "Bu ürünün güncel fiyatı yok; birim fiyatı girin."
        }
        guard let draft else { return nil }
        return calculator.validate(draft)?.message(unit: asset?.unit)
    }

    private var canSave: Bool { draft != nil && problem == nil }

    private var availableText: String? {
        guard kind == .sell, let asset, let personID, let locationID,
              personID != Self.addNewID, locationID != Self.addNewID
        else { return nil }
        let probe = TransactionInfo(
            id: record?.id ?? draftID, kind: .sell, personID: personID, assetID: asset.id, locationID: locationID,
            quantity: 0, unitPrice: 0, date: Calendar.current.startOfDay(for: date),
            createdAt: record?.createdAt ?? draftCreatedAt
        )
        return "Bu kişi ve yerde mevcut: \(Format.quantity(calculator.availableQuantity(before: probe), unit: asset.unit))"
    }

    // MARK: Eylemler

    private func save() {
        guard let draft, problem == nil else { return }
        let summary = Journal.describe(draft, ledger: ledger)
        if let record {
            let before = [Journal.entry(record)]
            record.update(from: draft, note: note.trimmed)
            Journal.recordTransactions(.edited, summary: summary, before: before, after: [record], in: context)
        } else {
            let record = TransactionRecord(info: draft, note: note.trimmed)
            context.insert(record)
            Journal.recordTransactions(.added, summary: summary, before: [TransactionRecord](), after: [record], in: context)
        }
        try? context.save()
        dismiss()
    }

    private func requestDelete() {
        guard let record else { return }
        if let error = calculator.validateDeletion(of: record.id) {
            deleteError = error.message(unit: asset?.unit)
        } else {
            isConfirmingDelete = true
        }
    }

    private func delete() {
        guard let record else { return }
        Journal.recordTransactions(.deleted, summary: Journal.describe(record.info, ledger: ledger), before: [record], after: [], in: context)
        context.delete(record)
        try? context.save()
        dismiss()
    }
}

import SwiftData
import SwiftUI

// Kişi, saklama yeri ve ürün yönetimi. Kayda bağlı olanlar silinemez; Türk lirası hiç silinemez.

struct PeopleView: View {
    @Environment(\.ledger) private var ledger
    @Environment(\.modelContext) private var context
    @State private var renaming: Person?
    @State private var isAdding = false
    @State private var name = ""
    @State private var blockedMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(ledger.people) { person in
                    Button {
                        name = person.name
                        renaming = person
                    } label: {
                        Text(person.name).foregroundStyle(Color.primary)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Sil", systemImage: "trash", role: .destructive) { delete(person) }
                    }
                }
            } footer: {
                Text("İşlem veya borç kaydı olan kişiler silinemez. Adı değiştirmek için dokunun.")
            }
        }
        .navigationTitle("Kişiler")
        .toolbar {
            Button {
                name = ""
                isAdding = true
            } label: {
                Label("Kişi ekle", systemImage: "plus")
            }
        }
        .alert("Yeni kişi", isPresented: $isAdding) {
            TextField("Ad", text: $name)
            Button("Vazgeç", role: .cancel) {}
            Button("Ekle") { Store.addPerson(named: name, in: context) }
        }
        .alert("Kişiyi yeniden adlandır", isPresented: Binding(isPresent: $renaming)) {
            TextField("Ad", text: $name)
            Button("Vazgeç", role: .cancel) {}
            Button("Kaydet") {
                if let renaming, !name.trimmed.isEmpty {
                    renaming.name = name.trimmed
                    try? context.save()
                }
            }
        }
        .alert("Silinemez", isPresented: Binding(isPresent: $blockedMessage)) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(blockedMessage ?? "")
        }
    }

    private func delete(_ person: Person) {
        guard !ledger.isInUse(person) else {
            blockedMessage = "\(person.name) için kayıtlı işlem veya borç var. Önce onları silin ya da başka kişiye aktarın."
            return
        }
        Journal.recordDeletion(.person, summary: Journal.describe(person), snapshot: .init(people: [Journal.entry(person)]), in: context)
        context.delete(person)
        try? context.save()
    }
}

struct LocationsView: View {
    @Environment(\.ledger) private var ledger
    @Environment(\.modelContext) private var context
    @State private var editing: Location?
    @State private var isAdding = false
    @State private var blockedMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(ledger.locations) { location in
                    Button {
                        editing = location
                    } label: {
                        Label {
                            LabeledContent(location.name, value: location.kind.title)
                        } icon: {
                            PlaceIcon(location: location.info, size: 28)
                        }
                    }
                    .foregroundStyle(Color.primary)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Sil", systemImage: "trash", role: .destructive) { delete(location) }
                    }
                }
            } footer: {
                Text("İşlem kaydı olan yerler silinemez.")
            }
        }
        .navigationTitle("Saklama yerleri")
        .toolbar {
            Button {
                isAdding = true
            } label: {
                Label("Yer ekle", systemImage: "plus")
            }
        }
        .sheet(item: $editing) { location in
            LocationEditorView(location: location)
        }
        .sheet(isPresented: $isAdding) {
            LocationEditorView()
        }
        .alert("Silinemez", isPresented: Binding(isPresent: $blockedMessage)) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(blockedMessage ?? "")
        }
    }

    private func delete(_ location: Location) {
        guard !ledger.isInUse(location) else {
            blockedMessage = "\(location.name) için kayıtlı işlem var. Önce o işlemleri silin ya da başka yere taşıyın."
            return
        }
        Journal.recordDeletion(.location, summary: Journal.describe(location),
                               snapshot: .init(locations: [Journal.entry(location)]), in: context)
        context.delete(location)
        try? context.save()
    }
}

struct LocationEditorView: View {
    let location: Location?
    var onCreate: ((Location) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name: String
    @State private var kind: LocationKind

    init(location: Location? = nil, onCreate: ((Location) -> Void)? = nil) {
        self.location = location
        self.onCreate = onCreate
        _name = State(initialValue: location?.name ?? "")
        _kind = State(initialValue: location?.kind ?? .bank)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Ad (ör. Ziraat Bankası, Kasa)", text: $name)
                    .textInputAutocapitalization(.words)
                if kind == .bank {
                    InstitutionMatchRow(name: name)
                }
                Picker("Tür", selection: $kind) {
                    ForEach(LocationKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .navigationTitle(location == nil ? "Yeni saklama yeri" : "Saklama yeri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save).disabled(name.trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .lockProtected()
    }

    private func save() {
        if let location {
            location.name = name.trimmed
            location.kind = kind
        } else {
            let location = Location(name: name.trimmed, kind: kind)
            context.insert(location)
            onCreate?(location)
        }
        try? context.save()
        dismiss()
    }
}

struct AssetsView: View {
    @Environment(\.ledger) private var ledger
    @Environment(\.modelContext) private var context
    @State private var editing: Asset?
    @State private var isAdding = false
    @State private var blockedMessage: String?

    var body: some View {
        List {
            ForEach(AssetCategory.allCases) { category in
                let assets = ledger.assets.filter { $0.category == category }
                if !assets.isEmpty {
                    Section(category.title) {
                        ForEach(assets) { asset in
                            Button {
                                editing = asset
                            } label: {
                                LabeledContent {
                                    Text(asset.unit.symbol)
                                } label: {
                                    HStack(spacing: 10) {
                                        AssetIcon(asset: asset.info, size: 32)
                                        Text(asset.name)
                                        if asset.isLira {
                                            Image(systemName: "lock.fill")
                                                .font(.caption)
                                                .foregroundStyle(Color.secondary)
                                                .accessibilityLabel("Silinemez")
                                        }
                                    }
                                }
                            }
                            .foregroundStyle(Color.primary)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("Sil", systemImage: "trash", role: .destructive) { delete(asset) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Ürünler")
        .toolbar {
            Button {
                isAdding = true
            } label: {
                Label("Ürün ekle", systemImage: "plus")
            }
        }
        .sheet(item: $editing) { asset in
            AssetEditorView(asset: asset)
        }
        .sheet(isPresented: $isAdding) {
            AssetEditorView()
        }
        .alert("Silinemez", isPresented: Binding(isPresent: $blockedMessage)) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(blockedMessage ?? "")
        }
    }

    private func delete(_ asset: Asset) {
        if asset.isLira {
            blockedMessage = "Türk lirası silinemez."
            return
        }
        guard !ledger.isInUse(asset) else {
            blockedMessage = "\(asset.name) için kayıtlı işlem var. Önce o işlemleri silin."
            return
        }
        let prices = ledger.prices.filter { $0.assetID == asset.id }
        Journal.recordDeletion(.asset, summary: Journal.describe(asset, priceCount: prices.count),
                               snapshot: .init(assets: [Journal.entry(asset)], prices: prices.map(Journal.entry)), in: context)
        prices.forEach(context.delete)
        context.delete(asset)
        try? context.save()
    }
}

struct AssetEditorView: View {
    let asset: Asset?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.ledger) private var ledger
    @State private var name: String
    @State private var unit: AssetUnit
    @State private var category: AssetCategory

    init(asset: Asset? = nil) {
        self.asset = asset
        _name = State(initialValue: asset?.name ?? "")
        _unit = State(initialValue: asset?.unit ?? .piece)
        _category = State(initialValue: asset?.category ?? .other)
    }

    var body: some View {
        let isLira = asset?.isLira ?? false
        let isInUse = asset.map(ledger.isInUse) ?? false

        NavigationStack {
            Form {
                Section {
                    TextField("Ad (ör. Reşat altını)", text: $name)
                }
                Section {
                    Picker("Birim", selection: $unit) {
                        ForEach(AssetUnit.allCases) { Text($0.symbol).tag($0) }
                    }
                    .disabled(isLira || isInUse)
                    Picker("Tür", selection: $category) {
                        ForEach(AssetCategory.allCases) { Text($0.title).tag($0) }
                    }
                    .disabled(isLira)
                } footer: {
                    if isLira {
                        Text("Türk lirasının birimi ve türü değiştirilemez; fiyatı her zaman ₺1'dir.")
                    } else if isInUse {
                        Text("Bu ürün için kayıtlı işlem olduğundan birimi değiştirilemez.")
                    } else if unit == .lira {
                        Text("Birimi ₺ olan ürünlerin fiyatı her zaman ₺1 kabul edilir.")
                    }
                }
            }
            .navigationTitle(asset == nil ? "Yeni ürün" : "Ürün")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save).disabled(name.trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .lockProtected()
    }

    private func save() {
        if let asset {
            asset.name = name.trimmed
            if !asset.isLira {
                asset.unit = unit
                asset.category = category
            }
        } else {
            let sortOrder = (ledger.assets.map(\.sortOrder).max() ?? 0) + 1
            context.insert(Asset(name: name.trimmed, unit: unit, category: category, sortOrder: sortOrder))
        }
        try? context.save()
        dismiss()
    }
}

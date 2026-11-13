import CryptoKit
import Foundation
import SwiftData

// Telefon ile web arasında eşitleme. Her kayıt Firestore'da `users/{uid}/items/{tür}_{kimlik}` belgesidir:
// `type`, `data` (yedek dosyasındaki biçimde JSON), `updatedAt` (ms, istemci saati), `deleted` ve sunucunun yazdığı
// `serverTime`. Aynı kayıt iki yerde değişirse son eşitlenen kazanır. Telefon önce kendi değişikliklerini gönderir,
// sonra son çekmeden beri değişen belgeleri alır. Üçüncü taraf paket yok: Firestore REST API kullanılır.

enum SyncType: String, CaseIterable, Sendable {
    case person, location, asset, price, transaction, debt, payment, goal, journal
}

/// Bir kaydın eşitlemedeki hâli.
struct SyncRecord: Equatable, Sendable {
    let id: String
    let type: SyncType
    let data: String

    var hash: String {
        SHA256.hash(data: Data(data.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    static func id(_ type: SyncType, _ uuid: UUID) -> String { "\(type.rawValue)_\(uuid.uuidString)" }
}

/// Buluttan gelen belge.
struct RemoteItem: Equatable, Sendable {
    let id: String
    let type: SyncType?
    let data: String
    let updatedAt: Int64
    let deleted: Bool
}

/// Son başarılı eşitlemeden kalan durum: her kaydın gönderilen/alınan hâlinin özeti.
struct SyncState: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        /// Kaydın verisinin özeti; silinmiş kayıtta nil.
        var hash: String?
        var updatedAt: Int64
    }

    var uid: String?
    /// Son çekmenin sunucu zamanı (RFC 3339).
    var cursor: String?
    var records: [String: Entry] = [:]
}

/// Eşitlemenin saf kısmı: neyin gönderileceği, neyin uygulanacağı. Birim testlidir.
enum SyncPlanner {
    struct Push: Equatable, Sendable {
        let id: String
        let type: SyncType
        /// nil: silme işareti.
        let data: String?
    }

    /// Son eşitlemeden beri değişen, eklenen ve silinen kayıtlar.
    static func pushes(local: [String: SyncRecord], state: SyncState) -> [Push] {
        var result: [Push] = []
        for record in local.values.sorted(by: { $0.id < $1.id }) where state.records[record.id]?.hash != record.hash {
            result.append(Push(id: record.id, type: record.type, data: record.data))
        }
        for (id, entry) in state.records.sorted(by: { $0.key < $1.key }) where entry.hash != nil && local[id] == nil {
            guard let type = type(of: id) else { continue }
            result.append(Push(id: id, type: type, data: nil))
        }
        return result
    }

    /// Bilinen hâlden daha yeni olan uzak belgeler.
    static func incoming(_ remote: [RemoteItem], state: SyncState) -> [RemoteItem] {
        remote.filter { $0.type != nil && $0.updatedAt > (state.records[$0.id]?.updatedAt ?? Int64.min) }
    }

    /// Kayıtların yarısından fazlasını birden silecek bir değişiklik büyük olasılıkla hatadır; uygulanmaz.
    static func isMassDeletion(deletions: Int, total: Int) -> Bool {
        deletions > 20 && deletions * 2 > total
    }

    static func type(of id: String) -> SyncType? {
        id.split(separator: "_", maxSplits: 1).first.flatMap { SyncType(rawValue: String($0)) }
    }
}

/// Kayıtların JSON biçimi; yedek dosyasıyla aynı tarih biçimi, anahtarlar sıralı (aynı veri aynı metni üretsin).
enum SyncCoding {
    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func encode<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(dateStyle))
        }
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func decode<T: Decodable>(_ type: T.Type, from text: String) -> T? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = try? Date(text, strategy: dateStyle) { return date }
            if let date = try? Date(text, strategy: .iso8601) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Geçersiz tarih: \(text)")
        }
        return try? decoder.decode(type, from: Data(text.utf8))
    }
}

/// İşlem geçmişi kaydının eşitlemedeki biçimi.
struct JournalSyncEntry: Codable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var action: String
    var entity: String
    var summary: String
    var before: String?
    var after: String?
    var isUndone: Bool
}

// MARK: - Yerel kayıtlar

@MainActor
enum SyncSnapshot {
    /// Depodaki her kaydın eşitleme biçimi.
    static func make(from context: ModelContext) -> [String: SyncRecord] {
        let ledger = Ledger.fetch(from: context)
        let journal = (try? context.fetch(FetchDescriptor<JournalEntry>())) ?? []
        var result: [String: SyncRecord] = [:]
        func add<T: Encodable>(_ type: SyncType, _ id: UUID, _ entry: T) {
            guard let data = SyncCoding.encode(entry) else { return }
            let record = SyncRecord(id: SyncRecord.id(type, id), type: type, data: data)
            result[record.id] = record
        }
        ledger.people.forEach { add(.person, $0.id, Journal.entry($0)) }
        ledger.locations.forEach { add(.location, $0.id, Journal.entry($0)) }
        ledger.assets.forEach { add(.asset, $0.id, Journal.entry($0)) }
        ledger.prices.forEach { add(.price, $0.id, Journal.entry($0)) }
        ledger.transactions.forEach { add(.transaction, $0.id, Journal.entry($0)) }
        ledger.debts.forEach { add(.debt, $0.id, Journal.entry($0)) }
        ledger.payments.forEach { add(.payment, $0.id, Journal.entry($0)) }
        ledger.goals.forEach { add(.goal, $0.id, Journal.entry($0)) }
        journal.forEach {
            add(.journal, $0.id, JournalSyncEntry(
                id: $0.id, date: $0.date, action: $0.actionRaw, entity: $0.entityRaw, summary: $0.summary,
                before: $0.beforeJSON, after: $0.afterJSON, isUndone: $0.isUndone
            ))
        }
        return result
    }
}

/// Buluttan gelen kayıtları kimliğe göre ekler, günceller ya da siler.
@MainActor
enum SyncApplier {
    static func apply(_ items: [RemoteItem], in context: ModelContext) throws {
        for item in items {
            guard let type = item.type, let uuid = UUID(uuidString: String(item.id.dropFirst(type.rawValue.count + 1))) else {
                continue
            }
            if item.deleted {
                delete(type, uuid, in: context)
            } else {
                upsert(type, uuid, data: item.data, in: context)
            }
        }
        try context.save()
    }

    private static func first<T: PersistentModel>(_ type: T.Type, in context: ModelContext, where match: (T) -> Bool) -> T? {
        ((try? context.fetch(FetchDescriptor<T>())) ?? []).first(where: match)
    }

    private static func delete(_ type: SyncType, _ id: UUID, in context: ModelContext) {
        let object: (any PersistentModel)? = switch type {
        case .person: first(Person.self, in: context) { $0.id == id }
        case .location: first(Location.self, in: context) { $0.id == id }
        case .asset: first(Asset.self, in: context) { $0.id == id }
        case .price: first(PricePoint.self, in: context) { $0.id == id }
        case .transaction: first(TransactionRecord.self, in: context) { $0.id == id }
        case .debt: first(Debt.self, in: context) { $0.id == id }
        case .payment: first(DebtPayment.self, in: context) { $0.id == id }
        case .goal: first(Goal.self, in: context) { $0.id == id }
        case .journal: first(JournalEntry.self, in: context) { $0.id == id }
        }
        if let object { context.delete(object) }
    }

    private static func upsert(_ type: SyncType, _ id: UUID, data: String, in context: ModelContext) {
        switch type {
        case .person:
            guard let entry = SyncCoding.decode(BackupFile.PersonEntry.self, from: data) else { return }
            if let person = first(Person.self, in: context, where: { $0.id == id }) {
                person.name = entry.name
                person.createdAt = entry.createdAt
            } else {
                context.insert(Person(id: id, name: entry.name, createdAt: entry.createdAt))
            }
        case .location:
            guard let entry = SyncCoding.decode(BackupFile.LocationEntry.self, from: data) else { return }
            if let location = first(Location.self, in: context, where: { $0.id == id }) {
                location.name = entry.name
                location.kindRaw = entry.kind.rawValue
                location.createdAt = entry.createdAt
            } else {
                context.insert(Location(id: id, name: entry.name, kind: entry.kind, createdAt: entry.createdAt))
            }
        case .asset:
            guard let entry = SyncCoding.decode(BackupFile.AssetEntry.self, from: data) else { return }
            if let asset = first(Asset.self, in: context, where: { $0.id == id }) {
                asset.name = entry.name
                asset.unitRaw = entry.unit.rawValue
                asset.categoryRaw = entry.category.rawValue
                asset.sortOrder = entry.sortOrder
                asset.createdAt = entry.createdAt
            } else {
                context.insert(Asset(id: id, name: entry.name, unit: entry.unit, category: entry.category,
                                     sortOrder: entry.sortOrder, createdAt: entry.createdAt))
            }
        case .price:
            guard let entry = SyncCoding.decode(BackupFile.PriceEntry.self, from: data),
                  let price = Decimal(storageText: entry.price) else { return }
            if let point = first(PricePoint.self, in: context, where: { $0.id == id }) {
                point.assetID = entry.assetID
                point.priceText = price.storageText
                point.date = entry.date
                point.locationID = entry.locationID
            } else {
                context.insert(PricePoint(id: id, assetID: entry.assetID, price: price, date: entry.date, locationID: entry.locationID))
            }
        case .transaction:
            guard let entry = SyncCoding.decode(BackupFile.TransactionEntry.self, from: data),
                  let quantity = Decimal(storageText: entry.quantity), let unitPrice = Decimal(storageText: entry.unitPrice)
            else { return }
            let info = TransactionInfo(
                id: id, kind: entry.kind, personID: entry.personID, assetID: entry.assetID, locationID: entry.locationID,
                quantity: quantity, unitPrice: unitPrice, date: entry.date, createdAt: entry.createdAt, transferID: entry.transferID
            )
            if let record = first(TransactionRecord.self, in: context, where: { $0.id == id }) {
                record.update(from: info, note: entry.note)
                record.createdAt = entry.createdAt
            } else {
                context.insert(TransactionRecord(info: info, note: entry.note))
            }
        case .debt:
            guard let entry = SyncCoding.decode(BackupFile.DebtEntry.self, from: data),
                  let remaining = Decimal(storageText: entry.remaining) else { return }
            let monthly = entry.monthlyInstallment.flatMap { Decimal(storageText: $0) }
            if let debt = first(Debt.self, in: context, where: { $0.id == id }) {
                debt.personID = entry.personID
                debt.institution = entry.institution
                debt.kind = entry.kind
                debt.title = entry.title
                debt.remaining = remaining
                debt.monthlyInstallment = monthly
                debt.dueDate = entry.dueDate
                debt.note = entry.note
                debt.updatedAt = entry.updatedAt
                debt.paymentDay = entry.paymentDay
            } else {
                context.insert(Debt(
                    id: id, personID: entry.personID, institution: entry.institution, kind: entry.kind, title: entry.title,
                    remaining: remaining, monthlyInstallment: monthly, dueDate: entry.dueDate, note: entry.note,
                    updatedAt: entry.updatedAt, paymentDay: entry.paymentDay
                ))
            }
        case .payment:
            guard let entry = SyncCoding.decode(BackupFile.DebtPaymentEntry.self, from: data),
                  let amount = Decimal(storageText: entry.amount) else { return }
            if let payment = first(DebtPayment.self, in: context, where: { $0.id == id }) {
                payment.debtID = entry.debtID
                payment.amountText = amount.storageText
                payment.date = entry.date
                payment.note = entry.note
                payment.createdAt = entry.createdAt
            } else {
                context.insert(DebtPayment(id: id, debtID: entry.debtID, amount: amount, date: entry.date, note: entry.note,
                                           createdAt: entry.createdAt))
            }
        case .goal:
            guard let entry = SyncCoding.decode(BackupFile.GoalEntry.self, from: data),
                  let target = Decimal(storageText: entry.target) else { return }
            if let goal = first(Goal.self, in: context, where: { $0.id == id }) {
                goal.title = entry.title
                goal.kind = entry.kind
                goal.target = target
                goal.assetID = entry.assetID
                goal.personID = entry.personID
                goal.createdAt = entry.createdAt
            } else {
                context.insert(Goal(id: id, title: entry.title, kind: entry.kind, target: target, assetID: entry.assetID,
                                    personID: entry.personID, createdAt: entry.createdAt))
            }
        case .journal:
            guard let entry = SyncCoding.decode(JournalSyncEntry.self, from: data) else { return }
            if let journal = first(JournalEntry.self, in: context, where: { $0.id == id }) {
                journal.date = entry.date
                journal.actionRaw = entry.action
                journal.entityRaw = entry.entity
                journal.summary = entry.summary
                journal.beforeJSON = entry.before
                journal.afterJSON = entry.after
                journal.isUndone = entry.isUndone
            } else {
                let journal = JournalEntry(
                    id: id, action: JournalAction(rawValue: entry.action) ?? .edited,
                    entity: JournalEntity(rawValue: entry.entity) ?? .transaction, summary: entry.summary,
                    before: entry.before, after: entry.after, date: entry.date
                )
                journal.isUndone = entry.isUndone
                context.insert(journal)
            }
        }
    }
}

// MARK: - Firestore REST

enum FirestoreError: LocalizedError {
    case http(Int, String)
    case unauthorized
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .http(let code, let message): "Bulut hatası (\(code)): \(message)"
        case .unauthorized: "Oturumun süresi doldu; yeniden giriş yapın."
        case .permissionDenied: "Bu Google hesabının buluttaki verilere erişim izni yok."
        }
    }
}

struct FirestoreClient: Sendable {
    let projectID: String
    let uid: String
    let token: String

    private var root: String { "projects/\(projectID)/databases/(default)/documents" }
    private var base: String { "https://firestore.googleapis.com/v1/\(root)" }

    /// Kayıtları 400'lük gruplar hâlinde yazar; sunucu zamanı `serverTime` alanına işlenir.
    func commit(_ pushes: [SyncPlanner.Push], updatedAt: Int64) async throws {
        for start in stride(from: 0, to: pushes.count, by: 400) {
            let writes = pushes[start..<min(start + 400, pushes.count)].map { push -> [String: Any] in
                [
                    "update": [
                        "name": "\(root)/users/\(uid)/items/\(push.id)",
                        "fields": [
                            "type": ["stringValue": push.type.rawValue],
                            "data": ["stringValue": push.data ?? ""],
                            "updatedAt": ["integerValue": String(updatedAt)],
                            "deleted": ["booleanValue": push.data == nil],
                        ],
                    ],
                    "updateTransforms": [["fieldPath": "serverTime", "setToServerValue": "REQUEST_TIME"]],
                ]
            }
            _ = try await post("\(base):commit", body: ["writes": writes])
        }
    }

    /// `since` sonrasında değişen bütün belgeler ve sorgunun okunduğu sunucu zamanı.
    func changes(since: String?) async throws -> (items: [RemoteItem], readTime: String?) {
        var query: [String: Any] = [
            "from": [["collectionId": "items"]],
            "orderBy": [["field": ["fieldPath": "serverTime"], "direction": "ASCENDING"]],
        ]
        if let since {
            query["where"] = ["fieldFilter": [
                "field": ["fieldPath": "serverTime"], "op": "GREATER_THAN", "value": ["timestampValue": since],
            ]]
        }
        let data = try await post("\(base)/users/\(uid):runQuery", body: ["structuredQuery": query])
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return ([], nil) }
        var items: [RemoteItem] = []
        var readTime: String?
        for row in rows {
            if let time = row["readTime"] as? String { readTime = time }
            guard let document = row["document"] as? [String: Any], let name = document["name"] as? String,
                  let fields = document["fields"] as? [String: Any]
            else { continue }
            func string(_ key: String) -> String? { (fields[key] as? [String: Any])?["stringValue"] as? String }
            let stamp = fields["updatedAt"] as? [String: Any]
            let updated = (stamp?["integerValue"] as? String).flatMap { Int64($0) }
                ?? (stamp?["doubleValue"] as? Double).map { Int64($0) } ?? 0
            let deleted = ((fields["deleted"] as? [String: Any])?["booleanValue"] as? Bool) ?? false
            let id = String(name.split(separator: "/").last ?? "")
            items.append(RemoteItem(id: id, type: string("type").flatMap(SyncType.init(rawValue:)), data: string("data") ?? "",
                                    updatedAt: updated, deleted: deleted))
        }
        return (items, readTime)
    }

    private func post(_ url: String, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: URL(string: url)!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: return data
        case 401: throw FirestoreError.unauthorized
        case 403: throw FirestoreError.permissionDenied
        default: throw FirestoreError.http(status, String(data: data, encoding: .utf8)?.prefix(200).description ?? "")
        }
    }
}

// MARK: - Eşitleme

@MainActor
@Observable
final class CloudSync {
    enum Status: Equatable {
        case idle
        case syncing
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var session: CloudSession? = SharedStore.load(CloudSession.self, key: CloudSession.storeKey)
    private(set) var lastSync: Date? = UserDefaults.standard.object(forKey: "cloudLastSync") as? Date
    private var pending: Task<Void, Never>?
    private var isApplying = false

    var isSignedIn: Bool { session != nil }

    /// Debug'da örnek veriyle açılışta eşitleme kapalıdır; örnek veri buluttaki gerçek verinin üstüne yazılmasın.
    static var isEnabled: Bool {
        #if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("-demoData") else { return false }
        #endif
        return CloudConfig.isConfigured
    }

    private static var stateURL: URL {
        URL.applicationSupportDirectory.appending(path: "cloud-sync-state.json")
    }

    func signIn(context: ModelContext) async {
        do {
            let session = try await CloudAuth.signIn()
            self.session = session
            SharedStore.save(session, key: CloudSession.storeKey)
            status = .idle
            await sync(context: context)
        } catch CloudAuth.AuthError.cancelled {
            return
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func signOut() {
        session = nil
        SharedStore.delete(key: CloudSession.storeKey)
        try? FileManager.default.removeItem(at: Self.stateURL)
        status = .idle
    }

    /// Kısa aralıklı değişiklikleri birleştirerek eşitler.
    func scheduleSync(context: ModelContext, delay: Duration = .seconds(2)) {
        guard Self.isEnabled, isSignedIn, !isApplying else { return }
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await sync(context: context)
        }
    }

    /// Toplu silme engeline takılan son eşitleme; kullanıcı "Yine de eşitle" diyebilir.
    private(set) var isBlockedByMassDeletion = false

    /// İlk eşitlemede (ya da yeniden girişte) önce bulut alınır, sonra yerel farklar gönderilir; böylece bulutta silinen
    /// kayıtlar geri yazılmaz. Sonraki eşitlemelerde önce gönderilir, sonra alınır.
    func sync(context: ModelContext, allowMassDeletion: Bool = false) async {
        guard Self.isEnabled, var session, status != .syncing else { return }
        status = .syncing
        do {
            let token = try await CloudAuth.idToken(for: &session)
            self.session = session
            SharedStore.save(session, key: CloudSession.storeKey)
            let client = FirestoreClient(projectID: CloudConfig.projectID, uid: session.uid, token: token)
            var state = loadState()
            if state.uid != session.uid { state = SyncState(uid: session.uid) }

            if state.cursor == nil {
                try await pull(client, state: &state, context: context, allowMassDeletion: allowMassDeletion)
                try await push(client, state: &state, context: context, allowMassDeletion: allowMassDeletion)
            } else {
                try await push(client, state: &state, context: context, allowMassDeletion: allowMassDeletion)
                try await pull(client, state: &state, context: context, allowMassDeletion: allowMassDeletion)
            }
            lastSync = .now
            UserDefaults.standard.set(lastSync, forKey: "cloudLastSync")
            isBlockedByMassDeletion = false
            status = .idle
        } catch FirestoreError.unauthorized {
            signOut()
            status = .failed(FirestoreError.unauthorized.localizedDescription)
        } catch let error as SyncError {
            isBlockedByMassDeletion = true
            status = .failed(error.localizedDescription)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func push(_ client: FirestoreClient, state: inout SyncState, context: ModelContext, allowMassDeletion: Bool) async throws {
        let local = SyncSnapshot.make(from: context)
        let pushes = SyncPlanner.pushes(local: local, state: state)
        guard !pushes.isEmpty else { return }
        let deletions = pushes.filter { $0.data == nil }.count
        let known = state.records.values.filter { $0.hash != nil }.count
        if !allowMassDeletion, SyncPlanner.isMassDeletion(deletions: deletions, total: known) {
            throw SyncError.massDeletion(deletions)
        }
        let now = Int64(Date.now.timeIntervalSince1970 * 1000)
        try await client.commit(pushes, updatedAt: now)
        for push in pushes {
            state.records[push.id] = SyncState.Entry(hash: local[push.id]?.hash, updatedAt: now)
        }
        saveState(state)
    }

    private func pull(_ client: FirestoreClient, state: inout SyncState, context: ModelContext, allowMassDeletion: Bool) async throws {
        // Sunucu saatindeki küçük sıra farklarına karşı 2 dakika geriden sorulur; tekrar gelenler `updatedAt` ile elenir.
        let since = state.cursor.flatMap { try? Date($0, strategy: .iso8601) }
            .map { $0.addingTimeInterval(-120).formatted(.iso8601) }
        let (remote, readTime) = try await client.changes(since: since)
        let incoming = SyncPlanner.incoming(remote, state: state)
        let remoteDeletions = incoming.filter(\.deleted).count
        let localCount = SyncSnapshot.make(from: context).count
        if !allowMassDeletion, SyncPlanner.isMassDeletion(deletions: remoteDeletions, total: localCount) {
            throw SyncError.remoteMassDeletion(remoteDeletions)
        }
        if !incoming.isEmpty {
            isApplying = true
            defer { isApplying = false }
            try SyncApplier.apply(incoming, in: context)
            let updated = SyncSnapshot.make(from: context)
            for item in incoming {
                state.records[item.id] = SyncState.Entry(hash: updated[item.id]?.hash, updatedAt: item.updatedAt)
            }
        }
        state.cursor = readTime ?? state.cursor ?? Date.now.formatted(.iso8601)
        saveState(state)
    }

    private func loadState() -> SyncState {
        (try? Data(contentsOf: Self.stateURL)).flatMap { try? JSONDecoder().decode(SyncState.self, from: $0) } ?? SyncState()
    }

    private func saveState(_ state: SyncState) {
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(state).write(to: Self.stateURL, options: .atomic)
    }
}

enum SyncError: LocalizedError {
    case massDeletion(Int)
    case remoteMassDeletion(Int)

    var errorDescription: String? {
        switch self {
        case .massDeletion(let count):
            "Telefonda \(count) kayıt birden silinmiş görünüyor; güvenlik için buluta gönderilmedi. Bilerek yaptıysanız \"Yine de eşitle\"ye dokunun."
        case .remoteMassDeletion(let count):
            "Bulutta \(count) kayıt birden silinmiş görünüyor; güvenlik için telefona uygulanmadı. Bilerek yaptıysanız \"Yine de eşitle\"ye dokunun."
        }
    }
}

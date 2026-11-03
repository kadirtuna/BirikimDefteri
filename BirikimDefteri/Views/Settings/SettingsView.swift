import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.ledger) private var ledger
    @Environment(\.modelContext) private var context
    @AppStorage(PriceUpdater.autoUpdateKey) private var autoUpdatePrices = true

    @State private var exportDocument: BackupDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var pendingRestore: BackupFile?
    @State private var notice: Notice?

    private struct Notice {
        let title: String
        let message: String
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        AppLogo(size: 84)
                        Text("Birikim Defteri")
                            .font(.title3.weight(.semibold))
                        Text("Altın, döviz ve birikimleriniz tek defterde")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section("Tanımlar") {
                    NavigationLink {
                        PeopleView()
                    } label: {
                        LabeledContent { Text("\(ledger.people.count)") } label: { Label("Kişiler", systemImage: "person.2") }
                    }
                    NavigationLink {
                        LocationsView()
                    } label: {
                        LabeledContent { Text("\(ledger.locations.count)") } label: {
                            Label("Saklama yerleri", systemImage: "building.columns")
                        }
                    }
                    NavigationLink {
                        AssetsView()
                    } label: {
                        LabeledContent { Text("\(ledger.assets.count)") } label: {
                            Label("Ürünler", systemImage: "square.stack.3d.up")
                        }
                    }
                }

                Section {
                    Button(action: export) {
                        Label("Yedeği dışa aktar", systemImage: "square.and.arrow.up")
                    }
                    .fileExporter(
                        isPresented: $isExporting,
                        document: exportDocument,
                        contentType: .json,
                        defaultFilename: BackupService.defaultFilename()
                    ) { result in
                        switch result {
                        case .success:
                            notice = Notice(title: "Yedek kaydedildi", message: "Dosyayı güvenli bir yerde saklayın.")
                        case .failure(let error):
                            notice = Notice(title: "Yedek kaydedilemedi", message: error.localizedDescription)
                        }
                    }

                    Button {
                        isImporting = true
                    } label: {
                        Label("Yedekten geri yükle", systemImage: "square.and.arrow.down")
                    }
                    .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                        do {
                            pendingRestore = try BackupService.read(from: result.get())
                        } catch {
                            notice = Notice(title: "Yedek açılamadı", message: error.localizedDescription)
                        }
                    }
                } header: {
                    Text("Yedekleme")
                } footer: {
                    Text("Yedek bir JSON dosyasıdır. Geri yükleme mevcut tüm verilerin yerine geçer.")
                }

                Section {
                    Toggle(isOn: $autoUpdatePrices) {
                        Label("Fiyatları otomatik güncelle", systemImage: "arrow.triangle.2.circlepath")
                    }
                } header: {
                    Text("Fiyatlar")
                } footer: {
                    Text("Açıkken uygulama her açılışta, son güncellemenin üzerinden bir saat geçtiyse fiyatları internetten çeker. Altın ve gümüş Truncgil Finans'tan, dolar ve euro TCMB'den alınır. Fiyatları her zaman elle de girebilirsiniz.")
                }

                Section {
                    LabeledContent {
                        Text(AppLock.isAvailable ? "Her zaman açık" : "Çalışmıyor")
                            .foregroundStyle(AppLock.isAvailable ? Color.secondary : Color.orange)
                    } label: {
                        Label("\(AppLock.biometryName) kilidi", systemImage: AppLock.biometrySymbol)
                    }
                } header: {
                    Text("Güvenlik")
                } footer: {
                    if AppLock.isAvailable {
                        Text("Uygulama her açılışta ve arka plandan her dönüşte kimlik doğrulaması ister. \(AppLock.biometryName) olmazsa cihaz şifresi kullanılabilir.")
                    } else {
                        Text("Bu iPhone'da cihaz şifresi ayarlı olmadığı için kilit çalışamıyor. iPhone Ayarlar > Face ID ve Parola'dan bir şifre belirleyin.")
                    }
                }

                Section {
                    LabeledContent("Sürüm", value: appVersion)
                } footer: {
                    Text("Tüm veriler yalnızca bu iPhone'da saklanır; internetten yalnızca güncel fiyatlar indirilir.")
                }
            }
            .navigationTitle("Ayarlar")
            .alert(
                "Yedek geri yüklensin mi?",
                isPresented: Binding(isPresent: $pendingRestore),
                presenting: pendingRestore
            ) { backup in
                Button("Vazgeç", role: .cancel) {}
                Button("Geri yükle", role: .destructive) { restore(backup) }
            } message: { backup in
                Text("\(Format.dateTime(backup.exportedAt)) tarihli yedek: \(backup.transactions.count) işlem, \(backup.debts.count) borç. Mevcut tüm veriler silinecek ve yedektekilerle değiştirilecek. Bu işlem geri alınamaz.")
            }
            .alert(notice?.title ?? "", isPresented: Binding(isPresent: $notice), presenting: notice) { _ in
                Button("Tamam", role: .cancel) {}
            } message: { notice in
                Text(notice.message)
            }
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func export() {
        do {
            exportDocument = BackupDocument(data: try BackupService.encode(BackupService.makeBackup(from: ledger)))
            isExporting = true
        } catch {
            notice = Notice(title: "Yedek oluşturulamadı", message: error.localizedDescription)
        }
    }

    private func restore(_ backup: BackupFile) {
        do {
            try BackupService.restore(backup, into: context)
            notice = Notice(title: "Geri yükleme tamamlandı", message: "\(backup.transactions.count) işlem ve \(backup.debts.count) borç yüklendi.")
        } catch {
            notice = Notice(title: "Geri yükleme başarısız", message: error.localizedDescription)
        }
    }
}

import SwiftData
import SwiftUI

/// Ayarlar'daki bulut ve web bölümü: Google ile giriş, eşitleme durumu ve web adresi.
struct CloudSection: View {
    @Environment(CloudSync.self) private var cloud: CloudSync?
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let cloud, CloudSync.isEnabled {
            Section {
                if let session = cloud.session {
                    LabeledContent {
                        Text(session.email)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } label: {
                        Label("Google hesabı", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    HStack {
                        Label(statusText(cloud), systemImage: statusSymbol(cloud))
                            .foregroundStyle(isFailure(cloud) ? Theme.negative : Color.primary)
                            .font(.subheadline)
                        Spacer(minLength: 8)
                        if cloud.status == .syncing {
                            ProgressView()
                        } else {
                            Button("Şimdi eşitle") { Task { await cloud.sync(context: context) } }
                                .buttonStyle(.bordered)
                        }
                    }
                    if cloud.isBlockedByMassDeletion {
                        Button("Yine de eşitle", role: .destructive) {
                            Task { await cloud.sync(context: context, allowMassDeletion: true) }
                        }
                    }
                    Button {
                        openURL(CloudConfig.webURL)
                    } label: {
                        Label("Web sürümünü aç", systemImage: "safari")
                    }
                    Button("Çıkış yap", role: .destructive) { cloud.signOut() }
                } else {
                    Button {
                        Task { await cloud.signIn(context: context) }
                    } label: {
                        Label("Google ile giriş yap", systemImage: "icloud.and.arrow.up")
                    }
                    if case .failed(let message) = cloud.status {
                        ErrorLabel(message: message)
                    }
                }
            } header: {
                Text("Bulut ve web")
            } footer: {
                Text(cloud.isSignedIn
                     ? "Veriler Google Firebase'de yalnızca sizin hesabınızın erişebildiği bir alanda tutulur ve web sürümüyle eşitlenir. Telefon uygulama açıldığında, her değişiklikte ve açıkken dakikada bir eşitler. Web: \(CloudConfig.webURL.absoluteString)"
                     : "Giriş yaparsanız veriler Google Firebase'de yalnızca sizin hesabınızın erişebildiği bir alanda tutulur; web sürümünden de görüp değiştirebilirsiniz. Giriş yapmazsanız veriler yalnızca bu iPhone'da kalır.")
            }
        }
    }

    private func isFailure(_ cloud: CloudSync) -> Bool {
        if case .failed = cloud.status { return true }
        return false
    }

    private func statusText(_ cloud: CloudSync) -> String {
        switch cloud.status {
        case .syncing: return "Eşitleniyor…"
        case .failed(let message): return message
        case .idle: return cloud.lastSync.map { "Son eşitleme: \(Format.dateTime($0))" } ?? "Henüz eşitlenmedi"
        }
    }

    private func statusSymbol(_ cloud: CloudSync) -> String {
        switch cloud.status {
        case .syncing: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.icloud"
        case .idle: "checkmark.icloud"
        }
    }
}

import LocalAuthentication
import SwiftUI

#if DEBUG
/// Örnek veriyle (-demoData) açılan hata ayıklama derlemesinde kilit atlanır; simülatörde ekran görüntüsü için.
private let bypassesLock = ProcessInfo.processInfo.arguments.contains("-demoData")
#else
private let bypassesLock = false
#endif

/// Zorunlu Face ID / Touch ID kilidi: her açılışta ve arka plandan dönüşte sorar.
/// Biyometri başarısız olursa cihaz şifresine düşer.
@MainActor
@Observable
final class AppLock {
    enum AuthResult {
        case success
        case failed
        case unavailable
    }

    private(set) var isUnlocked = bypassesLock
    private(set) var isAuthenticating = false
    private var needsAuthentication = !bypassesLock

    func scenePhaseChanged(to phase: ScenePhase) {
        guard !bypassesLock else { return }
        switch phase {
        case .background:
            isUnlocked = false
            needsAuthentication = true
        case .active where needsAuthentication:
            needsAuthentication = false
            Task { await unlock() }
        default:
            break
        }
    }

    func unlock() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        switch await Self.authenticate(reason: "Birikim Defteri'ni açmak için kimliğinizi doğrulayın.") {
        case .success, .unavailable:
            // Cihazda şifre kaldırıldıysa kullanıcı dışarıda kalmasın.
            isUnlocked = true
        case .failed:
            break
        }
    }

    static func authenticate(reason: String) async -> AuthResult {
        let context = LAContext()
        context.localizedCancelTitle = "Vazgeç"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .unavailable
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) ? .success : .failed
        } catch {
            return .failed
        }
    }

    /// Cihazda şifre (ve isteğe bağlı Face ID) tanımlı mı? Değilse kilit çalışamaz.
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Cihaz şifresi"
        }
    }

    static var biometrySymbol: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "lock"
        }
    }
}

struct LockView: View {
    @Environment(AppLock.self) private var lock: AppLock?

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                AppLogo(size: 104)
                Text("Birikim Defteri")
                    .font(.title2.bold())
                Label("Kilitli", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
                if let lock {
                    Button {
                        Task { await lock.unlock() }
                    } label: {
                        Label("Kilidi aç", systemImage: AppLock.biometrySymbol)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(lock.isAuthenticating)
                    .padding(.top, 8)
                }
            }
            .padding()
        }
    }
}

private struct LockProtectedModifier: ViewModifier {
    @Environment(AppLock.self) private var lock: AppLock?
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.overlay {
            // Uygulama değiştiricide içerik görünmesin diye etkin değilken de kapatılır.
            if let lock, !lock.isUnlocked || scenePhase != .active {
                LockView()
            }
        }
    }
}

extension View {
    /// Kilit açık değilken içeriği gizler. Kök görünüm ve her sayfa (sheet) için uygulanır.
    func lockProtected() -> some View {
        modifier(LockProtectedModifier())
    }
}

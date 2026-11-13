import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Firebase projesinin herkese açık ayarları. Bunlar gizli değildir; verileri Firestore kuralları korur
/// (yalnızca sahibinin Google hesabı okuyup yazabilir).
enum CloudConfig {
    static let projectID = ""
    static let apiKey = ""
    /// Firebase'in oluşturduğu iOS OAuth istemcisi (GoogleService-Info.plist'teki CLIENT_ID).
    static let iosClientID = ""
    static let webURL = URL(string: "https://kadirtuna.github.io/BirikimDefteri/")!

    static var isConfigured: Bool { !projectID.isEmpty && !apiKey.isEmpty && !iosClientID.isEmpty }

    /// "123-abc.apps.googleusercontent.com" → "com.googleusercontent.apps.123-abc"
    static var redirectScheme: String { iosClientID.split(separator: ".").reversed().joined(separator: ".") }
}

/// Buluttaki oturum; paylaşılan Anahtar Zinciri'nde saklanır.
struct CloudSession: Codable, Equatable, Sendable {
    static let storeKey = "cloud-session"

    var uid: String
    var email: String
    var refreshToken: String
    var idToken: String
    var expiresAt: Date
}

/// Google ile giriş (ASWebAuthenticationSession + PKCE) ve Firebase oturumu, Firebase SDK'sı olmadan.
@MainActor
enum CloudAuth {
    enum AuthError: LocalizedError {
        case cancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .cancelled: "Giriş iptal edildi."
            case .failed(let message): message
            }
        }
    }

    static func signIn() async throws -> CloudSession {
        let verifier = randomURLSafe(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        let redirect = "\(CloudConfig.redirectScheme):/oauth2redirect"
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: CloudConfig.iosClientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid email"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "prompt", value: "select_account"),
        ]
        let callback = try await authenticate(url: components.url!, scheme: CloudConfig.redirectScheme)
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        else { throw AuthError.failed("Google girişi tamamlanamadı.") }

        let google = try await postForm("https://oauth2.googleapis.com/token", [
            "client_id": CloudConfig.iosClientID, "code": code, "code_verifier": verifier,
            "grant_type": "authorization_code", "redirect_uri": redirect,
        ])
        guard let googleIDToken = google["id_token"] as? String else { throw AuthError.failed("Google kimlik belirteci alınamadı.") }

        let firebase = try await postJSON(
            "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=\(CloudConfig.apiKey)",
            ["postBody": "id_token=\(googleIDToken)&providerId=google.com", "requestUri": "http://localhost",
             "returnSecureToken": true, "returnIdpCredential": true]
        )
        guard let uid = firebase["localId"] as? String, let idToken = firebase["idToken"] as? String,
              let refresh = firebase["refreshToken"] as? String
        else { throw AuthError.failed("Firebase oturumu açılamadı.") }
        let expires = Double(firebase["expiresIn"] as? String ?? "3600") ?? 3600
        return CloudSession(uid: uid, email: firebase["email"] as? String ?? "", refreshToken: refresh, idToken: idToken,
                            expiresAt: .now.addingTimeInterval(expires - 120))
    }

    /// Geçerli kimlik belirteci; süresi dolduysa yenileme anahtarıyla yenilenir.
    static func idToken(for session: inout CloudSession) async throws -> String {
        if session.expiresAt > .now { return session.idToken }
        let response = try await postForm(
            "https://securetoken.googleapis.com/v1/token?key=\(CloudConfig.apiKey)",
            ["grant_type": "refresh_token", "refresh_token": session.refreshToken]
        )
        guard let idToken = response["id_token"] as? String else { throw FirestoreError.unauthorized }
        session.idToken = idToken
        session.refreshToken = response["refresh_token"] as? String ?? session.refreshToken
        let expires = Double(response["expires_in"] as? String ?? "3600") ?? 3600
        session.expiresAt = .now.addingTimeInterval(expires - 120)
        return idToken
    }

    // MARK: Yardımcılar

    private static let presenter = Presenter()

    private final class Presenter: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            MainActor.assumeIsolated {
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                    .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
            }
        }
    }

    private static func authenticate(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.cancelled)
                } else {
                    continuation.resume(throwing: AuthError.failed(error?.localizedDescription ?? "Google girişi açılamadı."))
                }
            }
            session.presentationContextProvider = presenter
            session.start()
        }
    }

    private static func postForm(_ url: String, _ fields: [String: String]) async throws -> [String: Any] {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
        return try await post(url, body: Data(body.utf8), contentType: "application/x-www-form-urlencoded")
    }

    private static func postJSON(_ url: String, _ body: [String: Any]) async throws -> [String: Any] {
        try await post(url, body: try JSONSerialization.data(withJSONObject: body), contentType: "application/json")
    }

    private static func post(_ url: String, body: Data, contentType: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let message = ((object["error"] as? [String: Any])?["message"] as? String) ?? (object["error_description"] as? String)
            throw AuthError.failed("Giriş başarısız: \(message ?? "bilinmeyen hata")")
        }
        return object
    }

    private static func randomURLSafe(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes).base64URLEncoded
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

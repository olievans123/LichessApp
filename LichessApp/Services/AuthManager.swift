import Foundation
import AuthenticationServices
import SwiftUI
import Security

@MainActor
class AuthManager: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: LichessUser?
    @Published var accessToken: String?
    @Published var isLoading = false
    @Published var error: String?

    private let clientId = "lichess-macos-app"
    private let redirectUri = "com.lichess.macos://oauth-callback"
    private var authSession: ASWebAuthenticationSession?

    private let keychainService = "com.lichess.macos"
    private let keychainAccount = "lichess_access_token"

    override init() {
        super.init()
        loadStoredToken()
    }

    private func loadStoredToken() {
        if let token = loadTokenFromKeychain() {
            self.accessToken = token
            self.isAuthenticated = true
            Task {
                await fetchCurrentUser()
            }
        }
    }

    // MARK: - Keychain Storage

    private func saveTokenToKeychain(_ token: String) {
        let data = token.data(using: .utf8)!

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            print("Keychain save error: \(status)")
        }
    }

    private func loadTokenFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    private func deleteTokenFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    func login() {
        isLoading = true
        error = nil

        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)

        var components = URLComponents(string: "https://lichess.org/oauth")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "scope", value: "preference:read challenge:read challenge:write board:play")
        ]

        guard let authURL = components.url else {
            error = "Failed to create auth URL"
            isLoading = false
            return
        }

        authSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "com.lichess.macos"
        ) { [weak self] callbackURL, authError in
            Task { @MainActor in
                guard let self = self else { return }

                if let authError = authError {
                    self.error = authError.localizedDescription
                    self.isLoading = false
                    return
                }

                guard let callbackURL = callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    self.error = "Failed to get authorization code"
                    self.isLoading = false
                    return
                }

                await self.exchangeCodeForToken(code: code, codeVerifier: codeVerifier)
            }
        }

        authSession?.presentationContextProvider = self
        authSession?.prefersEphemeralWebBrowserSession = false
        authSession?.start()
    }

    private func exchangeCodeForToken(code: String, codeVerifier: String) async {
        guard let url = URL(string: "https://lichess.org/api/token") else {
            error = "Invalid token URL"
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": codeVerifier,
            "redirect_uri": redirectUri,
            "client_id": clientId
        ]
        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

            self.accessToken = tokenResponse.access_token
            saveTokenToKeychain(tokenResponse.access_token)
            self.isAuthenticated = true

            await fetchCurrentUser()
        } catch {
            self.error = "Failed to exchange token: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func fetchCurrentUser() async {
        guard let token = accessToken else { return }

        guard let url = URL(string: "https://lichess.org/api/account") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let user = try JSONDecoder().decode(LichessUser.self, from: data)
            self.currentUser = user
        } catch {
            print("Failed to fetch user: \(error)")
        }
    }

    func logout() {
        accessToken = nil
        currentUser = nil
        isAuthenticated = false
        deleteTokenFromKeychain()
    }

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension AuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? ASPresentationAnchor()
    }
}

struct TokenResponse: Codable {
    let access_token: String
    let token_type: String
}

// CommonCrypto bridge
import CommonCrypto

import Foundation
import Security
import UsageCore

/// What went wrong, in words the menu can show.
enum FetchError: Error {
    case notSignedIn          // no Claude Code sign-in in the Keychain
    case keychainDenied       // the Keychain prompt was refused
    case expired              // the token has expired; Claude Code renews it
    case unauthorized         // 401/403 although the token looked valid
    case http(Int)
    case network(String)
    case unreadable           // an answer we could not decode

    var title: String {
        switch self {
        case .notSignedIn: return "Not signed in to Claude Code"
        case .keychainDenied: return "No access to the Keychain"
        case .expired, .unauthorized: return "Claude Code's sign-in has expired"
        case .http(let code): return "Anthropic answered \(code)"
        case .network: return "Could not reach Anthropic"
        case .unreadable: return "Unexpected answer from Anthropic"
        }
    }

    var detail: String {
        switch self {
        case .notSignedIn: return "Run claude and sign in with your subscription."
        case .keychainDenied: return "Open the menu again and choose Always Allow."
        case .expired, .unauthorized: return "Run claude once; it renews the sign-in."
        case .http: return "Try again in a moment."
        case .network(let why): return why
        case .unreadable: return "The usage format may have changed."
        }
    }
}

/// One check of the subscription's usage: read Claude Code's sign-in from the
/// Keychain, ask Anthropic, decode. Runs only when asked (the menu opening);
/// nothing is scheduled. The token lives only for the request.
final class UsageClient {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let queue = DispatchQueue(label: "claude-usage.keychain")

    struct Result {
        let report: UsageReport
        let plan: String
        /// The answer as received (for `claude-usage --json`).
        let raw: Data
    }

    func fetch(_ completion: @escaping (Swift.Result<Result, FetchError>) -> Void) {
        let done = { (r: Swift.Result<Result, FetchError>) in DispatchQueue.main.async { completion(r) } }
        // The Keychain may show its prompt: keep it off the main thread.
        queue.async {
            let credentials: Credentials
            switch Self.readCredentials() {
            case .failure(let e): done(.failure(e)); return
            case .success(let c): credentials = c
            }
            if credentials.isExpired(at: Date()) { done(.failure(.expired)); return }
            var request = URLRequest(url: Self.endpoint, timeoutInterval: 10)
            request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let plan = credentials.plan
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error { done(.failure(.network(error.localizedDescription))); return }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200 else {
                    done(.failure(status == 401 || status == 403 ? .unauthorized : .http(status)))
                    return
                }
                guard let data, let report = try? UsageReport.decode(data) else { done(.failure(.unreadable)); return }
                done(.success(Result(report: report, plan: plan, raw: data)))
            }.resume()
        }
    }

    private static func readCredentials() -> Swift.Result<Credentials, FetchError> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Credentials.keychainService,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let c = Credentials(keychainData: data) else { return .failure(.notSignedIn) }
            return .success(c)
        case errSecItemNotFound: return .failure(.notSignedIn)
        default: return .failure(.keychainDenied)   // user refused, or interaction not allowed
        }
    }
}

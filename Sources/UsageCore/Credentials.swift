import Foundation

/// Claude Code's sign-in, as stored in the login Keychain (generic password,
/// service `Claude Code-credentials`). Read fresh on every check, used for
/// one request, never stored, logged or printed (`description` hides it).
///
/// The app never refreshes an expired token: refreshing rotates the refresh
/// token, which would sign Claude Code out. Claude Code renews it itself the
/// next time it runs.
public struct Credentials: CustomStringConvertible {
    public let accessToken: String
    public let expiresAt: Date?
    public let subscriptionType: String?
    public let rateLimitTier: String?

    public static let keychainService = "Claude Code-credentials"

    public init?(keychainData data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        accessToken = token
        expiresAt = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        subscriptionType = oauth["subscriptionType"] as? String
        rateLimitTier = oauth["rateLimitTier"] as? String
    }

    public func isExpired(at now: Date) -> Bool { expiresAt.map { $0 <= now } ?? false }

    public var plan: String { Self.planName(subscriptionType: subscriptionType, tier: rateLimitTier) }

    public var description: String { "Credentials(plan: \(plan), expiresAt: \(expiresAt.map { "\($0)" } ?? "-"), token: <hidden>)" }

    /// "Max 20x" from `max` + `default_claude_max_20x`, "Pro" from `pro`.
    public static func planName(subscriptionType: String?, tier: String?) -> String {
        let base = (subscriptionType ?? "").isEmpty ? "Claude" : subscriptionType!.prefix(1).uppercased() + subscriptionType!.dropFirst()
        if let tier, let r = tier.range(of: #"\d+x$"#, options: .regularExpression) {
            return "\(base) \(tier[r])"
        }
        return base
    }
}

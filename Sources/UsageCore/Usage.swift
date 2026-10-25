import Foundation

/// The answer of `GET https://api.anthropic.com/api/oauth/usage`, the
/// undocumented endpoint behind Claude Code's `/usage`. Only the parts the menu
/// shows are decoded, and every field is optional: Anthropic can change the
/// shape at any time, and a missing part must hide a row, not break the menu.
public struct UsageReport: Decodable, Equatable {
    /// One entry per limit (session, weekly, weekly per model, ...).
    public let limits: [Limit]
    public let extraUsage: ExtraUsage?
    public let spend: Spend?
    public let weekBreakdown: Breakdown?

    enum CodingKeys: String, CodingKey {
        case limits, spend
        case extraUsage = "extra_usage"
        case weekBreakdown = "seven_day_breakdown"
        case fiveHour = "five_hour", sevenDay = "seven_day"
    }

    public init(limits: [Limit], extraUsage: ExtraUsage?, spend: Spend?, weekBreakdown: Breakdown?) {
        self.limits = limits
        self.extraUsage = extraUsage
        self.spend = spend
        self.weekBreakdown = weekBreakdown
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        extraUsage = try? c.decodeIfPresent(ExtraUsage.self, forKey: .extraUsage)
        spend = try? c.decodeIfPresent(Spend.self, forKey: .spend)
        weekBreakdown = try? c.decodeIfPresent(Breakdown.self, forKey: .weekBreakdown)
        if let list = try? c.decodeIfPresent([Limit].self, forKey: .limits), !list.isEmpty {
            limits = list
        } else {
            // The older shape: one object per window, no `limits` list.
            var built: [Limit] = []
            if let w = try? c.decodeIfPresent(Window.self, forKey: .fiveHour), let u = w.utilization {
                built.append(Limit(kind: "session", percent: u, severity: nil, resetsAt: w.resetsAt, scope: nil))
            }
            if let w = try? c.decodeIfPresent(Window.self, forKey: .sevenDay), let u = w.utilization {
                built.append(Limit(kind: "weekly_all", percent: u, severity: nil, resetsAt: w.resetsAt, scope: nil))
            }
            limits = built
        }
    }

    /// Decode with the date format the endpoint uses (ISO 8601, with or
    /// without fractional seconds).
    public static func decode(_ data: Data) throws -> UsageReport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let text = try d.singleValueContainer().decode(String.self)
            guard let date = ISODate.parse(text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: d.codingPath, debugDescription: "bad date \(text)"))
            }
            return date
        }
        return try decoder.decode(UsageReport.self, from: data)
    }

    private struct Window: Decodable {
        let utilization: Double?
        let resetsAt: Date?
        enum CodingKeys: String, CodingKey { case utilization, resetsAt = "resets_at" }
    }
}

public struct Limit: Decodable, Equatable {
    /// `session`, `weekly_all`, `weekly_scoped`, or something newer.
    public let kind: String
    public let percent: Double
    /// `normal` today; anything else is treated as a warning.
    public let severity: String?
    public let resetsAt: Date?
    public let scope: Scope?

    public init(kind: String, percent: Double, severity: String?, resetsAt: Date?, scope: Scope?) {
        self.kind = kind
        self.percent = percent
        self.severity = severity
        self.resetsAt = resetsAt
        self.scope = scope
    }

    enum CodingKeys: String, CodingKey { case kind, percent, severity, scope, resetsAt = "resets_at" }

    public struct Scope: Decodable, Equatable {
        public let model: Named?
        public let surface: Named?
        public init(model: Named?, surface: Named?) { self.model = model; self.surface = surface }
    }

    public struct Named: Decodable, Equatable {
        public let id: String?
        public let displayName: String?
        public init(id: String?, displayName: String?) { self.id = id; self.displayName = displayName }
        enum CodingKeys: String, CodingKey { case id, displayName = "display_name" }
    }
}

/// Pay-as-you-go credits used once the plan's limits are reached.
public struct ExtraUsage: Decodable, Equatable {
    public let isEnabled: Bool?
    public let monthlyLimit: Double?
    public let usedCredits: Double?
    public let currency: String?
    public let spendLimitReached: Bool?

    enum CodingKeys: String, CodingKey {
        case currency
        case isEnabled = "is_enabled", monthlyLimit = "monthly_limit", usedCredits = "used_credits"
        case spendLimitReached = "spend_limit_reached"
    }
}

public struct Spend: Decodable, Equatable {
    public let used: Money?
    public let limit: Money?
    public let enabled: Bool?
}

public struct Money: Decodable, Equatable {
    public let amountMinor: Int
    public let currency: String
    public let exponent: Int

    public init(amountMinor: Int, currency: String, exponent: Int) {
        self.amountMinor = amountMinor
        self.currency = currency
        self.exponent = exponent
    }

    enum CodingKeys: String, CodingKey { case currency, exponent, amountMinor = "amount_minor" }
}

/// How the week's usage splits over Claude Code, chats, Cowork, ...
public struct Breakdown: Decodable, Equatable {
    public let rows: [Row]

    public struct Row: Decodable, Equatable {
        public let key: String
        public let displayName: String
        public let percent: Double
        enum CodingKeys: String, CodingKey { case key, percent, displayName = "display_name" }
    }
}

enum ISODate {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ text: String) -> Date? {
        if let d = withFraction.date(from: text) ?? plain.date(from: text) { return d }
        // Microseconds ("…00.124398+00:00"): trim the fraction to milliseconds.
        guard let dot = text.firstIndex(of: "."),
              let end = text[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) else { return nil }
        let digits = text[text.index(after: dot)..<end]
        return withFraction.date(from: text[..<dot] + "." + digits.prefix(3).padding(toLength: 3, withPad: "0", startingAt: 0) + text[end...])
    }
}

import Foundation

/// The words and numbers the menu shows.
public enum Format {
    /// "Current session", "This week · all models", "This week · Fable".
    public static func title(of limit: Limit) -> String {
        switch limit.kind {
        case "session": return "Current session (5 h)"
        case "weekly_all": return "This week · all models"
        case "weekly_scoped":
            let name = limit.scope?.model?.displayName ?? limit.scope?.surface?.displayName
            return "This week · \(name ?? "limited")"
        default:
            return limit.kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    public enum Level { case normal, warning, critical }

    public static func level(of limit: Limit) -> Level {
        if limit.percent >= 90 { return .critical }
        if limit.percent >= 75 || (limit.severity.map { $0 != "normal" } ?? false) { return .warning }
        return .normal
    }

    public static func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }

    /// "Resets 09:00 · in 1 h 20 m" today, "Resets Sat 07:00 · in 2 d 3 h" later.
    public static func reset(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let left = date.timeIntervalSince(now)
        guard left > 0 else { return "Resets now" }
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = locale
        f.timeZone = calendar.timeZone
        // Anthropic sends times like 05:59:59.9: show the nearest minute.
        let shown = Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded() * 60)
        f.setLocalizedDateFormatFromTemplate(calendar.isDate(shown, inSameDayAs: now) ? "HH:mm" : "EEE HH:mm")
        return "Resets \(f.string(from: shown)) · in \(duration(left))"
    }

    /// "45 m", "1 h 20 m", "2 d 3 h" (rounded up to the minute).
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded(.up))
        let d = minutes / 1440, h = (minutes % 1440) / 60, m = minutes % 60
        if d > 0 { return h > 0 ? "\(d) d \(h) h" : "\(d) d" }
        if h > 0 { return m > 0 ? "\(h) h \(m) m" : "\(h) h" }
        return "\(m) m"
    }

    public static func money(_ m: Money, locale: Locale = .current) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = m.currency
        f.locale = locale
        f.minimumFractionDigits = m.exponent
        f.maximumFractionDigits = m.exponent
        let value = Decimal(m.amountMinor) / pow(10, m.exponent)
        return f.string(from: value as NSDecimalNumber) ?? "\(value) \(m.currency)"
    }

    /// The extra-usage line: "Off", "Spend limit reached", "12.50 of 50 USD".
    public static func extraUsage(_ e: ExtraUsage) -> String {
        guard e.isEnabled == true else { return "Off" }
        if e.spendLimitReached == true { return "Spend limit reached" }
        let cur = e.currency.map { " \($0)" } ?? ""
        switch (e.usedCredits, e.monthlyLimit) {
        case let (used?, limit?): return String(format: "%.2f of %.2f%@ this month", used, limit, cur)
        case let (used?, nil): return String(format: "%.2f%@ used this month", used, cur)
        default: return "On"
        }
    }
}

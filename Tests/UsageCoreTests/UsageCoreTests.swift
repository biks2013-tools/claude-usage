import XCTest
@testable import UsageCore

final class UsageCoreTests: XCTestCase {
    /// The shape the endpoint returned on 2026-10-24 (unused keys trimmed).
    static let sample = """
    {
     "five_hour": {"utilization": 12.0, "resets_at": "2026-10-24T06:00:00.124398+00:00"},
     "seven_day": {"utilization": 11.0, "resets_at": "2026-10-24T04:00:00.124417+00:00"},
     "seven_day_opus": null,
     "extra_usage": {"is_enabled": false, "monthly_limit": null, "used_credits": null, "currency": null,
                     "user_disabled": true, "spend_limit_reached": false, "daily": null},
     "limits": [
      {"kind": "session", "group": "session", "percent": 12, "severity": "normal",
       "resets_at": "2026-10-24T06:00:00.124398+00:00", "scope": null, "is_active": true},
      {"kind": "weekly_all", "group": "weekly", "percent": 11, "severity": "normal",
       "resets_at": "2026-10-24T04:00:00.124417+00:00", "scope": null, "is_active": false},
      {"kind": "weekly_scoped", "group": "weekly", "percent": 0, "severity": "normal",
       "resets_at": "2026-10-24T04:00:00+00:00",
       "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}, "is_active": false}
     ],
     "spend": {"used": {"amount_minor": 0, "currency": "USD", "exponent": 2}, "limit": null, "percent": 0,
               "enabled": false},
     "seven_day_breakdown": {"as_of": "2026-10-24T03:40:38.151559+00:00",
      "rows": [{"key": "claude_code", "display_name": "Claude Code", "percent": 99},
               {"key": "chat", "display_name": "Chats", "percent": 1}]}
    }
    """

    func testDecodesTheLiveShape() throws {
        let r = try UsageReport.decode(Data(Self.sample.utf8))
        XCTAssertEqual(r.limits.map(\.kind), ["session", "weekly_all", "weekly_scoped"])
        XCTAssertEqual(r.limits[0].percent, 12)
        XCTAssertEqual(r.limits[0].resetsAt?.timeIntervalSince1970 ?? 0, 1_792_821_600.124, accuracy: 0.01)
        XCTAssertEqual(r.limits[2].resetsAt?.timeIntervalSince1970, 1_792_814_400)
        XCTAssertEqual(Format.title(of: r.limits[2]), "This week · Fable")
        XCTAssertEqual(r.weekBreakdown?.rows.map(\.displayName), ["Claude Code", "Chats"])
        XCTAssertEqual(r.extraUsage.map(Format.extraUsage), "Off")
        XCTAssertEqual(r.spend?.used, Money(amountMinor: 0, currency: "USD", exponent: 2))
    }

    func testOlderShapeWithoutLimitsList() throws {
        let json = #"{"five_hour": {"utilization": 40, "resets_at": "2026-10-24T06:00:00Z"}, "seven_day": {"utilization": 5}}"#
        let r = try UsageReport.decode(Data(json.utf8))
        XCTAssertEqual(r.limits.map(\.kind), ["session", "weekly_all"])
        XCTAssertEqual(r.limits.map(\.percent), [40, 5])
        XCTAssertNil(r.limits[1].resetsAt)
    }

    func testUnknownPartsDoNotBreakDecoding() throws {
        let json = #"{"limits": [{"kind": "monthly_new", "percent": 3}], "spend": "something else", "extra_usage": 7}"#
        let r = try UsageReport.decode(Data(json.utf8))
        XCTAssertEqual(Format.title(of: r.limits[0]), "Monthly New")
        XCTAssertNil(r.spend)
        XCTAssertNil(r.extraUsage)
    }

    func testCredentialsKeepTheTokenOutOfDescriptions() throws {
        let json = #"{"claudeAiOauth": {"accessToken": "secret-token", "refreshToken": "r", "expiresAt": 1761300000000,"#
            + #" "subscriptionType": "max", "rateLimitTier": "default_claude_max_20x"}}"#
        let c = try XCTUnwrap(Credentials(keychainData: Data(json.utf8)))
        XCTAssertEqual(c.plan, "Max 20x")
        XCTAssertFalse(c.description.contains("secret-token"))
        XCTAssertFalse("\(c)".contains("secret-token"))
        XCTAssertTrue(c.isExpired(at: Date(timeIntervalSince1970: 1_761_300_000)))
        XCTAssertFalse(c.isExpired(at: Date(timeIntervalSince1970: 1_761_299_999)))
        XCTAssertNil(Credentials(keychainData: Data(#"{"claudeAiOauth": {}}"#.utf8)))
    }

    func testPlanNames() {
        XCTAssertEqual(Credentials.planName(subscriptionType: "pro", tier: "default_claude_pro"), "Pro")
        XCTAssertEqual(Credentials.planName(subscriptionType: "max", tier: "default_claude_max_5x"), "Max 5x")
        XCTAssertEqual(Credentials.planName(subscriptionType: nil, tier: nil), "Claude")
    }

    func testResetAndDurationText() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Athens")!
        let locale = Locale(identifier: "en_GB")
        let now = Date(timeIntervalSince1970: 1_792_816_800)       // 2026-10-24 07:40 Athens (Sat)
        XCTAssertEqual(Format.reset(now.addingTimeInterval(80 * 60), now: now, calendar: cal, locale: locale), "Resets 09:00 · in 1 h 20 m")
        XCTAssertTrue(Format.reset(now.addingTimeInterval(2 * 86400 + 3 * 3600), now: now, calendar: cal, locale: locale)
            .hasSuffix("· in 2 d 3 h"))
        XCTAssertEqual(Format.reset(now.addingTimeInterval(-5), now: now, calendar: cal, locale: locale), "Resets now")
        XCTAssertEqual(Format.reset(now.addingTimeInterval(80 * 60 - 0.2), now: now, calendar: cal, locale: locale), "Resets 09:00 · in 1 h 20 m")
        XCTAssertEqual(Format.duration(45 * 60), "45 m")
        XCTAssertEqual(Format.duration(59), "1 m")
        XCTAssertEqual(Format.duration(3600), "1 h")
    }

    func testLevels() {
        func l(_ p: Double, _ s: String? = "normal") -> Limit { Limit(kind: "session", percent: p, severity: s, resetsAt: nil, scope: nil) }
        XCTAssertEqual(Format.level(of: l(12)), .normal)
        XCTAssertEqual(Format.level(of: l(80)), .warning)
        XCTAssertEqual(Format.level(of: l(20, "high")), .warning)
        XCTAssertEqual(Format.level(of: l(95)), .critical)
    }

    func testMoneyAndExtraUsage() throws {
        XCTAssertEqual(Format.money(Money(amountMinor: 1250, currency: "USD", exponent: 2), locale: Locale(identifier: "en_US")), "$12.50")
        let on = try JSONDecoder().decode(ExtraUsage.self, from: Data(#"{"is_enabled": true, "monthly_limit": 50, "used_credits": 12.5, "currency": "USD"}"#.utf8))
        XCTAssertEqual(Format.extraUsage(on), "12.50 of 50.00 USD this month")
    }
}

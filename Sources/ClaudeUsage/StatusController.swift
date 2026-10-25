import AppKit
import ServiceManagement
import UsageCore

/// The menu bar item. Opening its menu is the only thing that checks usage:
/// the menu shows the last answer at once (marked "Checking…"), asks
/// Anthropic, and redraws itself in place when the answer arrives. No timer.
final class StatusController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let client = UsageClient()
    private var last: (result: UsageClient.Result, at: Date)?
    private var error: FetchError?
    private var checking = false
    private var menuOpen = false
    private let sessionsClient = SessionsClient()
    private let navigator = Navigator()
    private var sessions: [AgentSession] = []
    private var sessionsError: String?
    private var listingSessions = false

    static let width: CGFloat = 330

    override init() {
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        item.button?.image = StatusIcon.image
        item.button?.toolTip = "Claude subscription usage"
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        if !checking { check() }
        if !listingSessions { listSessions() }
        build()
    }

    func menuWillOpen(_ menu: NSMenu) { menuOpen = true }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false }

    private func check() {
        checking = true
        client.fetch { [weak self] result in
            guard let self else { return }
            checking = false
            switch result {
            case .success(let r): last = (r, Date()); error = nil
            case .failure(let e): error = e
            }
            if menuOpen { build() }
        }
    }

    private func listSessions() {
        listingSessions = true
        sessionsClient.fetch { [weak self] result in
            guard let self else { return }
            listingSessions = false
            switch result {
            case .success(let list): sessions = list; sessionsError = nil
            case .failure(let f): sessionsError = f.text
            }
            if menuOpen { build() }
        }
    }

    // MARK: Menu

    private func build() {
        menu.removeAllItems()
        let now = Date()
        let status = checking ? "Checking…" : last.map { "Updated \(Self.time.string(from: $0.at))" } ?? ""
        add(view: HeaderView(title: "Claude \(last?.result.plan ?? "subscription")".replacingOccurrences(of: "Claude Claude", with: "Claude"),
                             status: status))

        if let error {
            add(view: MessageView(title: error.title, detail: error.detail))
        }
        if let report = last?.result.report {
            if !report.limits.isEmpty {
                menu.addItem(.sectionHeader(title: "Plan limits"))
                for limit in report.limits {
                    add(view: LimitView(title: Format.title(of: limit), percent: limit.percent, level: Format.level(of: limit),
                                        reset: limit.resetsAt.map { Format.reset($0, now: now) }))
                }
            }
            if let rows = report.weekBreakdown?.rows, !rows.isEmpty {
                menu.addItem(.sectionHeader(title: "This week by product"))
                for row in rows { add(view: RowView(label: row.displayName, value: Format.percent(row.percent))) }
            }
            if report.extraUsage != nil || report.spend?.used != nil {
                menu.addItem(.sectionHeader(title: "Beyond the plan"))
                if let e = report.extraUsage { add(view: RowView(label: "Extra usage", value: Format.extraUsage(e))) }
                if let used = report.spend?.used {
                    let limit = report.spend?.limit.map { " of \(Format.money($0))" } ?? ""
                    add(view: RowView(label: "Credits spent", value: Format.money(used) + limit))
                }
            }
        } else if error == nil {
            add(view: MessageView(title: "Asking Anthropic…", detail: "Your usage appears here in a moment."))
        }

        addSessions()

        menu.addItem(.separator())
        action("Open Usage on claude.ai", #selector(openUsage))
        let billing = action("Billing and Renewal Date…", #selector(openBilling))
        billing.toolTip = "Anthropic does not report the renewal date to apps; it is on the billing page."
        menu.addItem(.separator())
        let login = action("Open at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let quit = action("Quit Claude Usage", #selector(NSApplication.terminate(_:)), target: NSApp)
        quit.keyEquivalent = "q"
    }

    /// The open Claude Code sessions; choosing one takes you there.
    private func addSessions() {
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: sessions.isEmpty ? "Claude Code sessions" : "Claude Code sessions · \(sessions.count)"))
        if let sessionsError {
            add(view: MessageView(title: "Sessions unavailable", detail: sessionsError))
        } else if sessions.isEmpty {
            add(view: RowView(label: listingSessions ? "Looking…" : "None open", value: ""))
        }
        for (i, s) in sessions.enumerated() {
            let mi = NSMenuItem(title: s.title, action: #selector(openSession(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = i
            let where_ = s.isBackground ? "background" : AgentSession.shortPath(s.cwd)
            let text = NSMutableAttributedString(string: s.title, attributes: [.font: NSFont.menuFont(ofSize: 13)])
            text.append(NSAttributedString(string: "\n\(where_) · \(s.activity)",
                                           attributes: [.font: NSFont.menuFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
            mi.attributedTitle = text
            mi.image = Self.dot(for: s.attention)
            mi.toolTip = "\(s.cwd)\nSession \(s.sessionId)"
            menu.addItem(mi)
        }
    }

    @objc private func openSession(_ sender: NSMenuItem) {
        guard sessions.indices.contains(sender.tag) else { return }
        let s = sessions[sender.tag]
        navigator.go(to: s) { problem in
            let alert = NSAlert()
            alert.messageText = "Could not open “\(s.title)”"
            alert.informativeText = problem
            NSApp.activate()
            alert.runModal()
        }
    }

    /// Orange: needs you (blocked, waiting). Green: working. Grey: idle.
    private static func dot(for attention: AgentSession.Attention) -> NSImage {
        let color: NSColor = switch attention {
        case .needsYou: .systemOrange
        case .working: .systemGreen
        case .idle: .tertiaryLabelColor
        }
        return NSImage(size: NSSize(width: 10, height: 10), flipped: false) { r in
            color.setFill()
            NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }

    private func add(view: NSView) {
        let mi = NSMenuItem()
        mi.view = view
        menu.addItem(mi)
    }

    @discardableResult
    private func action(_ title: String, _ selector: Selector, target: AnyObject? = nil) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        mi.target = target ?? self
        menu.addItem(mi)
        return mi
    }

    @objc private func openUsage() { NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!) }
    @objc private func openBilling() { NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/billing")!) }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            NSSound.beep()
        }
    }

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("HH:mm")
        return f
    }()
}

// MARK: Menu rows

private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = .systemFont(ofSize: size, weight: weight)
    l.textColor = color
    l.lineBreakMode = .byTruncatingTail
    l.translatesAutoresizingMaskIntoConstraints = false
    return l
}

/// A fixed-width row with the menu's standard 14 pt side insets.
private class Row: NSView {
    init(height: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: StatusController.width, height: height))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: StatusController.width).isActive = true
        heightAnchor.constraint(equalToConstant: height).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func pin(_ left: NSView, _ right: NSView?, y: CGFloat) {
        addSubview(left)
        left.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14).isActive = true
        left.topAnchor.constraint(equalTo: topAnchor, constant: y).isActive = true
        if let right {
            addSubview(right)
            right.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14).isActive = true
            right.firstBaselineAnchor.constraint(equalTo: left.firstBaselineAnchor).isActive = true
            left.trailingAnchor.constraint(lessThanOrEqualTo: right.leadingAnchor, constant: -8).isActive = true
        } else {
            left.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14).isActive = true
        }
    }
}

private final class HeaderView: Row {
    init(title: String, status: String) {
        super.init(height: 30)
        pin(label(title, size: 13, weight: .semibold), label(status, size: 11, color: .secondaryLabelColor), y: 7)
    }
    required init?(coder: NSCoder) { fatalError() }
}

private final class MessageView: Row {
    init(title: String, detail: String) {
        super.init(height: 42)
        pin(label(title, size: 13, weight: .medium), nil, y: 3)
        pin(label(detail, size: 11, color: .secondaryLabelColor), nil, y: 21)
    }
    required init?(coder: NSCoder) { fatalError() }
}

private final class RowView: Row {
    init(label text: String, value: String) {
        super.init(height: 22)
        pin(label(text, size: 13), label(value, size: 13, color: .secondaryLabelColor), y: 2)
    }
    required init?(coder: NSCoder) { fatalError() }
}

private final class LimitView: Row {
    init(title: String, percent: Double, level: Format.Level, reset: String?) {
        super.init(height: reset == nil ? 40 : 56)
        let color: NSColor = switch level {
        case .normal: .controlAccentColor
        case .warning: .systemOrange
        case .critical: .systemRed
        }
        pin(label(title, size: 13), label(Format.percent(percent), size: 13, weight: .semibold), y: 3)
        let bar = Bar(fraction: percent / 100, color: color)
        addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            bar.topAnchor.constraint(equalTo: topAnchor, constant: 23),
            bar.heightAnchor.constraint(equalToConstant: 6),
        ])
        if let reset { pin(label(reset, size: 11, color: .secondaryLabelColor), nil, y: 34) }
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// A rounded progress bar on a faint track.
private final class Bar: NSView {
    private let fraction: Double
    private let color: NSColor

    init(fraction: Double, color: NSColor) {
        self.fraction = min(max(fraction, 0), 1)
        self.color = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.height / 2
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: r, yRadius: r).fill()
        guard fraction > 0 else { return }
        var fill = bounds
        fill.size.width = max(bounds.height, bounds.width * fraction)
        color.setFill()
        NSBezierPath(roundedRect: fill, xRadius: r, yRadius: r).fill()
    }
}

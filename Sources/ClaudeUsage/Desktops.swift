import AppKit

// Read-only SkyLight calls (private, as used by Tiler): which desktop (Space) a
// window is on and which one a display shows. Nothing here changes Spaces;
// switching is done with the user's own Mission Control shortcuts.
typealias SpaceID = UInt64

@_silgen_name("SLSMainConnectionID") private func SLSMainConnectionID() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> Unmanaged<CFArray>?
@_silgen_name("SLSManagedDisplayGetCurrentSpace") private func SLSManagedDisplayGetCurrentSpace(_ cid: Int32, _ display: CFString) -> SpaceID
@_silgen_name("SLSManagedDisplayIsAnimating") private func SLSManagedDisplayIsAnimating(_ cid: Int32, _ display: CFString) -> Bool
@_silgen_name("SLSCopySpacesForWindows") private func SLSCopySpacesForWindows(_ cid: Int32, _ mask: Int32, _ ids: CFArray) -> Unmanaged<CFArray>?
@_silgen_name("_AXUIElementGetWindow") private func _AXUIElementGetWindow(_ e: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

private enum Spaces {
    static let cid = SLSMainConnectionID()

    /// Each display ("Main" when Displays have separate Spaces is off) with its Spaces in Mission Control order.
    static func displays() -> [(display: String, spaces: [SpaceID])] {
        guard let list = CGSCopyManagedDisplaySpaces(cid)?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return list.map { d in
            let spaces = (d["Spaces"] as? [[String: Any]] ?? []).compactMap {
                (($0["ManagedSpaceID"] ?? $0["id64"]) as? NSNumber)?.uint64Value
            }
            return (d["Display Identifier"] as? String ?? "Main", spaces)
        }
    }

    static func current(_ display: String) -> SpaceID { SLSManagedDisplayGetCurrentSpace(cid, display as CFString) }
    static func animating(_ display: String) -> Bool { SLSManagedDisplayIsAnimating(cid, display as CFString) }

    static func of(window: CGWindowID) -> [SpaceID] {
        let r = SLSCopySpacesForWindows(cid, 0x7, [NSNumber(value: window)] as CFArray)?.takeRetainedValue() as? [NSNumber]
        return (r ?? []).map(\.uint64Value)
    }

    static func isVisible(_ space: SpaceID) -> Bool {
        displays().contains { $0.spaces.contains(space) && current($0.display) == space }
    }
}

/// The user's Mission Control "Move left/right a space" shortcut (symbolic
/// hotkeys 79 and 81); nil when turned off.
private struct MissionControlShortcut {
    let keyCode: CGKeyCode
    let flags: CGEventFlags

    static func read(forward: Bool) -> MissionControlShortcut? {
        guard let all = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys"),
              let entry = all[forward ? "81" : "79"] as? [String: Any] else {
            // Never customised: macOS uses its default, Control (+fn) + arrow.
            return MissionControlShortcut(keyCode: forward ? 0x7C : 0x7B, flags: [.maskControl, .maskSecondaryFn])
        }
        guard (entry["enabled"] as? Bool) ?? ((entry["enabled"] as? Int) == 1),
              let value = entry["value"] as? [String: Any],
              let p = value["parameters"] as? [Int], p.count == 3 else { return nil }
        return MissionControlShortcut(keyCode: CGKeyCode(p[1]), flags: CGEventFlags(rawValue: UInt64(p[2])))
    }

    func post() {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down) else { continue }
            e.flags = flags
            e.post(tap: .cghidEventTap)
        }
    }
}

/// Shows the desktop a given window is on. Runs off the main thread.
///
/// The window is found by its Accessibility identifier (cmux names its
/// windows "cmux.main.<UUID>"). macOS lists an app's windows on other desktops
/// only partly, so when it is not listed, the desktops holding the app's other
/// unlisted windows are visited in turn until it shows up.
enum DesktopSwitcher {
    /// Nil once the window's desktop is on screen, else what went wrong.
    static func reveal(pid: pid_t, axIdentifier: String) -> String? {
        guard AXIsProcessTrusted() else {
            DispatchQueue.main.async {
                AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
            }
            return "To go to a window on another desktop, allow Claude Usage in System Settings › Privacy & Security › Accessibility, then choose the session again."
        }
        let listed = axWindows(pid: pid)
        if let id = listed[axIdentifier] {
            let spaces = Spaces.of(window: id)
            if spaces.isEmpty || spaces.contains(where: Spaces.isVisible) { return nil }
            return show(spaces[0]) ? nil : "Could not switch to the window's desktop (check the Mission Control shortcuts “Move left/right a space”)."
        }
        // Not listed: it is on a desktop not shown. Try the desktops of the app's unlisted windows.
        let known = Set(listed.values)
        var candidates: [SpaceID] = []
        for id in normalWindows(pid: pid) where !known.contains(id) {
            for s in Spaces.of(window: id) where !Spaces.isVisible(s) && !candidates.contains(s) { candidates.append(s) }
        }
        for space in candidates {
            guard show(space) else { return "Could not switch desktops (check the Mission Control shortcuts “Move left/right a space”)." }
            if axWindows(pid: pid)[axIdentifier] != nil { return nil }
        }
        return "Could not find that cmux window on any desktop."
    }

    /// AX identifier → window id, for the app's windows macOS lists.
    private static func axWindows(pid: pid_t) -> [String: CGWindowID] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [:] }
        var result: [String: CGWindowID] = [:]
        for w in windows {
            var ident: AnyObject?
            var id: CGWindowID = 0
            guard AXUIElementCopyAttributeValue(w, kAXIdentifierAttribute as CFString, &ident) == .success,
                  let name = ident as? String, _AXUIElementGetWindow(w, &id) == .success, id != 0 else { continue }
            result[name] = id
        }
        return result
    }

    /// The app's normal windows on any desktop (layer 0, not tiny); no window titles needed.
    private static func normalWindows(pid: pid_t) -> [CGWindowID] {
        let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { w in
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid, (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b),
                  r.width > 200, r.height > 200 else { return nil }
            return w[kCGWindowNumber as String] as? CGWindowID
        }
    }

    /// Step the space's display to it with "Move left/right a space", one
    /// desktop at a time, the pointer briefly on that display (the shortcut acts
    /// on the display under the pointer). True when it is shown.
    private static func show(_ space: SpaceID) -> Bool {
        guard let d = Spaces.displays().first(where: { $0.spaces.contains(space) }) else { return false }
        let current = Spaces.current(d.display)
        guard let from = d.spaces.firstIndex(of: current), let to = d.spaces.firstIndex(of: space) else { return false }
        if from == to { return true }
        guard let shortcut = MissionControlShortcut.read(forward: to > from) else { return false }
        let saved = CGEvent(source: nil)?.location
        if let screen = screen(for: d.display) { CGWarpMouseCursorPosition(CGPoint(x: screen.midX, y: screen.midY)) }
        for _ in 0..<abs(to - from) {
            let before = Spaces.current(d.display)
            shortcut.post()
            // A bounded wait for the switch to finish (50 ms checks, at most 1.5 s).
            var waited = 0.0
            repeat {
                Thread.sleep(forTimeInterval: 0.05)
                waited += 0.05
            } while waited < 1.5 && (Spaces.current(d.display) == before || Spaces.animating(d.display))
            Thread.sleep(forTimeInterval: 0.1)
        }
        if let saved { CGWarpMouseCursorPosition(saved) }
        return Spaces.current(d.display) == space
    }

    /// The display's frame in top-left (window server) coordinates.
    private static func screen(for display: String) -> CGRect? {
        let screens = NSScreen.screens
        guard let primary = screens.first?.frame.height else { return nil }
        let match = display == "Main" ? screens.first : screens.first { s in
            guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(n)?.takeRetainedValue() else { return false }
            return (CFUUIDCreateString(nil, uuid) as String) == display
        }
        guard let f = match?.frame else { return nil }
        return CGRect(x: f.minX, y: primary - f.maxY, width: f.width, height: f.height)
    }
}

// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit

enum KeyboardInputMode: String, Codable, CaseIterable, Sendable {
    case shortcutsOnly
    case globalMonitoring

    var displayName: String {
        switch self {
        case .shortcutsOnly: String(localized: "No global keyboard monitoring")
        case .globalMonitoring: String(localized: "Advanced keyboard monitoring")
        }
    }
}

/// An application policy, independent of macOS permissions (including Accessibility).
/// In restricted mode, unknown event types are denied: adding an API or mask requires an explicit review here.
struct KeyboardInputPolicy: Equatable, Sendable {
    let mode: KeyboardInputMode

    init(mode: KeyboardInputMode = .shortcutsOnly) {
        self.mode = mode
    }

    var allowsGlobalKeyboardMonitoring: Bool {
        mode == .globalMonitoring
    }

    private static let mouseEventMask: CGEventMask = [
        CGEventType.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
        .mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged
    ].reduce(0) { $0 | (CGEventMask(1) << $1.rawValue) }

    private static let mouseMonitorMask: NSEvent.EventTypeMask = [
        .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
        .mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged
    ]

    func createEventTap<T>(mask: CGEventMask, create: () -> T?) -> T? {
        guard allowsGlobalKeyboardMonitoring || (mask != 0 && mask & ~Self.mouseEventMask == 0) else {
            return nil
        }
        return create()
    }

    func createGlobalMonitor<T>(mask: NSEvent.EventTypeMask, create: () -> T?) -> T? {
        guard allowsGlobalKeyboardMonitoring
            || (!mask.isEmpty && mask.subtracting(Self.mouseMonitorMask).isEmpty)
        else { return nil }
        return create()
    }

    func readGlobalModifiers(read: () -> NSEvent.ModifierFlags) -> NSEvent.ModifierFlags? {
        guard allowsGlobalKeyboardMonitoring else { return nil }
        return read()
    }

    func requestInputMonitoring(request: () -> Bool) -> Bool {
        guard allowsGlobalKeyboardMonitoring else { return false }
        return request()
    }
}

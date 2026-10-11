// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

@preconcurrency import AppKit
import IOKit.hidsystem

/// The only boundary allowed to open global event streams or poll keyboard state.
/// Freeze the policy for the lifetime of the process: a settings reload cannot enable
/// monitoring, and selecting a different mode requires restarting the application.
enum GlobalInputAccess {
    static let policy = KeyboardInputPolicy(
        mode: KeyboardInputPreference.configuredMode(in: SettingsFilePersistence.fileURL)
    )

    // Keep the native signature at this boundary to make every tap subscription auditable.
    // swiftlint:disable:next function_parameter_count
    static func createEventTap(
        tap: CGEventTapLocation,
        place: CGEventTapPlacement,
        options: CGEventTapOptions,
        eventsOfInterest: CGEventMask,
        callback: CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer?
    ) -> CFMachPort? {
        policy.createEventTap(mask: eventsOfInterest) {
            CGEvent.tapCreate(
                tap: tap, place: place, options: options,
                eventsOfInterest: eventsOfInterest, callback: callback, userInfo: userInfo
            )
        }
    }

    static func addGlobalMonitor(
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> Void
    ) -> Any? {
        policy.createGlobalMonitor(mask: mask) {
            NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
        }
    }

    static var modifierFlags: NSEvent.ModifierFlags? {
        policy.readGlobalModifiers { NSEvent.modifierFlags }
    }

    static func capsLockState(connection: io_connect_t) -> Bool? {
        guard policy.allowsGlobalKeyboardMonitoring else { return nil }
        var isLocked = false
        guard IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState), &isLocked) == KERN_SUCCESS else {
            return nil
        }
        return isLocked
    }

    static func inputMonitoringAccessGranted() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    static func requestInputMonitoringAccess() -> Bool {
        policy.requestInputMonitoring { IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
    }
}

// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Carbon
@testable import OmniWM
import XCTest

final class KeyboardInputPolicyTests: XCTestCase {
    func testDefaultPolicyNeverCallsKeyboardAcquisitionFactories() {
        let policy = KeyboardInputPolicy()
        XCTAssertEqual(policy.mode, .shortcutsOnly)
        var calls = 0
        for type in [CGEventType.keyDown, .keyUp, .flagsChanged] {
            let keyMask = CGEventMask(1) << type.rawValue
            for mask in [keyMask, keyMask | (1 << CGEventType.leftMouseDown.rawValue)] {
                let result: Int? = policy.createEventTap(mask: mask) { calls += 1
                    return 1
                }
                XCTAssertNil(result)
            }
        }
        for mask: NSEvent.EventTypeMask in [.keyDown, .keyUp, .flagsChanged, [.leftMouseDown, .keyDown], .any] {
            let result: Int? = policy.createGlobalMonitor(mask: mask) { calls += 1
                return 1
            }
            XCTAssertNil(result)
        }
        XCTAssertNil(policy.readGlobalModifiers { calls += 1
            return .command
        })
        XCTAssertFalse(policy.requestInputMonitoring { calls += 1
            return true
        })
        // Permission grants cannot affect these decisions: none of the native factories was entered.
        XCTAssertEqual(calls, 0)
    }

    func testOnlyReviewedMouseEventBitsCanReachEventTapFactory() {
        let policy = KeyboardInputPolicy()
        let allowed: Set<UInt32> = [1, 2, 3, 4, 5, 6, 7, 22, 25, 26, 27]
        for bit in UInt32(0) ..< 64 {
            var called = false
            let result: Bool? = policy.createEventTap(mask: CGEventMask(1) << bit) { called = true
                return true
            }
            XCTAssertEqual(called, allowed.contains(bit), "event type \(bit)")
            XCTAssertEqual(result != nil, allowed.contains(bit))
        }
        for mask: CGEventMask in [0, .max] {
            let result: Bool? = policy.createEventTap(mask: mask) { XCTFail("Unsafe mask")
                return true
            }
            XCTAssertNil(result)
        }
    }

    func testMouseOnlyGlobalMonitorsRemainAvailable() {
        let policy = KeyboardInputPolicy()
        var calls = 0
        let result = policy.createGlobalMonitor(mask: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) {
            calls += 1
            return "mouse"
        }
        XCTAssertEqual(result, "mouse")
        XCTAssertEqual(calls, 1)
        for mask in [NSEvent.EventTypeMask(), NSEvent.EventTypeMask(rawValue: 1 << 63)] {
            let denied: Bool? = policy.createGlobalMonitor(mask: mask) { XCTFail("Unsafe mask")
                return true
            }
            XCTAssertNil(denied)
        }
    }

    func testAdvancedMonitoringRequiresExplicitOptIn() {
        let policy = KeyboardInputPolicy(mode: .globalMonitoring)
        XCTAssertEqual(policy.createEventTap(mask: 1 << CGEventType.keyDown.rawValue) { "tap" }, "tap")
        XCTAssertEqual(policy.createGlobalMonitor(mask: .flagsChanged) { "monitor" }, "monitor")
        XCTAssertEqual(policy.readGlobalModifiers { .shift }, .shift)
        XCTAssertTrue(policy.requestInputMonitoring { true })
    }

    func testStartupPreferenceFailsClosed() {
        for text in [
            "", "[general]\nhotkeysEnabled = true", "[general]\nkeyboardInputMode = true",
            "[general]\nkeyboardInputMode = \"futureMode\"", "[general\ninvalid",
            "[general]\nkeyboardInputMode = \"globalMonitoring\"\ninvalid = [",
            "schemaVersion = 999\n[general]\nkeyboardInputMode = \"globalMonitoring\""
        ] {
            XCTAssertEqual(KeyboardInputPreference.configuredMode(in: Data(text.utf8)), .shortcutsOnly)
        }
        for mode in KeyboardInputMode.allCases {
            let data = Data("[general]\nkeyboardInputMode = \"\(mode.rawValue)\"".utf8)
            XCTAssertEqual(KeyboardInputPreference.configuredMode(in: data), mode)
        }
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertEqual(KeyboardInputPreference.configuredMode(in: missing), .shortcutsOnly)
    }

    func testSettingsRoundTripAndLegacyDefault() throws {
        var settings = SettingsExport.defaults()
        XCTAssertEqual(settings.keyboardInputMode, .shortcutsOnly)
        for mode in KeyboardInputMode.allCases {
            settings.keyboardInputMode = mode
            let data = try SettingsTOMLCodec.encode(settings)
            XCTAssertEqual(try SettingsTOMLCodec.decode(data), settings)
            XCTAssertEqual(KeyboardInputPreference.configuredMode(in: data), mode)
            XCTAssertFalse(SettingsTOMLCodec.unknownKeyPaths(in: data).contains("general.keyboardInputMode"))
        }
        let oldSettings = String(decoding: try SettingsTOMLCodec.encode(settings), as: UTF8.self)
            .split(separator: "\n").filter { !$0.hasPrefix("keyboardInputMode = ") }.joined(separator: "\n")
        let result = try SettingsTOMLCodec.decodeForLoad(Data(oldSettings.utf8))
        XCTAssertEqual(result.export.keyboardInputMode, .shortcutsOnly)
        XCTAssertNil(result.migration)
    }

    func testAllDefaultKeyboardShortcutsStillUseRegisteredHotkeys() {
        let bindings = HotkeyBindingRegistry.defaults()
        let strict = HotkeyCenter.registrationPlan(for: bindings)
        let advanced = HotkeyCenter.registrationPlan(for: bindings, policy: .init(mode: .globalMonitoring))
        XCTAssertFalse(strict.registrations.isEmpty)
        XCTAssertEqual(strict.registrations, advanced.registrations)
        XCTAssertTrue(strict.sideSpecificRegistrations.isEmpty)
        XCTAssertEqual(strict.failures, advanced.failures)
    }

    func testSidedBindingsAreRejectedWithoutChangingStandardBindings() {
        let standard = KeyBinding(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(optionKey))
        let sided = KeyBinding(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(optionKey)).settingSide(.left)
        let bindings = [
            HotkeyBinding(id: "focus.left", command: .focus(.left), binding: standard),
            HotkeyBinding(id: "focus.right", command: .focus(.right), binding: sided)
        ]
        let plan = HotkeyCenter.registrationPlan(for: bindings)
        XCTAssertEqual(plan.registrations.map(\.command), [.focus(.left)])
        XCTAssertTrue(plan.sideSpecificRegistrations.isEmpty)
        XCTAssertEqual(plan.failures, [.focus(.right): .disabledByKeyboardPrivacy])
    }
}

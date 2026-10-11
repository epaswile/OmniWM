// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import CoreGraphics
import Darwin
import Foundation

// Run independently of OmniWM: swift Scripts/audit-keyboard-event-taps.swift 60
// This enumerates subscriptions, never events or typed characters. It only covers
// CoreGraphics event taps visible to CGGetEventTapList at each sampling instant.

func inconclusive(_ message: String) -> Never {
    print("INCONCLUSIVE: \(message)")
    exit(2)
}

func eventMask(_ types: [CGEventType]) -> CGEventMask {
    types.reduce(0) { $0 | (CGEventMask(1) << $1.rawValue) }
}

func eventTaps() -> [CGEventTapInformation] {
    var capacity: UInt32 = 64
    for _ in 0 ..< 5 {
        var taps = Array(repeating: CGEventTapInformation(), count: Int(capacity))
        var count: UInt32 = 0
        let status = CGGetEventTapList(capacity, &taps, &count)
        guard status == .success else {
            inconclusive("CGGetEventTapList failed (\(status.rawValue)).")
        }
        if count < capacity {
            return Array(taps.prefix(Int(count)))
        }
        capacity = max(capacity * 2, count + 1)
    }
    inconclusive("Could not obtain a complete event-tap inventory.")
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--help"] {
    print("Usage: swift Scripts/audit-keyboard-event-taps.swift [seconds: 1...3600] [bundle ID]")
    print("Defaults: 30 seconds, com.barut.OmniWM.dev. Keep the app running throughout the check.")
    print("Exit codes: 0 = no non-mouse taps observed; 1 = non-mouse tap observed; 2 = inconclusive.")
    exit(0)
}

guard arguments.count <= 2,
      let duration = Double(arguments.first ?? "30"), duration.isFinite, (1 ... 3600).contains(duration)
else {
    inconclusive("Invalid arguments. Use --help for usage.")
}

let bundleID = arguments.count == 2 ? arguments[1] : "com.barut.OmniWM.dev"
let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
guard !apps.isEmpty else {
    inconclusive("No running app with bundle ID \(bundleID). Start OmniWM before testing.")
}

let initialPIDs = Set(apps.map(\.processIdentifier))
for app in apps {
    print("Target: PID=\(app.processIdentifier) path=\(app.bundleURL?.path ?? "unknown")")
}

print("Sampling every 250 ms for \(duration) s. Disabled subscriptions are included.")
print("No keystrokes are read. Test ordinary typing, shortcuts and OmniWM panels during this time.")

let keyboardMask = eventMask([.keyDown, .keyUp, .flagsChanged])
let mouseMask = eventMask([
    .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
    .mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel,
    .otherMouseDown, .otherMouseUp, .otherMouseDragged
])
let start = ProcessInfo.processInfo.systemUptime
var samples = 0
var foundNonMouseTap = false
var previousInventory: [String]?

while true {
    let currentPIDs = Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .map(\.processIdentifier))
    guard currentPIDs == initialPIDs,
          initialPIDs.allSatisfy({ kill($0, 0) == 0 })
    else {
        inconclusive("The target process changed or exited. Restart the check after relaunching OmniWM.")
    }

    let owned = eventTaps().filter { initialPIDs.contains($0.tappingProcess) }
    let keyboard = owned.filter { $0.eventsOfInterest & keyboardMask != 0 }
    let other = owned.filter {
        $0.eventsOfInterest == 0 || $0.eventsOfInterest & ~(mouseMask | keyboardMask) != 0
    }
    let inventory = owned.map { tap in
        "  pid=\(tap.tappingProcess) tap=\(tap.eventTapID) "
            + "mask=0x\(String(tap.eventsOfInterest, radix: 16)) enabled=\(tap.enabled)"
    }.sorted()
    if inventory != previousInventory {
        print("totalEventTaps=\(owned.count) keyboardEventTaps=\(keyboard.count) otherEventTaps=\(other.count)")
        inventory.forEach { print($0) }
        previousInventory = inventory
    }
    foundNonMouseTap = foundNonMouseTap || !keyboard.isEmpty || !other.isEmpty
    samples += 1

    let remaining = duration - (ProcessInfo.processInfo.systemUptime - start)
    if remaining <= 0 { break }
    RunLoop.current.run(until: Date().addingTimeInterval(min(0.25, remaining)))
}

if foundNonMouseTap {
    print("ALERT: A keyboard or other non-mouse subscription was observed during \(samples) samples.")
} else {
    print("OBSERVED: No keyboard or other non-mouse event taps in \(samples) samples over \(duration) s.")
}

print("Limits: sampling can miss short-lived taps; HID, keyboard-state polling, registered hotkeys,")
print("local app input and Accessibility text reads are outside this check. This is not a complete privacy proof.")
exit(foundNonMouseTap ? 1 : 0)

// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

@preconcurrency import AppKit
import Carbon
import Foundation
import IOKit.hidsystem

extension HotkeyCenter {
    nonisolated static func bindingFacts(
        for bindings: [HotkeyBinding],
        policy: KeyboardInputPolicy = KeyboardInputPolicy()
    ) -> [HotkeyBindingFact] {
        let failures = registrationPlan(for: bindings, policy: policy).failures
        return bindings.compactMap { binding in
            let trigger = binding.binding
            guard !trigger.isUnassigned else { return nil }
            let route = failures[binding.command].map { "unregistered(\($0))" } ?? registeredRoute(for: trigger)
            return HotkeyBindingFact(command: binding.command.displayName, display: trigger.displayString, route: route)
        }
    }

    private nonisolated static func registeredRoute(for trigger: HotkeyTrigger) -> String {
        if trigger.mouseButtonBinding != nil { return "mouse" }
        return trigger.chordBinding?.sidedModifiers.isEmpty == false ? "sided" : "carbon"
    }

    static func decisionLabel(_ decision: HyperTriggerStateMachine.Decision) -> String {
        switch decision {
        case .suppress: "suppress"
        case .passThrough: "passThrough"
        case .inject: "inject"
        case .toggleCapsLock: "toggleCapsLock"
        }
    }

    nonisolated static func inputMonitoringAccessGranted() -> Bool {
        GlobalInputAccess.inputMonitoringAccessGranted()
    }

    @discardableResult
    nonisolated static func requestInputMonitoringAccess() -> Bool {
        GlobalInputAccess.requestInputMonitoringAccess()
    }

    nonisolated static func registrationPlan(
        for bindings: [HotkeyBinding],
        policy: KeyboardInputPolicy = KeyboardInputPolicy()
    ) -> HotkeyRegistrationPlan {
        let candidates = bindings.filter { !$0.binding.isUnassigned }

        var failures: [HotkeyCommand: HotkeyRegistrationFailureReason] = [:]
        for index in candidates.indices {
            let overlaps = candidates.indices.contains { other in
                other != index && candidates[index].binding.conflicts(with: candidates[other].binding)
            }
            if overlaps {
                failures[candidates[index].command] = .duplicateBinding
            }
        }

        var registrations: [HotkeyPlannedRegistration] = []
        var sideSpecific: [HotkeyPlannedRegistration] = []
        var mouseButtons: [MouseButtonBinding: HotkeyCommand] = [:]
        for candidate in candidates where failures[candidate.command] == nil {
            switch candidate.binding {
            case let .chord(binding):
                let registration = HotkeyPlannedRegistration(binding: binding, command: candidate.command)
                if binding.sidedModifiers.isEmpty {
                    registrations.append(registration)
                } else if policy.allowsGlobalKeyboardMonitoring {
                    sideSpecific.append(registration)
                } else {
                    failures[candidate.command] = .disabledByKeyboardPrivacy
                }
            case let .mouseButton(binding):
                mouseButtons[binding] = candidate.command
            case .unassigned:
                break
            }
        }

        return HotkeyRegistrationPlan(
            registrations: registrations,
            sideSpecificRegistrations: sideSpecific,
            mouseButtonRegistrations: mouseButtons,
            failures: failures
        )
    }
}

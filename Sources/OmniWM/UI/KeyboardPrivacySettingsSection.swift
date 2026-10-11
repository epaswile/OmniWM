// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import SwiftUI

struct KeyboardPrivacySettingsSection: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Section("Keyboard privacy") {
            Picker("Keyboard input mode", selection: $settings.keyboardInputMode) {
                ForEach(KeyboardInputMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            LabeledContent("Active mode", value: GlobalInputAccess.policy.mode.displayName)
            if settings.keyboardInputMode != GlobalInputAccess.policy.mode {
                SettingsCaption(
                    localized: "Restart OmniWM to apply the selected keyboard input mode. The active mode is unchanged until restart."
                )
            }
            SettingsCaption(
                localized: "Without global keyboard monitoring, OmniWM receives only registered shortcuts and input in its own windows. System Hyper, Left/Right-specific modifiers, modifier-hold reveal, and Escape outside OmniWM panels are disabled. Mouse controls remain available."
            )
            SettingsCaption(
                localized: "This protection applies even when Accessibility or Input Monitoring is granted. Accessibility remains necessary for window management."
            )
        }
    }
}

extension SystemHyperTriggerFailure {
    var localizedMessage: String {
        switch self {
        case .disabledByKeyboardPrivacy:
            String(
                localized: "System Hyper is disabled without global keyboard monitoring. Standard shortcuts remain available."
            )
        case .eventTapUnavailable:
            String(localized: "System Hyper trigger is unavailable: grant Input Monitoring permission.")
        case .capsLockRemapUnavailable:
            String(localized: "System Hyper trigger is unavailable: Caps Lock remapping failed.")
        }
    }
}

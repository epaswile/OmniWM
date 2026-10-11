// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation
import TOML

enum KeyboardInputPreference {
    /// Read only, before the permissions window or SettingsStore can start services.
    /// Missing, unreadable, malformed and unrecognized settings all fail closed.
    static func configuredMode(in fileURL: URL) -> KeyboardInputMode {
        guard let targetURL = try? SettingsFileAccess.settingsTarget(for: fileURL),
              let data = try? SettingsFileAccess.existingData(at: targetURL)
        else { return .shortcutsOnly }
        return configuredMode(in: data)
    }

    static func configuredMode(in data: Data) -> KeyboardInputMode {
        guard let settings = try? TOMLDecoder().decode([String: TOMLNode].self, from: data) else {
            return .shortcutsOnly
        }
        if let version = settings["schemaVersion"] {
            guard case let .integer(value) = version,
                  (0 ... Int64(SettingsTOMLCodec.currentSchemaVersion)).contains(value)
            else { return .shortcutsOnly }
        }
        guard case let .table(general)? = settings["general"],
              case let .string(value)? = general["keyboardInputMode"],
              let mode = KeyboardInputMode(rawValue: value)
        else { return .shortcutsOnly }
        return mode
    }
}

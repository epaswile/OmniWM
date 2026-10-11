#!/usr/bin/env python3
"""Reject known global keyboard acquisition APIs outside the reviewed boundary.

Deliberately inspect comments and strings too: dynamic symbol lookups must not
bypass this check. This is a regression guard, not a sandbox or a security proof.
"""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
BOUNDARY = "Sources/OmniWM/Core/Input/GlobalInputAccess.swift"
# Only these existing, policy-guarded entry points have been reviewed. Introducing
# another acquisition API requires updating this list and its behavioral tests.
REVIEWED = {
    "tapCreate", "addGlobalMonitorForEvents", "NSEvent.modifierFlags",
    "IOHIDRequestAccess", "IOHIDGetModifierLockState",
}
APIS = re.compile(
    r"\b(?:"
    r"tapCreate\w*|CGEventTapCreate\w*|addGlobalMonitorForEvents|"
    r"CGEventSource(?:KeyState|FlagsState)|CGRequestListenEventAccess|"
    r"GetKeys|GetCurrent(?:Event)?KeyModifiers|kEventRawKey\w*|"
    r"IOHIDRequestAccess|IOHIDGetModifierLockState|"
    r"IOHID(?:Manager|Device)Register\w*|IOHID(?:Manager|Device)Get\w*Value\w*|"
    r"IOHIDEventSystemClient(?:Register\w*|CopyEvent)|IOHIDQueue\w*|"
    r"NSEvent\s*\.\s*modifierFlags|CGEventSource\s*\.\s*(?:keyState|flagsState)"
    r")\b"
)
ALIASES = re.compile(r"\btypealias\s+\w+\s*=\s*(?:\w+\.)?(?:NSEvent|CGEventSource)\b")


def violations(source, relative_path):
    found = []
    for pattern in (APIS, ALIASES):
        for match in pattern.finditer(source):
            api = re.sub(r"\s+", "", match.group())
            if relative_path == BOUNDARY and api in REVIEWED:
                continue
            line = source.count("\n", 0, match.start()) + 1
            found.append(f"{relative_path}:{line}: unreviewed global input API: {match.group()}")
    return found


def check(root):
    errors = []
    if not (root / BOUNDARY).is_file():
        errors.append(f"Missing required global input boundary: {BOUNDARY}")
    for path in sorted((root / "Sources").rglob("*")):
        if path.is_file() and path.suffix in {".swift", ".m", ".mm", ".c", ".h", ".cc", ".cpp", ".cxx", ".hpp", ".hxx"}:
            errors.extend(violations(path.read_text(), path.relative_to(root).as_posix()))
    return errors


if __name__ == "__main__":
    errors = check(ROOT)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        sys.exit("Global input must go through GlobalInputAccess and respect KeyboardInputPolicy.")
    print("Keyboard input boundary check passed.")

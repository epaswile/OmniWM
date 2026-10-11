import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("keyboard_policy", ROOT / "Scripts/check-keyboard-input-policy.py")
checker = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checker)


class KeyboardInputBoundaryTests(unittest.TestCase):
    def test_repository_has_no_bypasses(self):
        self.assertEqual(checker.check(ROOT), [])

    def test_global_capture_variants_are_rejected(self):
        for api in [
            "CGEvent.tapCreate", "CGEvent.tapCreateForPid", "CGEventTapCreate",
            "NSEvent.addGlobalMonitorForEvents", "NSEvent .\n modifierFlags",
            "CGEventSource.keyState", "CGEventSourceFlagsState", "GetKeys",
            "IOHIDRequestAccess", "IOHIDManagerRegisterInputValueCallback",
            "IOHIDDeviceRegisterInputReportCallback", "IOHIDDeviceGetValue",
            "IOHIDGetModifierLockState", "CGRequestListenEventAccess",
            "kEventRawKeyDown", 'dlsym(handle, "CGEventTapCreate")',
            "typealias InputEvent = AppKit.NSEvent",
        ]:
            with self.subTest(api=api):
                self.assertTrue(checker.violations(api, "Sources/NewFeature.swift"))

    def test_new_apis_are_not_implicitly_allowed_inside_boundary(self):
        self.assertEqual(checker.violations("CGEvent.tapCreate", checker.BOUNDARY), [])
        self.assertTrue(checker.violations("CGEventSource.keyState", checker.BOUNDARY))

    def test_local_events_mouse_state_and_registered_hotkeys_are_allowed(self):
        source = """
        NSEvent.addLocalMonitorForEvents(matching: .keyDown)
        event.modifierFlags
        NSEvent.pressedMouseButtons
        RegisterEventHotKey(key, modifiers, id, target, 0, &ref)
        GlobalInputAccess.addGlobalMonitor(matching: .leftMouseDown)
        """
        self.assertEqual(checker.violations(source, "Sources/Feature.swift"), [])

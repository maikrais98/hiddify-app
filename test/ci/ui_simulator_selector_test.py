import importlib.util
import pathlib
import unittest

path = pathlib.Path(__file__).resolve().parents[2] / "scripts/ui_test_simulator_id.py"
spec = importlib.util.spec_from_file_location("selector", path)
selector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selector)


class SimulatorSelectorTests(unittest.TestCase):
    def inventory(self, runtime="iOS-26-5", count=1, available=True):
        return {"devices": {f"com.apple.CoreSimulator.SimRuntime.{runtime}": [
            {"name": "WIR UI Verification", "udid": f"test-{index}", "isAvailable": available}
            for index in range(count)]}}

    def test_selects_only_one_named_available_ios_simulator(self):
        self.assertEqual("test-0", selector.select_device(self.inventory()))

    def test_refuses_missing_ambiguous_unavailable_or_non_ios(self):
        for data in [self.inventory(count=0), self.inventory(count=2),
                     self.inventory(available=False), self.inventory(runtime="tvOS-26-5"),
                     {"devices": {"physical": [{"name": "WIR UI Verification", "udid": "phone", "isAvailable": True}]}}]:
            with self.subTest(data=data), self.assertRaises(ValueError):
                selector.select_device(data)

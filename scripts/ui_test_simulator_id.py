#!/usr/bin/env python3
"""Select one explicitly named available iOS test simulator; never pick a phone."""
import json
import subprocess
import sys


def select_device(inventory):
    matches = [device for runtime, devices in inventory.get("devices", {}).items()
               if runtime.startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
               for device in devices if device.get("isAvailable") is True
               and device.get("name") == "WIR UI Verification"]
    if len(matches) != 1:
        raise ValueError("Expected exactly one available WIR UI Verification iOS Simulator")
    return matches[0]["udid"]


if __name__ == "__main__":
    try:
        result = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "--json"],
                                check=True, capture_output=True, text=True)
        print(select_device(json.loads(result.stdout)))
    except (ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"Simulator selection refused: {type(error).__name__}", file=sys.stderr)
        sys.exit(1)

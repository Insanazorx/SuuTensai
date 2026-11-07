#!/usr/bin/env python3
"""Apple JSON çıktısından tek hedef seçer; kişisel cihaz bilgilerini kaydetmez."""
import json
import sys

mode, filename = sys.argv[1:]
with open(filename) as stream:
    data = json.load(stream)
if mode == "device":
    candidates = []
    for device in data["result"]["devices"]:
        hardware = device.get("properties", {}).get("hardware", device.get("hardwareProperties", {}))
        if hardware.get("reality") == "physical" and hardware.get("platform") == "iOS":
            candidates.append(hardware.get("udid") or device["identifier"])
else:
    candidates = [device["udid"] for devices in data["devices"].values() for device in devices if device["state"] == "Booted"]
if len(candidates) != 1:
    sys.exit("Tek hedef seçilemedi. --device UDID veya --simulator UDID kullan; --list-devices ile listele.")
print(candidates[0])

#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
if [[ "${1:-}" == --help ]]; then printf 'Kullanım: bash Scripts/test-ios.sh [SİMÜLATÖR_UDID]\n         bash Scripts/test-ios.sh --device auto|IPHONE_UDID [--team TEAM_ID]\n'; exit 0; fi
rigor_apple_environment
rigor_require python3
mkdir -p "$rigor_root/.build/tmp"
rigor_mode=simulator
rigor_target="${1:-auto}"
rigor_team="${RIGOR_TEAM_ID:-auto}"
rigor_sdk=iphonesimulator
rigor_derived="$rigor_root/.build/iOS"
rigor_signing=(CODE_SIGNING_ALLOWED=NO)
if [[ "${1:-}" == --device ]]; then
    rigor_mode=device
    rigor_target="${2:?--device auto veya UDID gerektirir}"
    if [[ "${3:-}" == --team ]]; then rigor_team="${4:?--team bir takım gerektirir}"; fi
    if [[ "$rigor_team" == auto ]]; then rigor_team="$(python3 "$rigor_root/Scripts/signing-team.py")"; fi
    rigor_sdk=iphoneos
    rigor_derived="$rigor_root/.build/iPhone"
    rigor_signing=("DEVELOPMENT_TEAM=$rigor_team" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates -allowProvisioningDeviceRegistration)
fi
if [[ "$rigor_target" == auto ]]; then
    rigor_devices="$(mktemp "$rigor_root/.build/tmp/ui-simulators.XXXXXX")"
    trap 'rm -f "$rigor_devices"' EXIT
    if [[ "$rigor_mode" == device ]]; then
        xcrun devicectl list devices --timeout 30 --json-output "$rigor_devices" >/dev/null
    else
        xcrun simctl list devices booted --json > "$rigor_devices"
    fi
    rigor_target="$(python3 "$rigor_root/Scripts/apple-device.py" "$rigor_mode" "$rigor_devices")"
fi
if [[ "$rigor_mode" == simulator ]]; then xcrun simctl bootstatus "$rigor_target" -b; fi
rigor_result="$rigor_root/.build/iOS-UI-$rigor_mode-$(date +%Y%m%d-%H%M%S).xcresult"
xcodebuild -project "$rigor_root/iOS/Rigor.xcodeproj" -scheme Rigor \
    -configuration Debug -sdk "$rigor_sdk" -destination "id=$rigor_target" \
    -derivedDataPath "$rigor_derived" -clonedSourcePackagesDirPath "$rigor_root/.build/SourcePackages" \
    -resultBundlePath "$rigor_result" -parallel-testing-enabled NO "${rigor_signing[@]}" test
printf 'UI test raporu: %s\n' "$rigor_result"

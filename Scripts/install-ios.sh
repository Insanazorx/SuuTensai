#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
rigor_mode=simulator
rigor_target=generic
rigor_team="${RIGOR_TEAM_ID:-${DEVELOPMENT_TEAM:-auto}}"
rigor_configuration=Debug
rigor_install=false
rigor_run=false
rigor_list=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --device) rigor_mode=device; rigor_target="${2:?--device auto veya UDID gerektirir}"; shift 2 ;;
        --simulator)
            rigor_mode=simulator; rigor_target=generic; shift
            if [[ $# -gt 0 && "$1" != --* ]]; then rigor_target="$1"; shift; fi ;;
        --team) rigor_team="${2:?--team auto veya TEAM_ID gerektirir}"; shift 2 ;;
        --configuration) rigor_configuration="${2:?--configuration Debug veya Release gerektirir}"; shift 2 ;;
        --install) rigor_install=true; shift ;;
        --run) rigor_install=true; rigor_run=true; shift ;;
        --build-only) rigor_install=false; rigor_run=false; shift ;;
        --list-devices) rigor_list=true; shift ;;
        -h|--help)
            cat <<'HELP'
Kullanım: ./install.sh ios [seçenekler]
  --simulator [UDID]          Simülatör build'i (varsayılan, imza gerekmez)
  --device auto|UDID          Gerçek iPhone build'i (Apple hesabıyla imzalanır)
  --team auto|TEAM_ID         İmzalama takımı; varsayılan tek geçerli sertifikadan seçilir
  --configuration Debug|Release
  --install                  Build'i hedefe yükle
  --run                      Build'i yükle ve aç
  --build-only               Yalnızca build hazırla (varsayılan)
  --list-devices             Apple cihaz/simülatör listesini göster
HELP
            exit 0 ;;
        *) printf 'Bilinmeyen seçenek: %s\n' "$1" >&2; exit 2 ;;
    esac
done
[[ "$rigor_configuration" == Debug || "$rigor_configuration" == Release ]] || { printf 'Geçersiz yapılandırma.\n' >&2; exit 2; }
rigor_apple_environment
rigor_require python3
mkdir -p "$rigor_root/.build/tmp"
if [[ "$rigor_list" == true ]]; then
    xcrun devicectl list devices
    xcrun simctl list devices available
    exit 0
fi
if [[ "$rigor_mode" == device ]]; then
    if [[ "$rigor_target" == auto ]]; then
        rigor_devices="$(mktemp "$rigor_root/.build/tmp/devices.XXXXXX")"
        trap 'rm -f "$rigor_devices"' EXIT
        xcrun devicectl list devices --timeout 30 --json-output "$rigor_devices" >/dev/null
        rigor_target="$(python3 "$rigor_root/Scripts/apple-device.py" device "$rigor_devices")"
    fi
    if [[ "$rigor_team" == auto ]]; then rigor_team="$(python3 "$rigor_root/Scripts/signing-team.py")"; fi
    [[ "$rigor_team" =~ ^[A-Z0-9]{10}$ ]] || { printf 'Geçersiz Apple Team ID.\n' >&2; exit 2; }
    rigor_derived="$rigor_root/.build/iPhone"
    rigor_sdk=iphoneos
    rigor_destination="generic/platform=iOS"
    rigor_signing=("DEVELOPMENT_TEAM=$rigor_team" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates -allowProvisioningDeviceRegistration)
else
    rigor_derived="$rigor_root/.build/iOS"
    rigor_sdk=iphonesimulator
    rigor_destination="generic/platform=iOS Simulator"
    rigor_signing=(CODE_SIGNING_ALLOWED=NO)
    if [[ "$rigor_install" == true && "$rigor_target" == generic ]]; then
        rigor_devices="$(mktemp "$rigor_root/.build/tmp/simulators.XXXXXX")"
        trap 'rm -f "$rigor_devices"' EXIT
        xcrun simctl list devices booted --json > "$rigor_devices"
        rigor_target="$(python3 "$rigor_root/Scripts/apple-device.py" simulator "$rigor_devices")"
    fi
fi
if [[ "$rigor_target" != generic ]]; then rigor_destination="id=$rigor_target"; fi
xcodebuild -project "$rigor_root/iOS/Rigor.xcodeproj" -scheme Rigor \
    -configuration "$rigor_configuration" -sdk "$rigor_sdk" -destination "$rigor_destination" \
    -derivedDataPath "$rigor_derived" -clonedSourcePackagesDirPath "$rigor_root/.build/SourcePackages" \
    "${rigor_signing[@]}" build
rigor_app="$rigor_derived/Build/Products/$rigor_configuration-$rigor_sdk/Rigor.app"
printf 'iOS build: %s\n' "$rigor_app"
if [[ "$rigor_install" == true ]]; then
    if [[ "$rigor_mode" == device ]]; then
        xcrun devicectl device install app --device "$rigor_target" "$rigor_app" --timeout 60
        if [[ "$rigor_run" == true ]]; then xcrun devicectl device process launch --device "$rigor_target" dev.suutensai.rigor --terminate-existing --timeout 30; fi
    else
        xcrun simctl bootstatus "$rigor_target" -b
        xcrun simctl install "$rigor_target" "$rigor_app"
        if [[ "$rigor_run" == true ]]; then xcrun simctl launch --terminate-running-process "$rigor_target" dev.suutensai.rigor; fi
    fi
fi

#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
rigor_package_only=false
rigor_skip_build=false
rigor_code=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --package-only) rigor_package_only=true; shift ;;
        --skip-build) rigor_skip_build=true; shift ;;
        --code) rigor_code="${2:?--code bir yol gerektirir}"; shift 2 ;;
        -h|--help)
            printf 'Kullanım: ./install.sh vscode [--package-only] [--skip-build] [--code VS_CODE_YOLU]\n'
            exit 0 ;;
        *) printf 'Bilinmeyen seçenek: %s\n' "$1" >&2; exit 2 ;;
    esac
done
rigor_require python3
if [[ "$rigor_skip_build" == false ]]; then bash "$rigor_root/Scripts/build.sh" debug; fi
rigor_vsix="$(python3 "$rigor_root/Scripts/package-vscode.py")"
[[ -f "$rigor_vsix" ]] || { printf 'VSIX paketi bulunamadı.\n' >&2; exit 1; }
printf 'VS Code paketi: %s\n' "$rigor_vsix"
if [[ "$rigor_package_only" == false ]]; then
    if [[ -z "$rigor_code" ]]; then rigor_code="$(rigor_code_path)"; fi
    "$rigor_code" --install-extension "$rigor_vsix" --force
    printf 'VS Code: Developer: Reload Window komutunu çalıştır ve proje kökünü aç.\n'
fi

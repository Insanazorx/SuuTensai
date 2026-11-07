#!/usr/bin/env bash
set -euo pipefail
rigor_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rigor_require() {
    command -v "$1" >/dev/null 2>&1 || { printf 'Gerekli araç bulunamadı: %s\n' "$1" >&2; exit 1; }
}
rigor_apple_environment() {
    if [[ "$(uname -s)" != Darwin ]]; then
        printf 'iOS hedefi için macOS ve Xcode gerekir.\n' >&2; exit 1
    fi
    if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
        export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    fi
    rigor_require xcodebuild
    rigor_require xcrun
}
rigor_code_path() {
    if command -v code >/dev/null 2>&1; then command -v code
    elif [[ -x '/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code' ]]; then
        printf '%s\n' '/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code'
    else printf 'VS Code bulunamadı; --code ile yürütülebilir yolunu belirt.\n' >&2; return 1
    fi
}

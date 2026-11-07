#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
export CLANG_MODULE_CACHE_PATH="$project_root/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_root/.build/ModuleCache"
if [[ "$(uname -s)" == "Darwin" && -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
exec swift build --package-path "$project_root" --product SuuTensai \
    --configuration "${1:-debug}" --disable-sandbox \
    --cache-path "$project_root/.build/cache" \
    --config-path "$project_root/.build/config" \
    --security-path "$project_root/.build/security"

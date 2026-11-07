#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$project_root/.build/ModuleCache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$project_root/.build/ModuleCache}"

test_command=(
    swift test --package-path "$project_root" --disable-sandbox --disable-xctest
    --cache-path "$project_root/.build/cache"
    --config-path "$project_root/.build/config"
    --security-path "$project_root/.build/security"
)

# Some Apple Swift 6.4 Command Line Tools installations omit this plugin from
# swiftbuild's automatically resolved plugins. Use the installed toolchain copy.
if [[ "$(uname -s)" == "Darwin" ]]; then
    swift_compiler="$(xcrun --find swiftc)"
    testing_plugin="$(dirname "$(dirname "$swift_compiler")")/lib/swift/host/plugins/testing/libTestingMacros.dylib"
    if [[ -f "$testing_plugin" ]]; then
        test_command+=(-Xswiftc -load-plugin-library -Xswiftc "$testing_plugin")
    fi
fi

exec "${test_command[@]}" "$@"

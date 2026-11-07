#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$project_root/.build/editor-integration"
mkdir -p "$scratch" "$project_root/.build/ModuleCache"
core_sources=()
while IFS= read -r file; do core_sources+=("$file"); done < <(rg --files "$project_root/Sources/SuuTensai" -g '*.swift')

xcrun swiftc -swift-version 6 -enable-upcoming-feature ApproachableConcurrency \
    -module-cache-path "$project_root/.build/ModuleCache" \
    -emit-library -emit-module -module-name SuuTensai \
    -emit-module-path "$scratch/SuuTensai.swiftmodule" \
    "${core_sources[@]}" -o "$scratch/libSuuTensai.dylib"

xcrun swiftc -swift-version 6 -parse-as-library \
    -module-cache-path "$project_root/.build/ModuleCache" \
    -I "$scratch" -L "$scratch" -lSuuTensai \
    -Xlinker -rpath -Xlinker "$scratch" \
    "$project_root/iOS/Rigor/EditorModel.swift" \
    "$project_root/Tests/EditorIntegration/EditorSmoke.swift" \
    -o "$scratch/EditorSmoke"

"$scratch/EditorSmoke" "$project_root"

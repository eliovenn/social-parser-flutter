#!/usr/bin/env bash
# Linux host validation of the bundled QuickJS engine. Requires Rust and libclang.
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
fjs_dir="$(dart run tool/package_path.dart fjs)"
export FLUTTER_ROOT="${FLUTTER_ROOT:-$(dirname "$(dirname "$(readlink -f "$(command -v flutter)")")")}"
export CARGOKIT_TOOL_TEMP_DIR="$task_root/build/js-verification/tool"
export CARGOKIT_CONFIGURATION=release
export CARGOKIT_TARGET_TEMP_DIR="$task_root/build/js-verification/target"
export CARGOKIT_OUTPUT_DIR="$task_root/build/js-verification/native"
export CARGOKIT_MANIFEST_DIR="$fjs_dir/libfjs"
export CARGOKIT_ROOT_PROJECT_DIR="$task_root"
export CARGOKIT_TARGET_PLATFORM=linux-x64
mkdir -p "$CARGOKIT_OUTPUT_DIR"
bash "$fjs_dir/cargokit/run_build_tool.sh" build-cmake
export LD_LIBRARY_PATH="$CARGOKIT_OUTPUT_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
flutter test --no-pub packages/social_parser_js/test
dart run tool/git_dependency_smoke.dart

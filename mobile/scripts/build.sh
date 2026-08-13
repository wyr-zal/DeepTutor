#!/usr/bin/env bash
# Compatibility launcher. The actual build always runs in Windows PowerShell.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-both}"
CMD_EXE="/mnt/c/Windows/System32/cmd.exe"
[[ -x "${CMD_EXE}" ]] || {
  echo "Windows CMD interop is required for the Windows-native build." >&2
  exit 1
}

BAT_SCRIPT="$(wslpath -w "${SCRIPT_DIR}/build.bat")"
export WSLENV="${WSLENV:+${WSLENV}:}SERVER_URL:ALLOW_SERVER_ENTRY:CLEAN:INSTALL:NO_TREE_SHAKE:FLUTTER_HOME:ANDROID_HOME:ANDROID_SDK_ROOT:ANDROID_AVD_HOME:PUB_CACHE:GRADLE_USER_HOME:JAVA_HOME"

echo "[DeepTutor] Delegating to the Windows-native CMD build..."
exec "${CMD_EXE}" /d /c call "${BAT_SCRIPT}" "${MODE}"

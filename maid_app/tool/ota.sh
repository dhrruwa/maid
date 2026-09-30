#!/bin/bash
# Over-the-air updates for the Maid app with Shorebird. See docs/OTA.md.
#
#   tool/ota.sh release       new APK (dist/Maid.apk) to install once on the phone:
#                             first time, and after native changes (new plugin,
#                             permission, icon, pubspec version bump)
#   tool/ota.sh patch         Dart changes → phones on the latest release get
#                             them at their next start
#   tool/ota.sh ios-release   the same for the iPhone (development build)
#   tool/ota.sh ios-patch
#
# Always builds with ../dart_defines.json: a patch without the Supabase key
# would break every call on the phone.
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-}" in
  release | patch | ios-release | ios-patch) ;;
  *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac

DEFINES=../dart_defines.json
export PATH="$HOME/.shorebird/bin:$HOME/.local/flutter/bin:$PATH"

[ -f "$DEFINES" ] || { echo "Missing $DEFINES (Supabase keys): see docs/SETUP_GUIDE.md step 6." >&2; exit 1; }
[ -f shorebird.yaml ] || { echo "Not set up yet: run 'shorebird login' and 'shorebird init' (docs/OTA.md)." >&2; exit 1; }

case "${1:-}" in
  release)
    shorebird release android --artifact apk --dart-define-from-file="$DEFINES"
    mkdir -p ../dist
    cp build/app/outputs/flutter-apk/app-release.apk ../dist/Maid.apk
    echo "Install ../dist/Maid.apk on the phone once (it updates the old app in place)."
    ;;
  patch)
    shorebird patch android --release-version=latest --dart-define-from-file="$DEFINES"
    ;;
  ios-release)
    shorebird release ios --export-method development --dart-define-from-file="$DEFINES"
    ;;
  ios-patch)
    shorebird patch ios --release-version=latest --dart-define-from-file="$DEFINES"
    ;;
esac

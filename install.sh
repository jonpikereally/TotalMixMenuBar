#!/bin/zsh
# Build MixBar and install it to ~/Applications, then launch it. Run from
# Terminal: apps can't run from inside Dropbox, and Claude's sandbox can't
# write to ~/Applications.
set -e
cd "$(dirname "$0")"
fail() {
  echo
  echo "Error $1: $2"
  echo "Look up this code on the MixBar error list:"
  echo "  https://github.com/jonpikereally/TotalMixMenuBar/blob/main/ERRORS.md"
  exit 1
}
./build.sh
APP="$HOME/Applications/MixBar.app"
pkill -x MixBar 2>/dev/null || true
sleep 0.5
mkdir -p ~/Applications || fail MB-601 "Couldn't create ~/Applications."
rm -rf "$APP"
ditto --norsrc MixBar.app "$APP" || fail MB-601 "Couldn't copy MixBar into ~/Applications."
# Sign outside Dropbox, after stripping xattrs, so the sync client can't slip any in between.
xattr -cr "$APP"
codesign --force --sign - "$APP" || fail MB-602 "Couldn't sign MixBar for this Mac."
# Ad-hoc signing changes identity on every rebuild, which silently voids the old grant.
tccutil reset Accessibility com.jonpike.mixbar >/dev/null 2>&1 || true
open "$APP" || fail MB-603 "MixBar was installed but couldn't be opened. Open it from ~/Applications yourself."
echo "Installed $APP"
echo "Turn MixBar on when macOS asks for Accessibility (that's what lets the volume keys control TotalMix)."

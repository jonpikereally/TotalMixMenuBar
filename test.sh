#!/bin/zsh
# Builds a test runner from the app's protocol code and drives it against a
# fake TotalMix (Tests/fake_totalmix.py) on spare ports.
set -e
cd "$(dirname "$0")"
CACHE="${TMPDIR:-/tmp}/mixbar-modcache"
mkdir -p "$CACHE"
[[ -f Sources/MixBar/Version.swift ]] || ./build.sh >/dev/null
swiftc -module-cache-path "$CACHE" -o "$CACHE/mixbar-tests" \
  Tests/main.swift Sources/MixBar/{OSC,Mixer,Prefs,Errors,Version}.swift
LOG="$CACHE/fake-totalmix.log"
if [[ "$1" == "--snapshot" ]]; then
  swiftc -module-cache-path "$CACHE" -o "$CACHE/mixbar-snapshot" \
    Tests/Snapshot/main.swift $(ls Sources/MixBar/*.swift | grep -v main.swift) 2>&1 | grep -v xcrun_db || true
  python3 -I Tests/fake_totalmix.py 7192 9192 "$LOG" &
  FAKE=$!
  trap "kill $FAKE 2>/dev/null" EXIT
  sleep 0.5
  mkdir -p "${2:-$CACHE}"
  "$CACHE/mixbar-snapshot" 7192 9192 "${2:-$CACHE}"
  exit
fi
python3 -I Tests/fake_totalmix.py 7191 9191 "$LOG" &
FAKE=$!
trap "kill $FAKE 2>/dev/null" EXIT
sleep 0.5
"$CACHE/mixbar-tests" 7191 9191
echo "--- what the fake TotalMix received:"
grep -v -e '^/sendall' -e '^/sendstate' "$LOG"

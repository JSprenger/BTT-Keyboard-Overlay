#!/bin/bash
# Baut das App-Bundle "Tastaturübersicht+.app" nach ./build.
#
# Wichtig: als .app-Bundle (mit stabiler Bundle-ID und Ad-hoc-Signatur)
# bekommt die App eine eigene Identität für die Berechtigung
# „Eingabeüberwachung" – bei einem nackten CLI-Binary würde die
# Berechtigung stattdessen am Terminal hängen.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Tastaturübersicht+.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/KeyboardOverlay "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force -s - "$APP"

echo "Fertig: $APP"

#!/usr/bin/env bash
# Builds the Windows release of The Appalachian Trail:
#   build/AppalachianTrail-Setup-<version>.exe        (installer)
#   build/AppalachianTrail-<version>-Windows-Portable.zip
#
# Needs: Godot 4.3 (set GODOT=/path/to/godot) with the 4.3 export templates
# installed, plus python3 (Pillow not required) and zip.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
GODOT="${GODOT:-godot}"
VERSION="$(grep -oP 'config/version="\K[^"]+' project.godot)"
TEMPLATES="${TEMPLATES:-$HOME/.local/share/godot/export_templates/4.3.stable}"
[ -f "$TEMPLATES/windows_release_x86_64.exe" ] || TEMPLATES="$APPDATA/Godot/export_templates/4.3.stable"
echo "== The Appalachian Trail $VERSION"

mkdir -p build/templates installer/payload
rm -f build/AppalachianTrail.exe build/*.zip build/AppalachianTrail-Setup*.exe installer/payload/*

# 1. brand the Windows templates (icon + version info) without rcedit
COPY="© 2026 Ironite. All rights reserved."
python3 tools/pe_resources.py "$TEMPLATES/windows_release_x86_64.exe" build/templates/game_template.exe \
  --icon branding/game.ico --version "$VERSION.0" --company Ironite --product "The Appalachian Trail" \
  --description "The Appalachian Trail" --copyright "$COPY" --original AppalachianTrail.exe
python3 tools/pe_resources.py "$TEMPLATES/windows_release_x86_64.exe" build/templates/setup_template.exe \
  --icon installer/assets/setup.ico --version "$VERSION.0" --company Ironite --product "The Appalachian Trail" \
  --description "The Appalachian Trail Setup" --copyright "$COPY" --original "AppalachianTrail-Setup-$VERSION.exe"

# keep the installer's version in step with the game
sed -i "s/^config\/version=.*/config\/version=\"$VERSION\"/" installer/project.godot

# 2. export the game
"$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
"$GODOT" --headless --path "$ROOT" --export-release "Windows Desktop" build/AppalachianTrail.exe 2>&1 | grep -E "ERROR|error" | grep -v "Parameter \"m\"" || true
[ -f build/AppalachianTrail.exe ] || { echo "game export failed"; exit 1; }

# 3. payload for the installer + portable zip
STAGE="$(mktemp -d)"
cp build/AppalachianTrail.exe branding/game.ico README.md CHANGELOG.md CREDITS.md "$STAGE/"
(cd "$STAGE" && zip -q -9 "$ROOT/installer/payload/game.zip" ./*)
(cd "$STAGE" && zip -q -9 "$ROOT/build/AppalachianTrail-$VERSION-Windows-Portable.zip" AppalachianTrail.exe README.md CHANGELOG.md CREDITS.md)
rm -rf "$STAGE"

# 4. export the installer
"$GODOT" --headless --path "$ROOT/installer" --import >/dev/null 2>&1 || true
(cd installer && "$GODOT" --headless --path . --export-release "Windows Setup" "../build/AppalachianTrail-Setup-$VERSION.exe" 2>&1 | grep -E "ERROR|error" || true)
[ -f "build/AppalachianTrail-Setup-$VERSION.exe" ] || { echo "installer export failed"; exit 1; }

ls -lh build/*.exe build/*.zip

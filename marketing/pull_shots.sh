#!/bin/bash
# Extrait les captures produites par PicpicUITests/MarketingShots vers
# marketing/shots/, en 1320x2868 natif.
#
# La variable doit porter le prefixe TEST_RUNNER_ : xcodebuild ne transmet pas
# l'environnement du shell au processus de test, seulement les variables ainsi
# prefixees. Sans ca les cas sont ignores et le test passe au vert a vide.
#
#   TEST_RUNNER_PICPIC_CAPTURE=1 xcodebuild test \
#     -project Picpic.xcodeproj -scheme Picpic \
#     -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
#     -only-testing:PicpicUITests/MarketingShots \
#     -resultBundlePath /tmp/picpic_shots.xcresult
#   ./marketing/pull_shots.sh
set -euo pipefail

BUNDLE="${1:-/tmp/picpic_shots.xcresult}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/marketing/shots"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

xcrun xcresulttool export attachments --path "$BUNDLE" --output-path "$TMP" >/dev/null
mkdir -p "$DEST"

# le manifeste donne le nom logique de chaque piece jointe (home_full, sudoc_full...)
python3 - "$TMP" "$DEST" <<'PY'
import json, pathlib, re, shutil, sys
tmp, dest = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
manifest = json.loads((tmp / "manifest.json").read_text())
seen = 0
for test in manifest:
    for att in test.get("attachments", []):
        name = (att.get("suggestedHumanReadableName") or att.get("exportedFileName", "")).removesuffix(".png")
        # xcresulttool suffixe le nom logique d'un index et d'un UUID
        name = re.sub(r"_\d+_[0-9A-Fa-f-]{36}$", "", name)
        src = tmp / att["exportedFileName"]
        # un test qui echoue joint aussi des descriptions d'accessibilite et un
        # enregistrement video : on ne garde que les captures, nommees par shoot()
        if not re.fullmatch(r"[A-Za-z0-9_-]+", name) or not src.exists():
            continue
        if src.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n":
            continue
        shutil.copy(src, dest / f"{name}.png")
        seen += 1
print(f"{seen} captures extraites")
PY

python3 - "$DEST" <<'PY'
import pathlib, sys
from struct import unpack
for f in sorted(pathlib.Path(sys.argv[1]).glob("*.png")):
    head = f.read_bytes()[16:24]
    w, h = unpack(">II", head)
    print(f"  {f.name:22s} {w}x{h}")
PY

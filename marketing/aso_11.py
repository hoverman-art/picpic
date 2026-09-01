#!/usr/bin/env python3
"""Applique le pack ASO 1.1 dans App Store Connect — À LANCER APRÈS
L'APPROBATION DE LA 1.0 (le nom et la création de version sont verrouillés
pendant la review de la première version).

Fait : version 1.1 + nom/sous-titre enrichis + mots-clés optimisés +
texte promo + nouveautés + captures marketing avec accroches (iPhone + iPad).
Nécessite le client `asc.py` (JWT clé API ASC) dans le même dossier ou PYTHONPATH.
"""
import hashlib
import json
import sys
import urllib.request
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, "/private/tmp/claude-501/-Users-gabindepaire-Desktop-Picpic/59e45b0d-45c3-417a-950d-9dc0d6053766/scratchpad")
from asc import call  # noqa: E402

APP = "6807048077"
FRAMED = HERE / "framed"

# --- Le pack ASO (voir docs/ASO-1.1.md pour la logique) ---
NAME = "Picpic : scan & suivi lecture"          # 29/30 — le champ le plus indexé
SUBTITLE = "Bibliothèque, PAL & audio"          # 25/30
KEYWORDS = ("livre,isbn,étagère,roman,BU,étudiant,librairie,médiathèque,"
            "epub,gratuit,gutenberg,booktok,citations")  # 99/100
PROMO = ("Nouveau : lis et écoute les classiques gratuitement (Gutenberg, LibriVox) "
         "et scanne une étagère entière en une photo. Tes données restent sur ton iPhone.")
WHATS_NEW = ("Des améliorations et des corrections pour rendre Picpic encore plus "
             "agréable. Bonne lecture !")

IPHONE_SHOTS = ["home_full.png", "shelfscan_full.png", "freereading_full.png",
                "stats_full.png", "paywall_full.png"]
IPAD_SHOTS = ["ipad_home.png", "ipad_freereading.png", "ipad_stats.png"]

assert len(NAME) <= 30 and len(SUBTITLE) <= 30 and len(KEYWORDS) <= 100
assert len(PROMO) <= 170 and len(WHATS_NEW) <= 4000


def expect(st, out, ctx):
    if st >= 400:
        print(f"ERREUR {ctx}: HTTP {st} {json.dumps(out, ensure_ascii=False)[:500]}")
        sys.exit(1)
    return out


def upload_shot(res_type, relationships, path):
    data = path.read_bytes()
    out = expect(*call("POST", f"/v1/{res_type}", {"data": {
        "type": res_type,
        "attributes": {"fileName": path.name, "fileSize": len(data)},
        "relationships": relationships,
    }}), f"réservation {path.name}")
    shot = out["data"]
    for op in shot["attributes"]["uploadOperations"]:
        chunk = data[op["offset"]: op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], method=op["method"].upper(), data=chunk)
        for h in op.get("requestHeaders", []):
            req.add_header(h["name"], h["value"])
        urllib.request.urlopen(req).read()
    expect(*call("PATCH", f"/v1/{res_type}/{shot['id']}", {"data": {
        "type": res_type, "id": shot["id"],
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()},
    }}), f"commit {path.name}")
    print("  ", path.name, "✔")


# 1. Version 1.1
st, out = call("GET", f"/v1/apps/{APP}/appStoreVersions?filter[versionString]=1.1")
if st == 200 and out.get("data"):
    version_id = out["data"][0]["id"]
    print("version 1.1 déjà là:", version_id)
else:
    out = expect(*call("POST", "/v1/appStoreVersions", {"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": "IOS", "versionString": "1.1"},
        "relationships": {"app": {"data": {"type": "apps", "id": APP}}},
    }}), "création 1.1")
    version_id = out["data"]["id"]
    print("version 1.1 créée:", version_id)

# 2. Nom + sous-titre (appInfo éditable = celui en PREPARE_FOR_SUBMISSION)
st, out = call("GET", f"/v1/apps/{APP}/appInfos")
editable = next((i for i in out["data"]
                 if i["attributes"].get("state") in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED")),
                None)
if not editable:
    print("! Aucun appInfo éditable (1.0 encore en review ?) — nom/sous-titre non modifiés")
else:
    st, out = call("GET", f"/v1/appInfos/{editable['id']}/appInfoLocalizations")
    loc = next(l for l in out["data"] if l["attributes"]["locale"] == "fr-FR")
    expect(*call("PATCH", f"/v1/appInfoLocalizations/{loc['id']}", {"data": {
        "type": "appInfoLocalizations", "id": loc["id"],
        "attributes": {"name": NAME, "subtitle": SUBTITLE},
    }}), "nom/sous-titre")
    print("nom:", NAME, "| sous-titre:", SUBTITLE)

# 3. Textes de la version 1.1
st, out = call("GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations")
vloc = next((l for l in out["data"] if l["attributes"]["locale"] == "fr-FR"), None)
if not vloc:
    out2 = expect(*call("POST", "/v1/appStoreVersionLocalizations", {"data": {
        "type": "appStoreVersionLocalizations",
        "attributes": {"locale": "fr-FR"},
        "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}},
    }}), "localization 1.1")
    vloc = out2["data"]
expect(*call("PATCH", f"/v1/appStoreVersionLocalizations/{vloc['id']}", {"data": {
    "type": "appStoreVersionLocalizations", "id": vloc["id"],
    "attributes": {"keywords": KEYWORDS, "promotionalText": PROMO, "whatsNew": WHATS_NEW},
}}), "textes 1.1")
print("mots-clés / promo / nouveautés : OK")

# 4. Captures avec accroches
for display_type, names in [("APP_IPHONE_67", IPHONE_SHOTS), ("APP_IPAD_PRO_3GEN_129", IPAD_SHOTS)]:
    st, out = call("GET", f"/v1/appStoreVersionLocalizations/{vloc['id']}/appScreenshotSets")
    sset = next((s for s in out["data"] if s["attributes"]["screenshotDisplayType"] == display_type), None)
    if not sset:
        out2 = expect(*call("POST", "/v1/appScreenshotSets", {"data": {
            "type": "appScreenshotSets",
            "attributes": {"screenshotDisplayType": display_type},
            "relationships": {"appStoreVersionLocalization": {
                "data": {"type": "appStoreVersionLocalizations", "id": vloc["id"]}}},
        }}), f"set {display_type}")
        sset = out2["data"]
    st, out = call("GET", f"/v1/appScreenshotSets/{sset['id']}/appScreenshots")
    for old in out.get("data", []):
        call("DELETE", f"/v1/appScreenshots/{old['id']}")
    print(display_type, ":")
    for name in names:
        upload_shot("appScreenshots",
                    {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": sset["id"]}}},
                    FRAMED / name)

print("\nPack ASO 1.1 appliqué. Reste : contenu réel de la 1.1, build, soumission.")

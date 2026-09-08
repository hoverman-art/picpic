#!/usr/bin/env python3
"""Envoi des captures App Store Connect (iPhone 6,9") par l'API.

Le serveur MCP App Store Connect ne couvre pas les captures : il expose les
versions, les localisations, les builds, les avis, les tarifs, mais ni
`appScreenshotSets` ni `appScreenshots`. D'ou ce script, qui refait le chemin
officiel en quatre temps par fichier :

  1. reserver l'image        POST /v1/appScreenshots
  2. pousser les octets      PUT  sur chaque uploadOperation renvoyee
  3. confirmer               PATCH avec la somme MD5 et uploaded=true
  4. verifier l'etat         GET  jusqu'a assetDeliveryState COMPLETE

Signature ES256 par openssl : ni PyJWT ni cryptography ne sont installes, et un
script de publication n'a pas a imposer une installation. La conversion DER vers
R||S est faite a la main, l'API refusant la signature DER telle quelle.

RIEN N'EST ECRIT SANS --go. Par defaut le script se contente de lire et
d'afficher ce qu'il ferait.

  ~/tools/pyimg/bin/python marketing/asc_upload.py            # simulation
  ~/tools/pyimg/bin/python marketing/asc_upload.py --go       # execution
"""
import argparse
import base64
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

KEY_ID = "59GW84MP93"
ISSUER_ID = "c6030ad8-f637-440d-89cd-a17c224d0fd7"
KEY_PATH = "/Users/gabindepaire/Downloads/AuthKey_59GW84MP93.p8"

APP_ID = "6807048077"          # Picpic : scan & suivi lecture
LOCALE = "fr-FR"
VERSION = "1.3"
PLATFORM = "IOS"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = [f"{ROOT}/marketing/asc/{n}.png" for n in
         ("01_scanne", "02_bibliotheque", "03_classiques", "04_retrospective")]

BASE = "https://api.appstoreconnect.apple.com"
# 1320x2868 est une taille « 6,9 pouces », qu'Apple range sous le type 6,7.
# Le script verifie ce choix en listant les jeux deja presents sur la fiche.
DISPLAY_TYPE = "APP_IPHONE_67"


def b64(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def der_to_raw(der):
    """Signature ECDSA : DER (SEQUENCE de deux INTEGER) vers R||S sur 64 octets."""
    assert der[0] == 0x30
    i = 2 + (2 if der[1] & 0x80 else 0)   # saute la longueur, courte ou longue
    out = b""
    for _ in range(2):
        assert der[i] == 0x02
        ln = der[i + 1]
        val = der[i + 2:i + 2 + ln].lstrip(b"\x00")
        out += val.rjust(32, b"\x00")
        i += 2 + ln
    return out


def token():
    now = int(time.time())
    head = b64(json.dumps({"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}).encode())
    body = b64(json.dumps({"iss": ISSUER_ID, "iat": now, "exp": now + 1200,
                           "aud": "appstoreconnect-v1"}).encode())
    signing_input = f"{head}.{body}".encode()
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", KEY_PATH],
                         input=signing_input, capture_output=True, check=True).stdout
    return f"{head}.{body}.{b64(der_to_raw(der))}"


def api(method, path, body=None, headers=None, raw=None, base=BASE, auth=True):
    """auth=False pour les uploadOperations : leur URL est deja signee dans ses
    parametres de requete, et un en-tete Authorization en plus invalide la
    signature — le stockage d'Apple repond alors 400 « Invalid request »."""
    url = path if path.startswith("http") else base + path
    h = {"Authorization": f"Bearer {token()}"} if auth else {}
    if body is not None:
        h["Content-Type"] = "application/json"
    h.update(headers or {})
    data = raw if raw is not None else (json.dumps(body).encode() if body else None)
    req = urllib.request.Request(url, data=data, headers=h, method=method)
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            payload = r.read()
            return json.loads(payload) if payload and r.headers.get(
                "Content-Type", "").startswith("application/") else None
    except urllib.error.HTTPError as e:
        detail = e.read().decode()[:600]
        raise SystemExit(f"{method} {url}\n  HTTP {e.code} : {detail}")


def editable_version(go):
    """Version en cours de preparation, creee au besoin.

    Une capture s'attache a la localisation d'une version modifiable. Si les
    seules versions sont en vente, il n'existe aucune cible : il faut en creer
    une, et c'est une ecriture visible sur la fiche."""
    vs = api("GET", f"/v1/apps/{APP_ID}/appStoreVersions?limit=10")["data"]
    for v in vs:
        if v["attributes"]["appStoreState"] not in ("READY_FOR_SALE", "REPLACED_WITH_NEW_VERSION"):
            print(f"  version modifiable existante : {v['attributes']['versionString']} "
                  f"({v['attributes']['appStoreState']})")
            return v["id"]
    print(f"  aucune version modifiable — il faut creer la {VERSION}")
    if not go:
        return None
    r = api("POST", "/v1/appStoreVersions", {"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": PLATFORM, "versionString": VERSION},
        "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})
    print(f"  version {VERSION} creee")
    return r["data"]["id"]


def localization(version_id, go):
    ls = api("GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations"
                    f"?limit=50")["data"]
    for loc in ls:
        if loc["attributes"]["locale"] == LOCALE:
            return loc["id"]
    print(f"  localisation {LOCALE} absente, creation")
    if not go:
        return None
    r = api("POST", "/v1/appStoreVersionLocalizations", {"data": {
        "type": "appStoreVersionLocalizations",
        "attributes": {"locale": LOCALE},
        "relationships": {"appStoreVersion": {
            "data": {"type": "appStoreVersions", "id": version_id}}}}})
    return r["data"]["id"]


def screenshot_set(loc_id, go):
    sets = api("GET", f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets"
                      f"?limit=50")["data"]
    print(f"  jeux de captures existants : "
          f"{[s['attributes']['screenshotDisplayType'] for s in sets] or 'aucun'}")
    for s in sets:
        if s["attributes"]["screenshotDisplayType"] == DISPLAY_TYPE:
            return s["id"], len(api("GET", f"/v1/appScreenshotSets/{s['id']}/appScreenshots"
                                           f"?limit=50")["data"])
    if not go:
        return None, 0
    r = api("POST", "/v1/appScreenshotSets", {"data": {
        "type": "appScreenshotSets",
        "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
        "relationships": {"appStoreVersionLocalization": {
            "data": {"type": "appStoreVersionLocalizations", "id": loc_id}}}}})
    return r["data"]["id"], 0


def upload(set_id, path):
    blob = open(path, "rb").read()
    name = os.path.basename(path)

    r = api("POST", "/v1/appScreenshots", {"data": {
        "type": "appScreenshots",
        "attributes": {"fileSize": len(blob), "fileName": name},
        "relationships": {"appScreenshotSet": {
            "data": {"type": "appScreenshotSets", "id": set_id}}}}})
    sid = r["data"]["id"]

    for op in r["data"]["attributes"]["uploadOperations"]:
        chunk = blob[op["offset"]:op["offset"] + op["length"]]
        api(op["method"], op["url"], raw=chunk, auth=False,
            headers={h["name"]: h["value"] for h in op["requestHeaders"]})

    api("PATCH", f"/v1/appScreenshots/{sid}", {"data": {
        "type": "appScreenshots", "id": sid,
        "attributes": {"uploaded": True,
                       "sourceFileChecksum": hashlib.md5(blob).hexdigest()}}})

    for _ in range(30):   # Apple traite l'image de son cote
        state = api("GET", f"/v1/appScreenshots/{sid}")["data"]["attributes"][
            "assetDeliveryState"]["state"]
        if state != "UPLOAD_COMPLETE":
            return sid, state
        time.sleep(2)
    return sid, "UPLOAD_COMPLETE"


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--go", action="store_true",
                    help="ecrire reellement sur App Store Connect")
    ap.add_argument("--replace", action="store_true",
                    help="supprimer les captures deja presentes dans le jeu avant "
                         "d'envoyer les nouvelles. Sans cette option elles s'ajoutent, "
                         "et App Store Connect en refuse plus de dix")
    args = ap.parse_args()

    for p in SHOTS:
        if not os.path.exists(p):
            raise SystemExit(f"capture manquante : {p}")

    app = api("GET", f"/v1/apps/{APP_ID}")["data"]["attributes"]
    print(f"App : {app['name']} ({app['bundleId']})")
    print("MODE SIMULATION — rien ne sera ecrit. Ajouter --go pour executer.\n"
          if not args.go else "MODE ECRITURE\n")

    vid = editable_version(args.go)
    if not vid:
        print("\nSimulation arretee ici : la suite exige une version modifiable.")
        return
    lid = localization(vid, args.go)
    if not lid:
        return
    set_id, existing = screenshot_set(lid, args.go)
    if not set_id:
        return
    if existing and args.replace:
        olds = api("GET", f"/v1/appScreenshotSets/{set_id}/appScreenshots?limit=50")["data"]
        print(f"  suppression des {len(olds)} captures existantes")
        if args.go:
            for o in olds:
                api("DELETE", f"/v1/appScreenshots/{o['id']}")
    elif existing:
        print(f"  ! le jeu contient deja {existing} captures — les nouvelles s'ajoutent, "
              f"ce qui ferait {existing + len(SHOTS)} (maximum 10). "
              f"Utiliser --replace pour repartir a zero.")

    if not args.go:
        print("\n" + "\n".join(f"  a envoyer : {os.path.basename(p)}" for p in SHOTS))
        return

    for i, p in enumerate(SHOTS, 1):
        sid, state = upload(set_id, p)
        print(f"  {i}/{len(SHOTS)}  {os.path.basename(p):24s} {state}")
        if state != "COMPLETE":
            print(f"     ! etat inattendu, verifier la capture {sid} dans l'interface")
    print(f"\nTermine. Fiche : https://appstoreconnect.apple.com/apps/{APP_ID}"
          f"/distribution/ios/version/inflight")


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Applique le pack ASO 1.4 sur App Store Connect (voir docs/ASO-1.4.md).

Trois champs, trois regimes differents :

  texte promotionnel  modifiable sur la version EN VENTE, effet immediat
  sous-titre          appInfoLocalization, exige un appInfo modifiable
  mots-cles           appStoreVersionLocalization, exige une version en
                      preparation

D'ou --promo-seul, qui ne touche qu'au premier et ne demande aucune version
nouvelle. Sans cette option, le script cible la version en preparation et
s'arrete si elle n'existe pas : creer une version est une ecriture visible sur
la fiche, ce n'est pas au script de la decider.

RIEN N'EST ECRIT SANS --go.

  ~/tools/pyimg/bin/python marketing/aso_apply.py                 # simulation
  ~/tools/pyimg/bin/python marketing/aso_apply.py --promo-seul --go
  ~/tools/pyimg/bin/python marketing/aso_apply.py --go            # pack complet
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from asc import call  # noqa: E402

APP = "6807048077"
LOCALE = "fr-FR"

SUBTITLE = "Bibliothèque, ISBN & étagère"
KEYWORDS = ("roman,epub,poche,bd,lire,manga,booktok,polar,citations,"
            "liseuse,classiques,audio,étudiant,livres")
PROMO = ("Nouveau : cherche dans le Sudoc et vois ce que la BU d'à côté a en rayon. "
         "Scanne une étagère entière en une photo. Lis et écoute les classiques, "
         "gratuitement.")

# Les limites d'Apple, verifiees avant tout appel reseau : un pack trop long
# est rejete champ par champ, avec une erreur qui ne dit pas lequel.
assert len(SUBTITLE) <= 30, len(SUBTITLE)
assert len(KEYWORDS) <= 100, len(KEYWORDS)
assert len(PROMO) <= 170, len(PROMO)

EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
            "METADATA_REJECTED", "WAITING_FOR_REVIEW", "INVALID_BINARY"}


def get(path, ctx):
    st, out = call("GET", path)
    if st >= 400:
        sys.exit(f"ERREUR {ctx} : HTTP {st} {json.dumps(out, ensure_ascii=False)[:400]}")
    return out


def patch(path, body, ctx, go):
    if not go:
        print(f"    [simulation] PATCH {path}")
        return
    st, out = call("PATCH", path, body)
    if st >= 400:
        sys.exit(f"ERREUR {ctx} : HTTP {st} {json.dumps(out, ensure_ascii=False)[:400]}")
    print(f"    ecrit : {ctx}")


def versions():
    return get(f"/v1/apps/{APP}/appStoreVersions?limit=20", "versions")["data"]


def localization(version_id):
    locs = get(f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations?limit=50",
               "localisations")["data"]
    for loc in locs:
        if loc["attributes"]["locale"] == LOCALE:
            return loc
    sys.exit(f"pas de localisation {LOCALE} sur cette version")


def promo_only(go):
    """Le texte promotionnel s'ecrit sur la version en vente."""
    live = [v for v in versions()
            if v["attributes"]["appStoreState"] == "READY_FOR_SALE"]
    if not live:
        sys.exit("aucune version en vente")
    live.sort(key=lambda v: v["attributes"]["createdDate"], reverse=True)
    v = live[0]
    print(f"  version en vente : {v['attributes']['versionString']}")
    loc = localization(v["id"])
    print(f"  promo actuelle : {loc['attributes']['promotionalText'] or '(vide)'}")
    print(f"  promo visee    : {PROMO}  [{len(PROMO)}/170]")
    patch(f"/v1/appStoreVersionLocalizations/{loc['id']}",
          {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"],
                    "attributes": {"promotionalText": PROMO}}},
          "texte promotionnel", go)


def full_pack(go):
    draft = [v for v in versions() if v["attributes"]["appStoreState"] in EDITABLE]
    if not draft:
        sys.exit("aucune version en preparation : le sous-titre et les mots-cles ne "
                 "sont pas modifiables. Cree la 1.4 dans App Store Connect, puis "
                 "relance. (--promo-seul fonctionne sans version nouvelle.)")
    v = draft[0]
    print(f"  version en preparation : {v['attributes']['versionString']}")

    loc = localization(v["id"])
    a = loc["attributes"]
    print(f"  mots-cles actuels : {a['keywords']}")
    print(f"  mots-cles vises   : {KEYWORDS}  [{len(KEYWORDS)}/100]")
    patch(f"/v1/appStoreVersionLocalizations/{loc['id']}",
          {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"],
                    "attributes": {"keywords": KEYWORDS, "promotionalText": PROMO}}},
          "mots-cles + promo", go)

    info = get(f"/v1/apps/{APP}/appInfos?limit=10", "appInfos")["data"]
    # L'appInfo modifiable est celui qui n'est pas encore distribue ; sur une
    # fiche sans version en preparation il n'y en a qu'un, deja en vente.
    target = next((i for i in info
                   if i["attributes"]["state"] != "READY_FOR_DISTRIBUTION"), info[0])
    ilocs = get(f"/v1/appInfos/{target['id']}/appInfoLocalizations?limit=50",
                "appInfoLocalizations")["data"]
    iloc = next((l for l in ilocs if l["attributes"]["locale"] == LOCALE), None)
    if iloc is None:
        sys.exit(f"pas de localisation {LOCALE} au niveau de la fiche")
    print(f"  sous-titre actuel : {iloc['attributes']['subtitle']}")
    print(f"  sous-titre vise   : {SUBTITLE}  [{len(SUBTITLE)}/30]")
    patch(f"/v1/appInfoLocalizations/{iloc['id']}",
          {"data": {"type": "appInfoLocalizations", "id": iloc["id"],
                    "attributes": {"subtitle": SUBTITLE}}},
          "sous-titre", go)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--go", action="store_true", help="ecrire reellement")
    ap.add_argument("--promo-seul", action="store_true",
                    help="n'ecrire que le texte promotionnel, sur la version en vente")
    args = ap.parse_args()

    print("=== pack ASO 1.4 ===" + ("" if args.go else "  (SIMULATION)"))
    (promo_only if args.promo_seul else full_pack)(args.go)
    if not args.go:
        print("\nRien n'a ete ecrit. Ajoute --go pour appliquer.")


if __name__ == "__main__":
    main()

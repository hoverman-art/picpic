#!/usr/bin/env python3
"""Passe 2 du bandeau ASO : incrustation des assets reels et decoupe App Store.

La planche (marketing/aso_plate.py) est une scene continue 5504x3072 ou le modele
n'a dessine que ce qui n'existe pas en vrai : fonds, typographie, chassis. Tout le
reste est incruste ici depuis les sources de l'app, parce qu'un modele d'image
redessine systematiquement de travers ce qu'on lui demande de reproduire --
libelles d'interface approximatifs, mascotte hors-modele, icone inventee.

  1. cadrage sur 5280x2868, soit quatre captures App Store de 1320x2868 cote a
     cote. La planche etant plus grande, tout se fait en reduction ;
  2. ecrans : le masque magenta donne les quatre quadrilateres, les captures y
     sont posees par homographie. L'ecran etant coupe par le bord bas, le
     rectangle plein est reconstruit depuis l'arete haute ; le masque sert de
     decoupe, ce qui recolle proprement derriere les pastilles ;
  3. mascotte et icone : PNG de Assets.xcassets, jamais agrandis au-dela de
     MASCOT_SCALE ;
  4. sorties : les quatre fichiers 1320x2868 a uploader tels quels sur App Store
     Connect (la fiche espace les captures elle-meme, donc aucune gouttiere dans
     ces fichiers), plus une version bandeau avec gouttieres pour la presse.

La continuite entre panneaux -- un telephone tranche par une coupe et repris de
l'autre cote en registre -- vient de ce que la scene n'a jamais ete divisee :
c'est la decoupe finale qui cree les panneaux. Le modele ne sait pas la produire
sur demande, il redessine quatre affiches independantes.

Rejouer :  ~/tools/pyimg/bin/python marketing/aso_banner_nb.py
"""
import os
import cv2
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLATE = f"{ROOT}/marketing/aso-source/plate_v10.png"
CROPS = f"{ROOT}/marketing/aso-source/crops"
ASSETS = f"{ROOT}/Picpic/Assets.xcassets"
ASC = f"{ROOT}/marketing/asc"
BANNER = f"{ROOT}/marketing/aso_banner_nb.png"

PANEL_W, PANEL_H, N = 1320, 2868, 4          # capture App Store iPhone 6,9"
W, H = PANEL_W * N, PANEL_H

# gauche a droite, dans l'ordre des panneaux
SCREENS = ["home_full.png", "shelfscan_full.png", "freereading_full.png", "stats_full.png"]
NAMES = ["01_bibliotheque", "02_scan_etagere", "03_classiques", "04_retrospective"]
MIN_AREA = 20000

MASCOT = f"{ASSETS}/mascot-reading.imageset/mascot-reading.png"
MASCOT_SCALE = 2.6      # la source ne fait que 224x315 : au-dela ca ramollit
ICON = f"{ASSETS}/AppIcon.appiconset/AppIcon.png"

SAND = (210, 224, 231)  # #E7E0D2 en BGR
GUTTER = 40
RADIUS = 56


def magenta_mask(bgr):
    b, g, r = (c.astype(np.int16) for c in cv2.split(bgr))
    return (((r > 150) & (b > 150) & (g < 110) & (np.abs(r - b) < 80)).astype(np.uint8)) * 255


def corners(mask_i):
    """Coins du rectangle d'ecran visible, ordonnes TL, TR, BR, BL."""
    cnts, _ = cv2.findContours(mask_i, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    box = sorted(cv2.boxPoints(cv2.minAreaRect(max(cnts, key=cv2.contourArea))),
                 key=lambda p: p[1])
    top, bot = sorted(box[:2], key=lambda p: p[0]), sorted(box[2:], key=lambda p: p[0])
    return np.float32([top[0], top[1], bot[1], bot[0]])


def full_quad(quad, src_ratio):
    """Etend le quadrilatere vers le bas jusqu'a l'aspect reel de la capture.

    L'ecran est tranche par le bord de l'image : on n'en voit que le haut. On
    repart de l'arete haute et on descend de la hauteur theorique, pour que la
    capture soit posee a son echelle et non ecrasee dans la portion visible."""
    tl, tr, br, bl = quad
    width = np.linalg.norm(tr - tl)
    down = (bl - tl) + (br - tr)
    down /= np.linalg.norm(down)
    full_h = width * src_ratio
    if full_h <= max(np.linalg.norm(bl - tl), np.linalg.norm(br - tr)):
        return quad
    return np.float32([tl, tr, tr + down * full_h, tl + down * full_h])


def paste(dst, png, x, y, height, squircle=False):
    """Colle un PNG a canal alpha, coin haut gauche en (x, y), a la hauteur voulue.

    squircle : arrondit aux coins iOS, l'AppIcon etant livre carre et arrondi par
    le systeme."""
    a = cv2.imread(png, cv2.IMREAD_UNCHANGED)
    if squircle:
        m = np.zeros(a.shape[:2], np.uint8)
        r = round(a.shape[0] * 0.2237)   # rayon de l'icone iOS
        cv2.rectangle(m, (r, 0), (a.shape[1] - r, a.shape[0]), 255, -1)
        cv2.rectangle(m, (0, r), (a.shape[1], a.shape[0] - r), 255, -1)
        for cx, cy in ((r, r), (a.shape[1] - r, r), (r, a.shape[0] - r),
                       (a.shape[1] - r, a.shape[0] - r)):
            cv2.circle(m, (cx, cy), r, 255, -1)
        a = np.dstack([a[:, :, :3], m])
    scale = height / a.shape[0]
    a = cv2.resize(a, (round(a.shape[1] * scale), height),
                   interpolation=cv2.INTER_AREA if scale < 1 else cv2.INTER_LANCZOS4)
    h, w = a.shape[:2]
    x, y = max(0, x), max(0, y)
    w, h = min(w, dst.shape[1] - x), min(h, dst.shape[0] - y)
    a = a[:h, :w]
    alpha = (a[:, :, 3:4].astype(np.float32) / 255.0) if a.shape[2] == 4 else 1.0
    roi = dst[y:y + h, x:x + w]
    dst[y:y + h, x:x + w] = (a[:, :, :3] * alpha + roi * (1 - alpha)).astype(np.uint8)
    return w, h


def icon_slot(img):
    """Carre vide reserve a l'icone, en haut a gauche : le modele le dessine en
    contour fin sur le creme, on le retrouve par contraste local."""
    win = img[:round(H * 0.14), :round(W * 0.09)]
    edges = cv2.Canny(cv2.cvtColor(win, cv2.COLOR_BGR2GRAY), 30, 90)
    cnts, _ = cv2.findContours(cv2.dilate(edges, np.ones((5, 5), np.uint8)),
                               cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    best = None
    for c in cnts:
        x, y, w, h = cv2.boundingRect(c)
        if w > 60 and 0.75 < w / h < 1.33 and (best is None or w * h > best[2] * best[3]):
            best = (x, y, w, h)
    return best


def rounded(img, radius):
    m = np.zeros(img.shape[:2], np.uint8)
    cv2.rectangle(m, (radius, 0), (img.shape[1] - radius, img.shape[0]), 255, -1)
    cv2.rectangle(m, (0, radius), (img.shape[1], img.shape[0] - radius), 255, -1)
    for cx, cy in ((radius, radius), (img.shape[1] - radius, radius),
                   (radius, img.shape[0] - radius),
                   (img.shape[1] - radius, img.shape[0] - radius)):
        cv2.circle(m, (cx, cy), radius, 255, -1)
    a = (cv2.GaussianBlur(m, (0, 0), 0.7).astype(np.float32) / 255.0)[..., None]
    return (img * a + np.full_like(img, SAND) * (1 - a)).astype(np.uint8)


# ---------------------------------------------------------------- 1. cadrage
plate = cv2.imread(PLATE, cv2.IMREAD_COLOR)
ph, pw = plate.shape[:2]
keep_h = round(pw * H / W)
assert keep_h <= ph, "planche trop courte pour le cadre App Store"
# on rogne par le bas : les telephones y sont deja coupes, les titres sont en haut
canvas = cv2.resize(plate[:keep_h], (W, H), interpolation=cv2.INTER_AREA)

# ---------------------------------------------------------------- 2. ecrans
mask = magenta_mask(canvas)
n, labels, stats, cent = cv2.connectedComponentsWithStats(mask, 8)
keep = sorted([i for i in range(1, n) if stats[i, cv2.CC_STAT_AREA] >= MIN_AREA],
              key=lambda i: cent[i][0])
assert len(keep) == N, f"{len(keep)} ecrans magenta detectes, {N} attendus"

# un objet qui traverse un ecran (couverture de livre) coupe sa zone magenta en
# plusieurs composantes : on ne se sert des grosses que pour trouver les quatre
# quadrilateres, puis on repeint TOUT le magenta contenu dans chaque quadrilatere,
# fragments detaches compris
quads = []
for i in zip(keep):
    mi = (labels == i[0]).astype(np.uint8) * 255
    quads.append(full_quad(corners(mi), 2463 / 1070))

done = np.zeros(mask.shape, bool)      # magenta deja attribue a un quadrilatere
painted = np.zeros(mask.shape, bool)   # magenta effectivement recouvert
for quad, name in zip(quads, SCREENS):
    src = cv2.imread(f"{CROPS}/{name}", cv2.IMREAD_COLOR)
    sh, sw = src.shape[:2]

    poly = np.zeros(mask.shape, np.uint8)
    cv2.fillConvexPoly(poly, quad.astype(np.int32), 255)
    mi = ((mask > 0) & (poly > 0) & ~done).astype(np.uint8) * 255
    done |= mi > 0

    tw = int(round(np.linalg.norm(quad[1] - quad[0])))
    th = int(round(np.linalg.norm(quad[3] - quad[0])))
    if tw < sw:   # pas de reduction forte en une passe bicubique : INTER_AREA d'abord
        src = cv2.resize(src, (tw, th), interpolation=cv2.INTER_AREA)
        sh, sw = src.shape[:2]

    M = cv2.getPerspectiveTransform(np.float32([[0, 0], [sw, 0], [sw, sh], [0, sh]]), quad)
    warped = cv2.warpPerspective(src, M, (W, H), flags=cv2.INTER_CUBIC,
                                 borderMode=cv2.BORDER_REPLICATE)
    # on peint large : le seuil laisse un anneau de magenta anti-alise au bord
    mi = cv2.dilate(mi, np.ones((3, 3), np.uint8), iterations=3)
    painted |= mi > 0
    a = (cv2.GaussianBlur(mi, (0, 0), 1.2).astype(np.float32) / 255.0)[..., None]
    canvas = (warped * a + canvas * (1 - a)).astype(np.uint8)
    print(f"   {name:22s} ecran {tw}x{th}  (source 1070 px)")

# le controle compte les pixels d'ecran de la planche qu'on n'a pas recouverts.
# Chercher du magenta dans l'image finale ne marche pas : la couverture Gutenberg
# du "Comte de Monte-Cristo" est authentiquement magenta (#CC00CC) dans la capture
reste = int(((mask > 0) & ~painted).sum())
assert reste < 500, f"{reste} pixels d'ecran non recouverts"
print(f"   controle : {reste} px d'ecran non recouverts")

# ------------------------------------------------- 3. mascotte et icone reelles
mh = round(cv2.imread(MASCOT, cv2.IMREAD_UNCHANGED).shape[0] * MASCOT_SCALE)
mw, mh = paste(canvas, MASCOT, round(W * 0.015), H - mh - round(H * 0.03), mh)
print(f"   mascotte {mw}x{mh} ({MASCOT_SCALE}x la source)")

slot = icon_slot(canvas)
if slot:
    x, y, w, h = slot
    paste(canvas, ICON, x, y, h, squircle=True)
    print(f"   icone posee dans le carre reserve {w}x{h} en ({x}, {y})")
else:
    print("   ! carre d'icone introuvable, icone non posee")

# ------------------------------------------------------------ 4. sorties
os.makedirs(ASC, exist_ok=True)
for k, name in enumerate(NAMES):
    cv2.imwrite(f"{ASC}/{name}.png", canvas[:, k * PANEL_W:(k + 1) * PANEL_W])

ground = np.full_like(canvas, SAND)
for k in range(N):
    x0 = k * PANEL_W + (GUTTER // 2 if k else 0)
    x1 = (k + 1) * PANEL_W - (GUTTER // 2 if k < N - 1 else 0)
    ground[:, x0:x1] = rounded(canvas[:, x0:x1], RADIUS)
cv2.imwrite(BANNER, ground)

print(f"OK -> {ASC}/  {N} captures {PANEL_W}x{PANEL_H} pour App Store Connect")
print(f"OK -> {BANNER}  {W}x{H} (bandeau avec gouttieres)")

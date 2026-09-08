#!/usr/bin/env python3
"""Captures App Store Picpic : une toile continue, tranchee en quatre.

Modele de reference : la fiche ReciMe. Ses quatre captures ne sont pas quatre
affiches, c'est UNE composition decoupee. L'accroche geante traverse la coupe et
se retrouve tranchee en plein mot, le telephone aussi, et les deux moities
retombent en registre quand on fait defiler la fiche.

D'ou la construction ici : tout est peint sur une toile de 5280x2868, et la
decoupe en quatre fichiers de 1320x2868 n'intervient qu'a la toute fin. La
continuite n'est donc pas une consigne a respecter, c'est une consequence -- rien
n'a jamais ete divise. Demander cette continuite a un modele d'image ne marche
pas : il redessine quatre affiches independantes.

ReciMe alterne aussi les roles, ce qu'une grille repetee quatre fois ne fait pas :

  1 + 2   accroche geante tranchee par la coupe, un seul telephone a cheval,
          lockup de marque, mascotte, telephone secondaire incline
  3       capture SANS chassis, qui deborde par le haut, accroche en bas
  4       accroche en haut, telephone encadre coupe par le bord bas

Pixel perfect : la capture native fait 1320 px, la largeur exacte d'un panneau.
Posee a l'echelle 1 et sans rotation, elle traverse la chaine sans un seul
reechantillonnage. Le bezel et la capture sont assembles PUIS tournes d'un bloc,
donc ils ne peuvent pas se desaligner, et on ne redessine pas de Dynamic Island :
la capture porte la sienne.

Rejouer :  ~/tools/pyimg/bin/python marketing/aso_v2.py
"""
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = f"{ROOT}/marketing/shots"
CROPS = f"{ROOT}/marketing/aso-source/crops"
MASCOT = f"{ROOT}/marketing/aso-source/mascot_hd.png"
ICON = f"{ROOT}/Picpic/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
OUT = f"{ROOT}/marketing/asc"
PREVIEW = f"{ROOT}/marketing/aso_banner_nb.png"

P, H, N = 1320, 2868, 4                    # capture App Store iPhone 6,9"
W = P * N
CUT = [P, P * 2, P * 3]                    # les trois coupes

PAPER = (247, 245, 238)
INK = (26, 26, 46)
CORAL = (242, 112, 79)
TEAL = (46, 158, 143)
CREAM = (252, 250, 245)
SAND = (231, 224, 210)

NY = "/System/Library/Fonts/NewYork.ttf"
SF = "/System/Library/Fonts/SFNS.ttf"
MARGIN = 96
BEZEL = 0.020


def var(path, size, weight):
    f = ImageFont.truetype(path, size)
    try:
        f.set_variation_by_name(weight)
    except Exception:
        pass
    return f


def serif(size, weight="Black"):
    return var(NY, size, weight)


def sans(size, weight="Bold"):
    return var(SF, size, weight)


def probe():
    return ImageDraw.Draw(Image.new("L", (1, 1)))


def mask_round(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return m


def shadow(layer, blur, offset, opacity=110):
    pad = blur * 3
    sh = Image.new("RGBA", (layer.width + pad * 2, layer.height + pad * 2), (0, 0, 0, 0))
    sh.paste(Image.new("RGBA", layer.size, (0, 0, 0, opacity)),
             (pad + offset[0], pad + offset[1]), layer)
    return sh.filter(ImageFilter.GaussianBlur(blur)), pad


def put(canvas, layer, x, y, blur=56, off=(0, 28), opacity=105):
    if blur:
        sh, pad = shadow(layer, blur, off, opacity)
        canvas.alpha_composite(sh, (x - pad, y - pad))
    canvas.alpha_composite(layer, (x, y))


def screenshot(name):
    native = f"{SHOTS}/{name}.png"
    if os.path.exists(native):
        return Image.open(native).convert("RGB")
    old = f"{CROPS}/{name}.png"
    if os.path.exists(old):
        return Image.open(old).convert("RGB")
    raise SystemExit(
        f"Capture « {name} » introuvable (ni {native}, ni {old}).\n"
        f"La produire :  TEST_RUNNER_PICPIC_CAPTURE=1 xcodebuild test "
        f"-project Picpic.xcodeproj -scheme Picpic "
        f"-destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' "
        f"-only-testing:PicpicUITests/MarketingShots "
        f"-resultBundlePath /tmp/picpic_shots.xcresult && ./marketing/pull_shots.sh\n"
        f"Le prefixe TEST_RUNNER_ est obligatoire : sans lui les cas sont ignores "
        f"et le test passe au vert sans rien produire.")


def device(name, screen_w, tilt=0.0):
    """Chassis et capture assembles, PUIS tournes d'un seul bloc."""
    shot = screenshot(name)
    if shot.width != screen_w:
        shot = shot.resize((screen_w, round(screen_w * shot.height / shot.width)), Image.LANCZOS)
    r_in = round(screen_w * 0.088)
    shot = shot.convert("RGBA")
    shot.putalpha(mask_round(shot.size, r_in))

    bez = max(4, round(screen_w * BEZEL))
    body = Image.new("RGBA", (screen_w + bez * 2, shot.height + bez * 2), (0, 0, 0, 0))
    frame = Image.new("RGBA", body.size, (24, 24, 28, 255))
    frame.putalpha(mask_round(body.size, r_in + bez))
    body.alpha_composite(frame)
    body.alpha_composite(shot, (bez, bez))
    return body.rotate(tilt, resample=Image.BICUBIC, expand=True) if tilt else body


def bare(name, width, radius=0, fade=0):
    """Capture nue, sans chassis : le panneau 3 de ReciMe montre l'interface a vif.

    fade : hauteur du fondu en bas. Sans lui la capture s'arrete net au milieu
    d'une carte et se lit comme un recadrage rate ; avec, elle se dissout dans le
    fond du panneau et la coupe devient un parti pris."""
    shot = screenshot(name).convert("RGBA")
    shot = shot.resize((width, round(width * shot.height / shot.width)), Image.LANCZOS)
    a = mask_round(shot.size, radius) if radius else Image.new("L", shot.size, 255)
    if fade:
        px = a.load()
        top = shot.height - fade
        for j in range(top, shot.height):
            k = 1.0 - (j - top) / fade
            for i in range(shot.width):
                px[i, j] = int(px[i, j] * k * k)
    shot.putalpha(a)
    return shot


def fitted(lines, max_w, start=340, floor=90):
    size = start
    while size > floor and max(probe().textlength(t, font=serif(size)) for t in lines) > max_w:
        size -= 4
    return serif(size)


def slab(canvas, text, font, x, y, slab_col, text_col, angle=-2.0):
    """Ligne d'accroche sur un bandeau incline, comme les bandeaux blancs de ReciMe."""
    tw = probe().textlength(text, font=font)
    pad_x, pad_y = round(font.size * 0.20), round(font.size * 0.13)
    w, h = round(tw + pad_x * 2), round(font.size * 1.28 + pad_y * 2)
    lay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    d.rectangle([0, 0, w - 1, h - 1], fill=slab_col + (255,))
    d.text((pad_x, pad_y - round(font.size * 0.06)), text, font=font, fill=text_col)
    lay = lay.rotate(angle, resample=Image.BICUBIC, expand=True)
    canvas.alpha_composite(lay, (x, y))
    return h


def subtitle(canvas, lines, x, y, color, size=62, lead=1.34, max_w=None):
    """Ligne secondaire sous l'accroche : toutes les fiches de reference en ont
    une, elle porte le comment quand l'accroche porte la promesse."""
    f = sans(size, "Medium")
    d = ImageDraw.Draw(canvas)
    for i, t in enumerate(lines):
        d.text((x, y + round(i * size * lead)), t, font=f, fill=color)
    return y + round(len(lines) * size * lead)


def pill(text, bg, fg, size=84, tilt=-7.0):
    """Pastille : sans glyphe, les SF Symbols n'etant pas des caracteres."""
    f = sans(size)
    tw = probe().textlength(text, font=f)
    w, h = round(tw + size * 1.7), round(size * 2.1)
    chip = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(chip)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=h // 2, fill=bg + (255,))
    d.text(((w - tw) / 2, (h - f.size * 1.3) / 2), text, font=f, fill=fg)
    return chip.rotate(tilt, resample=Image.BICUBIC, expand=True)


def lockup(canvas, x, y, side=190, color=CREAM):
    icon = Image.open(ICON).convert("RGBA").resize((side, side), Image.LANCZOS)
    icon.putalpha(mask_round(icon.size, round(side * 0.2237)))
    canvas.alpha_composite(icon, (x, y))
    ImageDraw.Draw(canvas).text((x + side + 44, y + 14), "Picpic", font=serif(140), fill=color)


# ------------------------------------------------------------------- la toile

def compose():
    c = Image.new("RGBA", (W, H), PAPER + (255,))
    d = ImageDraw.Draw(c)

    # fonds : les panneaux 1 et 2 partagent un seul aplat, c'est lui qui porte la
    # composition a cheval sur la premiere coupe
    d.rectangle([0, 0, CUT[1] - 1, H], fill=CORAL + (255,))
    d.rectangle([CUT[1], 0, CUT[2] - 1, H], fill=PAPER + (255,))
    d.rectangle([CUT[2], 0, W, H], fill=INK + (255,))

    # --- panneaux 1 + 2 : l'accroche traverse la coupe et se fait trancher
    lockup(c, MARGIN, 130)
    f = fitted(["Scanne un livre,", "il est rangé."], CUT[1] - MARGIN * 2 - 300, 400)
    y = 400
    # la premiere ligne traverse la coupe et s'y fait trancher, c'est le geste de
    # ReciMe. La seconde descend dans la zone libre en bas a gauche : la garder
    # sous la premiere la ferait recouvrir par le telephone, qu'il faut placer
    # haut pour que les jaquettes de « Mes scans » tiennent dans le cadre
    h1 = slab(c, "Scanne un livre,", f, MARGIN, y, CREAM, CORAL, angle=-2.0)
    f2 = fitted(["il est rangé."], 690, 260)   # le telephone commence a x=826
    slab(c, "il est rangé.", f2, MARGIN, round(H * 0.50), CREAM, INK, angle=-2.0)

    # pas de sous-titre ici : l'accroche tient sur deux panneaux, ajouter une
    # ligne la ferait passer sous le telephone. ReciMe n'en met pas non plus sur
    # ses deux premiers panneaux, seulement sur les deux derniers
    dev = device("home_full", 1180)
    # remonte pour que la rangee « Mes scans » et ses jaquettes tiennent
    # entierement dans le cadre : c'est le contenu que la fiche doit montrer
    put(c, dev, CUT[0] - dev.width // 2 + 120, 930, blur=80, off=(0, 44), opacity=130)

    small = device("sudoc_full", 500, tilt=-11)
    put(c, small, CUT[1] - 700, 900, blur=44, off=(0, 24), opacity=110)

    # la mascotte tient le coin bas gauche, devant le telephone ; la pastille passe
    # sous le petit ecran a droite. Rien ne doit chevaucher un mot d'une pastille
    m = Image.open(MASCOT).convert("RGBA")
    mh = round(H * 0.30)
    m = m.resize((round(m.width * mh / m.height), mh), Image.LANCZOS)
    put(c, m, 90, H - mh - 40, blur=40, off=(0, 20), opacity=70)

    tag = pill("Sans compte, sans pub", CREAM, INK, size=62, tilt=-3)
    put(c, tag, CUT[1] - tag.width - MARGIN, H - 420, blur=28, off=(0, 14), opacity=70)

    # --- panneau 3 : capture a vif, qui deborde par le haut, accroche en bas
    shot = bare("freereading_full", P - 120, radius=64, fade=460)
    c.alpha_composite(shot, (CUT[1] + 60, -660))
    f3 = fitted(["Les classiques,", "gratuits."], P - MARGIN * 2, 250)
    y3 = H - round(f3.size * 4.25)
    slab(c, "Les classiques,", f3, CUT[1] + MARGIN, y3, PAPER, INK, angle=0)
    slab(c, "gratuits.", f3, CUT[1] + MARGIN, y3 + round(f3.size * 1.34), CORAL, CREAM, angle=0)
    subtitle(c, ["Domaine public, en EPUB et en audio,", "légalement."],
             CUT[1] + MARGIN, y3 + round(f3.size * 2.78), (120, 118, 116), size=54)
    put(c, pill("Audio", TEAL, CREAM, size=70), CUT[1] + P - 560, y3 - 470,
        blur=30, off=(0, 16), opacity=90)

    # --- panneau 4 : accroche en haut, telephone encadre coupe par le bord bas
    f4 = fitted(["Ton année", "lecture,", "en chiffres."], P - MARGIN * 2, 260)
    y4 = 240
    for i, (t, col) in enumerate((("Ton année", CREAM), ("lecture,", CREAM),
                                  ("en chiffres.", CORAL))):
        d.text((CUT[2] + MARGIN, y4 + i * round(f4.size * 1.08)), t, font=f4, fill=col)
    subtitle(c, ["Calculé sur ton iPhone,", "rien que pour toi."],
             CUT[2] + MARGIN, y4 + round(f4.size * 3.42), (190, 190, 200), size=56)
    dev4 = device("stats_full", P - 220)
    put(c, dev4, CUT[2] + 110, y4 + round(f4.size * 4.55), blur=80, off=(0, 44), opacity=150)
    return c


def slice_out(canvas):
    os.makedirs(OUT, exist_ok=True)
    names = ["01_scanne", "02_bibliotheque", "03_classiques", "04_retrospective"]
    rgb = canvas.convert("RGB")
    for k, name in enumerate(names):
        rgb.crop((k * P, 0, (k + 1) * P, H)).save(f"{OUT}/{name}.png")

    # apercu : les memes panneaux espaces, pour juger la continuite d'un coup d'oeil
    g, r = 44, 60
    prev = Image.new("RGB", (W + g * 3, H), SAND)
    for k in range(N):
        piece = rgb.crop((k * P, 0, (k + 1) * P, H)).convert("RGBA")
        piece.putalpha(mask_round(piece.size, r))
        bg = Image.new("RGBA", piece.size, SAND + (255,))
        bg.alpha_composite(piece)
        prev.paste(bg.convert("RGB"), (k * (P + g), 0))
    prev.save(PREVIEW)
    return names


if __name__ == "__main__":
    names = slice_out(compose())
    native = sum(os.path.exists(f"{SHOTS}/{s}.png")
                 for s in ("home_full", "sudoc_full", "freereading_full", "stats_full"))
    print(f"OK -> {OUT}/  4 captures {P}x{H}  ({native}/4 ecrans natifs, poses sans agrandissement)")
    print(f"OK -> {PREVIEW}  apercu avec gouttieres")

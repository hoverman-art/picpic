#!/usr/bin/env python3
"""Bandeau ASO Picpic : les 4 captures a accroche recomposees en une seule image 16:9
(3840x2160), pour un post, une page de presse ou une preview de fiche.
L'ecran est decoupe dans marketing/framed/ : aucune capture n'est regeneree."""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FRAMED = f"{ROOT}/marketing/framed"
OUT = f"{ROOT}/marketing/aso_banner.png"
ICON = f"{ROOT}/Picpic/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
# zone de l'ecran dans les captures a accroche (marketing/frame_shots.py)
SCREEN_BOX = (125, 405, 1195, 2868)

PAPER = (247, 245, 238)
INK = (26, 26, 46)
CORAL = (242, 112, 79)
TEAL = (46, 158, 143)
SAND = (231, 224, 210)
CREAM = (252, 250, 245)

W, H = 3840, 2160
MARGIN, GAP, RADIUS = 96, 36, 56
HEAD_Y, PHONE_Y = 232, 566

PANELS = [
    ("home_full.png",        PAPER, ("Scanne un livre,", INK),     ("il est déjà rangé.", CORAL), None),
    ("shelfscan_full.png",   INK,   ("Une photo,", CREAM),         ("toute l'étagère.", CORAL),   ("Pro", CORAL, CREAM)),
    ("freereading_full.png", PAPER, ("Les classiques,", INK),      ("gratuits.", CORAL),          ("Audio", TEAL, CREAM)),
    ("stats_full.png",       CORAL, ("Ton année lecture,", CREAM), ("en chiffres.", INK),         None),
]


def variable(path, size, weight):
    f = ImageFont.truetype(path, size)
    try:
        f.set_variation_by_name(weight)
    except Exception:
        pass
    return f


def serif(size, weight="Bold"):
    return variable("/System/Library/Fonts/NewYork.ttf", size, weight)


def sans(size, weight="Bold"):
    return variable("/System/Library/Fonts/SFNS.ttf", size, weight)


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return m


def fitted_serif(lines, max_w, start=100):
    """Plus grosse taille qui garde les deux lignes dans la largeur utile."""
    probe = ImageDraw.Draw(Image.new("L", (1, 1)))
    size = start
    while size > 48 and max(probe.textlength(t, font=serif(size)) for t in lines) > max_w:
        size -= 2
    return serif(size)


def phone(name, width):
    """Capture dans un chassis iPhone : bezel sombre, coins arrondis."""
    shot = Image.open(f"{FRAMED}/{name}").convert("RGB").crop(SCREEN_BOX)
    bezel = max(6, round(width * 0.015))
    inner_w = width - bezel * 2
    shot = shot.resize((inner_w, round(inner_w * shot.height / shot.width)), Image.LANCZOS)
    r_in = round(inner_w * 0.085)
    shot.putalpha(rounded_mask(shot.size, r_in))

    body = Image.new("RGBA", (width, shot.height + bezel * 2), (0, 0, 0, 0))
    frame = Image.new("RGBA", body.size, (20, 20, 24, 255))
    frame.putalpha(rounded_mask(body.size, r_in + bezel))
    body.alpha_composite(frame)
    body.alpha_composite(shot, (bezel, bezel))
    return body


def drop_shadow(layer, blur, offset, opacity=110):
    pad = blur * 3
    sh = Image.new("RGBA", (layer.width + pad * 2, layer.height + pad * 2), (0, 0, 0, 0))
    sh.paste(Image.new("RGBA", layer.size, (0, 0, 0, opacity)), (pad + offset[0], pad + offset[1]), layer)
    return sh.filter(ImageFilter.GaussianBlur(blur)), pad


def centered(draw, text, font, y, color, cx):
    draw.text((cx - draw.textlength(text, font=font) / 2, y), text, font=font, fill=color)


canvas = Image.new("RGBA", (W, H), SAND + (255,))
pw = (W - MARGIN * 2 - GAP * 3) // 4
ph = H - MARGIN * 2
f_pill = sans(54)

for i, (shot, bg, (l1, c1), (l2, c2), badge) in enumerate(PANELS):
    panel = Image.new("RGBA", (pw, ph), bg + (255,))
    d = ImageDraw.Draw(panel)
    cx = pw / 2

    head = fitted_serif([l1, l2], pw - 120)
    centered(d, l1, head, HEAD_Y, c1, cx)
    centered(d, l2, head, HEAD_Y + round(head.size * 1.22), c2, cx)

    ph_w = round(pw * 0.80)
    device = phone(shot, ph_w)
    shadow, pad = drop_shadow(device, 40, (0, 30))
    px = round((pw - ph_w) / 2)
    panel.alpha_composite(shadow, (px - pad, PHONE_Y - pad))
    panel.alpha_composite(device, (px, PHONE_Y))

    if badge:
        label, bgc, fgc = badge
        tw = d.textlength(label, font=f_pill)
        bw, bh = round(tw + 96), 116
        bx, by = px + ph_w - round(bw * 0.78), PHONE_Y - round(bh * 0.44)
        chip = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
        ImageDraw.Draw(chip).rounded_rectangle([0, 0, bw - 1, bh - 1], radius=bh // 2, fill=bgc + (255,))
        ImageDraw.Draw(chip).text(((bw - tw) / 2, (bh - f_pill.size) / 2 - 6), label, font=f_pill, fill=fgc)
        csh, cpad = drop_shadow(chip, 18, (0, 10), 90)
        panel.alpha_composite(csh, (bx - cpad, by - cpad))
        panel.alpha_composite(chip, (bx, by))

    if i == 0:  # lockup icone + nom, en tete du premier panneau
        icon = Image.open(ICON).convert("RGBA").resize((104, 104), Image.LANCZOS)
        icon.putalpha(rounded_mask(icon.size, 24))
        panel.alpha_composite(icon, (64, 76))
        d.text((190, 92), "Picpic", font=serif(72), fill=INK)

    panel.putalpha(rounded_mask((pw, ph), RADIUS))
    canvas.alpha_composite(panel, (MARGIN + i * (pw + GAP), MARGIN))

canvas.convert("RGB").save(OUT, "PNG")
print("OK ->", OUT, canvas.size)

#!/usr/bin/env python3
"""Captures marketing App Store : fond papier, accroche New York bold,
capture arrondie avec ombre, qui fuit sur le bord bas (style fiche moderne)."""
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SHOTS = "/private/tmp/claude-501/-Users-gabindepaire-Desktop-Picpic/59e45b0d-45c3-417a-950d-9dc0d6053766/scratchpad/shots"
OUT = f"{SHOTS}/framed"
PAPER = (247, 245, 238)
INK = (26, 26, 46)
ACCENT = (242, 112, 79)

IPHONE = [
    ("home_full.png", "Scanne un livre,", "il est déjà rangé."),
    ("shelfscan_full.png", "Une photo,", "toute l'étagère."),
    ("freereading_full.png", "Les classiques gratuits,", "à lire et à écouter."),
    ("stats_full.png", "Ton année lecture,", "en chiffres."),
    ("paywall_full.png", "Sans abonnement", "obligatoire."),
]
IPAD = [
    ("ipad_home.png", "Ta bibliothèque,", "scannée en 2 secondes."),
    ("ipad_freereading.png", "Les classiques gratuits,", "à lire et à écouter."),
    ("ipad_stats.png", "Ton année lecture,", "en chiffres."),
]


def font(size):
    f = ImageFont.truetype("/System/Library/Fonts/NewYork.ttf", size)
    try:
        f.set_variation_by_name("Bold")
    except Exception:
        pass
    return f


def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, *img.size], radius=radius, fill=255)
    out = Image.new("RGBA", img.size)
    out.paste(img, (0, 0), mask)
    return out


def frame(name, line1, line2, size):
    W, H = size
    canvas = Image.new("RGB", (W, H), PAPER)
    draw = ImageDraw.Draw(canvas)

    # Accroche sur deux lignes, la seconde en corail.
    fsize = int(W * 0.062)
    f = font(fsize)
    y = int(H * 0.045)
    for line, color in [(line1, INK), (line2, ACCENT)]:
        w = draw.textlength(line, font=f)
        draw.text(((W - w) / 2, y), line, font=f, fill=color)
        y += int(fsize * 1.22)

    # Capture : occupe ~82 % de la largeur, ancrée en bas (coupée net).
    shot = Image.open(f"{SHOTS}/{name}").convert("RGB")
    target_w = int(W * 0.82)
    scale = target_w / shot.width
    shot = shot.resize((target_w, int(shot.height * scale)), Image.LANCZOS)
    radius = int(W * 0.045)
    shot = rounded(shot, radius)

    top = y + int(H * 0.028)
    x = (W - target_w) // 2

    # Ombre douce.
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [x, top + 18, x + target_w, top + shot.height], radius=radius, fill=(26, 26, 46, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(30))
    canvas.paste(Image.alpha_composite(canvas.convert("RGBA"), shadow).convert("RGB"), (0, 0))
    canvas.paste(shot, (x, top), shot)

    return canvas


import os
os.makedirs(OUT, exist_ok=True)
for name, l1, l2 in IPHONE:
    frame(name, l1, l2, (1320, 2868)).save(f"{OUT}/{name}", "PNG")
    print("iphone:", name)
for name, l1, l2 in IPAD:
    frame(name, l1, l2, (2064, 2752)).save(f"{OUT}/{name}", "PNG")
    print("ipad  :", name)
print("OK ->", OUT)

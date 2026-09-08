#!/usr/bin/env python3
"""Passe 1 du bandeau ASO : la planche, generee par Gemini 3 Pro Image en 4K.

Le MCP nano banana plafonne a 1376x768 et n'expose pas la resolution ; l'appel
direct accepte imageConfig.imageSize, d'ou ce script (meme chaine que
flit-marketing-2026-09-04/v6/pipeline.py).

Le modele ne dessine QUE ce qui n'existe pas en vrai : les fonds, la typographie,
les chassis de telephone. Les ecrans sortent en aplat magenta, la mascotte et
l'icone ne sont pas dessinees du tout -- elles sont incrustees en passe 2 depuis
les assets de l'app, sinon le modele en invente des variantes fausses.

Rejouer :  ~/tools/pyimg/bin/python marketing/aso_plate.py
"""
import base64
import json
import os
import re
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = f"{ROOT}/marketing/aso-source/plate_v10.png"
# 4 captures App Store de 1320x2868 cote a cote : la planche est calee sur ce cadre
REF = ("/Users/gabindepaire/Desktop/flit-marketing-2026-09-04/pinterest-aso/"
       "aso_screenshots_inspiration/pinterest_4672275cddfff6ef0dd0c201fe5f3c5b.jpg")
ENV = "/Users/gabindepaire/Desktop/flit-api/.env"
MODEL = "gemini-3-pro-image-preview"

PROMPT = """ONE single continuous 16:9 marketing poster for the French iPhone app "Picpic", a book scanner and reading tracker. It is a SINGLE uninterrupted scene edge to edge. There are NO panels, NO dividers, NO gutters, NO rounded corners, NO borders anywhere. Do not split the image into sections. It gets sliced afterwards, so nothing may be pre-divided.

The reference image shows the compositional energy to match: enormous display typography, phones far larger than life cropped by the image edge, objects overlapping and breaking out. Copy its aggression, none of its words, colours or logos.

BACKGROUND: four flat vertical colour fields meeting edge to edge with hard straight seams, no gap and no line between them, each exactly a quarter of the width: paper cream #F7F5EE, then deep ink navy #1A1A2E, then paper cream #F7F5EE, then coral #F2704F. The seams fall at 25%, 50% and 75% of the width.

ABSOLUTE RULE 1 — EVERY PHONE SCREEN IS PURE FLAT MAGENTA #FF00FF. Draw the device body, the thin dark titanium bezel and the rounded screen corners, but fill the entire display with solid magenta #FF00FF: no wallpaper, no interface, no icon, no text, no reflection, no gradient, no glow. Flat magenta only. Real screenshots are composited in afterwards.

ABSOLUTE RULE 2 — DRAW NO CHARACTER AND NO APP ICON. No bird, no mascot, no animal, no person anywhere in the image. No rounded-square app icon. The real ones are composited in afterwards. Leave the bottom-left quarter of the first cream field COMPLETELY EMPTY: no object, no book, no text, no shadow there, only flat cream.

THE FOUR PHONES FORM ONE CONTINUOUS ROW THAT SPANS THE WHOLE WIDTH. They are the subject of the poster and they are enormous. Four iPhone 15 Pro, thin dark titanium bezel, tilted 8 to 12 degrees, laid side by side, each one AS WIDE AS A QUARTER OF THE IMAGE — the same width as a colour field — touching and slightly overlapping its neighbour so that together they cover the width from 12% to 100% with no background visible between them at their height.
Their centres fall exactly on the colour seams: phone 1 centred at 25% of the width, phone 2 at 50%, phone 3 at 75%. Each of those three therefore straddles a seam, half its body on one colour and half on the next. Phone 4 is centred at about 95%, overlapping phone 3 and cut by the right edge of the image.
Only the leftmost eighth of the image is free of phones — that strip carries the wordmark, the first headline and the reserved empty corner.
Each phone's top edge sits at about 40% of the image height and its lower third runs off the bottom edge and is cut by it: no bottom bezel, no home indicator, no empty ground under any phone. Soft realistic drop shadows, overlapping front to back.

WHAT MAY CROSS A SEAM. The image gets cut along the three seams, so only large objects may lie across one: a phone, a book cover. Anything carrying a short word must sit WELL INSIDE a single colour field, at least a tenth of the total width away from any seam, so it is never cut through its own lettering.

HEADLINES in a very heavy high-contrast display serif (Playfair Display Black), enormous, in the top third, tight leading, perfect French with correct accents, each fitting inside one colour field without touching a seam:
- on the first cream: "Scanne un livre," / "il est rangé." — ink navy, second line coral #F2704F.
- on the navy: "Une photo," / "toute l'étagère." — cream, second line coral.
- on the second cream: "Les classiques," / "gratuits." — ink navy, with "gratuits." reversed out in cream on a solid coral block.
- on the coral: "Ton année lecture," / "en chiffres." — cream, second line ink navy.
At the very top left, above the first headline, the wordmark "Picpic" in heavy ink navy serif, with an EMPTY SQUARE GAP of the same height immediately to its left: leave that square strictly empty, flat cream, the app icon goes there later.

FILL THE REST OF THE SCENE, no large flat empty area except the reserved bottom-left corner: a tilted coral pill with a camera glyph and the word "Pro" in the middle of the navy field, far from both seams. A tilted teal #2E9E8F pill with a headphone glyph and the word "Audio" in the middle of the second cream field, far from both seams. Five classic book covers floating loose at different angles, tucked behind and between the phones, several lying across the seams. They must never compete with the devices for space. Cream rounded chips reading "534 pages lues", "6 livres" and "2 terminés", each well inside the coral field.

Flat editorial poster style, crisp, confident, premium indie-app marketing. No watermark, no App Store chrome, no laurels, no star ratings, no English words, no repeated words."""


def key():
    return re.search(r'^GEMMA_API_KEY=(.*)$', open(ENV).read(), re.M).group(1).strip().strip('"')


def call(prompt, ref, out, ratio="16:9", size="4K", tries=3):
    parts = [{"text": prompt}]
    if ref:
        parts.append({"inline_data": {"mime_type": "image/jpeg",
                                      "data": base64.b64encode(open(ref, 'rb').read()).decode()}})
    body = {"contents": [{"parts": parts}],
            "generationConfig": {"responseModalities": ["IMAGE"],
                                 "imageConfig": {"aspectRatio": ratio, "imageSize": size}}}
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent?key={key()}"
    for n in range(tries):
        try:
            req = urllib.request.Request(url, json.dumps(body).encode(),
                                         {"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=300) as r:
                data = json.load(r)
            for p in data["candidates"][0]["content"]["parts"]:
                if "inlineData" in p:
                    open(out, 'wb').write(base64.b64decode(p["inlineData"]["data"]))
                    return out
            raise RuntimeError(f"pas d'image dans la reponse : {json.dumps(data)[:400]}")
        except Exception as e:
            print(f"  essai {n + 1}/{tries} : {e}", file=sys.stderr)
            if n == tries - 1:
                raise


if __name__ == "__main__":
    call(PROMPT, REF, OUT)
    from PIL import Image
    print("OK ->", OUT, Image.open(OUT).size)

#!/usr/bin/env python3
"""Mascotte en haute definition, pour les planches ASO.

L'asset de l'app ne fait que 224x315 : a la taille ou les exemples App Store
placent leur personnage (35 a 45 % de la hauteur du panneau), il faudrait
l'agrandir 4x, ce qui le ramollit visiblement. On le fait donc redessiner a
l'identique en 2K, puis on detoure sur fond vert -- le personnage n'a aucun vert,
la cle est donc sans ambiguite.

Le resultat DOIT etre compare a l'original avant usage : c'est le seul endroit de
la chaine ou un modele redessine un asset de marque.

Rejouer :  ~/tools/pyimg/bin/python marketing/aso_mascot.py
"""
import os
import sys

import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aso_plate import call  # noqa: E402  meme chaine d'appel Gemini

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = f"{ROOT}/Picpic/Assets.xcassets/mascot-reading.imageset/mascot-reading.png"
RAW = f"{ROOT}/marketing/aso-source/mascot_hd_raw.png"
OUT = f"{ROOT}/marketing/aso-source/mascot_hd.png"

PROMPT = """Redraw the cartoon character in the reference image at high resolution, IDENTICALLY.

This is an existing brand mascot. It must come out as the SAME character, not a new one. Keep strictly: the same species and silhouette (a plump round blue bird), the same pose, the same proportions and head-to-body ratio, the same flat vector style with a uniform dark outline of constant weight, the same colours exactly — royal blue body, cream-ivory belly, the fan of alternating gold and blue crest feathers behind the head, the dark navy graduation mortarboard with its gold tassel, the round dark-rimmed eyeglasses over two large white eyes with dark pupils and a white catchlight, the small orange triangular beak, the two yellow three-toed feet, and the open red hardcover book with cream pages and a gold ribbon held against its chest with both wings.

Change NOTHING: no new accessory, no different expression, no extra feather, no shading style change, no gradient, no drop shadow, no texture, no outline thickness change. Same drawing, more pixels — as if the original vector artwork had simply been exported larger.

The outermost edge of the drawing is its own dark outline. Do NOT add a white keyline, a white sticker border, a halo, a glow or any second contour around the character. Keep the crest feathers overlapping each other exactly as in the reference, not spread apart.

Place it centred on a PURE FLAT GREEN #00FF00 background, filling most of the frame, with nothing else in the image: no ground, no shadow, no props, no text, no border."""


def cutout(raw, out):
    """Detoure le vert et rend un PNG a canal alpha, bords propres."""
    bgr = cv2.imread(raw, cv2.IMREAD_COLOR)
    b, g, r = (c.astype(np.int16) for c in cv2.split(bgr))
    green = (g > 110) & (g - np.maximum(r, b) > 45)
    alpha = np.where(green, 0, 255).astype(np.uint8)

    # on mord d'un pixel dans le vert pour ne pas garder de frange, puis on adoucit
    alpha = cv2.erode(alpha, np.ones((3, 3), np.uint8), iterations=1)
    alpha = cv2.GaussianBlur(alpha, (0, 0), 0.8)

    rgba = np.dstack([bgr, alpha])
    ys, xs = np.where(alpha > 8)
    rgba = rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    cv2.imwrite(out, rgba)
    return rgba.shape[1], rgba.shape[0]


if __name__ == "__main__":
    call(PROMPT, SRC, RAW, ratio="3:4", size="2K")
    w, h = cutout(RAW, OUT)
    src_h = cv2.imread(SRC, cv2.IMREAD_UNCHANGED).shape[0]
    print(f"OK -> {OUT}  {w}x{h}  ({h / src_h:.1f}x la hauteur de l'asset d'origine)")

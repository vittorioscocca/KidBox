"""Immagine per «Intestazione e risultati di ricerca» (5244x2950), nello stile degli screenshot.

Testo a sinistra, due telefoni inclinati a destra; tutto vicino al centro per stare
nella zona sicura. Uso: python3 compose-header.py  → header/<lingua>/header.png
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os

W, H = 5244, 2950
FONT = "/System/Library/Fonts/Avenir Next.ttc"
HEAVY, DEMI = 8, 2
INK = (28, 18, 12)
TEXTS = {
    "it": ("KidBox, l'agente\ndella tua famiglia", "Calendario, to-do, spese e documenti\nin un solo posto"),
    "en": ("KidBox, the agent\nfor your family", "Calendar, to-dos, expenses and documents\nin one place"),
    "es": ("KidBox, el agente\nde tu familia", "Calendario, tareas, gastos y documentos\nen un solo lugar"),
    "fr": ("KidBox, l'agent\nde votre famille", "Calendrier, tâches, dépenses et documents\nau même endroit"),
}


def background():
    top, bot = (250, 180, 96), (242, 126, 34)
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / H
        d.line([(0, y), (W, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
    return img


def phone(shot, width):
    sw = width
    sh = int(shot.height * sw / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    bezel, ring, radius = int(width * 0.026), max(4, int(width * 0.004)), int(width * 0.135)
    ow, oh = sw + 2 * (bezel + ring), sh + 2 * (bezel + ring)
    out = Image.new("RGBA", (ow, oh), (0, 0, 0, 0))
    d = ImageDraw.Draw(out)
    d.rounded_rectangle([0, 0, ow - 1, oh - 1], radius=radius + bezel + ring, fill=(88, 86, 90, 255))
    d.rounded_rectangle([ring, ring, ow - 1 - ring, oh - 1 - ring], radius=radius + bezel, fill=(10, 10, 12, 255))
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw - 1, sh - 1], radius=radius, fill=255)
    out.paste(shot, (bezel + ring, bezel + ring), mask)
    iw, ih = int(sw * 0.29), int(sw * 0.088)
    ix, iy = (ow - iw) // 2, bezel + ring + int(sw * 0.026)
    d.rounded_rectangle([ix, iy, ix + iw, iy + ih], radius=ih // 2, fill=(0, 0, 0, 255))
    return out


def shadowed(base, im, pos, blur=60, dy=50, alpha=95):
    sh = Image.new("RGBA", base.size, (0, 0, 0, 0))
    a = im.split()[3].point(lambda v: min(v, alpha))
    tmp = Image.new("RGBA", im.size, (60, 20, 0, 255))
    tmp.putalpha(a)
    sh.paste(tmp, (pos[0], pos[1] + dy), tmp)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    base.paste(sh, (0, 0), sh)
    base.paste(im, pos, im)


def fit_block(text, max_w, start, index):
    size = start
    while size > 60:
        f = ImageFont.truetype(FONT, size, index=index)
        if all(f.getlength(l) <= max_w for l in text.split("\n")):
            return f
        size -= 6
    return ImageFont.truetype(FONT, 60, index=index)


def make(lang):
    title, sub = TEXTS[lang]
    img = background()
    d = ImageDraw.Draw(img)
    # telefoni a destra (dietro: calendario, davanti: home)
    back = phone(Image.open(f"raw/{lang}/02-calendar.png").convert("RGB"), 1020).rotate(7, resample=Image.BICUBIC, expand=True)
    front = phone(Image.open(f"raw/{lang}/01-home.png").convert("RGB"), 1060).rotate(-8, resample=Image.BICUBIC, expand=True)
    shadowed(img, back, (3720, 120))
    shadowed(img, front, (3000, 230))
    # testo a sinistra, centrato in verticale
    f1 = fit_block(title, 2250, 330, HEAVY)
    f2 = fit_block(sub, 2250, 118, DEMI)
    l1 = title.split("\n")
    l2 = sub.split("\n")
    lh1, lh2 = int(f1.size * 1.08), int(f2.size * 1.25)
    total = lh1 * len(l1) + 120 + lh2 * len(l2)
    y = (H - total) // 2
    x = 560
    for line in l1:
        d.text((x, y), line, font=f1, fill=INK, anchor="la")
        y += lh1
    y += 120
    for line in l2:
        d.text((x, y), line, font=f2, fill=(70, 38, 10), anchor="la")
        y += lh2
    os.makedirs(f"header/{lang}", exist_ok=True)
    img.save(f"header/{lang}/header.png")


for lang in TEXTS:
    make(lang)
print("ok")

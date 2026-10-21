"""Compone gli screenshot degli store nello stile di quelli già in vendita.

Sfondo arancione sfumato, titolo nero molto grande, telefono con bordo scuro e
Dynamic Island disegnata (il simulatore non la cattura). Tre disposizioni, come
nel set attuale: titolo in alto, titolo in basso, telefono inclinato.

Uso: python3 compose.py
Legge raw/<lingua>/NN-*.png (1320x2868) e scrive final/<lingua>/NN-*.png.
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os, shutil

W, H = 1320, 2868
FONT = "/System/Library/Fonts/Avenir Next.ttc"
HEAVY = 8  # indice «Heavy» nella collezione

# (nome, disposizione, titoli per lingua)
SLIDES = [
    ("01-home", "tilt", {
        "it": "Chi prende Marco giovedì?",
        "en": "Who picks Marco up on Thursday?",
        "es": "¿Quién recoge a Marco el jueves?",
        "fr": "Qui récupère Marco jeudi\u00a0?"}),
    ("02-calendar", "title-bottom", {
        "it": "Un calendario per tutta la famiglia",
        "en": "One calendar for the whole family",
        "es": "Un calendario para toda la familia",
        "fr": "Un calendrier pour toute la famille"}),
    ("03-todo", "title-top", {
        "it": "Cose da fare assegnate a ognuno",
        "en": "Tasks assigned to each person",
        "es": "Tareas asignadas a cada uno",
        "fr": "Des tâches assignées à chacun"}),
    ("04-spese", "title-bottom", {
        "it": "Spese di casa sotto controllo",
        "en": "Household spending under control",
        "es": "Los gastos de casa bajo control",
        "fr": "Les dépenses de la maison maîtrisées"}),
    ("05-assistant", "title-top", {
        "it": "Un assistente che conosce la tua famiglia",
        "en": "An assistant that knows your family",
        "es": "Un asistente que conoce a tu familia",
        "fr": "Un assistant qui connaît votre famille"}),
]
TITLE_COLOR = (28, 18, 12)


def background():
    top, bot = (250, 180, 96), (242, 126, 34)
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / H
        d.line([(0, y), (W, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
    return img


def phone(shot, width):
    """Schermata dentro a un telefono: anello grigio, bordo nero, isola."""
    sw = width
    sh = int(shot.height * sw / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    bezel = int(width * 0.026)
    ring = max(3, int(width * 0.004))
    radius = int(width * 0.135)
    ow, oh = sw + 2 * (bezel + ring), sh + 2 * (bezel + ring)
    out = Image.new("RGBA", (ow, oh), (0, 0, 0, 0))
    d = ImageDraw.Draw(out)
    d.rounded_rectangle([0, 0, ow - 1, oh - 1], radius=radius + bezel + ring, fill=(88, 86, 90, 255))
    d.rounded_rectangle([ring, ring, ow - 1 - ring, oh - 1 - ring], radius=radius + bezel, fill=(10, 10, 12, 255))
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw - 1, sh - 1], radius=radius, fill=255)
    out.paste(shot, (bezel + ring, bezel + ring), mask)
    iw, ih = int(sw * 0.29), int(sw * 0.088)
    ix = (ow - iw) // 2
    iy = bezel + ring + int(sw * 0.026)
    d.rounded_rectangle([ix, iy, ix + iw, iy + ih], radius=ih // 2, fill=(0, 0, 0, 255))
    return out


def wrap(text, font, max_w):
    lines, cur = [], ""
    for word in text.split(" "):
        t = (cur + " " + word).strip()
        if font.getlength(t) <= max_w or not cur:
            cur = t
        else:
            lines.append(cur)
            cur = word
    lines.append(cur)
    return lines


def fit(text, max_w, max_lines, start=168):
    size = start
    while size > 70:
        f = ImageFont.truetype(FONT, size, index=HEAVY)
        lines = wrap(text, f, max_w)
        if len(lines) <= max_lines and all(f.getlength(l) <= max_w for l in lines):
            return f, lines
        size -= 6
    f = ImageFont.truetype(FONT, 70, index=HEAVY)
    return f, wrap(text, f, max_w)


def draw_title(img, text, y, align="center", max_lines=3, max_w=1120, x=None):
    f, lines = fit(text, max_w, max_lines)
    d = ImageDraw.Draw(img)
    lh = int(f.size * 1.08)
    for i, line in enumerate(lines):
        if align == "center":
            d.text((W / 2, y + i * lh), line, font=f, fill=TITLE_COLOR, anchor="ma")
        else:
            d.text((x if x is not None else 84, y + i * lh), line, font=f, fill=TITLE_COLOR, anchor="la")
    return lh * len(lines)


def shadowed(base, im, pos, blur=40, dy=30, alpha=90):
    sh = Image.new("RGBA", base.size, (0, 0, 0, 0))
    a = im.split()[3].point(lambda v: min(v, alpha))
    tmp = Image.new("RGBA", im.size, (60, 20, 0, 255))
    tmp.putalpha(a)
    sh.paste(tmp, (pos[0], pos[1] + dy), tmp)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    base.paste(sh, (0, 0), sh)
    base.paste(im, pos, im)


def compose(lang, name, layout, title):
    shot = Image.open(f"raw/{lang}/{name}.png").convert("RGB")
    img = background()
    if layout == "title-top":
        h = draw_title(img, title, 150, "center", 3)
        ph = phone(shot, 1010)
        shadowed(img, ph, ((W - ph.width) // 2, 150 + h + 90))
    elif layout == "title-bottom":
        ph = phone(shot, 1010)
        shadowed(img, ph, ((W - ph.width) // 2, -430))
        draw_title(img, title, 1960, "center", 3)
    else:  # tilt
        ph = phone(shot, 960)
        ph = ph.rotate(-9, resample=Image.BICUBIC, expand=True)
        shadowed(img, ph, (W - ph.width + 140, -300))
        draw_title(img, title, 1960, "left", 3, max_w=1150, x=84)
    os.makedirs(f"final/{lang}", exist_ok=True)
    img.save(f"final/{lang}/{name}.png")


if os.path.isdir("final"):
    shutil.rmtree("final")
for lang in ("it", "en", "es", "fr"):
    for name, layout, titles in SLIDES:
        compose(lang, name, layout, titles[lang])
print("ok")

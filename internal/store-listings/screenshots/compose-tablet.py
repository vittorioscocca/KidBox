"""Screenshot degli store per iPad 13" e iPhone Duo aperto, nello stile del set iPhone.

Stesso sfondo arancione e titolo nero di `compose.py`. iPad in verticale (la
barra laterale c'è anche così), Duo in orizzontale: in verticale ha la barra in
basso, come l'iPhone. Titolo in alto, dispositivo sotto con bordo scuro; sul
Duo una piega leggera al centro.

Uso: python3 compose-tablet.py
Legge raw-ipad/<lingua>/NN-*.png e raw-duo/<lingua>/NN-*.png (schermate del
simulatore con la demo, vedi README) e scrive final-ipad/ e final-duo/.
Non tocca final/ (quello dell'iPhone, che `compose.py` ricrea da zero).

Formati richiesti da App Store Connect: iPad 13" 2064×2752, in verticale (set
APP_IPAD_PRO_3GEN_129), iPhone Duo schermo interno 2853×2007 (set APP_IPHONE_DUO).
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os, shutil

FONT = "/System/Library/Fonts/Avenir Next.ttc"
HEAVY = 8
TITLE_COLOR = (28, 18, 12)

DEVICES = {
    "ipad": {"size": (2064, 2752), "radius": 0.035, "bezel": 0.018, "hinge": False},
    "duo": {"size": (2853, 2007), "radius": 0.045, "bezel": 0.014, "hinge": False, "fold": True},
}

SLIDES = [
    ("01-home", {
        "it": "Tutta la famiglia a colpo d'occhio",
        "en": "Your whole family at a glance",
        "es": "Toda la familia de un vistazo",
        "fr": "Toute la famille en un coup d'œil"}),
    ("02-calendar", {
        "it": "Un calendario per tutta la famiglia",
        "en": "One calendar for the whole family",
        "es": "Un calendario para toda la familia",
        "fr": "Un calendrier pour toute la famille"}),
    ("03-todo", {
        "it": "Cose da fare assegnate a ognuno",
        "en": "Tasks assigned to each person",
        "es": "Tareas asignadas a cada uno",
        "fr": "Des tâches assignées à chacun"}),
    ("04-spese", {
        "it": "Spese di casa sotto controllo",
        "en": "Household spending under control",
        "es": "Los gastos de casa bajo control",
        "fr": "Les dépenses de la maison maîtrisées"}),
    ("05-assistant", {
        "it": "Un assistente che conosce la tua famiglia",
        "en": "An assistant that knows your family",
        "es": "Un asistente que conoce a tu familia",
        "fr": "Un assistant qui connaît votre famille"}),
]


# Duo: 7 aperte (leggermente piegate) + 2 chiuse, al massimo 10 per set.
# (file in uscita, layout, schermata aperta, schermata chiusa, titoli)
DUO_SLIDES = [
    ("01-home", "open", "01-home", None, None),
    ("02-chiuso", "closed+open", "01-home", "home", {
        "it": "Chiuso o aperto, sempre con te",
        "en": "Folded or open, always with you",
        "es": "Plegado o abierto, siempre contigo",
        "fr": "Plié ou ouvert, toujours avec vous"}),
    ("03-calendar", "open", "02-calendar", None, None),
    ("04-todo", "open", "03-todo", None, None),
    ("05-spese", "open", "04-spese", None, None),
    ("06-spesa", "open", "06-spesa", None, {
        "it": "La spesa condivisa con tutti",
        "en": "A shopping list everyone shares",
        "es": "La compra compartida con todos",
        "fr": "Des courses partagées avec tous"}),
    ("07-salute", "open", "07-salute", None, {
        "it": "La salute di tutti in un posto",
        "en": "Everyone's health in one place",
        "es": "La salud de todos en un solo lugar",
        "fr": "La santé de tous au même endroit"}),
    ("08-assistant", "open", "05-assistant", None, None),
    ("09-chiuso-assistente", "closed", None, "assistant", {
        "it": "L'assistente anche a telefono chiuso",
        "en": "The assistant, even when folded",
        "es": "El asistente, también plegado",
        "fr": "L'assistant, même plié"}),
]


def background(W, H):
    top, bot = (250, 180, 96), (242, 126, 34)
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / H
        d.line([(0, y), (W, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
    return img


def device(shot, width, spec):
    """Schermata dentro al dispositivo: anello grigio, bordo nero, angoli tondi."""
    sw = width
    sh = int(shot.height * sw / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    bezel = int(width * spec["bezel"])
    ring = max(3, int(width * 0.003))
    radius = int(width * spec["radius"])
    ow, oh = sw + 2 * (bezel + ring), sh + 2 * (bezel + ring)
    out = Image.new("RGBA", (ow, oh), (0, 0, 0, 0))
    d = ImageDraw.Draw(out)
    d.rounded_rectangle([0, 0, ow - 1, oh - 1], radius=radius + bezel + ring, fill=(88, 86, 90, 255))
    d.rounded_rectangle([ring, ring, ow - 1 - ring, oh - 1 - ring], radius=radius + bezel, fill=(10, 10, 12, 255))
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw - 1, sh - 1], radius=radius, fill=255)
    out.paste(shot, (bezel + ring, bezel + ring), mask)
    if spec["hinge"]:
        # La piega del Duo: un'ombra appena visibile al centro dello schermo.
        crease = Image.new("RGBA", (ow, oh), (0, 0, 0, 0))
        cd = ImageDraw.Draw(crease)
        cx = ow // 2
        for dx in range(-6, 7):
            a = int(18 * (1 - abs(dx) / 7))
            cd.line([(cx + dx, bezel + ring), (cx + dx, oh - bezel - ring)], fill=(0, 0, 0, a))
        out = Image.alpha_composite(out, crease)
    return out


def _coeffs(dst, src):
    """Coefficienti di Image.PERSPECTIVE: per ogni punto di arrivo, da dove
    prendere il pixel nell'immagine di partenza."""
    import numpy as np
    m = []
    for (x, y), (u, v) in zip(dst, src):
        m.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        m.append([0, 0, 0, x, y, 1, -v * x, -v * y])
    a = np.array(m, dtype=float)
    b = np.array([c for pt in src for c in pt], dtype=float)
    return np.linalg.solve(a, b).tolist()


def folded(dev, squeeze=0.93, shrink=0.045):
    """Il Duo leggermente piegato verso chi guarda, come un libro aperto: le
    due metà si accorciano verso la cerniera, che resta più lontana."""
    w, h = dev.size
    half = w // 2
    hw = int(half * squeeze)
    dy = int(h * shrink)
    out = Image.new("RGBA", (2 * hw, h), (0, 0, 0, 0))
    left = dev.crop((0, 0, half, h))
    right = dev.crop((half, 0, w, h))
    # sinistra: bordo esterno intero, cerniera più corta
    lq = [(0, 0), (hw, dy), (hw, h - dy), (0, h)]
    lsrc = [(0, 0), (half, 0), (half, h), (0, h)]
    L = left.transform((hw, h), Image.PERSPECTIVE, _coeffs(lq, lsrc), Image.BICUBIC)
    rq = [(0, dy), (hw, 0), (hw, h), (0, h - dy)]
    rsrc = [(0, 0), (w - half, 0), (w - half, h), (0, h)]
    R = right.transform((hw, h), Image.PERSPECTIVE, _coeffs(rq, rsrc), Image.BICUBIC)
    # luce: la metà destra un filo più in ombra, e un'ombra stretta sulla piega
    shade = Image.new("RGBA", (hw, h), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shade)
    for x in range(hw):
        t = x / hw
        sd.line([(x, 0), (x, h)], fill=(0, 0, 0, int(26 * (1 - t) ** 3)))
    R = Image.alpha_composite(R, Image.composite(shade, Image.new("RGBA", (hw, h)), R.split()[3]))
    lshade = shade.transpose(Image.FLIP_LEFT_RIGHT)
    L = Image.alpha_composite(L, Image.composite(lshade, Image.new("RGBA", (hw, h)), L.split()[3]))
    out.paste(L, (0, 0), L)
    out.paste(R, (hw, 0), R)
    return out


def _shape_mask(size, r_left, r_right):
    """Rettangolo con angoli diversi: piccoli a sinistra (cerniera), grandi a destra."""
    w, h = size
    left = Image.new("L", size, 0)
    ImageDraw.Draw(left).rounded_rectangle([0, 0, w - 1, h - 1], radius=max(1, r_left), fill=255)
    right = Image.new("L", size, 0)
    ImageDraw.Draw(right).rounded_rectangle([0, 0, w - 1, h - 1], radius=max(1, r_right), fill=255)
    out = Image.new("L", size, 0)
    out.paste(left.crop((0, 0, w // 2, h)), (0, 0))
    out.paste(right.crop((w // 2, 0, w, h)), (w // 2, 0))
    return out


def phone(shot, width):
    """Il Duo chiuso com'è davvero: angoli arrotondati solo a destra, a
    sinistra la cerniera con il dorso scuro; foro della fotocamera in alto a
    destra, due tasti sopra e uno sul lato destro."""
    sw = width
    sh = int(shot.height * sw / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    bezel = int(width * 0.028)
    ring = max(3, int(width * 0.006))
    r_right = int(width * 0.13)
    r_left = int(width * 0.025)
    spine = int(width * 0.045)      # dorso della cerniera che sporge a sinistra
    btn = int(width * 0.012)        # sporgenza dei tasti
    bw, bh = sw + 2 * (bezel + ring), sh + 2 * (bezel + ring)
    ow, oh = bw + spine + btn, bh + 2 * btn
    out = Image.new("RGBA", (ow, oh), (0, 0, 0, 0))
    d = ImageDraw.Draw(out)
    bx, by = spine, btn               # angolo in alto a sinistra del corpo
    grey, dark = (88, 86, 90, 255), (62, 61, 64, 255)
    # tasti: due sopra, uno sul lato destro
    for fx in (0.50, 0.66):
        x = bx + int(bw * fx)
        d.rounded_rectangle([x, by - btn, x + int(bw * 0.13), by + btn], radius=btn, fill=grey)
    yb = by + int(bh * 0.24)
    d.rounded_rectangle([bx + bw - btn, yb, bx + bw + btn, yb + int(bh * 0.13)], radius=btn, fill=grey)
    # dorso della cerniera, dietro al corpo
    d.rounded_rectangle([0, by + int(bh * 0.008), bx + r_left * 2, by + bh - int(bh * 0.008)],
                        radius=int(spine * 0.45), fill=dark)
    # corpo: anello grigio e bordo nero con gli angoli giusti
    body = Image.new("RGBA", (bw, bh), grey)
    out.paste(body, (bx, by), _shape_mask((bw, bh), r_left + bezel + ring, r_right + bezel + ring))
    inner = Image.new("RGBA", (bw - 2 * ring, bh - 2 * ring), (10, 10, 12, 255))
    out.paste(inner, (bx + ring, by + ring), _shape_mask(inner.size, r_left + bezel, r_right + bezel))
    out.paste(shot, (bx + bezel + ring, by + bezel + ring), _shape_mask((sw, sh), r_left, r_right))
    # foro della fotocamera, in alto a destra sopra l'ora
    cr = int(sw * 0.042)
    cx = bx + bezel + ring + int(sw * 0.895)
    cy = by + bezel + ring + int(sw * 0.075)
    d.ellipse([cx - cr, cy - cr, cx + cr, cy + cr], fill=(0, 0, 0, 255))
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


def fit(text, max_w, max_lines, start):
    size = start
    while size > 60:
        f = ImageFont.truetype(FONT, size, index=HEAVY)
        lines = wrap(text, f, max_w)
        if len(lines) <= max_lines and all(f.getlength(l) <= max_w for l in lines):
            return f, lines
        size -= 6
    f = ImageFont.truetype(FONT, 60, index=HEAVY)
    return f, wrap(text, f, max_w)


def shadowed(base, im, pos, blur=40, dy=30, alpha=90):
    sh = Image.new("RGBA", base.size, (0, 0, 0, 0))
    a = im.split()[3].point(lambda v: min(v, alpha))
    tmp = Image.new("RGBA", im.size, (60, 20, 0, 255))
    tmp.putalpha(a)
    sh.paste(tmp, (pos[0], pos[1] + dy), tmp)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    base.paste(sh, (0, 0), sh)
    base.paste(im, pos, im)


def load(path, landscape):
    shot = Image.open(path).convert("RGB")
    if (shot.width < shot.height) == landscape:
        shot = shot.rotate(-90, expand=True)
    return shot


def compose_duo(lang, out, layout, open_name, closed_name, title):
    """Slide del Duo con lo schermo esterno (chiuso), da solo o accanto
    all'aperto piegato."""
    spec = DEVICES["duo"]
    W, H = spec["size"]
    img = background(W, H)
    f, lines = fit(title, int(W * 0.86), 1, int(H * 0.085))
    d = ImageDraw.Draw(img)
    top = int(H * 0.07)
    lh = int(f.size * 1.08)
    d.text((W / 2, top), lines[0], font=f, fill=TITLE_COLOR, anchor="ma")
    y = top + lh + int(H * 0.05)
    avail_h = H - y - int(H * 0.04)
    closed = load(f"raw-duo-closed/{lang}/{closed_name}.png", landscape=False)
    ph_w = int(avail_h * 0.86 * closed.width / closed.height)
    ph = phone(closed, ph_w)
    if layout == "closed":
        shadowed(img, ph, ((W - ph.width) // 2, y))
    else:
        opened = load(f"raw-duo/{lang}/{open_name}.png", landscape=True)
        dw = int(W * 0.56)
        dev = folded(device(opened, dw, spec))
        gap = int(W * 0.04)
        total = ph.width + gap + dev.width
        x0 = (W - total) // 2
        shadowed(img, dev, (x0 + ph.width + gap, y + (ph.height - dev.height) // 2))
        shadowed(img, ph, (x0, y))
    os.makedirs(f"final-duo/{lang}", exist_ok=True)
    img.save(f"final-duo/{lang}/{out}.png")


def compose(kind, lang, name, title, out=None):
    spec = DEVICES[kind]
    W, H = spec["size"]
    shot = Image.open(f"raw-{kind}/{lang}/{name}.png").convert("RGB")
    if (shot.width < shot.height) != (W < H):
        # simctl salva il framebuffer nel verso nativo: un'interfaccia girata
        # rispetto al canvas arriva ruotata di 90°.
        shot = shot.rotate(-90, expand=True)
    img = background(W, H)
    portrait = W < H
    f, lines = fit(title, int(W * 0.86), 2 if portrait else 1, int(H * (0.062 if portrait else 0.085)))
    d = ImageDraw.Draw(img)
    top = int(H * 0.07)
    lh = int(f.size * 1.08)
    for i, line in enumerate(lines):
        d.text((W / 2, top + i * lh), line, font=f, fill=TITLE_COLOR, anchor="ma")
    y = top + lh * len(lines) + int(H * 0.05)
    avail_h = H - y - int(H * 0.05)
    width = int(W * (0.84 if portrait else 0.80))
    if width * shot.height / shot.width > avail_h * 0.97:
        width = int(avail_h * 0.97 * shot.width / shot.height)
    dev = device(shot, width, spec)
    if spec.get("fold"):
        dev = folded(dev)
    shadowed(img, dev, ((W - dev.width) // 2, y))
    os.makedirs(f"final-{kind}/{lang}", exist_ok=True)
    img.save(f"final-{kind}/{lang}/{out or name}.png")


TITLES = {name: titles for name, titles in SLIDES}

for kind in DEVICES:
    if not os.path.isdir(f"raw-{kind}"):
        continue
    if os.path.isdir(f"final-{kind}"):
        shutil.rmtree(f"final-{kind}")
    for lang in sorted(os.listdir(f"raw-{kind}")):
        if kind == "duo":
            for out, layout, open_name, closed_name, titles in DUO_SLIDES:
                titles = titles or TITLES[open_name]
                if layout == "open":
                    if os.path.exists(f"raw-duo/{lang}/{open_name}.png"):
                        compose("duo", lang, open_name, titles[lang], out)
                elif os.path.exists(f"raw-duo-closed/{lang}/{closed_name}.png"):
                    compose_duo(lang, out, layout, open_name, closed_name, titles[lang])
            continue
        for name, titles in SLIDES:
            if os.path.exists(f"raw-{kind}/{lang}/{name}.png"):
                compose(kind, lang, name, titles[lang])
print("ok")

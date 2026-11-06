"""Intestazione e risultati di ricerca (5244x2950) con l'iPhone Duo, chiuso e aperto.

Stesso impianto di `compose-header.py` (testo a sinistra, dispositivi a destra,
stessi testi), ma al posto dei due iPhone il Duo chiuso accanto al Duo aperto e
leggermente piegato, con le cornici di `compose-tablet.py`.

Uso: python3 compose-header-duo.py
  → header-duo/<lingua>/header.png          risultati della ricerca (intera)
  → header-duo-pagina/<lingua>/header.png   intestazione della pagina prodotto
    (gruppo compatto al centro: l'App Store ritaglia i lati e copre il fondo)
"""
import importlib.util
import os

from PIL import Image, ImageDraw

spec = importlib.util.spec_from_file_location("tablet", "compose-tablet.py")
tablet = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tablet)

spec = importlib.util.spec_from_file_location("header", "compose-header.py")
header = importlib.util.module_from_spec(spec)
# compose-header.py rifà le immagini iPhone quando gira: qui servono solo le funzioni.
src = open("compose-header.py").read().split("\nfor lang in TEXTS:")[0]
exec(compile(src, "compose-header.py", "exec"), header.__dict__)

W, H = header.W, header.H


def duo_pair(lang, height):
    """Duo chiuso (davanti, a sinistra) e Duo aperto piegato, alti `height`."""
    closed = tablet.load(f"raw-duo-closed/{lang}/home.png", landscape=False)
    opened = tablet.load(f"raw-duo/{lang}/01-home.png", landscape=True)
    ph = tablet.phone(closed, int(height * closed.width / closed.height))
    dev = tablet.folded(tablet.device(opened, int(height * 0.86 * opened.width / opened.height),
                                      tablet.DEVICES["duo"]))
    return ph, dev


def place(img, lang, x0, x1, y_mid, height, blur, dy):
    """Il chiuso davanti, sovrapposto al bordo sinistro dell'aperto; tutto fra
    x0 e x1, alto al massimo `height` (si rimpicciolisce se non ci sta)."""
    overlap = 0.22
    ph, dev = duo_pair(lang, height)
    total = ph.width + dev.width - int(ph.width * overlap)
    if total > x1 - x0:
        ph, dev = duo_pair(lang, int(height * (x1 - x0) / total))
        total = ph.width + dev.width - int(ph.width * overlap)
    x = x0 + (x1 - x0 - total) // 2
    header.shadowed(img, dev, (x + ph.width - int(ph.width * overlap), y_mid - dev.height // 2), blur=blur, dy=dy)
    header.shadowed(img, ph, (x, y_mid - ph.height // 2), blur=blur, dy=dy)


def text(img, lang, x, y_mid, max_w, t_size, s_size, gap):
    title, sub = header.TEXTS[lang]
    d = ImageDraw.Draw(img)
    f1 = header.fit_block(title, max_w, t_size, header.HEAVY)
    f2 = header.fit_block(sub, max_w, s_size, header.DEMI)
    l1, l2 = title.split("\n"), sub.split("\n")
    lh1, lh2 = int(f1.size * 1.08), int(f2.size * 1.25)
    y = y_mid - (lh1 * len(l1) + gap + lh2 * len(l2)) // 2
    for line in l1:
        d.text((x, y), line, font=f1, fill=header.INK, anchor="la")
        y += lh1
    y += gap
    for line in l2:
        d.text((x, y), line, font=f2, fill=(70, 38, 10), anchor="la")
        y += lh2


# Nei risultati di ricerca la scheda dell'iPhone (3:2) mostra solo un ritaglio
# dell'immagine. Misurato su uno screenshot reale il 06/11/2026: x ~1570–3670
# (centrato in orizzontale), y ~450–1850 (NON centrato: parte dall'alto).
# Prima testo e dispositivi arrivavano fino a x 560 e 4850: la scheda tagliava
# «KidBox,» e il Duo aperto. Ora tutto sta in un gruppo largo ~1850 px fra
# x 1700 e 3550, intorno a y 1150, con margine su ogni lato; niente sottotitolo
# (nella scheda starebbe sotto i 7 pt). Il Duo chiuso e quello aperto restano
# vicini, il titolo a sinistra.
SEARCH_X0, SEARCH_X1 = 1700, 3550
SEARCH_MID = 1150
SEARCH_TEXT_W = 860


def make(lang):
    img = header.background()
    place(img, lang, SEARCH_X0 + SEARCH_TEXT_W + 70, SEARCH_X1, SEARCH_MID, 620, 26, 20)
    title, _ = header.TEXTS[lang]
    d = ImageDraw.Draw(img)
    f1 = header.fit_block(title, SEARCH_TEXT_W, 150, header.HEAVY)
    l1 = title.split("\n")
    lh1 = int(f1.size * 1.08)
    y = SEARCH_MID - lh1 * len(l1) // 2
    for line in l1:
        d.text((SEARCH_X0, y), line, font=f1, fill=header.INK, anchor="la")
        y += lh1
    os.makedirs(f"header-duo/{lang}", exist_ok=True)
    img.save(f"header-duo/{lang}/header.png")


def make_compact(lang):
    img = header.background()
    place(img, lang, 2880, 4380, 1330, 1350, 40, 34)
    text(img, lang, 1240, 1330, 1540, 220, 72, 70)
    os.makedirs(f"header-duo-pagina/{lang}", exist_ok=True)
    img.save(f"header-duo-pagina/{lang}/header.png")


for lang in header.TEXTS:
    make(lang)
    make_compact(lang)
print("ok")

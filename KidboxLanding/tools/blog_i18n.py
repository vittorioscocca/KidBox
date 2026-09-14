# -*- coding: utf-8 -*-
"""
Traduzioni del blog in spagnolo e francese, a lotti.

Ogni modulo `blog_<lingua>_<n>.py` (es: ES = {...}, fr: FR = {...}) espone un
dizionario slug → {title, desc, body} nel formato degli articoli (vedi
blog_data.py); vengono raccolti tutti in ordine di numero. Le traduzioni sono
adattate, non letterali: niente Alexa (solo italiano), niente funzioni che
KidBox non ha, e i link interni puntano solo ad articoli già tradotti.
"""
import importlib
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent


def _load(lang):
    found = {}
    mods = sorted(HERE.glob(f"blog_{lang}_*.py"), key=lambda p: int(re.search(r"_(\d+)\.py$", p.name).group(1)))
    for path in mods:
        items = getattr(importlib.import_module(path.stem), lang.upper())
        dup = set(found) & set(items)
        if dup:
            raise SystemExit(f"traduzione {lang}: articoli ripetuti in {path.name}: {dup}")
        found.update(items)
    return found


TRANSLATIONS = {lang: _load(lang) for lang in ("es", "fr")}


def apply(articles):
    by_slug = {a["slug"]: a for a in articles}
    for lang, items in TRANSLATIONS.items():
        for slug, text in items.items():
            if slug not in by_slug:
                raise SystemExit(f"traduzione {lang}: articolo sconosciuto {slug}")
            if set(text) != {"title", "desc", "body"}:
                raise SystemExit(f"traduzione {lang}: campi errati in {slug}")
            by_slug[slug][lang] = text

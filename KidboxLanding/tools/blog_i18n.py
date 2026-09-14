# -*- coding: utf-8 -*-
"""
Traduzioni del blog in spagnolo e francese, a lotti.

Ogni modulo `blog_<lingua>_<n>.py` espone un dizionario slug → {title, desc,
body} nel formato degli articoli (vedi blog_data.py). Le traduzioni sono
adattate, non letterali: niente Alexa (solo italiano), niente funzioni che
KidBox non ha, e i link interni puntano solo ad articoli già tradotti.
"""
from blog_es_1 import ES as _ES1  # noqa: E402
from blog_es_2 import ES as _ES2  # noqa: E402

TRANSLATIONS = {
    "es": {**_ES1, **_ES2},
}

try:
    from blog_fr_1 import FR as _FR1  # noqa: E402
    from blog_fr_2 import FR as _FR2  # noqa: E402
    TRANSLATIONS["fr"] = {**_FR1, **_FR2}
except ImportError:
    pass


def apply(articles):
    by_slug = {a["slug"]: a for a in articles}
    for lang, items in TRANSLATIONS.items():
        for slug, text in items.items():
            if slug not in by_slug:
                raise SystemExit(f"traduzione {lang}: articolo sconosciuto {slug}")
            by_slug[slug][lang] = text

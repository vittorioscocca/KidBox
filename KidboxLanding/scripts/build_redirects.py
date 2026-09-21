#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Scrive in `firebase.json` i redirect 301 dagli URL vecchi del blog a quelli
attuali, così le pagine già indicizzate e i link in giro non muoiono.

    python3 scripts/build_redirects.py

Lo lancia `build_blog.py` alla fine. Le sorgenti sono:
  - lo slug italiano nelle cartelle EN/ES/FR (fino al 21/09/2026 le traduzioni
    lo usavano com'era), per ogni articolo e categoria con uno slug tradotto;
  - gli slug elencati a mano in `blog_slugs.OLD` (rinomine successive).
Il blocco `redirects` di firebase.json è interamente generato: non editarlo a mano.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from blog_data import ARTICLES, CATEGORIES, article_slug, category_slug  # noqa: E402
from blog_slugs import OLD  # noqa: E402
from site_langs import BLOG_DIR  # noqa: E402

LANGS = ("en", "es", "fr")


def redirects():
    out = {}  # sorgente → destinazione, senza doppioni
    for lang in LANGS:
        d = BLOG_DIR[lang]
        pairs = [(a["slug"], article_slug(a, lang)) for a in ARTICLES if lang in a]
        # Le categorie senza articoli tradotti non hanno pagina in quella lingua.
        pairs += [(c, category_slug(c, lang)) for c in CATEGORIES
                  if lang in CATEGORIES[c] and any(a["category"] == c and lang in a for a in ARTICLES)]
        current = {new for _, new in pairs}
        for old, new in pairs:
            if old != new:
                out[f"/{d}/{old}"] = f"/{d}/{new}"
        for new, olds in OLD.get(lang, {}).items():
            for old in olds:
                out[f"/{d}/{old}"] = f"/{d}/{new}"
        # Una sorgente che è anche una pagina viva sarebbe un errore di mappa.
        clash = {src for src in out if src.startswith(f"/{d}/") and src.split("/")[-1] in current}
        if clash:
            raise SystemExit(f"redirects: sorgenti che sono anche pagine attuali: {sorted(clash)}")
    return [{"source": src, "destination": dst, "type": 301} for src, dst in sorted(out.items())]


def main():
    path = ROOT / "firebase.json"
    cfg = json.loads(path.read_text(encoding="utf-8"))
    hosting = cfg["hosting"]
    rules = redirects()
    # `redirects` va prima di `rewrites`: Firebase applica i redirect prima di
    # servire i file statici e prima delle rewrite.
    items = [(k, v) for k, v in hosting.items() if k != "redirects"]
    i = next((n for n, (k, _) in enumerate(items) if k == "rewrites"), len(items))
    items.insert(i, ("redirects", rules))
    cfg["hosting"] = dict(items)
    path.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"firebase.json: {len(rules)} redirect")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Genera `public/sitemap.xml` e `public/robots.txt`.

    python3 scripts/build_sitemap.py

Lo lanciano anche `build_tools.py` e `build_blog.py` alla fine, così la mappa
segue da sola gli strumenti e gli articoli aggiunti. Le pagine statiche sono
elencate in `STATIC`: una pagina nuova scritta a mano va aggiunta lì.

Ogni URL porta le alternative hreflang delle traduzioni che esistono davvero. Gli URL sono quelli puliti
serviti da Firebase (`cleanUrls`), senza `.html`.
"""
import subprocess
import sys
from datetime import date
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
PUBLIC = ROOT / "public"
sys.path.insert(0, str(ROOT / "tools"))
from blog_data import ARTICLES, CATEGORIES, article_slug, category_slug  # noqa: E402
from tools_data import TOOLS  # noqa: E402

SITE = "https://kidboxapp.com"

LANGS = ["it", "en", "es", "fr"]
TOOLS_DIR = {"it": "strumenti", "en": "en/tools", "es": "es/tools", "fr": "fr/tools"}
BLOG_DIR = {"it": "blog", "en": "en/blog", "es": "es/blog", "fr": "fr/blog"}

# Pagine scritte a mano: base italiana, le altre lingue sono `<base>-<lang>`.
# join, scarica e 404 restano fuori: sono noindex o di servizio.
STATIC = ["", "guide", "support", "privacy", "terms", "data-deletion"]


def git_date(*files):
    """Ultima modifica dei sorgenti: data dell'ultimo commit che li tocca, oggi
    se hanno modifiche non committate. Mai l'mtime, che cambia a ogni build."""
    paths = [str(f) for f in files if Path(f).exists()]
    dirty = subprocess.run(["git", "status", "--porcelain", "--", *paths], cwd=ROOT,
                           capture_output=True, text=True).stdout.strip()
    if dirty:
        return date.today().isoformat()
    out = subprocess.run(["git", "log", "-1", "--format=%cs", "--", *paths], cwd=ROOT,
                         capture_output=True, text=True).stdout.strip()
    return out or None


def source(loc):
    return PUBLIC / ((loc.rstrip("/") + "/index.html") if loc.endswith("/") else f"{loc or 'index'}.html")


def groups():
    """Gruppi ({lingua: path}, lastmod o None): solo le traduzioni che esistono."""
    out = []
    for base in STATIC:
        paths = {"it": base}
        for l in LANGS[1:]:
            name = f"{base or 'index'}-{l}"
            if (PUBLIC / f"{name}.html").exists():
                paths[l] = name
        out.append((paths, git_date(*(source(p) for p in paths.values()))))
    tools_src = (ROOT / "tools" / "tools_data.py", ROOT / "tools" / "tools_data_es_fr.py", ROOT / "scripts" / "build_tools.py")
    tool_langs = [l for l in LANGS if any(l in t for t in TOOLS)]
    out.append(({l: f"{TOOLS_DIR[l]}/" for l in tool_langs}, git_date(*tools_src)))
    out += [({l: f"{TOOLS_DIR[l]}/{t['slug']}" for l in LANGS if l in t}, git_date(*tools_src)) for t in TOOLS]
    blog_langs = [l for l in LANGS if any(l in a for a in ARTICLES)]
    out.append(({l: f"{BLOG_DIR[l]}/" for l in blog_langs}, max(a["date"] for a in ARTICLES)))
    for cslug, cat in CATEGORIES.items():
        paths = {l: f"{BLOG_DIR[l]}/{category_slug(cslug, l)}" for l in LANGS
                 if l in cat and any(a["category"] == cslug and l in a for a in ARTICLES)}
        dates = [a["date"] for a in ARTICLES if a["category"] == cslug]
        if paths:
            out.append((paths, max(dates)))
    out += [({l: f"{BLOG_DIR[l]}/{article_slug(a, l)}" for l in LANGS if l in a}, a["date"]) for a in ARTICLES]
    return out


def url_entry(loc, paths, lastmod):
    alts = list(paths.items()) + [("x-default", paths.get("it") or next(iter(paths.values())))]
    links = "".join(
        f'\n    <xhtml:link rel="alternate" hreflang="{lang}" href="{escape(f"{SITE}/{p}")}"/>'
        for lang, p in alts
    )
    mod = f"\n    <lastmod>{lastmod}</lastmod>" if lastmod else ""
    return f"  <url>\n    <loc>{escape(f'{SITE}/{loc}')}</loc>{mod}{links}\n  </url>"


def main():
    entries = []
    for paths, lastmod in groups():
        for loc in paths.values():
            if not source(loc).exists():
                raise SystemExit(f"sitemap: manca {source(loc).relative_to(ROOT)} per /{loc}")
            entries.append(url_entry(loc, paths, lastmod))
    xml = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" '
        'xmlns:xhtml="http://www.w3.org/1999/xhtml">\n'
        + "\n".join(entries)
        + "\n</urlset>\n"
    )
    (PUBLIC / "sitemap.xml").write_text(xml, encoding="utf-8")
    (PUBLIC / "robots.txt").write_text(
        f"User-agent: *\nAllow: /\n\nSitemap: {SITE}/sitemap.xml\n", encoding="utf-8"
    )
    print(f"sitemap.xml: {len(entries)} URL")


if __name__ == "__main__":
    main()

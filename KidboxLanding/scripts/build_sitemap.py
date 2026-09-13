#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Genera `public/sitemap.xml` e `public/robots.txt`.

    python3 scripts/build_sitemap.py

Lo lanciano anche `build_tools.py` e `build_blog.py` alla fine, così la mappa
segue da sola gli strumenti e gli articoli aggiunti. Le pagine statiche sono
elencate in `STATIC`: una pagina nuova scritta a mano va aggiunta lì.

Ogni URL porta le alternative hreflang it/en. Gli URL sono quelli puliti
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
from blog_data import ARTICLES, CATEGORIES  # noqa: E402
from tools_data import TOOLS  # noqa: E402

SITE = "https://kidboxapp.com"

# (italiano, inglese) — join, scarica e 404 restano fuori: sono noindex o di servizio.
STATIC = [
    ("", "index-en"),
    ("guide", "guide-en"),
    ("support", "support-en"),
    ("privacy", "privacy-en"),
    ("terms", "terms-en"),
    ("data-deletion", "data-deletion-en"),
]


def git_date(*files):
    """Ultima modifica dei sorgenti: data dell'ultimo commit che li tocca, oggi
    se hanno modifiche non committate. Mai l'mtime, che cambia a ogni build."""
    paths = [str(f) for f in files]
    dirty = subprocess.run(["git", "status", "--porcelain", "--", *paths], cwd=ROOT,
                           capture_output=True, text=True).stdout.strip()
    if dirty:
        return date.today().isoformat()
    out = subprocess.run(["git", "log", "-1", "--format=%cs", "--", *paths], cwd=ROOT,
                         capture_output=True, text=True).stdout.strip()
    return out or None


def pairs():
    """Coppie (path it, path en, lastmod o None)."""
    out = [(it, en, git_date(PUBLIC / f"{it or 'index'}.html", PUBLIC / f"{en}.html")) for it, en in STATIC]
    tools_src = (ROOT / "tools" / "tools_data.py", ROOT / "scripts" / "build_tools.py")
    out.append(("strumenti/", "en/tools/", git_date(*tools_src)))
    out += [(f"strumenti/{t['slug']}", f"en/tools/{t['slug']}", git_date(*tools_src)) for t in TOOLS]
    newest = max(a["date"] for a in ARTICLES)
    out.append(("blog/", "en/blog/", newest))
    for cslug in CATEGORIES:
        dates = [a["date"] for a in ARTICLES if a["category"] == cslug]
        if dates:
            out.append((f"blog/{cslug}", f"en/blog/{cslug}", max(dates)))
    out += [(f"blog/{a['slug']}", f"en/blog/{a['slug']}", a["date"]) for a in ARTICLES]
    return out


def url_entry(loc, it, en, lastmod):
    alts = "".join(
        f'\n    <xhtml:link rel="alternate" hreflang="{lang}" href="{escape(f"{SITE}/{p}")}"/>'
        for lang, p in (("it", it), ("en", en), ("x-default", it))
    )
    mod = f"\n    <lastmod>{lastmod}</lastmod>" if lastmod else ""
    return f"  <url>\n    <loc>{escape(f'{SITE}/{loc}')}</loc>{mod}{alts}\n  </url>"


def main():
    entries = []
    for it, en, lastmod in pairs():
        for loc in (it, en):
            src = PUBLIC / ((loc.rstrip("/") + "/index.html") if loc.endswith("/") else f"{loc or 'index'}.html")
            if not src.exists():
                raise SystemExit(f"sitemap: manca {src.relative_to(ROOT)} per /{loc}")
            entries.append(url_entry(loc, it, en, lastmod))
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

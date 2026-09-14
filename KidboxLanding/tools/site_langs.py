# -*- coding: utf-8 -*-
"""
Le lingue della landing e dove vive ogni pagina in ciascuna lingua.

Schema degli URL (puliti, senza .html grazie a cleanUrls):
  home          /             /index-en       /index-es       /index-fr
  statiche      /guide        /guide-en       /guide-es       /guide-fr     (support, privacy, terms, data-deletion)
  strumenti     /strumenti/x  /en/tools/x     /es/tools/x     /fr/tools/x
  blog          /blog/x       /en/blog/x      /es/blog/x      /fr/blog/x

L'italiano sta alla radice per ragioni storiche (inviti e link già in giro).
Il menu delle lingue (`lang_menu`) è lo stesso ovunque: i generatori e
build_footer.py gli passano gli href della pagina gemella in ogni lingua.
"""

LANGS = ["it", "en", "es", "fr"]

LABEL = {"it": "Italiano", "en": "English", "es": "Español", "fr": "Français"}
MENU_ARIA = {"it": "Lingua", "en": "Language", "es": "Idioma", "fr": "Langue"}

HOME = {"it": "index.html", "en": "index-en.html", "es": "index-es.html", "fr": "index-fr.html"}
TOOLS_DIR = {"it": "strumenti", "en": "en/tools", "es": "es/tools", "fr": "fr/tools"}
BLOG_DIR = {"it": "blog", "en": "en/blog", "es": "es/blog", "fr": "fr/blog"}

STATIC_BASES = ["guide", "support", "privacy", "terms", "data-deletion"]


def static_file(base, lang):
    return f"{base}.html" if lang == "it" else f"{base}-{lang}.html"


def clean_url(path):
    """'index-en.html' → 'index-en', 'index.html' → '', 'blog/x.html' → 'blog/x'."""
    if path in ("index.html", ""):
        return ""
    return path[:-5] if path.endswith(".html") else path


GLOBE = ('<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" '
         'aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.7 3.8 5.7 3.8 9s-1.3 6.3-3.8 9'
         'M12 3C9.5 5.7 8.2 8.7 8.2 12s1.3 6.3 3.8 9"/></svg>')


def lang_menu(current, hrefs):
    """Menu a tendina delle lingue. `hrefs`: lingua → href relativo della pagina
    gemella (le lingue senza gemella portano alla home di quella lingua)."""
    items = "".join(
        f'<a href="{hrefs[l]}" hreflang="{l}" lang="{l}" data-lang="{l}"'
        + (' aria-current="true"' if l == current else "")
        + f'>{LABEL[l]}</a>'
        for l in LANGS
    )
    return (f'<details class="lang-menu"><summary aria-label="{MENU_ARIA[current]}">{GLOBE}'
            f'<span>{current.upper()}</span></summary><div class="lang-list">{items}</div></details>')


# Stile del menu: usa le variabili della home (--text, --muted, --border,
# --surface, --accent) con ripiego su quelle delle pagine statiche (--c-*).
LANG_MENU_CSS = """
  /* langmenu:css:start */
  .lang-menu { position:relative; font-size:0.82rem; font-weight:600; }
  .lang-menu summary { list-style:none; cursor:pointer; display:inline-flex; align-items:center; gap:6px; padding:6px 10px; border-radius:50px;
    border:1px solid var(--border, var(--c-border)); color:var(--muted, var(--c-muted)); user-select:none; }
  .lang-menu summary::-webkit-details-marker { display:none; }
  .lang-menu summary:hover, .lang-menu[open] summary { color:var(--text, var(--c-text)); border-color:var(--accent, var(--c-accent)); }
  .lang-list { position:absolute; right:0; top:calc(100% + 8px); min-width:150px; padding:6px; border-radius:14px; z-index:200;
    background:var(--surface, var(--c-surface)); border:1px solid var(--border, var(--c-border)); box-shadow:0 12px 32px rgba(0,0,0,.18); }
  .lang-list a { display:block; padding:8px 12px; border-radius:9px; color:var(--text, var(--c-text)); text-decoration:none; font-weight:500; white-space:nowrap; }
  .lang-list a:hover { background:var(--border, var(--c-border)); }
  .lang-list a[aria-current] { color:var(--accent, var(--c-accent)); font-weight:700; }
  /* langmenu:css:end */"""

# Script del menu: ricorda la scelta (vince sull'automatismo della home) e
# chiude la tendina cliccando fuori o con Esc.
LANG_JS = "/assets/lang.js"

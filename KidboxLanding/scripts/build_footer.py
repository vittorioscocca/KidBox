#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Genera il footer «mappa del sito» di index.html e index-en.html e delle pagine
statiche (guida, supporto, privacy, termini, eliminazione dati).

    python3 scripts/build_footer.py

Lo lanciano anche build_tools.py e build_blog.py all'inizio, prima di copiare
il footer della home nelle loro pagine: così una categoria del blog o uno
strumento nuovo compare nel footer di tutto il sito senza toccare l'HTML.

Il blocco sta tra i commenti <!-- footer:start --> e <!-- footer:end -->; le
regole CSS tra /* footer:css:start */ e /* footer:css:end */ nello <style>.
I link sono relativi alla home: le pagine generate li riportano alla radice con
rebase_links. Il link alla lingua ha `data-lang-other`, che i generatori
puntano alla pagina gemella.
"""
import html
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUBLIC = ROOT / "public"
sys.path.insert(0, str(ROOT / "tools"))
from blog_data import ARTICLES, CATEGORIES, category_slug  # noqa: E402
from tools_data import TOOLS  # noqa: E402
from site_langs import (BLOG_DIR, HOME, LABEL, LANG_JS, LANG_MENU_CSS, LANGS, STATIC_BASES,  # noqa: E402
                        TOOLS_DIR, clean_url, lang_menu, static_file)

YEAR = 2026
FACEBOOK = "https://www.facebook.com/profile.php?id=61574265148948"
INSTAGRAM = "https://www.instagram.com/kidbox_app"
WEBAPP = "https://app.kidboxapp.com"

L = {
    "it": {
        "src": "index.html", "tools": "strumenti", "blog": "blog",
        "notes": [
            "Piano Alimentare, Piano Fitness e itinerari di viaggio con l'AI richiedono il piano Pro o Max. L'assistente AI e le altre funzioni AI (lettura di documenti e biglietti, agenti proattivi) usano i messaggi del piano: il Free ne include 5 di prova, una tantum.",
            "La skill Alexa è disponibile solo in italiano. Le funzioni possono cambiare e alcune potrebbero non essere disponibili su tutte le piattaforme.",
            "App Store è un marchio di Apple Inc. Google Play è un marchio di Google LLC. Alexa è un marchio di Amazon.com, Inc. o delle sue affiliate.",
        ],
        "cols": [
            ("Organizzazione", ["calendario", "to-do", "lista-della-spesa", "spese", "note"],
             "Documenti e sicurezza", ["documenti", "password", "wallet"]),
            ("Famiglia", ["famiglia", "chat", "posizione", "foto-e-video"],
             "Salute, casa e auto", ["salute", "casa", "veicoli", "animali"]),
            ("Intelligenza AI", ["assistente-ai", "viaggi"],
             "Voce", ["alexa"]),
        ],
        "all_tools": "Tutti gli strumenti", "blog_h": "Blog", "all_blog": "Tutti gli articoli",
        "kidbox_h": "KidBox",
        "kidbox": [("#prodotti", "Prodotti"), ("#ai", "Intelligenza AI"), ("#prezzi", "Prezzi"),
                   ("guide.html", "Guida"), (WEBAPP, "Apri la web app")],
        "get_h": "Scarica", "ios": "App Store", "android": "Google Play",
        "help_h": "Supporto e privacy",
        "help": [("support.html", "Supporto"), ("privacy.html", "Privacy"), ("terms.html", "Termini di servizio"),
                 ("data-deletion.html", "Eliminazione dati"), ("#consent", "Preferenze cookie")],
        "social_h": "Seguici",
        "copy": f"Copyright © {YEAR} KidBox. Tutti i diritti riservati. Fatto con ❤️ in Italia.",
        "legal": [("privacy.html", "Privacy"), ("terms.html", "Termini"), ("#consent", "Cookie"),
                  ("data-deletion.html", "Eliminazione dati")],
        "region": "Italia", "other_label": "English", "other_href": "index-en.html",
        "this_label": "Italiano",
    },
    "en": {
        "src": "index-en.html", "tools": "en/tools", "blog": "en/blog",
        "notes": [
            "The Meal Plan, the Fitness Plan and AI trip itineraries require a Pro or Max plan. The AI assistant and the other AI features (document and ticket reading, proactive agents) use your plan's messages: Free includes 5 one-off trial messages.",
            "Features may change, and some may not be available on every platform.",
            "App Store is a trademark of Apple Inc. Google Play is a trademark of Google LLC.",
        ],
        "cols": [
            ("Organisation", ["calendario", "to-do", "lista-della-spesa", "spese", "note"],
             "Documents and security", ["documenti", "password", "wallet"]),
            ("Family", ["famiglia", "chat", "posizione", "foto-e-video"],
             "Health, home and cars", ["salute", "casa", "veicoli", "animali"]),
            ("AI", ["assistente-ai", "viaggi"], None, None),
        ],
        "all_tools": "All tools", "blog_h": "Blog", "all_blog": "All articles",
        "kidbox_h": "KidBox",
        "kidbox": [("#prodotti", "Products"), ("#ai", "AI"), ("#prezzi", "Pricing"),
                   ("guide-en.html", "Guide"), (WEBAPP, "Open the web app")],
        "get_h": "Download", "ios": "App Store", "android": "Google Play",
        "help_h": "Support and privacy",
        "help": [("support-en.html", "Support"), ("privacy-en.html", "Privacy"), ("terms-en.html", "Terms of service"),
                 ("data-deletion-en.html", "Data deletion"), ("#consent", "Cookie preferences")],
        "social_h": "Follow us",
        "copy": f"Copyright © {YEAR} KidBox. All rights reserved. Made with ❤️ in Italy.",
        "legal": [("privacy-en.html", "Privacy"), ("terms-en.html", "Terms"), ("#consent", "Cookies"),
                  ("data-deletion-en.html", "Data deletion")],
        "region": "Italy", "other_label": "Italiano", "other_href": "index.html",
        "this_label": "English",
    },
    "es": {
        "src": "index-es.html", "tools": "es/tools", "blog": "es/blog",
        "notes": [
            "El Plan de Alimentación, el Plan Fitness y los itinerarios de viaje con IA requieren el plan Pro o Max. El asistente de IA y las demás funciones de IA (lectura de documentos y billetes, agentes proactivos) usan los mensajes del plan: el Free incluye 5 de prueba, únicos.",
            "Las funciones pueden cambiar y algunas podrían no estar disponibles en todas las plataformas.",
            "App Store es una marca de Apple Inc. Google Play es una marca de Google LLC.",
        ],
        "cols": [
            ("Organización", ["calendario", "to-do", "lista-della-spesa", "spese", "note"],
             "Documentos y seguridad", ["documenti", "password", "wallet"]),
            ("Familia", ["famiglia", "chat", "posizione", "foto-e-video"],
             "Salud, hogar y coche", ["salute", "casa", "veicoli", "animali"]),
            ("IA", ["assistente-ai", "viaggi"], None, None),
        ],
        "all_tools": "Todas las herramientas", "blog_h": "Blog", "all_blog": "Todos los artículos",
        "kidbox_h": "KidBox",
        "kidbox": [("#prodotti", "Productos"), ("#ai", "IA"), ("#prezzi", "Precios"),
                   ("guide-es.html", "Guía"), (WEBAPP, "Abrir la web app")],
        "get_h": "Descargar", "ios": "App Store", "android": "Google Play",
        "help_h": "Soporte y privacidad",
        "help": [("support-es.html", "Soporte"), ("privacy-es.html", "Privacidad"), ("terms-es.html", "Términos del servicio"),
                 ("data-deletion-es.html", "Eliminación de datos"), ("#consent", "Preferencias de cookies")],
        "social_h": "Síguenos",
        "copy": f"Copyright © {YEAR} KidBox. Todos los derechos reservados. Hecho con ❤️ en Italia.",
        "legal": [("privacy-es.html", "Privacidad"), ("terms-es.html", "Términos"), ("#consent", "Cookies"),
                  ("data-deletion-es.html", "Eliminación de datos")],
    },
    "fr": {
        "src": "index-fr.html", "tools": "fr/tools", "blog": "fr/blog",
        "notes": [
            "Le Plan alimentaire, le Plan fitness et les itinéraires de voyage par l'IA nécessitent l'abonnement Pro ou Max. L'assistant IA et les autres fonctions IA (lecture de documents et de billets, agents proactifs) utilisent les messages de l'offre : Free en comprend 5 d'essai, uniques.",
            "Les fonctionnalités peuvent évoluer et certaines peuvent ne pas être disponibles sur toutes les plateformes.",
            "App Store est une marque d'Apple Inc. Google Play est une marque de Google LLC.",
        ],
        "cols": [
            ("Organisation", ["calendario", "to-do", "lista-della-spesa", "spese", "note"],
             "Documents et sécurité", ["documenti", "password", "wallet"]),
            ("Famille", ["famiglia", "chat", "posizione", "foto-e-video"],
             "Santé, maison et voiture", ["salute", "casa", "veicoli", "animali"]),
            ("IA", ["assistente-ai", "viaggi"], None, None),
        ],
        "all_tools": "Tous les outils", "blog_h": "Blog", "all_blog": "Tous les articles",
        "kidbox_h": "KidBox",
        "kidbox": [("#prodotti", "Produits"), ("#ai", "IA"), ("#prezzi", "Tarifs"),
                   ("guide-fr.html", "Guide"), (WEBAPP, "Ouvrir l'app web")],
        "get_h": "Télécharger", "ios": "App Store", "android": "Google Play",
        "help_h": "Assistance et confidentialité",
        "help": [("support-fr.html", "Assistance"), ("privacy-fr.html", "Confidentialité"), ("terms-fr.html", "Conditions d'utilisation"),
                 ("data-deletion-fr.html", "Suppression des données"), ("#consent", "Préférences cookies")],
        "social_h": "Suivez-nous",
        "copy": f"Copyright © {YEAR} KidBox. Tous droits réservés. Fait avec ❤️ en Italie.",
        "legal": [("privacy-fr.html", "Confidentialité"), ("terms-fr.html", "Conditions"), ("#consent", "Cookies"),
                  ("data-deletion-fr.html", "Suppression des données")],
    },
}

# Nomi brevi degli strumenti per il footer (i titoli delle schede sono lunghi).
SHORT = {
    "it": {"calendario": "Calendario", "to-do": "Cose da fare", "lista-della-spesa": "Lista della spesa",
           "spese": "Spese", "note": "Note", "documenti": "Documenti", "password": "Password", "wallet": "Wallet",
           "famiglia": "Famiglia e inviti", "chat": "Chat", "posizione": "Posizione", "foto-e-video": "Foto e video",
           "salute": "Salute", "casa": "Casa", "veicoli": "Veicoli", "animali": "Animali",
           "assistente-ai": "Assistente AI", "viaggi": "Viaggi", "alexa": "Alexa"},
    "en": {"calendario": "Calendar", "to-do": "To-dos", "lista-della-spesa": "Grocery list",
           "spese": "Expenses", "note": "Notes", "documenti": "Documents", "password": "Passwords", "wallet": "Wallet",
           "famiglia": "Family and invites", "chat": "Chat", "posizione": "Location", "foto-e-video": "Photos and videos",
           "salute": "Health", "casa": "Home", "veicoli": "Vehicles", "animali": "Pets",
           "assistente-ai": "AI assistant", "viaggi": "Trips", "alexa": "Alexa"},
    "es": {"calendario": "Calendario", "to-do": "Tareas", "lista-della-spesa": "Lista de la compra",
           "spese": "Gastos", "note": "Notas", "documenti": "Documentos", "password": "Contraseñas", "wallet": "Wallet",
           "famiglia": "Familia e invitaciones", "chat": "Chat", "posizione": "Ubicación", "foto-e-video": "Fotos y vídeos",
           "salute": "Salud", "casa": "Hogar", "veicoli": "Vehículos", "animali": "Mascotas",
           "assistente-ai": "Asistente de IA", "viaggi": "Viajes", "alexa": "Alexa"},
    "fr": {"calendario": "Calendrier", "to-do": "Tâches", "lista-della-spesa": "Liste de courses",
           "spese": "Dépenses", "note": "Notes", "documenti": "Documents", "password": "Mots de passe", "wallet": "Wallet",
           "famiglia": "Famille et invitations", "chat": "Chat", "posizione": "Localisation", "foto-e-video": "Photos et vidéos",
           "salute": "Santé", "casa": "Maison", "veicoli": "Véhicules", "animali": "Animaux",
           "assistente-ai": "Assistant IA", "viaggi": "Voyages", "alexa": "Alexa"},
}

CSS = """
  /* footer:css:start */
  footer { border-top:1px solid var(--border); margin-top:70px; padding:26px 0 30px; font-size:0.78rem; color:var(--muted); line-height:1.45; }
  .sf-notes { padding-bottom:16px; border-bottom:1px solid var(--border); }
  .sf-notes p { margin:0 0 8px; }
  .sf-notes p:last-child { margin-bottom:0; }
  .sf-grid { align-items:start; display:grid; grid-template-columns:repeat(5, minmax(0,1fr)); gap:26px; padding:24px 0 26px; }
  .sf-col h3 { font-size:0.78rem; font-weight:700; color:var(--text); margin:0 0 10px; letter-spacing:0; }
  .sf-col ul + h3 { margin-top:24px; }
  .sf-col ul { list-style:none; margin:0; padding:0; }
  .sf-col li { margin:0 0 7px; }
  .sf-col a, .sf-bottom a { color:var(--muted); text-decoration:none; }
  .sf-col a:hover, .sf-bottom a:hover { color:var(--text); text-decoration:underline; }
  .sf-bottom { border-top:1px solid var(--border); padding-top:16px; display:flex; flex-wrap:wrap; align-items:center; justify-content:space-between; gap:10px 28px; }
  .sf-bottom-l { display:flex; flex-wrap:wrap; align-items:center; gap:6px 24px; }
  .sf-legal { display:flex; flex-wrap:wrap; align-items:center; }
  .sf-legal a + a::before { content:"|"; color:var(--faint); margin:0 10px; }
  .sf-lang strong { color:var(--text); font-weight:600; }
  .sf-lang span { color:var(--faint); margin:0 6px; }
  @media (max-width:900px) { .sf-grid { grid-template-columns:repeat(3, minmax(0,1fr)); } }
  @media (max-width:600px) { .sf-grid { grid-template-columns:repeat(2, minmax(0,1fr)); gap:22px 18px; } }
  /* footer:css:end */"""


def link(href, label, extra=""):
    if href == "#consent":
        return f'<a href="#" data-consent-open>{html.escape(label)}</a>'
    ext = ' target="_blank" rel="noopener"' if href.startswith("http") and "kidboxapp.com" not in href else ""
    return f'<a href="{href}"{ext}{extra}>{html.escape(label)}</a>'


def ul(items):
    return "<ul>" + "".join(f"<li>{i}</li>" for i in items if i) + "</ul>"


def store_links(src):
    ios = re.search(r'href="(https://apps\.apple\.com/[^"]+)"', src).group(1)
    android = re.search(r'href="(https://play\.google\.com/[^"]+)"', src).group(1)
    return html.unescape(ios), html.unescape(android)


def available(lang):
    """Lingue la cui home esiste già (ES e FR arrivano a lotti)."""
    return (PUBLIC / HOME[lang]).exists()


def footer(lang):
    C = L[lang]
    src = (PUBLIC / HOME["it"]).read_text(encoding="utf-8")
    ios, android = store_links(src)
    slugs = {t["slug"] for t in TOOLS if lang in t}
    tool = lambda s: link(f"{C['tools']}/{s}", SHORT[lang][s]) if s in slugs else ""

    cols = []
    for i, (h1, t1, h2, t2) in enumerate(C["cols"]):
        body = f"<h3>{html.escape(h1)}</h3>" + ul([tool(s) for s in t1])
        if h2:
            body += f"<h3>{html.escape(h2)}</h3>" + ul([tool(s) for s in t2] + (
                [link(f"{C['tools']}/", C["all_tools"] + " →")] if i == 1 else []))
        if i == len(C["cols"]) - 1:
            body += f"<h3>{html.escape(C['get_h'])}</h3>" + ul([link(ios, C["ios"]), link(android, C["android"])])
        cols.append(body)

    blog = f"<h3>{C['blog_h']}</h3>" + ul(
        [link(f"{C['blog']}/{category_slug(slug, lang)}", cat[lang][0]) for slug, cat in CATEGORIES.items()
         if lang in cat and any(a["category"] == slug and lang in a for a in ARTICLES)]
        + [link(f"{C['blog']}/", C["all_blog"] + " →")])
    info = (f"<h3>{C['kidbox_h']}</h3>" + ul([link(h, t) for h, t in C["kidbox"]])
            + f"<h3>{C['help_h']}</h3>" + ul([link(h, t) for h, t in C["help"]])
            + f"<h3>{C['social_h']}</h3>" + ul([link(FACEBOOK, "Facebook"), link(INSTAGRAM, "Instagram")]))
    grid = "".join(f'\n      <div class="sf-col">{c}</div>' for c in cols[:2] + [blog, cols[2], info])

    notes = "".join(f"<p>{html.escape(n)}</p>" for n in C["notes"])
    legal = "".join(link(h, t) for h, t in C["legal"])
    # Le lingue: href di default alle home, i generatori li puntano alla gemella.
    langs = "".join(
        (f'<strong aria-current="true">{LABEL[l]}</strong>' if l == lang
         else f'<a data-lang-alt="{l}" hreflang="{l}" href="{HOME[l]}">{LABEL[l]}</a>')
        for l in LANGS)
    aria = {"it": "Mappa del sito", "en": "Site map", "es": "Mapa del sitio", "fr": "Plan du site"}[lang]
    return f"""<!-- footer:start -->
  <footer>
    <div class="sf-notes">{notes}</div>
    <div class="sf-grid" role="navigation" aria-label="{aria}">{grid}
    </div>
    <div class="sf-bottom">
      <div class="sf-bottom-l"><span>{html.escape(C['copy'])}</span><div class="sf-legal">{legal}</div></div>
      <div class="sf-lang">{langs}</div>
    </div>
  </footer>
  <!-- footer:end -->"""


CSS = CSS.replace("""  .sf-lang strong { color:var(--text); font-weight:600; }
  .sf-lang span { color:var(--faint); margin:0 6px; }""", """  .sf-lang { display:flex; flex-wrap:wrap; align-items:center; }
  .sf-lang > * + *::before { content:"·"; color:var(--faint); margin:0 8px; }
  .sf-lang strong { color:var(--text); font-weight:600; }""")


def set_lang_hrefs(block, hrefs):
    """Punta i link di lingua (menu e footer) alle pagine gemelle."""
    for l, h in hrefs.items():
        block = re.sub(rf'(data-lang-alt="{l}" hreflang="{l}" href=")[^"]*"', lambda m: m.group(1) + h + '"', block)
    return block


def head_alternates(t, paths):
    """Canonical e hreflang nell'<head>: `paths` lingua → percorso dalla radice."""
    site = "https://kidboxapp.com/"
    t = re.sub(r'\n  <link rel="alternate" hreflang="[^"]+" href="[^"]*">', "", t)
    alts = "".join(f'\n  <link rel="alternate" hreflang="{l}" href="{site}{clean_url(p)}">' for l, p in paths.items())
    alts += f'\n  <link rel="alternate" hreflang="x-default" href="{site}{clean_url(paths["it"])}">'
    t, n = re.subn(r'(\n  <link rel="canonical" href="[^"]*">)', lambda m: m.group(1) + alts, t, count=1)
    assert n == 1, "canonical mancante"
    return t


def put_block(t, start, end, block, fallback_re, what, name):
    if start in t:
        return re.sub(re.escape(start) + r".*?" + re.escape(end), lambda m: block, t, flags=re.S)
    t, n = re.subn(fallback_re, lambda m: block, t, count=1, flags=re.S)
    assert n == 1, f"{what} non trovato in {name}"
    return t


def chrome(name, lang, hrefs, real, static=False):
    """Footer, menu delle lingue, CSS, lang.js e hreflang di una pagina scritta a mano."""
    f = PUBLIC / name
    t = f.read_text(encoding="utf-8")
    home = HOME[lang]
    # footer
    block = footer(lang)
    if static:
        block = block.replace("<footer>", '<footer class="sf-static">', 1)
        block = re.sub(r'href="#([a-z]+)"', lambda m: f'href="{home}#{m.group(1)}"', block)
    block = set_lang_hrefs(block, hrefs)
    t = put_block(t, "<!-- footer:start -->", "<!-- footer:end -->", block, r"<footer>.*?</footer>", "footer", name)
    # menu delle lingue nella barra in alto
    menu = lang_menu(lang, hrefs)
    if "<details class=\"lang-menu\">" in t:
        t = re.sub(r'<details class="lang-menu">.*?</details>', lambda m: menu, t, count=1, flags=re.S)
    elif static:
        t, n = re.subn(r'<div style="display:flex;align-items:center;gap:6px;font-size:0\.82rem;font-weight:600;">\s*<a [^>]*kidbox_lang.*?</div>',
                       lambda m: menu, t, count=1, flags=re.S)
        assert n == 1, f"selettore lingua non trovato in {name}"
    else:
        t, n = re.subn(r'<div class="nav-lang nav-hide">.*?</div>', lambda m: menu, t, count=1, flags=re.S)
        assert n == 1, f"selettore lingua non trovato in {name}"
    # CSS
    css = (STATIC_CSS if static else CSS)
    if "/* footer:css:start */" in t:
        t = re.sub(r"\n  /\* footer:css:start \*/.*?/\* footer:css:end \*/", lambda m: css, t, flags=re.S)
    elif static:
        t, n = OLD_STATIC_CSS.subn(lambda m: css, t, count=1)
        assert n == 1, f"CSS del footer non trovato in {name}"
    else:
        t, n = re.compile(r"\n  footer \{[^\n]*\n(?:  \.foot[^\n]*\n)+").subn(lambda m: css + "\n", t, count=1)
        assert n == 1, f"CSS del footer non trovato in {name}"
    if "/* langmenu:css:start */" in t:
        t = re.sub(r"\n  /\* langmenu:css:start \*/.*?/\* langmenu:css:end \*/", lambda m: LANG_MENU_CSS, t, flags=re.S)
    else:
        t = t.replace("\n  /* footer:css:start */", LANG_MENU_CSS + "\n  /* footer:css:start */", 1)
    # script del menu
    if LANG_JS not in t:
        t, n = re.subn(r'(<script src="/assets/consent\.js" defer(?: data-no-banner)?></script>)',
                       lambda m: m.group(1) + f'\n  <script src="{LANG_JS}" defer></script>', t, count=1)
        assert n == 1, f"consent.js non trovato in {name}"
    # hreflang
    t = re.sub(r'<link rel="canonical" href="[^"]*">', f'<link rel="canonical" href="https://kidboxapp.com/{clean_url(name)}">', t, count=1)
    t = head_alternates(t, real)
    t = re.sub(r'<html lang="[a-z]+">', f'<html lang="{lang}">', t, count=1)
    f.write_text(t, encoding="utf-8")


STATIC_CSS = CSS.replace("  /* footer:css:end */", """  footer.sf-static { --border:var(--c-border); --text:var(--c-text); --muted:var(--c-muted); --faint:var(--c-muted);
    max-width:1100px; margin:40px auto 0; padding:26px 24px 30px; font-family:inherit; }
  footer.sf-static p { margin:0 0 8px; font-weight:400; line-height:1.45; color:inherit; font-size:inherit; }
  footer.sf-static ul { margin:0; color:inherit; font-weight:400; }
  footer.sf-static ul li { padding:0; border:0; position:static; font-size:inherit; margin:0 0 7px; }
  footer.sf-static ul li::before { content:none; }
  /* footer:css:end */""")

OLD_STATIC_CSS = re.compile(
    r"\n[ \t]*(?:/\* ── FOOTER ── \*/\n[ \t]*)?footer \{[^}]*\}\n[ \t]*footer p \{[^}]*\}"
    r"\n[ \t]*footer a \{[^}]*\}\n[ \t]*footer a:hover \{[^}]*\}")


def main():
    homes = {l: HOME[l] if available(l) else HOME["en"] for l in LANGS}
    real_homes = {l: HOME[l] for l in LANGS if available(l)}
    done = 0
    for lang in real_homes:
        chrome(HOME[lang], lang, homes, real_homes)
        done += 1
    for base in STATIC_BASES:
        real = {l: static_file(base, l) for l in LANGS if (PUBLIC / static_file(base, l)).exists()}
        hrefs = {l: real.get(l, homes[l]) for l in LANGS}
        for lang in real:
            chrome(static_file(base, lang), lang, hrefs, real, static=True)
            done += 1
    print(f"footer e menu lingue: {done} pagine scritte a mano aggiornate")


if __name__ == "__main__":
    main()

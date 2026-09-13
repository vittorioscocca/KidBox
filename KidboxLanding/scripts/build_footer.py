#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Genera il footer «mappa del sito» di index.html e index-en.html.

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
from blog_data import CATEGORIES  # noqa: E402
from tools_data import TOOLS  # noqa: E402

YEAR = 2026
FACEBOOK = "https://www.facebook.com/profile.php?id=61574265148948"
INSTAGRAM = "https://www.instagram.com/kidbox_app"
WEBAPP = "https://app.kidboxapp.com"

L = {
    "it": {
        "src": "index.html", "tools": "strumenti", "blog": "blog",
        "notes": [
            "Alcune funzioni — l'assistente AI, il Piano Alimentare e il Piano Fitness, i viaggi con itinerario AI e la lettura dei documenti con l'AI — richiedono il piano Pro o Max. Il piano Free include 5 messaggi di prova con l'assistente.",
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
            "Some features — the AI assistant, the Meal Plan and Fitness Plan, AI trip itineraries and AI document reading — require a Pro or Max plan. The Free plan includes 5 trial messages with the assistant.",
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
    return "<ul>" + "".join(f"<li>{i}</li>" for i in items) + "</ul>"


def store_links(src):
    ios = re.search(r'href="(https://apps\.apple\.com/[^"]+)"', src).group(1)
    android = re.search(r'href="(https://play\.google\.com/[^"]+)"', src).group(1)
    return html.unescape(ios), html.unescape(android)


def footer(lang):
    C = L[lang]
    src = (PUBLIC / C["src"]).read_text(encoding="utf-8")
    ios, android = store_links(src)
    slugs = {t["slug"] for t in TOOLS}
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
        [link(f"{C['blog']}/{slug}", cat[lang][0]) for slug, cat in CATEGORIES.items()]
        + [link(f"{C['blog']}/", C["all_blog"] + " →")])
    info = (f"<h3>{C['kidbox_h']}</h3>" + ul([link(h, t) for h, t in C["kidbox"]])
            + f"<h3>{C['help_h']}</h3>" + ul([link(h, t) for h, t in C["help"]])
            + f"<h3>{C['social_h']}</h3>" + ul([link(FACEBOOK, "Facebook"), link(INSTAGRAM, "Instagram")]))
    # Ordine delle colonne: strumenti (3), blog, KidBox/supporto.
    grid = "".join(f'\n      <div class="sf-col">{c}</div>' for c in cols[:2] + [blog, cols[2], info])

    notes = "".join(f"<p>{html.escape(n)}</p>" for n in C["notes"])
    legal = "".join(link(h, t) for h, t in C["legal"])
    lang_sw = (f'<strong aria-current="true">{C["this_label"]}</strong><span>|</span>'
               f'<a data-lang-other href="{C["other_href"]}">{C["other_label"]}</a>')
    return f"""<!-- footer:start -->
  <footer>
    <div class="sf-notes">{notes}</div>
    <div class="sf-grid" role="navigation" aria-label="{'Mappa del sito' if lang == 'it' else 'Site map'}">{grid}
    </div>
    <div class="sf-bottom">
      <div class="sf-bottom-l"><span>{html.escape(C['copy'])}</span><div class="sf-legal">{legal}</div></div>
      <div class="sf-lang">{C['region']} · {lang_sw}</div>
    </div>
  </footer>
  <!-- footer:end -->"""


def apply(lang):
    f = PUBLIC / L[lang]["src"]
    t = f.read_text(encoding="utf-8")
    block = footer(lang)
    if "<!-- footer:start -->" in t:
        t = re.sub(r"<!-- footer:start -->.*?<!-- footer:end -->", lambda m: block, t, flags=re.S)
    else:
        t, n = re.subn(r"<footer>.*?</footer>", lambda m: block, t, count=1, flags=re.S)
        assert n == 1, f"footer non trovato in {f}"
    if "/* footer:css:start */" in t:
        t = re.sub(r"\n  /\* footer:css:start \*/.*?/\* footer:css:end \*/", lambda m: CSS, t, flags=re.S)
    else:
        old = re.compile(r"\n  footer \{[^\n]*\n(?:  \.foot[^\n]*\n)+")
        t, n = old.subn(lambda m: CSS + "\n", t, count=1)
        assert n == 1, f"CSS del footer non trovato in {f}"
    f.write_text(t, encoding="utf-8")


def main():
    for lang in L:
        apply(lang)
    print("footer: index.html e index-en.html aggiornati")


if __name__ == "__main__":
    main()

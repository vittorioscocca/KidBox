#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Genera il Blog della landing.

    python3 scripts/build_blog.py

Legge `tools/blog_data.py` (e i moduli `tools/blog_*.py` che importa) e produce:
  public/blog/index.html            + public/blog/<categoria>.html
  public/blog/<slug>.html                                        (italiano)
  public/en/blog/index.html         + public/en/blog/<categoria>.html
  public/en/blog/<slug>.html                                     (inglese)

Come per gli Strumenti, stile, nav, pulsanti degli store e footer vengono presi
da `index.html` / `index-en.html` al momento della generazione. Le regole in
più stanno in `BLOG_CSS`. Da rilanciare anche dopo un ritocco a quei blocchi.
"""
import html
import json
import re
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUBLIC = ROOT / "public"
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "scripts"))
from blog_data import ARTICLES, CATEGORIES  # noqa: E402
from build_tools import (SCRIPT, active_langs, alternates, extract, final_block,  # noqa: E402
                         footer_langs, head_links, hero, nav_for, parts_for, rebase_links)
from site_langs import BLOG_DIR, LANG_JS  # noqa: E402
import build_tools  # noqa: E402

SITE = "https://kidboxapp.com"

LANGS = {
    "it": {
        "src": "index.html", "dir": "blog", "other_dir": "en/blog", "tools_dir": "strumenti",
        "home": "Home", "blog": "Blog", "articles": "Articoli",
        "index_title": "Blog KidBox · Organizzazione familiare, casa, figli e genitori separati",
        "index_desc": "Guide pratiche per organizzare la famiglia: faccende, scadenze di casa, calendario tra due case, lista della spesa, documenti dei figli e routine che reggono.",
        "index_h1": "Il blog di KidBox",
        "index_p": "Guide pratiche per una famiglia che gira meglio: dividere le faccende, tenere i documenti dei figli, organizzarsi in due case, pianificare pasti e spesa — e togliersi qualcosa dalla testa.",
        "hero_eyebrow": "Scarica l'app", "hero_h": "Tutta la famiglia, <span class=\"g\">in un'unica app.</span>",
        "hero_p": "L'organizer di famiglia per iPhone, Android e browser, cifrato end-to-end. Gratis per tutta la famiglia, senza limite di membri.",
        "final_kicker": "Inizia oggi", "final_h": "La famiglia merita un'app all'altezza.", "final_p": "Gratuita per iniziare. Nessuna carta richiesta.",
        "all_in": "Tutti gli articoli su {cat} →", "min": "{n} min di lettura", "by": "Il team KidBox", "updated": "Aggiornato il",
        "related": "Da leggere dopo", "tools": "Gli strumenti di cui parla l'articolo", "in_cat": "Altri articoli su {cat}", "back": "Tutti gli articoli",
        "months": ["gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic"],
        "suffix": "Blog KidBox", "soon": "",
    },
    "en": {
        "src": "index-en.html", "dir": "en/blog", "other_dir": "blog", "tools_dir": "en/tools",
        "home": "Home", "blog": "Blog", "articles": "Articles",
        "index_title": "KidBox Blog · Family organisation, home, kids and co-parenting",
        "index_desc": "Practical guides to organising a family: chores, household deadlines, a calendar across two homes, the grocery list, the kids' documents and routines that hold.",
        "index_h1": "The KidBox blog",
        "index_p": "Practical guides for a family that runs smoother: splitting chores, keeping the kids' documents, organising across two homes, planning meals and groceries — and getting things out of your head.",
        "hero_eyebrow": "Get the app", "hero_h": "The whole family, <span class=\"g\">in a single app.</span>",
        "hero_p": "The family organiser for iPhone, Android and the browser, end-to-end encrypted. Free for the whole family, with no member limit.",
        "final_kicker": "Start today", "final_h": "Your family deserves an app that keeps up.", "final_p": "Free to start. No card required.",
        "all_in": "All articles on {cat} →", "min": "{n} min read", "by": "The KidBox team", "updated": "Updated",
        "related": "Read next", "tools": "The tools this article talks about", "in_cat": "More on {cat}", "back": "All articles",
        "months": ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"],
        "suffix": "KidBox Blog", "soon": "",
    },
    "es": {
        "src": "index-es.html", "dir": "es/blog", "tools_dir": "es/tools",
        "home": "Inicio", "blog": "Blog", "articles": "Artículos",
        "index_title": "Blog de KidBox · Organización familiar, hogar, hijos y padres separados",
        "index_desc": "Guías prácticas para organizar la familia: tareas del hogar, vencimientos de casa, calendario entre dos casas, lista de la compra, documentos de los hijos y rutinas que funcionan.",
        "index_h1": "El blog de KidBox",
        "index_p": "Guías prácticas para una familia que funciona mejor: repartir las tareas, guardar los documentos de los hijos, organizarse en dos casas, planificar comidas y compra — y quitarse cosas de la cabeza.",
        "hero_eyebrow": "Descarga la app", "hero_h": "Toda la familia, <span class=\"g\">en una sola app.</span>",
        "hero_p": "El organizador familiar para iPhone, Android y navegador, cifrado de extremo a extremo. Gratis para toda la familia, sin límite de miembros.",
        "final_kicker": "Empieza hoy", "final_h": "Tu familia merece una app a su altura.", "final_p": "Gratis para empezar. Sin tarjeta.",
        "all_in": "Todos los artículos sobre {cat} →", "min": "{n} min de lectura", "by": "El equipo de KidBox", "updated": "Actualizado el",
        "related": "Para seguir leyendo", "tools": "Las herramientas de las que habla el artículo", "in_cat": "Más sobre {cat}", "back": "Todos los artículos",
        "months": ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sept", "oct", "nov", "dic"],
        "suffix": "Blog de KidBox",
        "soon": "Estamos traduciendo los artículos al español. Mientras tanto, puedes leerlos en inglés en <a href=\"../../en/blog/\">el blog de KidBox</a>.",
    },
    "fr": {
        "src": "index-fr.html", "dir": "fr/blog", "tools_dir": "fr/tools",
        "home": "Accueil", "blog": "Blog", "articles": "Articles",
        "index_title": "Blog KidBox · Organisation familiale, maison, enfants et coparentalité",
        "index_desc": "Des guides pratiques pour organiser la famille : tâches ménagères, échéances de la maison, calendrier entre deux foyers, liste de courses, documents des enfants et routines qui tiennent.",
        "index_h1": "Le blog de KidBox",
        "index_p": "Des guides pratiques pour une famille qui tourne mieux : répartir les tâches, garder les documents des enfants, s'organiser entre deux maisons, planifier repas et courses — et se libérer l'esprit.",
        "hero_eyebrow": "Télécharger l'app", "hero_h": "Toute la famille, <span class=\"g\">dans une seule app.</span>",
        "hero_p": "L'organiseur familial pour iPhone, Android et navigateur, chiffré de bout en bout. Gratuit pour toute la famille, sans limite de membres.",
        "final_kicker": "Commencez aujourd'hui", "final_h": "Votre famille mérite une app à la hauteur.", "final_p": "Gratuit pour commencer. Sans carte.",
        "all_in": "Tous les articles sur {cat} →", "min": "{n} min de lecture", "by": "L'équipe KidBox", "updated": "Mis à jour le",
        "related": "À lire ensuite", "tools": "Les outils dont parle l'article", "in_cat": "Plus sur {cat}", "back": "Tous les articles",
        "months": ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."],
        "suffix": "Blog KidBox",
        "soon": "Nous traduisons les articles en français. En attendant, vous pouvez les lire en anglais sur <a href=\"../../en/blog/\">le blog KidBox</a>.",
    },
}

BLOG_CSS = """
  /* ── Blog ───────────────────────────────────────────────────────────── */
  .crumbs { display:flex; flex-wrap:wrap; gap:8px; font-size:0.86rem; color:var(--muted); padding:22px 0 18px; }
  .crumbs a { color:var(--muted); text-decoration:none; }
  .crumbs a:hover { color:var(--accent); }
  .crumbs span.cur { color:var(--text); font-weight:600; }
  .t-hero { display:grid; grid-template-columns:300px 1fr; gap:48px; align-items:center; background:var(--surface); border:1px solid var(--border); border-radius:var(--r-lg); box-shadow:var(--shadow); padding:44px; overflow:hidden; position:relative; }
  .t-hero::before { content:""; position:absolute; inset:auto -120px -160px auto; width:420px; height:420px; border-radius:50%; background:radial-gradient(closest-side, var(--accent-l), transparent); pointer-events:none; }
  .t-hero .device { margin:0 auto; }
  .t-hero-copy { position:relative; }
  .t-hero-copy h2 { font-size:clamp(1.9rem,4vw,2.8rem); font-weight:800; letter-spacing:-0.035em; line-height:1.05; margin-bottom:14px; text-wrap:balance; }
  .t-hero-copy h2 .g { background:linear-gradient(120deg,var(--accent),var(--accent2)); -webkit-background-clip:text; background-clip:text; color:transparent; }
  .t-hero-copy p { color:var(--muted); font-size:1.05rem; max-width:46ch; margin-bottom:24px; }
  .t-hero-copy .hero-cta { justify-content:flex-start; }
  .b-head { padding:64px 0 28px; max-width:760px; }
  .b-head h1 { font-size:clamp(2rem,4.6vw,3.2rem); font-weight:800; letter-spacing:-0.035em; line-height:1.05; text-wrap:balance; margin-bottom:14px; }
  .b-head p { color:var(--muted); font-size:1.08rem; }
  .b-cat { padding:44px 0 8px; }
  .b-cat-title { font-size:0.78rem; font-weight:800; letter-spacing:0.09em; text-transform:uppercase; color:var(--accent2); margin-bottom:6px; }
  .b-cat-desc { color:var(--muted); font-size:0.98rem; max-width:70ch; margin-bottom:20px; }
  .b-grid { display:grid; grid-template-columns:repeat(auto-fill, minmax(280px, 1fr)); gap:16px; }
  .b-card { display:flex; flex-direction:column; gap:10px; padding:22px; background:var(--surface); border:1px solid var(--border); border-radius:var(--r-md); box-shadow:var(--shadow); color:var(--text); text-decoration:none; transition:transform .18s, border-color .18s; }
  .b-card:hover { transform:translateY(-3px); border-color:var(--accent); }
  .b-card h3 { font-size:1.08rem; font-weight:800; letter-spacing:-0.02em; line-height:1.25; }
  .b-card p { color:var(--muted); font-size:0.9rem; line-height:1.55; }
  .b-card .b-meta { margin-top:auto; font-size:0.8rem; color:var(--faint); display:flex; gap:10px; align-items:center; }
  .b-more { margin:18px 0 0; }
  .b-more a { display:inline-flex; align-items:center; gap:8px; font-size:0.9rem; font-weight:700; color:var(--accent2); text-decoration:none; }
  .b-more a:hover { text-decoration:underline; }
  .b-art { max-width:740px; margin:0 auto; }
  .b-art-head { padding:56px 0 24px; }
  .b-art-head h1 { font-size:clamp(1.9rem,4.4vw,3rem); font-weight:800; letter-spacing:-0.035em; line-height:1.08; text-wrap:balance; margin-bottom:16px; }
  .b-art-meta { display:flex; flex-wrap:wrap; gap:10px; color:var(--muted); font-size:0.9rem; align-items:center; }
  .b-art-meta .sep { color:var(--faint); }
  .b-art .t-hero { margin:8px 0 40px; padding:36px; grid-template-columns:220px 1fr; gap:32px; }
  /* Il telefono è disegnato per 300px: restringerlo fa andare a capo le tessere e lo
     allunga; lo si rimpicciolisce intero, proporzioni comprese. */
  .b-art .t-hero .device { width:300px; max-width:none; zoom:.72; }
  .b-art .t-hero-copy h2 { font-size:clamp(1.5rem,3vw,2rem); }
  .b-art .t-hero-copy p { font-size:0.98rem; margin-bottom:18px; }
  .b-body { font-size:1.08rem; line-height:1.72; }
  .b-body p { margin:0 0 20px; }
  .b-body h2 { font-size:clamp(1.45rem,3vw,1.9rem); font-weight:800; letter-spacing:-0.03em; line-height:1.15; margin:44px 0 14px; }
  .b-body h3 { font-size:1.15rem; font-weight:800; letter-spacing:-0.01em; margin:28px 0 10px; }
  .b-body ul, .b-body ol { margin:0 0 20px; padding-left:26px; }
  .b-body li { margin-bottom:8px; }
  .b-body li::marker { color:var(--accent); font-weight:700; }
  .b-body a { color:var(--accent2); text-decoration:underline; text-decoration-color:rgba(232,131,58,.4); text-underline-offset:3px; }
  .b-body a:hover { text-decoration-color:var(--accent2); }
  .b-body blockquote { margin:0 0 22px; padding:16px 20px; border-left:3px solid var(--accent); background:var(--accent-l); border-radius:0 var(--r-sm) var(--r-sm) 0; color:var(--text); }
  .b-body blockquote p { margin:0; }
  .b-body strong { font-weight:700; }
  .b-sec { padding:40px 0 8px; }
  .b-sec h2 { font-size:clamp(1.35rem,3vw,1.8rem); font-weight:800; letter-spacing:-0.03em; margin-bottom:18px; }
  .b-tools { display:flex; flex-wrap:wrap; gap:10px; }
  .b-tools a { display:inline-flex; align-items:center; gap:8px; padding:9px 14px; border-radius:50px; border:1px solid var(--border); background:var(--surface); color:var(--text); text-decoration:none; font-size:0.9rem; font-weight:700; }
  .b-tools a:hover { border-color:var(--accent); }
  @media (max-width:820px) { .t-hero, .b-art .t-hero { grid-template-columns:1fr; padding:32px 22px; text-align:center; } .t-hero-copy .hero-cta { justify-content:center; } .t-hero-copy p { margin-inline:auto; } .b-art-head { padding-top:40px; } }
"""


# ── Markdown minimo → HTML ──────────────────────────────────────────────

def inline(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
    return text


def md_to_html(body):
    out = []
    blocks = re.split(r"\n\s*\n", body.strip())
    for block in blocks:
        lines = block.strip("\n").split("\n")
        first = lines[0]
        if first.startswith("### "):
            out.append(f"<h3>{inline(first[4:])}</h3>")
        elif first.startswith("## "):
            out.append(f"<h2>{inline(first[3:])}</h2>")
        elif all(l.startswith("- ") for l in lines):
            out.append("<ul>" + "".join(f"<li>{inline(l[2:])}</li>" for l in lines) + "</ul>")
        elif all(re.match(r"\d+\. ", l) for l in lines):
            items = [re.sub(r"^\d+\. ", "", l) for l in lines]
            out.append("<ol>" + "".join(f"<li>{inline(i)}</li>" for i in items) + "</ol>")
        elif all(l.startswith("> ") or l == ">" for l in lines):
            out.append("<blockquote><p>" + inline(" ".join(l[2:] for l in lines if l != ">")) + "</p></blockquote>")
        else:
            out.append(f"<p>{inline(' '.join(lines))}</p>")
    return "\n".join(out)


def words(body):
    return len(re.findall(r"\w+", body))


def minutes(body):
    return max(2, round(words(body) / 200))


def fmt_date(iso, L):
    d = date.fromisoformat(iso)
    return f"{d.day} {L['months'][d.month - 1]} {d.year}"


# ── Pagina ──────────────────────────────────────────────────────────────

def page(lang, title, desc, canonical, body, depth, ld=None, og_type="website"):
    L = LANGS[lang]
    # `parts_for`/`nav_for` leggono le loro chiavi da build_tools.LANGS: si
    # passano le nostre, che hanno gli stessi campi (src, other_dir, …).
    saved = build_tools.LANGS
    build_tools.LANGS = {lang: L, **{k: v for k, v in saved.items() if k != lang}}
    try:
        style, stores, footer, phone = parts_for(lang, depth)
        hrefs, real = alternates(lang, depth, BLOG_DIR, canonical, lambda l: blog_has(l, canonical))
        nav = nav_for(lang, depth, L, hrefs)
        footer = footer_langs(footer, hrefs)
    finally:
        build_tools.LANGS = saved
    style = style.replace(build_tools.TOOLS_CSS + "</style>", BLOG_CSS + "</style>")
    prefix = "../" * depth
    ld_tag = f'\n<script type="application/ld+json">{json.dumps(ld, ensure_ascii=False)}</script>' if ld else ""
    return f"""<!DOCTYPE html>
<html lang="{lang}">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{html.escape(title)}</title>
  <meta name="description" content="{html.escape(desc)}">
  <meta property="og:title" content="{html.escape(title)}">
  <meta property="og:description" content="{html.escape(desc)}">
  <meta property="og:type" content="{og_type}">
  <meta property="og:image" content="{SITE}/icon.png">
{head_links(lang, real) if lang in real else '  <meta name="robots" content="noindex">'}
  <link rel="icon" href="/favicon.ico" sizes="any">
  <link rel="icon" type="image/png" href="{prefix}icon.png?v=2">
  <link rel="apple-touch-icon" href="/apple-touch-icon.png">
  <script src="/assets/consent.js" defer></script>
  <script src="/assets/chat.js" defer></script>
  <script src="{LANG_JS}" defer></script>
{style}
</head>
<body>
{nav}
<div class="wrap">
{body.replace('%HERO%', hero(L, stores, phone))}
</div>
{final_block(L, stores, footer)}
{SCRIPT}{ld_tag}
</body>
</html>
"""


def card(a, lang):
    A = a[lang]
    L = LANGS[lang]
    return f"""
  <a class="b-card rv" href="{a['slug']}">
    <h3>{html.escape(A['title'])}</h3>
    <p>{html.escape(A['desc'])}</p>
    <span class="b-meta"><span>{L['min'].format(n=minutes(A['body']))}</span><span>·</span><span>{fmt_date(a['date'], L)}</span></span>
  </a>"""


def blog_has(lang, canonical):
    """La pagina `canonical` del blog esiste in `lang`? ('' = indice)."""
    if lang not in LANGS:
        return False
    if canonical == "":
        # Un indice ancora vuoto (lingua in traduzione) non è una gemella da indicizzare.
        return lang in ("it", "en") or any(lang in a for a in ARTICLES)
    if canonical in CATEGORIES:
        return lang in CATEGORIES[canonical] and any(a["category"] == canonical and lang in a for a in ARTICLES)
    return any(a["slug"] == canonical and lang in a for a in ARTICLES)


def by_category(lang="it"):
    groups = {slug: [] for slug in CATEGORIES}
    for a in ARTICLES:
        if lang in a:
            groups[a["category"]].append(a)
    for slug in groups:
        groups[slug].sort(key=lambda a: a["date"], reverse=True)
    return groups


def build_index(lang):
    L = LANGS[lang]
    depth = L["dir"].count("/") + 1
    prefix = "../" * depth
    groups = by_category(lang)
    sections = ""
    for cslug, C in CATEGORIES.items():
        arts = groups[cslug]
        if not arts or lang not in C:
            continue
        short, long_title, desc = C[lang]
        cards = "".join(card(a, lang) for a in arts[:4])
        sections += f"""
<section class="b-cat">
  <div class="b-cat-title">{html.escape(long_title)}</div>
  <p class="b-cat-desc">{html.escape(desc)}</p>
  <div class="b-grid">{cards}
  </div>
  <p class="b-more"><a href="{cslug}">{html.escape(L['all_in'].format(cat=short))}</a></p>
</section>"""
    body = f"""
<div class="crumbs"><a href="{prefix}{L['src']}">{L['home']}</a><span>/</span><span class="cur">{L['blog']}</span></div>
<div class="b-head rv">
  <h1>{L['index_h1']}</h1>
  <p>{L['index_p']}</p>
</div>
%HERO%
{sections or f'<section class="b-cat"><p class="b-cat-desc">{L["soon"]}</p></section>'}"""
    out = PUBLIC / L["dir"] / "index.html"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(page(lang, L["index_title"], L["index_desc"], "", body, depth), encoding="utf-8")


def build_category(lang, cslug, arts):
    L = LANGS[lang]
    C = CATEGORIES[cslug][lang]
    short, long_title, desc = C
    depth = L["dir"].count("/") + 1
    prefix = "../" * depth
    cards = "".join(card(a, lang) for a in arts)
    body = f"""
<div class="crumbs"><a href="{prefix}{L['src']}">{L['home']}</a><span>/</span><a href="./">{L['blog']}</a><span>/</span><span class="cur">{html.escape(short)}</span></div>
<div class="b-head rv">
  <h1>{html.escape(long_title)}</h1>
  <p>{html.escape(desc)}</p>
</div>
<div class="b-grid">{cards}
</div>
<div style="height:24px"></div>
%HERO%"""
    title = f"{long_title} · {L['suffix']}"
    out = PUBLIC / L["dir"] / f"{cslug}.html"
    out.write_text(page(lang, title, desc, cslug, body, depth), encoding="utf-8")


def build_article(lang, a):
    L = LANGS[lang]
    A = a[lang]
    depth = L["dir"].count("/") + 1
    prefix = "../" * depth
    by_slug = {x["slug"]: x for x in ARTICLES}
    short, long_title, _ = CATEGORIES[a["category"]][lang]

    body_html = md_to_html(A["body"])
    # I link assoluti del sito ("/strumenti/x", "/blog/y") diventano relativi,
    # così le pagine funzionano anche aperte da file e sotto un prefisso.
    body_html = re.sub(r'href="/([^"]*)"', lambda m: f'href="{prefix}{m.group(1)}"', body_html)

    related = "".join(card(by_slug[s], lang) for s in a["related"] if s in by_slug and lang in by_slug[s])
    tool_links = ""
    if a["tools"]:
        from tools_data import TOOLS
        tmap = {t["slug"]: t for t in TOOLS}
        chips = "".join(
            f'<a href="{prefix}{L["tools_dir"]}/{s}">{tmap[s]["icon"]} {html.escape(tmap[s][lang]["title"])}</a>'
            for s in a["tools"] if s in tmap and lang in tmap[s]
        )
        tool_links = f'<section class="b-sec"><h2>{L["tools"]}</h2><div class="b-tools">{chips}</div></section>'

    ld = {
        "@context": "https://schema.org", "@type": "Article",
        "headline": A["title"], "description": A["desc"],
        "datePublished": a["date"], "dateModified": a["date"],
        "inLanguage": lang,
        "author": {"@type": "Organization", "name": "KidBox"},
        "publisher": {"@type": "Organization", "name": "KidBox", "logo": {"@type": "ImageObject", "url": f"{SITE}/icon.png"}},
        "mainEntityOfPage": f"{SITE}/{L['dir']}/{a['slug']}",
    }
    body = f"""
<div class="crumbs"><a href="{prefix}{L['src']}">{L['home']}</a><span>/</span><a href="./">{L['blog']}</a><span>/</span><a href="{a['category']}">{html.escape(short)}</a><span>/</span><span class="cur">{html.escape(A['title'])}</span></div>
<article class="b-art">
  <header class="b-art-head rv">
    <h1>{html.escape(A['title'])}</h1>
    <div class="b-art-meta"><span>{L['by']}</span><span class="sep">·</span><span>{L['updated']} {fmt_date(a['date'], L)}</span><span class="sep">·</span><span>{L['min'].format(n=minutes(A['body']))}</span></div>
  </header>
  %HERO%
  <div class="b-body">
{body_html}
  </div>
  {tool_links}
  <section class="b-sec">
    <h2>{L['related']}</h2>
    <div class="b-grid">{related}
    </div>
    <p class="b-more"><a href="{a['category']}">{html.escape(L['in_cat'].format(cat=short))} →</a> &nbsp; <a href="./">{L['back']} →</a></p>
  </section>
</article>"""
    title = f"{A['title']} · {L['suffix']}"
    out = PUBLIC / L["dir"] / f"{a['slug']}.html"
    out.write_text(page(lang, title, A["desc"], a["slug"], body, depth, ld=ld, og_type="article"), encoding="utf-8")


def check():
    slugs = [a["slug"] for a in ARTICLES]
    dup = {s for s in slugs if slugs.count(s) > 1}
    if dup:
        raise SystemExit(f"slug duplicati: {dup}")
    for a in ARTICLES:
        for r in a["related"]:
            if r not in slugs:
                raise SystemExit(f"{a['slug']}: related sconosciuto {r}")
        if a["category"] not in CATEGORIES:
            raise SystemExit(f"{a['slug']}: categoria sconosciuta {a['category']}")
        for lang in LANGS:
            if lang not in a:
                continue
            for m in re.finditer(r"\]\(/(?:(en|es|fr)/)?blog/([^)]+)\)", a[lang]["body"]):
                target = next((x for x in ARTICLES if x["slug"] == m.group(2)), None)
                if target is None:
                    raise SystemExit(f"{a['slug']} [{lang}]: link a un articolo inesistente {m.group(2)}")
                if (m.group(1) or "it") != lang or lang not in target:
                    raise SystemExit(f"{a['slug']} [{lang}]: link a {m.group(0)} non tradotto o in un'altra lingua")


def main():
    import build_footer
    build_footer.main()
    check()
    langs = [l for l in active_langs() if l in LANGS]
    for lang in langs:
        groups = by_category(lang)
        (PUBLIC / LANGS[lang]["dir"]).mkdir(parents=True, exist_ok=True)
        for a in ARTICLES:
            if lang in a:
                build_article(lang, a)
        for cslug, arts in groups.items():
            if arts and lang in CATEGORIES[cslug]:
                build_category(lang, cslug, arts)
        build_index(lang)
    n = len(ARTICLES)
    import build_sitemap
    build_sitemap.main()
    print(f"{n} articoli; per lingua: " + ", ".join(f"{l} {sum(1 for a in ARTICLES if l in a)}" for l in langs) + " "
          f"({sum(words(a['it']['body']) for a in ARTICLES)} parole IT)")


if __name__ == "__main__":
    main()

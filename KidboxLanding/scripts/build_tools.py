#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Genera la sezione «Strumenti» della landing.

    python3 scripts/build_tools.py

Legge `tools/tools_data.py` e produce:
  public/strumenti/index.html   + public/strumenti/<slug>.html   (italiano)
  public/en/tools/index.html    + public/en/tools/<slug>.html    (inglese)
  public/tools-img/<slug>-N.webp  (screenshot ridotti, dai PNG del simulatore)

Lo stile è quello della landing: il blocco <style>, la barra di navigazione,
i pulsanti degli store e il footer vengono presi da `index.html` /
`index-en.html` al momento della generazione, così le pagine non divergono
mai dal resto del sito. Le regole in più stanno in `TOOLS_CSS` qui sotto.
"""
import html
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUBLIC = ROOT / "public"
sys.path.insert(0, str(ROOT / "tools"))
from tools_data import TOOLS  # noqa: E402

LANGS = {
    "it": {
        "src": "index.html", "dir": "strumenti", "other_dir": "en/tools", "other_label": "EN", "this_label": "IT",
        "home": "Home", "tools": "Strumenti",
        "index_title": "Strumenti KidBox · Tutto quello che l'app fa per la famiglia",
        "index_desc": "Calendario, liste, spese, documenti, salute, chat, posizione, viaggi e AI: ogni strumento di KidBox spiegato, con schermate e domande frequenti.",
        "index_h1": "Gli strumenti di KidBox",
        "index_p": "Tutto quello che l'app fa per una famiglia, scheda per scheda: cosa risolve, come funziona e le domande che ci fanno più spesso. Gratis per una famiglia di due genitori.",
        "hero_eyebrow": "Scarica l'app", "hero_h": "Tutta la famiglia, <span class=\"g\">in un'unica app.</span>",
        "hero_p": "L'organizer di famiglia per iPhone, Android e browser, cifrato end-to-end. Gratis per iniziare, nessuna carta richiesta.",
        "how": "Come funziona", "faq": "Domande frequenti", "related": "Strumenti collegati", "all_tools": "Tutti gli strumenti",
        "free": "Incluso nel Free", "pro": "Piano Pro", "open": "Apri nella web app", "shots": "Nell'app",
        "final_kicker": "Inizia oggi", "final_h": "La famiglia merita un'app all'altezza.", "final_p": "Gratuita per iniziare. Nessuna carta richiesta.",
        "guide": "guide.html",
    },
    "en": {
        "src": "index-en.html", "dir": "en/tools", "other_dir": "strumenti", "other_label": "IT", "this_label": "EN",
        "home": "Home", "tools": "Tools",
        "index_title": "KidBox Tools · Everything the app does for your family",
        "index_desc": "Calendar, lists, expenses, documents, health, chat, location, trips and AI: every KidBox tool explained, with screenshots and FAQs.",
        "index_h1": "The KidBox tools",
        "index_p": "Everything the app does for a family, section by section: what it solves, how it works and the questions we get asked most. Free for a family of two parents.",
        "hero_eyebrow": "Get the app", "hero_h": "The whole family, <span class=\"g\">in a single app.</span>",
        "hero_p": "The family organiser for iPhone, Android and the browser, end-to-end encrypted. Free to start, no card required.",
        "how": "How it works", "faq": "Frequently asked questions", "related": "Related tools", "all_tools": "All tools",
        "free": "Included in Free", "pro": "Pro plan", "open": "Open in the web app", "shots": "In the app",
        "final_kicker": "Start today", "final_h": "Your family deserves an app that keeps up.", "final_p": "Free to start. No card required.",
        "guide": "guide-en.html",
    },
}

TOOLS_CSS = """
  /* ── Strumenti ─────────────────────────────────────────────────────── */
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
  .t-head { padding:64px 0 28px; max-width:720px; }
  .t-head h1 { font-size:clamp(2rem,4.6vw,3.2rem); font-weight:800; letter-spacing:-0.035em; line-height:1.05; text-wrap:balance; margin-bottom:14px; }
  .t-head p { color:var(--muted); font-size:1.08rem; }
  .t-grid { display:grid; grid-template-columns:repeat(auto-fill, minmax(300px, 1fr)); gap:18px; padding-bottom:24px; }
  .t-card { display:flex; flex-direction:column; gap:14px; padding:24px; background:var(--surface); border:1px solid var(--border); border-radius:var(--r-md); box-shadow:var(--shadow); color:var(--text); text-decoration:none; transition:transform .18s, border-color .18s; }
  .t-card:hover { transform:translateY(-3px); border-color:var(--accent); }
  .t-card h3 { font-size:1.12rem; font-weight:800; letter-spacing:-0.02em; line-height:1.2; }
  .t-card p { color:var(--muted); font-size:0.92rem; line-height:1.55; }
  .t-card .t-card-foot { margin-top:auto; display:flex; align-items:center; justify-content:space-between; gap:10px; }
  .t-ico { width:48px; height:48px; border-radius:14px; display:grid; place-items:center; font-size:1.5rem; background:var(--accent-l); }
  .t-ico.green { background:rgba(46,158,107,.13); } .t-ico.blue { background:rgba(43,124,184,.13); } .t-ico.violet { background:rgba(124,92,191,.13); } .t-ico.amber { background:rgba(212,134,10,.14); }
  .t-badge { display:inline-flex; align-items:center; gap:6px; font-size:0.72rem; font-weight:700; letter-spacing:0.06em; text-transform:uppercase; padding:5px 11px; border-radius:50px; border:1px solid var(--border); color:var(--muted); }
  .t-badge.pro { color:var(--accent2); background:var(--accent-l); border-color:rgba(232,131,58,.22); }
  .t-arrow { color:var(--faint); font-size:1.3rem; line-height:1; }
  .t-title { display:flex; align-items:flex-start; gap:18px; padding:64px 0 10px; }
  .t-title .t-ico { width:64px; height:64px; border-radius:18px; font-size:2rem; flex:none; }
  .t-title h1 { font-size:clamp(2rem,4.6vw,3.2rem); font-weight:800; letter-spacing:-0.035em; line-height:1.05; text-wrap:balance; }
  .t-lead { color:var(--muted); font-size:1.12rem; max-width:64ch; margin:8px 0 18px; }
  .t-meta { display:flex; gap:10px; flex-wrap:wrap; align-items:center; margin-bottom:40px; }
  .t-open { display:inline-flex; align-items:center; gap:8px; font-size:0.86rem; font-weight:700; color:var(--accent2); text-decoration:none; }
  .t-open:hover { text-decoration:underline; }
  .t-shots { display:grid; grid-template-columns:repeat(auto-fit, minmax(220px, 1fr)); gap:26px; justify-items:center; padding:10px 0 50px; }
  .t-shots .device { max-width:260px; aspect-ratio:auto; }
  .t-shots .screen img { display:block; width:100%; height:auto; }
  .t-sec { padding:36px 0; }
  .t-sec h2 { font-size:clamp(1.5rem,3vw,2.1rem); font-weight:800; letter-spacing:-0.03em; margin-bottom:22px; }
  .t-steps { display:grid; grid-template-columns:repeat(auto-fit, minmax(240px, 1fr)); gap:16px; }
  .t-step { background:var(--surface); border:1px solid var(--border); border-radius:var(--r-md); padding:22px; box-shadow:var(--shadow); }
  .t-step .n { width:32px; height:32px; border-radius:50%; background:var(--accent); color:#fff; font-weight:800; display:grid; place-items:center; margin-bottom:14px; font-size:0.9rem; }
  .t-step h3 { font-size:1.02rem; font-weight:800; margin-bottom:6px; letter-spacing:-0.01em; }
  .t-step p { color:var(--muted); font-size:0.93rem; line-height:1.55; }
  .t-faq details { background:var(--surface); border:1px solid var(--border); border-radius:var(--r-sm); margin-bottom:10px; overflow:hidden; }
  .t-faq summary { cursor:pointer; list-style:none; display:flex; justify-content:space-between; align-items:center; gap:16px; padding:16px 20px; font-weight:700; }
  .t-faq summary::-webkit-details-marker { display:none; }
  .t-faq summary::after { content:"⌄"; color:var(--muted); font-size:1.2rem; transition:transform .2s; }
  .t-faq details[open] summary::after { transform:rotate(180deg); }
  .t-faq details p { padding:0 20px 18px; color:var(--muted); line-height:1.6; }
  @media (max-width:820px) { .t-hero { grid-template-columns:1fr; padding:32px 22px; text-align:center; } .t-hero-copy .hero-cta { justify-content:center; } .t-hero-copy p { margin-inline:auto; } .t-title { flex-direction:column; gap:12px; } }
"""


def extract(src, pattern):
    m = re.search(pattern, src, re.S)
    if not m:
        raise SystemExit(f"blocco non trovato: {pattern[:30]}")
    return m.group(0)


def rebase_links(block, depth, home="index.html"):
    """I link relativi della landing vanno riportati alla radice del sito.
    Le ancore (#prezzi…) puntano alla home della lingua della pagina."""
    prefix = "../" * depth
    block = re.sub(r'href="#([a-z]+)"', lambda m: f'href="{prefix}{home}#{m.group(1)}"', block)
    block = re.sub(r'href="(?!https?://|mailto:|#|\.\./|/)([^"]+)"', lambda m: f'href="{prefix}{m.group(1)}"', block)
    block = re.sub(r'src="(?!https?://|/|\.\./)([^"]+)"', lambda m: f'src="{prefix}{m.group(1)}"', block)
    return block


def nav_for(lang, depth, L, other_href):
    src = (PUBLIC / L["src"]).read_text(encoding="utf-8")
    nav = extract(src, r"<nav>.*?</nav>")
    nav = rebase_links(nav, depth, L["src"])
    # Il selettore di lingua deve portare alla pagina gemella, non alla home.
    nav = re.sub(r'<div class="nav-lang nav-hide">.*?</div>',
                 f'<div class="nav-lang nav-hide">'
                 f'<a href="{other_href if lang == "en" else "#"}" style="color:var(--{"muted" if lang == "en" else "accent"})" onclick="localStorage.setItem(\'kidbox_lang\',\'it\')">IT</a>'
                 f'<span style="color:var(--muted)">|</span>'
                 f'<a href="{other_href if lang == "it" else "#"}" style="color:var(--{"muted" if lang == "it" else "accent"})" onclick="localStorage.setItem(\'kidbox_lang\',\'en\')">EN</a>'
                 f'</div>', nav, flags=re.S)
    return nav


def parts_for(lang, depth):
    L = LANGS[lang]
    src = (PUBLIC / L["src"]).read_text(encoding="utf-8")
    style = extract(src, r"<style>.*?</style>")
    style = style.replace("</style>", TOOLS_CSS + "</style>")
    stores = extract(src, r'<div class="hero-cta">.*?</div>\n')
    footer = rebase_links(extract(src, r"<footer>.*?</footer>"), depth, L["src"])
    phone = extract(src, r'<div class="device sm">.*?\n    </div></div>')
    return style, stores, footer, phone


def hero(L, stores, phone):
    return f"""
<div class="t-hero rv">
  {phone}
  <div class="t-hero-copy">
    <div class="eyebrow"><span class="dot"></span>{L['hero_eyebrow']}</div>
    <h2>{L['hero_h']}</h2>
    <p>{L['hero_p']}</p>
    {stores}
  </div>
</div>"""


def final_block(L, stores, footer):
    return f"""
<section id="scarica" class="wrap">
  <div class="final rv">
    <div class="kicker">{L['final_kicker']}</div>
    <h2>{L['final_h']}</h2>
    <p>{L['final_p']}</p>
    {stores.replace('class="hero-cta"', 'class="hero-cta" style="justify-content:center"')}
  </div>
  {footer}
</section>"""


SCRIPT = """
<script>
  (function(){
    var tg=document.getElementById('tg');
    tg&&tg.addEventListener('click',function(){
      var r=document.documentElement, c=r.getAttribute('data-theme');
      var dark=c?c==='dark':matchMedia('(prefers-color-scheme: dark)').matches;
      r.setAttribute('data-theme',dark?'light':'dark');
    });
    var io=new IntersectionObserver(function(es){es.forEach(function(e){if(e.isIntersecting){e.target.classList.add('in');io.unobserve(e.target);}})},{threshold:0.12});
    document.querySelectorAll('.rv').forEach(function(el){io.observe(el);});
  })();
</script>"""


def page(lang, title, desc, canonical, body, depth):
    L = LANGS[lang]
    style, stores, footer, phone = parts_for(lang, depth)
    prefix = "../" * depth
    other = ("../" * depth) + LANGS[lang]["other_dir"] + "/" + canonical
    nav = nav_for(lang, depth, L, other)
    footer = re.sub(r'data-lang-other href="[^"]*"', f'data-lang-other href="{other}"', footer)
    return f"""<!DOCTYPE html>
<html lang="{lang}">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{html.escape(title)}</title>
  <meta name="description" content="{html.escape(desc)}">
  <meta property="og:title" content="{html.escape(title)}">
  <meta property="og:description" content="{html.escape(desc)}">
  <meta property="og:type" content="website">
  <meta property="og:image" content="{prefix}icon.png">
  <link rel="canonical" href="https://kidboxapp.com/{L['dir']}/{canonical}">
  <link rel="alternate" hreflang="it" href="https://kidboxapp.com/{LANGS['it']['dir']}/{canonical}">
  <link rel="alternate" hreflang="en" href="https://kidboxapp.com/{LANGS['en']['dir']}/{canonical}">
  <link rel="alternate" hreflang="x-default" href="https://kidboxapp.com/{LANGS['it']['dir']}/{canonical}">
  <link rel="icon" href="/favicon.ico" sizes="any">
  <link rel="icon" type="image/png" href="{prefix}icon.png?v=2">
  <link rel="apple-touch-icon" href="/apple-touch-icon.png">
  <script src="/assets/consent.js" defer></script>
{style}
</head>
<body>
{nav}
<div class="wrap">
{body.replace('%HERO%', hero(L, stores, phone))}
</div>
{final_block(L, stores, footer)}
{SCRIPT}
</body>
</html>
"""


def card(tool, lang, depth_prefix=""):
    T = tool[lang]
    L = LANGS[lang]
    badge = f'<span class="t-badge pro">{L["pro"]}</span>' if tool["plan"] == "pro" else f'<span class="t-badge">{L["free"]}</span>'
    return f"""
  <a class="t-card rv" href="{depth_prefix}{tool['slug']}">
    <span class="t-ico {tool['tint']}">{tool['icon']}</span>
    <h3>{html.escape(T['title'])}</h3>
    <p>{html.escape(T['short'])}</p>
    <span class="t-card-foot">{badge}<span class="t-arrow">›</span></span>
  </a>"""


def build_images(tool):
    """Fino a tre screenshot per strumento, ridotti a 600px e in WebP."""
    if not tool["shots"]:
        return []
    from PIL import Image
    src_dir = PUBLIC / "screenshots" / tool["shots"]
    out_dir = PUBLIC / "tools-img"
    out_dir.mkdir(exist_ok=True)
    files = sorted(p for p in src_dir.iterdir() if p.suffix.lower() == ".png")[:3]
    out = []
    for i, f in enumerate(files, 1):
        dest = out_dir / f"{tool['slug']}-{i}.webp"
        if not dest.exists() or dest.stat().st_mtime < f.stat().st_mtime:
            im = Image.open(f).convert("RGB")
            w = 600
            im = im.resize((w, round(im.height * w / im.width)), Image.LANCZOS)
            im.save(dest, "WEBP", quality=82)
        out.append(dest.name)
    return out


def build_index(lang):
    L = LANGS[lang]
    depth = L["dir"].count("/") + 1
    prefix = "../" * depth
    cards = "".join(card(t, lang) for t in TOOLS)
    body = f"""
<div class="crumbs"><a href="{prefix}index.html">{L['home']}</a><span>/</span><span class="cur">{L['tools']}</span></div>
%HERO%
<div class="t-head rv">
  <h1>{L['index_h1']}</h1>
  <p>{L['index_p']}</p>
</div>
<div class="t-grid">{cards}
</div>"""
    out = PUBLIC / L["dir"] / "index.html"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(page(lang, L["index_title"], L["index_desc"], "", body, depth), encoding="utf-8")


def build_tool(lang, tool, images):
    L = LANGS[lang]
    T = tool[lang]
    depth = L["dir"].count("/") + 1
    prefix = "../" * depth
    by_slug = {t["slug"]: t for t in TOOLS}
    badge = f'<span class="t-badge pro">{L["pro"]}</span>' if tool["plan"] == "pro" else f'<span class="t-badge">{L["free"]}</span>'
    shots = ""
    if images:
        frames = "".join(
            f'<div class="device"><div class="screen"><img src="{prefix}tools-img/{img}" alt="{html.escape(T["title"])}" loading="lazy"></div></div>'
            for img in images
        )
        shots = f'<div class="t-shots rv">{frames}</div>'
    steps = "".join(
        f'<div class="t-step rv"><div class="n">{i}</div><h3>{html.escape(h)}</h3><p>{html.escape(p)}</p></div>'
        for i, (h, p) in enumerate(T["steps"], 1)
    )
    faq = "".join(
        f'<details><summary>{html.escape(q)}</summary><p>{html.escape(a)}</p></details>' for q, a in T["faq"]
    )
    related = "".join(card(by_slug[s], lang) for s in tool["related"] if s in by_slug)
    faq_ld = {
        "@context": "https://schema.org", "@type": "FAQPage",
        "mainEntity": [{"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in T["faq"]],
    }
    import json
    body = f"""
<div class="crumbs"><a href="{prefix}index.html">{L['home']}</a><span>/</span><a href="./">{L['tools']}</a><span>/</span><span class="cur">{html.escape(T['title'])}</span></div>
%HERO%
<div class="t-title rv">
  <span class="t-ico {tool['tint']}">{tool['icon']}</span>
  <div>
    <h1>{html.escape(T['title'])}</h1>
    <p class="t-lead">{html.escape(T['lead'])}</p>
    <div class="t-meta">{badge}<a class="t-open" href="https://app.kidboxapp.com" target="_blank" rel="noopener">{L['open']} ↗</a></div>
  </div>
</div>
{shots}
<section class="t-sec">
  <h2>{L['how']}</h2>
  <div class="t-steps">{steps}</div>
</section>
<section class="t-sec t-faq">
  <h2>{L['faq']}</h2>
  {faq}
</section>
<section class="t-sec">
  <h2>{L['related']}</h2>
  <div class="t-grid">{related}
  </div>
  <p style="margin-top:18px"><a class="t-open" href="./">{L['all_tools']} →</a></p>
</section>
<script type="application/ld+json">{json.dumps(faq_ld, ensure_ascii=False)}</script>"""
    title = f"{T['title']} · KidBox"
    out = PUBLIC / L["dir"] / f"{tool['slug']}.html"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(page(lang, title, T["short"], tool["slug"], body, depth), encoding="utf-8")


def main():
    sys.path.insert(0, str(ROOT / "scripts"))
    import build_footer
    build_footer.main()
    for tool in TOOLS:
        images = build_images(tool)
        for lang in LANGS:
            build_tool(lang, tool, images)
    for lang in LANGS:
        build_index(lang)
    sys.path.insert(0, str(ROOT / "scripts"))
    import build_sitemap
    build_sitemap.main()
    print(f"{len(TOOLS)} strumenti × {len(LANGS)} lingue generati in public/")


if __name__ == "__main__":
    main()

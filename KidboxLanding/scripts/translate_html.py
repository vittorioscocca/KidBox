#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Genera le pagine scritte a mano in spagnolo e francese a partire dall'inglese.

    python3 scripts/translate_html.py extract index-en.html   # testi da tradurre
    python3 scripts/translate_html.py build                   # scrive tutte le pagine ES/FR

Le traduzioni stanno in `tools/i18n/<pagina>.json` come liste allineate:
    {"en": [...], "es": [...], "fr": [...]}
(`en` è l'output di `extract`). Ogni traduzione deve avere esattamente gli stessi
tag dell'inglese, nello stesso ordine: la build lo verifica.
Un «testo» è un blocco: una sequenza di testo e tag inline (a, strong, em, span,
br…) tra due tag di blocco, preso con i suoi tag. Si traducono anche alt, title,
aria-label, placeholder e il content delle meta description/og.

La build fallisce se manca una traduzione: quando l'inglese cambia, `extract`
mostra i testi nuovi. I link verso le pagine inglesi diventano quelli della
lingua (guide-en.html → guide-es.html, en/tools/ → es/tools/, …); poi
build_footer.py sistema footer, menu delle lingue e hreflang.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUBLIC = ROOT / "public"
I18N = ROOT / "tools" / "i18n"

PAGES = ["index-en.html", "guide-en.html", "support-en.html", "privacy-en.html", "terms-en.html", "data-deletion-en.html"]
TARGETS = ["es", "fr"]

INLINE = {"a", "strong", "em", "b", "i", "span", "br", "code", "small", "sup", "sub", "mark", "u", "abbr"}
SKIP = {"style", "script", "svg", "noscript"}
TOKEN = re.compile(r"<!--.*?-->|<![^>]*>|<(/?)([a-zA-Z0-9]+)([^>]*)>|[^<]+", re.S)
ATTRS = re.compile(r'(?<=\s)(alt|title|aria-label|placeholder)="([^"]*)"')
META = re.compile(r'(<meta\s+(?:name="description"|property="og:(?:title|description)")\s+content=")([^"]*)(")')


def segments(src):
    """(inizio, fine, testo) dei blocchi di testo, in ordine."""
    out, run_start, run_end, skip = [], None, None, 0

    def flush():
        nonlocal run_start, run_end
        if run_start is not None:
            raw = src[run_start:run_end]
            if re.search(r"[A-Za-z]{2}", re.sub(r"<[^>]+>", "", raw)):
                lead = len(raw) - len(raw.lstrip())
                trail = len(raw) - len(raw.rstrip())
                out.append((run_start + lead, run_end - trail, raw.strip()))
        run_start = run_end = None

    for m in TOKEN.finditer(src):
        tok = m.group(0)
        if tok.startswith("<!"):
            flush()
            continue
        if m.group(2):
            name = m.group(2).lower()
            closing = m.group(1) == "/"
            if name in SKIP:
                flush()
                skip += -1 if closing else (0 if tok.endswith("/>") else 1)
                continue
            if skip:
                continue
            if name in INLINE and name != "title":
                if run_start is None:
                    run_start = m.start()
                run_end = m.end()
            else:
                flush()
            continue
        if skip:
            continue
        if run_start is None:
            if not tok.strip():
                continue
            run_start = m.start()
        run_end = m.end()
    flush()
    # le <title> sono blocchi a sé
    return out


def attr_texts(src):
    items = [(m.start(2), m.end(2), m.group(2)) for m in ATTRS.finditer(src) if re.search(r"[A-Za-z]{2}", m.group(2))]
    items += [(m.start(2), m.end(2), m.group(2)) for m in META.finditer(src)]
    return items


# Footer e menu delle lingue li riscrive build_footer.py: non si traducono qui.
EXCLUDE = [re.compile(r"<!-- footer:start -->.*?<!-- footer:end -->", re.S),
           re.compile(r'<details class="lang-menu">.*?</details>', re.S)]


def items_of(src):
    spans = [(m.start(), m.end()) for rx in EXCLUDE for m in rx.finditer(src)]
    inside = lambda a, b: any(s <= a and b <= e for s, e in spans)
    return sorted((x for x in segments(src) + attr_texts(src) if not inside(x[0], x[1])), key=lambda x: x[0])


def texts(src):
    seen, res = set(), []
    for _, _, t in items_of(src):
        if t not in seen:
            seen.add(t)
            res.append(t)
    return res


LINK_MAP = [
    (r"index-en\.html", "index-{l}.html"), (r"guide-en\.html", "guide-{l}.html"),
    (r"support-en\.html", "support-{l}.html"), (r"privacy-en\.html", "privacy-{l}.html"),
    (r"terms-en\.html", "terms-{l}.html"), (r"data-deletion-en\.html", "data-deletion-{l}.html"),
    (r"/privacy-en\b", "/privacy-{l}"), (r"(?<![a-z])en/tools/", "{l}/tools/"), (r"(?<![a-z])en/blog/", "{l}/blog/"),
]


def build_page(name, lang):
    src = (PUBLIC / name).read_text(encoding="utf-8")
    dic_file = I18N / (name.replace("-en.html", "") + ".json")
    data = json.loads(dic_file.read_text(encoding="utf-8")) if dic_file.exists() else {"en": []}
    if len(data.get(lang, [])) != len(data["en"]):
        raise SystemExit(f"{dic_file.name} [{lang}]: {len(data.get(lang, []))} traduzioni per {len(data['en'])} testi")
    tags = lambda x: re.findall(r"<[^>]+>", x)
    for en, tr in zip(data["en"], data[lang]):
        if tags(en) != tags(tr):
            raise SystemExit(f"{dic_file.name} [{lang}]: tag diversi in {en[:70]!r}\n→ {tr[:70]!r}")
    dic = {en: {lang: tr} for en, tr in zip(data["en"], data[lang])}
    items = items_of(src)
    missing = [t for _, _, t in items if lang not in dic.get(t, {})]
    if missing:
        raise SystemExit(f"{name} [{lang}]: {len(missing)} testi senza traduzione, es. {missing[0][:80]!r}")
    out, pos = [], 0
    for start, end, t in items:
        if start < pos:
            continue
        out.append(src[pos:start])
        out.append(dic[t][lang])
        pos = end
    out.append(src[pos:])
    page = "".join(out)
    for pat, rep in LINK_MAP:
        page = re.sub(pat, rep.format(l=lang), page)
    page = re.sub(r'<html lang="en">', f'<html lang="{lang}">', page, count=1)
    target = name.replace("-en.html", f"-{lang}.html")
    (PUBLIC / target).write_text(page, encoding="utf-8")
    return target


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "extract":
        src = (PUBLIC / sys.argv[2]).read_text(encoding="utf-8")
        print(json.dumps(texts(src), ensure_ascii=False, indent=1))
        return
    built = []
    for name in PAGES:
        if not (I18N / (name.replace("-en.html", "") + ".json")).exists():
            continue
        for lang in TARGETS:
            built.append(build_page(name, lang))
    print("pagine tradotte:", ", ".join(built) or "nessuna")


if __name__ == "__main__":
    main()

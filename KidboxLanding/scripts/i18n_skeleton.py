#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Aiuto per tradurre le pagine con translate_html.py senza riscrivere i tag.

    python3 scripts/i18n_skeleton.py show guide-en.html       # testi con ⟨n⟩ al posto dei tag
    python3 scripts/i18n_skeleton.py save guide <file.py>     # scrive tools/i18n/guide.json

<file.py> definisce ES = [...] e FR = [...], allineate ai testi di `show`, con
⟨n⟩ al posto dell'n-esimo tag del testo inglese. `save` rimette i tag veri.
"""
import importlib.util
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import translate_html as th  # noqa: E402

TAG = re.compile(r"<[^>]+>")


def skeleton(t):
    i = iter(range(1000))
    return TAG.sub(lambda m: f"⟨{next(i)}⟩", t)


def expand(en, tr):
    tags = TAG.findall(en)
    return re.sub(r"⟨(\d+)⟩", lambda m: tags[int(m.group(1))], tr)


def main():
    cmd = sys.argv[1]
    if cmd == "show":
        src = (th.PUBLIC / sys.argv[2]).read_text(encoding="utf-8")
        for n, t in enumerate(th.texts(src)):
            print(n, json.dumps(skeleton(t), ensure_ascii=False))
    elif cmd == "save":
        page, pyfile = sys.argv[2], sys.argv[3]
        src = (th.PUBLIC / f"{page}-en.html").read_text(encoding="utf-8")
        en = th.texts(src)
        spec = importlib.util.spec_from_file_location("tr", pyfile)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        out = {"en": en}
        for lang, lst in (("es", mod.ES), ("fr", mod.FR)):
            if len(lst) != len(en):
                raise SystemExit(f"{lang}: {len(lst)} traduzioni per {len(en)} testi")
            out[lang] = [expand(e, t) for e, t in zip(en, lst)]
        (th.I18N / f"{page}.json").write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"tools/i18n/{page}.json: {len(en)} testi")


if __name__ == "__main__":
    main()

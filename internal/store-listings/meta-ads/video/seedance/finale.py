#!/usr/bin/env python3
"""Aggiunge allo spot di Seedance la chiusura con logo e messaggio, come i video
«Chi prende Marco»: stesso gradiente, stessa icona, stessi testi per lingua.

    python3 finale.py prova-480p-2.mp4 spot-it.mp4 [--lang it] [--end 3.5] \
        [--cuts 0,2.33,6.33,9.67,16.54,21.08,26.58]

Seedance non sa scrivere né disegnare il logo: frasi e chiusura si compongono
qui. `--cuts` sono gli stacchi fra le sette scene del prompt (scuola e ufficio
sono una scena sola); per un video nuovo si ritrovano con
`ffmpeg -i video.mp4 -vf "select='gt(scene,0.3)',showinfo" -f null -`.
"""
import argparse
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFilter

# Una frase per scena, nell'ordine del prompt (spot-famiglia.txt).
CAPTIONS = {
    "it": ["Una famiglia. Mille cose da ricordare.",
           "Da oggi, gli impegni di tutti in un calendario solo.",
           "Lei scrive la lista. Lui la spunta.",
           "È arrivato a scuola. Lo sai senza chiamare.",
           "Visite, referti, cure: tutto nella sua cartella.",
           "Chiedi all'assistente. Conosce la tua famiglia.",
           "E la sera, finalmente, si sta insieme."],
    "en": ["One family. A thousand things to remember.",
           "From now on, everyone's plans in one calendar.",
           "She writes the list. He ticks it off.",
           "He's at school. You know without calling.",
           "Visits, reports, treatments: all in one record.",
           "Ask the assistant. It knows your family.",
           "And in the evening, finally, together."],
    "fr": ["Une famille. Mille choses à retenir.",
           "Désormais, les rendez-vous de tous dans un seul agenda.",
           "Elle écrit la liste. Il la coche.",
           "Il est arrivé à l'école. Vous le savez sans appeler.",
           "Visites, comptes rendus, traitements : tout dans son dossier.",
           "Demandez à l'assistant. Il connaît votre famille.",
           "Et le soir, enfin, on se retrouve."],
    "es": ["Una familia. Mil cosas que recordar.",
           "Desde hoy, los planes de todos en un solo calendario.",
           "Ella escribe la lista. Él la tacha.",
           "Ha llegado al cole. Lo sabes sin llamar.",
           "Visitas, informes, tratamientos: todo en su historial.",
           "Pregunta al asistente. Conoce a tu familia.",
           "Y por la noche, por fin, juntos."],
}

# Chiusura dello spot: riprende l'ultima scena (la cena insieme) invece della
# frase dei video «Chi prende Marco» in compose_video.TEXT.
END = {
    "it": "Meno cose da ricordare. Più tempo insieme.",
    "en": "Less to remember. More time together.",
    "fr": "Moins de choses à retenir. Plus de temps ensemble.",
    "es": "Menos cosas que recordar. Más tiempo juntos.",
}

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from compose_video import ICON, TEXT, W, H, HEAVY, DEMI, font, gradient, wrap  # noqa: E402


def end_card(lang, bg, mark, words):
    """La chiusura in tre strati che entrano uno dopo l'altro: fondo con icona,
    marchio, frase."""
    txt = TEXT[lang]
    # Fondo scuro della landing (modalità scura): ci stanno «Kid» bianco e «Box» arancione.
    img = gradient(W, H, top=(30, 21, 13), bot=(20, 14, 8)).convert("RGBA")
    size = 300
    ic = Image.open(ICON).convert("RGB").resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=68, fill=255)
    # Un alone arancione morbido stacca l'icona dal fondo scuro.
    x0, y0 = (W - size) // 2, 470
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle([x0, y0 + 10, x0 + size, y0 + size + 10], radius=68, fill=(232, 131, 58, 110))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(40)))
    img.paste(ic, (x0, y0), mask)
    img.convert("RGB").save(bg)
    # Il marchio come sulla landing: «Kid» nel colore del testo, «Box» arancione.
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f = font(84, HEAVY)
    x = (W - f.getlength("KidBox")) / 2
    d.text((x, 805), "Kid", font=f, fill=(246, 239, 230))
    d.text((x + f.getlength("Kid"), 805), "Box", font=f, fill=(244, 153, 90))
    img.save(mark)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    y = 1010
    f = font(78, HEAVY)
    lines = balance(END[lang], f, W - 160)
    for line in lines:
        d.text(((W - f.getlength(line)) / 2, y), line, font=f, fill=(246, 239, 230))
        y += 96
    f = font(48, DEMI)
    d.text(((W - f.getlength(txt["sub"])) / 2, y + 60), txt["sub"], font=f, fill=(244, 153, 90))
    img.save(words)


def balance(text, f, width):
    """A capo dopo ogni frase, poi righe di lunghezza simile preferendo la
    punteggiatura: niente parola sola sulla riga sotto."""
    from itertools import combinations
    out = []
    for part in text.replace(". ", ".\n").split("\n"):
        words = part.split()
        k = len(wrap(part, f, width))
        best = None
        for cuts in combinations(range(1, len(words)), k - 1):
            lines = [" ".join(words[i:j]) for i, j in zip((0,) + cuts, cuts + (len(words),))]
            widths = [f.getlength(l) for l in lines]
            if max(widths) > width:
                continue
            score = max(widths) - min(widths) - sum(width * 0.5 for l in lines[:-1] if l[-1] in ",:;")
            if best is None or score < best[0]:
                best = (score, lines)
        out += best[1] if best else wrap(part, f, width)
    return out


def caption(text, path):
    """Frase in sovraimpressione sopra la fascia bassa che Reels copre coi suoi
    pulsanti (ultimo 35% circa dello schermo)."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    f = font(70, HEAVY)
    # A capo dopo il punto quando la frase non sta su una riga sola.
    lines = balance(text, f, W - 180)
    y = 1220 - len(lines) * 88
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    for i, line in enumerate(lines):
        sd.text(((W - f.getlength(line)) / 2, y + i * 88 + 4), line, font=f, fill=(0, 0, 0, 200))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(10)))
    d = ImageDraw.Draw(img)
    for i, line in enumerate(lines):
        d.text(((W - f.getlength(line)) / 2, y + i * 88), line, font=f, fill=(255, 255, 255))
    img.save(path)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("src")
    p.add_argument("dest")
    p.add_argument("--lang", default="it")
    p.add_argument("--end", type=float, default=5.0)
    p.add_argument("--cuts", default="0,2.33,6.33,9.67,16.54,21.08,26.58")
    p.add_argument("--audio-seedance", action="store_true",
                   help="tiene l'audio di Seedance invece della colonna sonora di musica_spot.py")
    a = p.parse_args()

    dur = float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                         "-of", "csv=p=0", a.src]).decode().strip())
    # Stacco lento: l'ultima scena scende nel buio e da lì sale la chiusura.
    fade = 1.6
    total = dur + a.end - fade
    tail = a.end - fade + 1.5
    with tempfile.TemporaryDirectory() as tmp:
        card, mark, words = (os.path.join(tmp, n) for n in ("card.png", "mark.png", "words.png"))
        end_card(a.lang, card, mark, words)
        cuts = [float(c) for c in a.cuts.split(",")] + [dur - fade]
        inputs, chain, last = [], "", "base"
        for i, text in enumerate(CAPTIONS[a.lang]):
            cap = os.path.join(tmp, f"cap{i}.png")
            caption(text, cap)
            inputs += ["-loop", "1", "-t", str(dur), "-i", cap]
            t0, t1 = cuts[i] + 0.25, cuts[i + 1] - 0.15
            # Ogni frase entra e sfuma dentro la sua scena.
            chain += (f"[{i + 4}:v]format=rgba,fade=t=in:st={t0}:d=0.3:alpha=1,"
                      f"fade=t=out:st={t1 - 0.3}:d=0.3:alpha=1[c{i}];"
                      f"[{last}][c{i}]overlay=0:0:enable='between(t,{t0},{t1})'[o{i}];")
            last = f"o{i}"
        # Video portato a 1080x1920 con le frasi, poi dissolvenza sulla chiusura;
        # l'audio di Seedance prosegue sotto la chiusura e sfuma fino al silenzio.
        flt = (
            f"[0:v]scale={W}:{H}:flags=lanczos,setsar=1,fps=30[base];"
            + chain +
            f"[{last}]format=yuv420p[v0];"
            # Marchio e frase entrano dopo l'icona, a mezzo secondo l'uno dall'altra.
            f"[2:v]format=rgba,fade=t=in:st={fade + 0.1}:d=0.6:alpha=1[mk];"
            f"[3:v]format=rgba,fade=t=in:st={fade + 0.7}:d=0.7:alpha=1[wd];"
            f"[1:v]scale={W}:{H},setsar=1,fps=30[cb];"
            f"[cb][mk]overlay=0:0[cm];[cm][wd]overlay=0:0,format=yuv420p[v1];"
            f"[v0][v1]xfade=transition=fadeblack:duration={fade}:offset={dur - fade}[v];"
            # La musica di Seedance finisce coi 30 s: per tenerla sotto la chiusura
            # si riprende un pezzo della scena finale e lo si incrocia col finale,
            # poi sfuma solo negli ultimi secondi.
            f"[0:a]asplit[a1][a2];"
            f"[a2]atrim=start={dur - 1.5 - tail}:end={dur - 1.5},asetpts=PTS-STARTPTS[tail];"
            f"[a1][tail]acrossfade=d=1.5,atrim=0:{total},"
            f"afade=t=out:st={total - 2.5}:d=2.5[a]"
        )
        if not a.audio_seedance:
            # La musica di Seedance è quasi solo ambiente: base continua composta
            # sugli stacchi, che sfuma da sola alla fine.
            music = os.path.join(tmp, "musica.wav")
            subprocess.run([sys.executable, os.path.join(HERE, "musica_spot.py"), music,
                            "--dur", str(total), "--card", str(dur - fade), "--cuts", a.cuts],
                           check=True, stdout=subprocess.DEVNULL)
            inputs += ["-i", music]
            n_music = 4 + len(CAPTIONS[a.lang])
            flt = flt[:flt.index("[0:a]asplit")] + f"[{n_music}:a]anull[a]"
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", a.src,
                        "-loop", "1", "-t", str(a.end), "-i", card,
                        "-loop", "1", "-t", str(a.end), "-i", mark,
                        "-loop", "1", "-t", str(a.end), "-i", words, *inputs,
                        "-filter_complex", flt, "-map", "[v]", "-map", "[a]",
                        "-c:v", "libx264", "-crf", "18", "-preset", "slow", "-pix_fmt", "yuv420p",
                        "-c:a", "aac", "-movflags", "+faststart", a.dest], check=True)
    print(a.dest)


if __name__ == "__main__":
    main()

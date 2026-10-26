"""Video verticale «Chi prende Marco giovedì?» per le inserzioni Meta.

1080x1920, 30 fps, 15 s, una versione per lingua. Testi e telefono restano
nella zona che Reels e Stories non coprono (14% in alto, 35% in basso).

Scene: 0–2,5 s titolo + notifica di Luca che scende sul telefono; 2,5–7 s
registrazione vera del tap su «Ci penso io»; 7–12 s calendario, to-do e spese;
12–15 s chiusura.

Uso: python3 compose_video.py <lingua> <cartella frame registrazione> <tap_x> <tap_y> <frame del tap>
Le coordinate del tap sono in pixel della registrazione. Legge gli screenshot
da ../../screenshots/raw/<lingua>/ e scrive out/kidbox-chi-prende-marco-<lingua>.mp4.
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os, sys, subprocess, shutil, glob, math

HERE = os.path.dirname(os.path.abspath(__file__))
SHOTS = os.path.join(HERE, "..", "..", "screenshots", "raw")
ICON = os.path.join(HERE, "..", "..", "..", "..", "KidBox", "KidBox", "Assets.xcassets", "AppIcon.appiconset", "1024.png")
FONT = "/System/Library/Fonts/Avenir Next.ttc"
HEAVY, DEMI, MEDIUM = 8, 2, 5
W, H, FPS = 1080, 1920, 30
DUR = 15.0

TEXT = {
    "it": dict(now="ora", hook="Chi prende Marco giovedì?", app="KidBox", who="Luca chiede",
               ask="Chi prende Marco giovedì alle 17?",
               claim="«Ci penso io»: ed è già nei tuoi to-do",
               tour="Calendario, to-do e spese. Per tutta la famiglia.",
               end="Smetti di essere l'unico promemoria della famiglia.",
               sub="Gratis su iPhone, Android e web"),
    "en": dict(now="now", hook="Who's picking up Marco on Thursday?", app="KidBox", who="Luca is asking",
               ask="Who picks Marco up on Thursday at 5pm?",
               claim="“I'll do it”: and it's already on your to-do list",
               tour="Calendar, to-dos and expenses. For the whole family.",
               end="Stop being the family's only reminder.",
               sub="Free on iPhone, Android and web"),
    "fr": dict(now="maintenant", hook="Qui récupère Marco jeudi ?", app="KidBox", who="Luca demande",
               ask="Qui récupère Marco jeudi à 17 h ?",
               claim="« Je m'en occupe » : c'est déjà dans vos tâches",
               tour="Calendrier, tâches et dépenses. Pour toute la famille.",
               end="Arrêtez d'être le seul pense-bête de la famille.",
               sub="Gratuit sur iPhone, Android et web"),
    "es": dict(now="ahora", hook="¿Quién recoge a Marco el jueves?", app="KidBox", who="Luca pide",
               ask="¿Quién recoge a Marco el jueves a las 17:00?",
               claim="«Me encargo yo»: y ya está en tus tareas",
               tour="Calendario, tareas y gastos. Para toda la familia.",
               end="Deja de ser el único recordatorio de la familia.",
               sub="Gratis en iPhone, Android y web"),
}

INK = (28, 18, 12)
font = lambda size, idx=HEAVY: ImageFont.truetype(FONT, size, index=idx)


def gradient(w, h, top=(250, 180, 96), bot=(242, 126, 34)):
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / h
        d.line([(0, y), (w, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
    return img


def wrap(text, f, max_w):
    words, lines, cur = text.split(" "), [], ""
    for w_ in words:
        test = (cur + " " + w_).strip()
        if f.getlength(test) <= max_w or not cur:
            cur = test
        else:
            lines.append(cur)
            cur = w_
    lines.append(cur)
    return lines


def draw_text(img, text, cy, size, max_w=980, idx=HEAVY, color=INK, alpha=1.0, max_lines=2):
    """Testo centrato su `cy`, con la dimensione che si riduce finché sta in `max_lines` righe."""
    while True:
        f = font(size, idx)
        lines = wrap(text, f, max_w)
        if len(lines) <= max_lines or size < 40:
            break
        size -= 4
    lh = int(size * 1.18)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    y = cy - lh * len(lines) // 2
    for line in lines:
        d.text(((W - f.getlength(line)) / 2, y), line, font=f, fill=color + (int(255 * alpha),))
        y += lh
    img.alpha_composite(layer)


# Telefono: la schermata (1206x2622 nel simulatore) larga SW, cornice disegnata.
SW = 700
PHONE_TOP = 560


def phone_parts(sw):
    sh = int(2622 * sw / 1206)
    bezel, ring, radius = int(sw * 0.026), max(3, int(sw * 0.004)), int(sw * 0.135)
    ow, oh = sw + 2 * (bezel + ring), sh + 2 * (bezel + ring)
    frame = Image.new("RGBA", (ow, oh), (0, 0, 0, 0))
    d = ImageDraw.Draw(frame)
    d.rounded_rectangle([0, 0, ow - 1, oh - 1], radius=radius + bezel + ring, fill=(88, 86, 90, 255))
    d.rounded_rectangle([ring, ring, ow - 1 - ring, oh - 1 - ring], radius=radius + bezel, fill=(10, 10, 12, 255))
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw - 1, sh - 1], radius=radius, fill=255)
    island = (int(sw * 0.29), int(sw * 0.088), int(sw * 0.026))
    shadow = Image.new("RGBA", (ow + 160, oh + 160), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([80, 110, ow + 80, oh + 110], radius=radius + bezel, fill=(60, 20, 0, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(40))
    return dict(sw=sw, sh=sh, off=bezel + ring, frame=frame, mask=mask, island=island, ow=ow, oh=oh, shadow=shadow)


P = phone_parts(SW)
PAN = 520       # di quanto sale il telefono nella scena del tap
BAND_H = 540    # altezza della fascia dei titoli
BAND = None
PX = (W - P["ow"]) // 2


def phone_with(screen):
    out = P["frame"].copy()
    out.paste(screen.resize((P["sw"], P["sh"]), Image.LANCZOS), (P["off"], P["off"]), P["mask"])
    iw, ih, iy = P["island"]
    d = ImageDraw.Draw(out)
    ix = (P["ow"] - iw) // 2
    d.rounded_rectangle([ix, P["off"] + iy, ix + iw, P["off"] + iy + ih], radius=ih // 2, fill=(0, 0, 0, 255))
    return out


def place_phone(img, phone, dy=0):
    img.alpha_composite(P["shadow"], (PX - 80, PHONE_TOP - 80 + dy))
    img.alpha_composite(phone, (PX, PHONE_TOP + dy))


def notification(t, txt, icon):
    """Banner di sistema in stile iOS, largo quanto lo schermo del telefono."""
    w, h = P["sw"] - 36, 170
    card = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(card)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=44, fill=(250, 248, 246, 245))
    ic = icon.resize((88, 88), Image.LANCZOS)
    m = Image.new("L", (88, 88), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, 87, 87], radius=20, fill=255)
    card.paste(ic, (24, 24), m)
    d.text((132, 22), txt["app"].upper(), font=font(22, DEMI), fill=(120, 110, 100))
    d.text((132, 52), txt["who"], font=font(30, HEAVY), fill=INK)
    ask_f = font(28, MEDIUM)
    ask = txt["ask"]
    while ask_f.getlength(ask) > w - 150 and len(ask) > 4:
        ask = ask.rstrip("…")[:-1] + "…"
    d.text((132, 92), ask, font=ask_f, fill=(40, 34, 30))
    nf = font(22, MEDIUM)
    d.text((w - 28 - nf.getlength(txt["now"]), 24), txt["now"], font=nf, fill=(120, 110, 100))
    return card


def ease(x):
    x = max(0.0, min(1.0, x))
    return 1 - (1 - x) ** 3


def main():
    lang, rec_dir, tap_x, tap_y, tap_frame = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
    txt = TEXT[lang]
    rec = sorted(glob.glob(os.path.join(rec_dir, "*.png")))
    icon = Image.open(ICON).convert("RGB")
    shots = {n: Image.open(os.path.join(SHOTS, lang, f"{n}.png")).convert("RGB")
             for n in ("01-home", "02-calendar", "03-todo", "04-spese")}
    bg = gradient(W, H).convert("RGBA")
    tmp = os.path.join(HERE, "frames", lang)
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp)

    # Prima immagine della registrazione = Home con la richiesta.
    first = Image.open(rec[0]).convert("RGB")
    first_phone = phone_with(first)
    global BAND
    # Fascia dei titoli: copia dello sfondo che copre il telefono salito, con
    # il bordo basso sfumato.
    BAND = bg.crop((0, 0, W, BAND_H)).copy()
    fade = Image.linear_gradient("L").resize((W, 50)).transpose(Image.FLIP_TOP_BOTTOM)
    alpha = Image.new("L", (W, BAND_H), 255)
    alpha.paste(fade, (0, BAND_H - 50))
    BAND.putalpha(alpha)
    BAND_full = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    BAND_full.paste(BAND, (0, 0))
    BAND = BAND_full
    tour = [phone_with(shots[n]) for n in ("02-calendar", "03-todo", "04-spese")]
    last_phone = None
    # La registrazione parte a 2,5 s; il tap cade a 3,6 s.
    rec_start = max(0, tap_frame - int(1.1 * FPS))
    sx = P["sw"] / 1206

    n_frames = int(DUR * FPS)
    for i in range(n_frames):
        t = i / FPS
        img = bg.copy()
        if t < 2.5:
            # Il telefono sale, poi scende la notifica.
            rise = ease(t / 0.6)
            draw_text(img, txt["hook"], 400, 92, alpha=ease(t / 0.4))
            place_phone(img, first_phone, dy=int((1 - rise) * 500))
            if t > 0.8:
                k = ease((t - 0.8) / 0.45)
                card = notification(t, txt, icon)
                y = PHONE_TOP + P["off"] + int(-180 + k * 230)
                card.putalpha(card.split()[3].point(lambda a: int(a * k)))
                img.alpha_composite(card, ((W - card.width) // 2, y))
        elif t < 7.0:
            fi = rec_start + int((t - 2.5) * FPS)
            fr = Image.open(rec[min(fi, len(rec) - 1)]).convert("RGB")
            # Il telefono sale finché la richiesta sta sopra il 35% basso, che
            # Reels e Stories coprono con didascalia e pulsante.
            pan = int(ease((t - 2.5) / 0.6) * PAN)
            last_phone = phone_with(fr)
            place_phone(img, phone_with(fr), dy=-pan)
            img.alpha_composite(BAND)
            # Il dito: un cerchio che si stringe sul punto del tap.
            dt = (fi - tap_frame) / FPS
            if -0.25 < dt < 0.35:
                a = 1 - abs(dt) / 0.35
                r = int(46 + 30 * max(0, dt) / 0.35)
                cx = PX + P["off"] + int(tap_x * sx)
                cy = PHONE_TOP - pan + P["off"] + int(tap_y * sx)
                ring = Image.new("RGBA", img.size, (0, 0, 0, 0))
                ImageDraw.Draw(ring).ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 255, int(110 * a)),
                                             outline=(255, 255, 255, int(220 * a)), width=4)
                img.alpha_composite(ring)
            if t < 3.6:
                draw_text(img, txt["hook"], 400, 92)
            else:
                draw_text(img, txt["claim"], 400, 78, alpha=ease((t - 3.6) / 0.35))
        elif t < 12.0:
            seg = (t - 7.0) / (5.0 / 3)
            k = min(2, int(seg))
            frac = seg - k
            draw_text(img, txt["tour"], 400, 78, alpha=ease((t - 7.0) / 0.35))
            # Scorrimento orizzontale: dalla registrazione al calendario (mentre
            # il telefono torna giù), poi to-do e spese.
            if frac < 0.22:
                m = ease(frac / 0.22)
                a = last_phone if k == 0 else tour[k - 1]
                b = tour[k]
                off = int(m * W)
                dya = -PAN if k == 0 else 0
                for ph, x, dy in ((a, PX - off, dya), (b, PX + W - off, 0)):
                    img.alpha_composite(P["shadow"], (x - 80, PHONE_TOP - 80 + dy))
                    img.alpha_composite(ph, (x, PHONE_TOP + dy))
                if k == 0:
                    img.alpha_composite(BAND)
            else:
                place_phone(img, tour[k])
            draw_text(img, txt["tour"], 400, 78, alpha=ease((t - 7.0) / 0.35))
        else:
            k = ease((t - 12.0) / 0.5)
            ic = icon.resize((260, 260), Image.LANCZOS)
            m = Image.new("L", (260, 260), 0)
            ImageDraw.Draw(m).rounded_rectangle([0, 0, 259, 259], radius=58, fill=255)
            m = m.point(lambda a: int(a * k))
            img.paste(ic, ((W - 260) // 2, 520), m)
            draw_text(img, txt["end"], 1010, 84, alpha=k, max_lines=3)
            draw_text(img, txt["sub"], 1250, 50, idx=DEMI, alpha=ease((t - 12.4) / 0.5))
        img.convert("RGB").save(os.path.join(tmp, f"{i:04d}.png"))

    out = os.path.join(HERE, "out")
    os.makedirs(out, exist_ok=True)
    dest = os.path.join(out, f"kidbox-chi-prende-marco-{lang}.mp4")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(tmp, "%04d.png"),
                    "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo", "-shortest",
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-preset", "slow",
                    "-c:a", "aac", "-movflags", "+faststart", dest], check=True)
    shutil.rmtree(tmp)
    print(dest)


if __name__ == "__main__":
    main()

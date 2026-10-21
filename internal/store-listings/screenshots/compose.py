"""Compone gli screenshot degli store: didascalia + schermata vera su sfondo KidBox.

Uso: python3 compose.py   (legge raw/<lingua>/NN-*.png, scrive final/<lingua>/NN-*.png, 1320x2868)
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os

W, H = 1320, 2868
FONT = "/System/Library/Fonts/Avenir Next.ttc"  # indice 0 = Bold, 8 = Heavy
CAPTIONS = {
    "it": {"01-home": ("Chi prende Marco?", "Un tocco e la famiglia risponde"),
           "02-calendar": ("Un calendario", "per tutta la famiglia"),
           "03-todo": ("Cose da fare assegnate,", "nessuno si dimentica")},
    "en": {"01-home": ("Who picks Marco up?", "One tap and the family answers"),
           "02-calendar": ("One shared calendar", "for the whole family"),
           "03-todo": ("Tasks assigned to each person,", "nothing gets forgotten")},
    "es": {"01-home": ("¿Quién recoge a Marco?", "Un toque y la familia responde"),
           "02-calendar": ("Un calendario compartido", "para toda la familia"),
           "03-todo": ("Tareas asignadas a cada uno,", "nada se olvida")},
    "fr": {"01-home": ("Qui récupère Marco ?", "Un appui et la famille répond"),
           "02-calendar": ("Un calendrier partagé", "pour toute la famille"),
           "03-todo": ("Des tâches assignées à chacun,", "rien n'est oublié")},
}

def gradient():
    top, bot = (255, 170, 80), (244, 112, 28)
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / H
        d.line([(0, y), (W, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
    return img

def fit_font(text, size, max_w, index=8):
    while size > 40:
        f = ImageFont.truetype(FONT, size, index=index)
        if f.getlength(text) <= max_w:
            return f
        size -= 4
    return ImageFont.truetype(FONT, 40, index=index)

def compose(lang, name):
    shot = Image.open(f"raw/{lang}/{name}.png").convert("RGB")
    bg = gradient()
    d = ImageDraw.Draw(bg)
    line1, line2 = CAPTIONS[lang][name]
    f1 = fit_font(line1, 112, W - 140)
    f2 = fit_font(line2, 84, W - 140, index=2)
    d.text((W / 2, 190), line1, font=f1, fill=(255, 255, 255), anchor="mm")
    d.text((W / 2, 325), line2, font=f2, fill=(255, 240, 224), anchor="mm")
    scale = 0.80
    sw, sh = int(W * scale), int(H * scale)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw, sh], radius=96, fill=255)
    x, y = (W - sw) // 2, 440
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([x, y + 24, x + sw, y + sh + 24], radius=96, fill=(90, 30, 0, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(36))
    bg.paste(shadow, (0, 0), shadow)
    # bordo scuro sottile come il telaio del telefono
    frame = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle([x - 10, y - 10, x + sw + 10, y + sh + 10], radius=104, fill=(28, 24, 22, 255))
    bg.paste(frame, (0, 0), frame)
    bg.paste(shot, (x, y), mask)
    os.makedirs(f"final/{lang}", exist_ok=True)
    bg.save(f"final/{lang}/{name}.png")

for lang in CAPTIONS:
    for name in CAPTIONS[lang]:
        compose(lang, name)
print("ok")

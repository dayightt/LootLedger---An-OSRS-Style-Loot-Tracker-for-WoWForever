"""LootLedger logo: an open ledger with a bookmark ribbon and a stack of coins.
Draws at 4x and downsamples. Produces an icon-only version and one with the name."""
import math, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

S = 4
SIZE = 1024
W = SIZE * S
OUT = sys.argv[1]

GOLD = (232, 196, 106)
GOLD_DARK = (150, 112, 38)
GOLD_LIGHT = (255, 236, 170)
PAGE = (236, 222, 186)
PAGE_SHADE = (214, 196, 156)
LINE = (150, 132, 100)
COVER = (72, 40, 24)
COVER_DARK = (46, 24, 14)
PURPLE = (163, 53, 238)
PURPLE_DARK = (110, 30, 170)
BG = (22, 17, 14)
BG_EDGE = (12, 9, 7)


def s(v):
    return int(round(v * S))


def radial_background():
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    # radial gradient: lighter centre, darker edges
    grad = Image.new("RGBA", (W, W), BG_EDGE + (255,))
    gd = ImageDraw.Draw(grad)
    steps = 60
    for i in range(steps, 0, -1):
        t = i / steps
        r = int(W * 0.78 * t)
        c = tuple(int(BG_EDGE[k] + (BG[k] + 14 - BG_EDGE[k]) * (1 - t)) for k in range(3))
        gd.ellipse([W // 2 - r, W // 2 - r - s(60), W // 2 + r, W // 2 + r - s(60)], fill=c + (255,))
    grad = grad.filter(ImageFilter.GaussianBlur(s(40)))
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, W - 1, W - 1], radius=s(190), fill=255)
    img.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([s(14), s(14), W - s(14), W - s(14)], radius=s(178), outline=GOLD_DARK, width=s(14))
    d.rounded_rectangle([s(22), s(22), W - s(22), W - s(22)], radius=s(170), outline=GOLD, width=s(5))
    return img


def draw_book(d, cx, cy, width, height):
    """Open book centred at (cx, cy)."""
    half = width / 2
    spine = s(10)
    top, bottom = cy - height / 2, cy + height / 2
    # cover (slightly larger than the pages)
    pad = s(22)
    d.rounded_rectangle([cx - half - pad, top - pad, cx + half + pad, bottom + pad], radius=s(26), fill=COVER_DARK)
    d.rounded_rectangle([cx - half - pad + s(6), top - pad + s(6), cx + half + pad - s(6), bottom + pad - s(6)], radius=s(22), fill=COVER)
    # pages with a little stack showing at the outer edges
    for i in range(3, 0, -1):
        off = s(6) * i
        d.rounded_rectangle([cx - half - off, top + off, cx - spine, bottom + off], radius=s(10), fill=PAGE_SHADE)
        d.rounded_rectangle([cx + spine, top + off, cx + half + off, bottom + off], radius=s(10), fill=PAGE_SHADE)
    d.rounded_rectangle([cx - half, top, cx - spine, bottom], radius=s(10), fill=PAGE)
    d.rounded_rectangle([cx + spine, top, cx + half, bottom], radius=s(10), fill=PAGE)
    # inner shading toward the spine
    for i in range(18):
        t = i / 18
        c = tuple(int(PAGE[k] + (PAGE_SHADE[k] - PAGE[k]) * (1 - t)) for k in range(3))
        d.rectangle([cx - spine - s(3) * (18 - i), top, cx - spine - s(3) * (17 - i), bottom], fill=c)
        d.rectangle([cx + spine + s(3) * (17 - i), top, cx + spine + s(3) * (18 - i), bottom], fill=c)
    d.rectangle([cx - spine, top - pad + s(6), cx + spine, bottom + pad - s(6)], fill=COVER_DARK)
    # ruled lines on both pages
    margin = s(40)
    lines = 7
    gap = (height - 2 * margin) / (lines - 1)
    for i in range(lines):
        y = top + margin + gap * i
        d.line([cx - half + margin, y, cx - spine - margin, y], fill=LINE, width=s(5))
        d.line([cx + spine + margin, y, cx + half - margin, y], fill=LINE, width=s(5))
    # a few "entries": short dark ticks and gold amounts on the right page
    for i in range(1, lines - 1):
        y = top + margin + gap * i - s(16)
        d.rounded_rectangle([cx - half + margin, y, cx - half + margin + s(70 + (i * 37) % 60), y + s(12)], radius=s(6), fill=(110, 90, 60))
        d.rounded_rectangle([cx + half - margin - s(60), y, cx + half - margin, y + s(12)], radius=s(6), fill=GOLD_DARK)


def draw_ribbon(d, x, top, bottom):
    w = s(52)
    pts = [(x - w / 2, top), (x + w / 2, top), (x + w / 2, bottom), (x, bottom - s(40)), (x - w / 2, bottom)]
    d.polygon(pts, fill=PURPLE_DARK)
    inner = [(x - w / 2 + s(8), top), (x + w / 2 - s(8), top), (x + w / 2 - s(8), bottom - s(10)), (x, bottom - s(44)), (x - w / 2 + s(8), bottom - s(10))]
    d.polygon(inner, fill=PURPLE)


def draw_coin_stack(d, cx, cy, radius, count):
    """Stack of coins seen slightly from above; only the top face is visible."""
    thickness = s(20)
    ry = radius * 0.40
    offsets = [0, s(6), -s(4), s(3), -s(5), s(2)]
    GOLD_MID = (198, 158, 66)
    for i in range(count):
        x = cx + offsets[i % len(offsets)]
        y = cy - i * thickness
        # side band of this coin
        d.ellipse([x - radius, y - ry + thickness, x + radius, y + ry + thickness], fill=GOLD_DARK)
        d.rectangle([x - radius, y, x + radius, y + thickness], fill=GOLD_DARK)
        # top edge of this coin (the rim of its face) so each coin separates
        d.ellipse([x - radius, y - ry, x + radius, y + ry], fill=GOLD_MID)
        d.ellipse([x - radius, y - ry, x + radius, y + ry], outline=(120, 86, 26), width=s(3))
    # top coin face
    x = cx + offsets[(count - 1) % len(offsets)]
    y = cy - (count - 1) * thickness
    d.ellipse([x - radius, y - ry, x + radius, y + ry], fill=GOLD)
    d.ellipse([x - radius, y - ry, x + radius, y + ry], outline=GOLD_DARK, width=s(4))
    d.ellipse([x - radius + s(16), y - ry + s(7), x + radius - s(16), y + ry - s(7)], outline=GOLD_DARK, width=s(5))
    d.arc([x - radius + s(24), y - ry + s(10), x + radius - s(24), y + ry - s(10)], start=190, end=300, fill=GOLD_LIGHT, width=s(5))


def draw_standing_coin(d, cx, cy, radius):
    d.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=GOLD_DARK)
    d.ellipse([cx - radius + s(4), cy - radius + s(4), cx + radius - s(4), cy + radius - s(4)], fill=GOLD)
    d.ellipse([cx - radius + s(22), cy - radius + s(22), cx + radius - s(22), cy + radius - s(22)], outline=GOLD_DARK, width=s(7))
    # glint
    d.arc([cx - radius + s(30), cy - radius + s(30), cx + radius - s(30), cy + radius - s(30)], start=200, end=290, fill=GOLD_LIGHT, width=s(8))


def render(with_text):
    img = radial_background()
    # soft shadow under the book
    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    book_w, book_h = s(640), s(400)
    cx, cy = W // 2, W // 2 - (s(70) if with_text else s(10))
    sd.rounded_rectangle([cx - book_w / 2 - s(30), cy - book_h / 2 + s(30), cx + book_w / 2 + s(30), cy + book_h / 2 + s(60)], radius=s(40), fill=(0, 0, 0, 170))
    shadow = shadow.filter(ImageFilter.GaussianBlur(s(28)))
    img = Image.alpha_composite(img, shadow)

    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    draw_book(d, cx, cy, book_w, book_h)
    draw_ribbon(d, cx + s(190), cy - book_h / 2 - s(24), cy + book_h / 2 + s(90))
    img = Image.alpha_composite(img, layer)

    coins = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    cd = ImageDraw.Draw(coins)
    draw_coin_stack(cd, cx - s(225), cy + book_h / 2 + s(40), s(88), 5)
    draw_standing_coin(cd, cx - s(335), cy + book_h / 2 + s(48), s(60))
    img = Image.alpha_composite(img, coins)

    if with_text:
        text = Image.new("RGBA", (W, W), (0, 0, 0, 0))
        td = ImageDraw.Draw(text)
        font = ImageFont.truetype("C:/Windows/Fonts/palab.ttf", s(118))
        label = "LootLedger"
        bbox = td.textbbox((0, 0), label, font=font)
        tw = bbox[2] - bbox[0]
        tx = (W - tw) / 2 - bbox[0]
        ty = W - s(250)
        # shadow + outline
        for dx, dy in [(-3, -3), (3, -3), (-3, 3), (3, 3), (0, 4), (4, 0), (-4, 0), (0, -4)]:
            td.text((tx + s(dx), ty + s(dy)), label, font=font, fill=(20, 12, 8))
        td.text((tx, ty + s(8)), label, font=font, fill=(0, 0, 0, 160))
        td.text((tx, ty), label, font=font, fill=GOLD)
        img = Image.alpha_composite(img, text)

    return img.resize((SIZE, SIZE), Image.LANCZOS)


render(True).save(OUT + "/logo.png")
render(False).save(OUT + "/icon.png")
render(False).resize((256, 256), Image.LANCZOS).save(OUT + "/icon-256.png")
print("done")

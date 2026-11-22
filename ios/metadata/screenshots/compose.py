"""App Store 1.1.0 screenshots: one waveform strip runs through all six frames (docs/store-shots-1.1.0.md).

Usage: python3 compose.py <raw dir with raw_N_*.png> <demo clip>
Writes en-US-110/01_hook.png ... 06_pro.png and contact.png next to this script.
"""
import subprocess, sys
from array import array
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

S, CLIP = Path(sys.argv[1]), sys.argv[2]
OUT = Path(__file__).resolve().parent / 'en-US-110'
W, H = 1320, 2868
X0, MAXW = 88, 1144
WHITE, GREY = (255, 255, 255), (163, 163, 163)
SF, MONO = '/System/Library/Fonts/SFNS.ttf', '/System/Library/Fonts/SFNSMono.ttf'


def sf(size, axes):
    f = ImageFont.truetype(SF, size)
    f.set_variation_by_axes(axes)  # [width, opsz, grad, weight]
    return f


def mono(size):
    return ImageFont.truetype(MONO, size)


def bars():
    """180 buckets of 0.25 s RMS, MonoWave.bars normalisation; True marks a cut bucket."""
    pcm = subprocess.run(['ffmpeg', '-v', 'error', '-i', CLIP, '-ac', '1', '-ar', '8000', '-f', 's16le', '-'],
                         capture_output=True, check=True).stdout
    s = array('h'); s.frombytes(pcm)
    n = 2000  # 0.25 s at 8 kHz
    assert len(s) >= 180 * n, f'clip too short: {len(s) / 8000:.1f}s'
    rms = [(sum(v * v for v in s[i * n:(i + 1) * n]) / n) ** 0.5 for i in range(180)]
    p95 = sorted(rms)[int(0.95 * 179)] or 1
    vals = [max(0.06, min(1, r / p95) ** 0.6) for r in rms]
    # Cut buckets come from ffmpeg silencedetect (-35 dB, 0.85 s), the pauses the app also cuts on Balanced.
    # The plan's "normalised < 0.12 for 4 buckets" rule found none: room noise keeps pauses at 0.12-0.14 here.
    err = subprocess.run(['ffmpeg', '-v', 'info', '-i', CLIP, '-af', 'silencedetect=n=-35dB:d=0.85', '-f', 'null', '-'],
                         capture_output=True, text=True, check=True).stderr
    starts = [float(l.split('silence_start: ')[1].split()[0]) for l in err.splitlines() if 'silence_start: ' in l]
    ends = [float(l.split('silence_end: ')[1].split()[0]) for l in err.splitlines() if 'silence_end: ' in l]
    pauses = list(zip(starts, ends + [45.0] * (len(starts) - len(ends))))
    cut = [any(a <= (i + 0.5) * 0.25 <= b for a, b in pauses) for i in range(180)]
    assert len(pauses) >= 5, f'only {len(pauses)} pauses in the clip'
    return vals, cut


def strip(d, k, vals, cut):
    for s in range(30):
        b = k * 30 + s
        cx = s * 44 + 22  # slot centre: the 1320 px seam never cuts a bar
        if cut[b]:
            d.ellipse([cx - 5, 875, cx + 5, 885], fill=(58, 58, 58))
        else:
            h = max(22, vals[b] * 240)
            d.rounded_rectangle([cx - 11, 880 - h / 2, cx + 11, 880 + h / 2], 11, fill=WHITE)


def title(d, lines, sub, top):
    size = 132
    while max(d.textlength(t, font=sf(size, [100, 96, 400, 700])) for t in lines) > MAXW:
        size -= 4
        assert size >= 112, f'title too long: {lines}'
    f = sf(size, [100, 96, 400, 700])
    for i, (t, c) in enumerate(zip(lines, (WHITE, GREY))):
        d.text((X0, top + i * 146), t, font=f, fill=c)
    bottom = top + 146 + f.getbbox(lines[1])[3]
    fs = sf(54, [100, 28, 400, 400])
    assert d.textlength(sub, font=fs) <= MAXW, f'subtitle too long: {sub}'
    d.text((X0, bottom + 36), sub, font=fs, fill=GREY)


def badge(d):
    f = mono(34)
    w = d.textlength('PRO', font=f) + 2 * 30
    d.rounded_rectangle([X0, 96, X0 + w, 156], 30, fill=WHITE)
    d.text((X0 + w / 2, 126), 'PRO', font=f, fill=(0, 0, 0), anchor='mm')


def paste_ui(canvas, raw, top, fade=140):
    """Raw UI from `top` down, 1:1 at the same y; the top edge fades so the player melts into black."""
    ui = raw.crop((0, top, W, H))
    mask = Image.new('L', ui.size, 255)
    md = ImageDraw.Draw(mask)
    for y in range(fade):
        md.line([(0, y), (W, y)], fill=int(255 * y / fade))
    canvas.paste(ui, (0, top), mask)


def frame(k, vals, cut):
    c = Image.new('RGB', (W, H), (0, 0, 0))
    strip(ImageDraw.Draw(c), k, vals, cut)
    return c


SHOTS = [
    ('01_hook', 'raw_1_review', ['Cut the silence.', 'Keep the talk.'], 'Free. No watermark. No sign-up.'),
    ('02_control', 'raw_2_cuts', ['You approve', 'every cut.'], 'Keep any pause before you save.'),
    ('03_private', 'raw_3_home', ['Private', 'by design.'], 'Your video never leaves your iPhone.'),
    ('04_levels', 'raw_4_tight', ['Balanced, Tight', 'or Hardcore.'], 'Pick how tight the cut feels.'),
    ('05_finetune', 'raw_5_finetune', ['Fine-tune', 'every pause.'], 'Set minimum pause and breathing room.'),
    ('06_pro', 'raw_6_paywall', ['Pay once.', 'No subscription.'], 'Free with ads. Pro removes them for good.'),
]

# Measured on the 1320x2868 iPhone 17 Pro Max captures (see docs/store-shots-1.1.0.md step 5).
HOME_TOP = 1817 - 40          # "CutSense" overline on Home
PAY_TOP = 325 - 40            # "CutSense Pro" overline on the paywall
PAY_BOTTOM = 1885 + 60        # bottom of the white Pro column; the price CTA starts at y=2195
SHEET_TOP = 1878              # top edge of the Fine-tune sheet


def main():
    vals, cut = bars()
    OUT.mkdir(exist_ok=True)
    for old in OUT.glob('*.png'):
        old.unlink()
    outs = []
    for k, (name, rawname, lines, sub) in enumerate(SHOTS):
        raw = Image.open(S / f'{rawname}.png').convert('RGB')
        assert raw.size == (W, H), f'{rawname}: {raw.size}'
        c = frame(k, vals, cut)
        d = ImageDraw.Draw(c)
        pro = k >= 4
        if pro: badge(d)
        title(d, lines, sub, 190 if pro else 170)

        if k == 2:
            paste_ui(c, raw, HOME_TOP)
            f, y = mono(50), 1100
            for label in ('No upload', 'No account', 'No watermark'):
                w = d.textlength(label, font=f) + 2 * 48
                assert y + 112 <= HOME_TOP, 'capsules overlap the Home crop'
                ov = Image.new('RGBA', (W, H), (0, 0, 0, 0))
                ImageDraw.Draw(ov).rounded_rectangle([X0, y, X0 + w, y + 112], 56, outline=(255, 255, 255, 56), width=2)
                c.paste(ov, (0, 0), ov)
                d = ImageDraw.Draw(c)
                d.text((X0 + 48, y + 56), label, font=f, fill=WHITE, anchor='lm')
                y += 112 + 28
        elif k == 5:
            ui = raw.crop((0, PAY_TOP, W, PAY_BOTTOM))
            if ui.height > 1740:
                ui = ui.resize((round(W * 1740 / ui.height), 1740), Image.LANCZOS)
            c.paste(ui, ((W - ui.width) // 2, 1080))
        else:
            paste_ui(c, raw, 1060)
        if k == 4:
            # The Fine-tune sheet cuts the stats row in half; black out the clipped digits above and beside its top.
            d.rectangle([0, 1790, W, SHEET_TOP - 1], fill=(0, 0, 0))
            px = c.load()
            for y in range(SHEET_TOP, SHEET_TOP + 24):
                for x in range(0, 300):
                    if sum(px[x, y]) > 90: px[x, y] = (0, 0, 0)

        if k == 0:
            f = mono(30)
            first = next(i for i in range(30) if cut[i])
            end = next((i for i in range(first, 30) if not cut[i]), 30)
            d.text((((first + end) / 2) * 44, 1010), 'cut', font=f, fill=(128, 128, 128), anchor='mt')
            top = max(range(30), key=lambda i: -1 if cut[i] else vals[i])
            d.text((top * 44 + 22, 1010), 'kept', font=f, fill=(128, 128, 128), anchor='mt')

        path = OUT / f'{name}.png'
        c.save(path, optimize=True)
        outs.append(path)

    sheet = Image.new('RGB', (300 * 6, round(300 * H / W)), (0, 0, 0))
    for i, p in enumerate(outs):
        sheet.paste(Image.open(p).resize((300, sheet.height), Image.LANCZOS), (i * 300, 0))
    sheet.save(OUT / 'contact.png', optimize=True)

    for p in outs:
        assert Image.open(p).size == (W, H), p
    print(f'{len(outs)} screenshots + contact.png -> {OUT}; cut buckets {sum(cut)}/180')


main()

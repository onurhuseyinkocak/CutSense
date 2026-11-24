"""App Store 1.1.0 screenshots: one waveform strip runs through all six frames (docs/store-shots-1.1.0.md).

Usage: python3 compose.py <raw dir with raw_N_*.png> <demo clip> [locale, default en-US]
Writes <locale>-110/01_hook.png ... 06_pro.png and contact.png next to this script.
Raw captures must be in the same app language as the locale's copy (COPY below).
"""
import subprocess, sys
from array import array
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

S, CLIP = Path(sys.argv[1]), sys.argv[2]
LOC = sys.argv[3] if len(sys.argv) > 3 else 'en-US'
OUT = Path(__file__).resolve().parent / f'{LOC}-110'
W, H = 1320, 2868
X0, MAXW = 88, 1144
WHITE, GREY = (255, 255, 255), (163, 163, 163)
SF, MONO = '/System/Library/Fonts/SFNS.ttf', '/System/Library/Fonts/SFNSMono.ttf'


CJK = {'ja': ('/System/Library/Fonts/ヒラギノ角ゴシック W7.ttc', 0, '/System/Library/Fonts/ヒラギノ角ゴシック W4.ttc', 0),
       'ko': ('/System/Library/Fonts/AppleSDGothicNeo.ttc', 6, '/System/Library/Fonts/AppleSDGothicNeo.ttc', 0)}.get(LOC)


def sf(size, axes):
    if CJK:
        bold = axes[3] >= 700
        return ImageFont.truetype(CJK[0 if bold else 2], size, index=CJK[1 if bold else 3])
    f = ImageFont.truetype(SF, size)
    f.set_variation_by_axes(axes)  # [width, opsz, grad, weight]
    return f


def mono(size):
    return ImageFont.truetype(MONO, size)


def label_font(size):
    """Capsules and strip notes: SF Mono for Latin, the CJK text face otherwise."""
    return sf(size, [100, 28, 400, 400]) if CJK else mono(size)


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


LEAD = 162 if CJK else 146  # CJK glyphs fill the whole em box and need more line gap


def title(d, lines, sub, top):
    size = 132
    while max(d.textlength(t, font=sf(size, [100, 96, 400, 700])) for t in lines) > MAXW:
        size -= 4
        assert size >= 112, f'title too long: {lines}'
    f = sf(size, [100, 96, 400, 700])
    for i, (t, c) in enumerate(zip(lines, (WHITE, GREY))):
        d.text((X0, top + i * LEAD), t, font=f, fill=c)
    bottom = top + LEAD + f.getbbox('gpy')[3]  # fixed descender depth: the subline sits at the same y on every frame
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


FILES = [('01_hook', 'raw_1_review'), ('02_control', 'raw_2_cuts'), ('03_private', 'raw_3_home'),
         ('04_levels', 'raw_4_tight'), ('05_finetune', 'raw_5_finetune'), ('06_pro', 'raw_6_paywall')]

# Per locale: six (headline lines, subline), the three Home capsules, the two strip notes on frame 1
# (the in-app Cut/Keep toggle words).
# Level and Fine-tune names match Translations.swift so the headline names what the screenshot shows.
COPY = {
    'en-US': ([
        (['Cut the silence.', 'Keep the talk.'], 'Free. No watermark. No sign-up.'),
        (['You approve', 'every cut.'], 'Keep any pause before you save.'),
        (['Cut on', 'your iPhone.'], 'Your video is never uploaded.'),
        (['Balanced, Tight', 'or Hardcore.'], 'Pick how tight the cut feels.'),
        (['Fine-tune', 'every pause.'], 'Set minimum pause and breathing room.'),
        (['Pay once.', 'No subscription.'], 'Free with ads. Pro removes them for good.'),
    ], ('No upload', 'No account', 'No watermark'), ('cut', 'keep')),
    'tr': ([
        (['Sessizliği kes.', 'Konuşma kalsın.'], 'Ücretsiz, filigransız, üyeliksiz.'),
        (['Her kesimi', 'sen onaylarsın.'], 'Kaydetmeden önce dilediğin duraklamayı tut.'),
        (['Videon', 'iPhone’unda kalır.'], 'Hiçbir sunucuya yüklenmez.'),
        (['Dengeli, Sıkı', 'ya da Hardcore.'], 'Kesimin ne kadar sıkı olacağını sen seç.'),
        (['Her duraklamaya', 'ince ayar.'], 'En kısa duraklamayı ve nefes payını ayarla.'),
        (['Bir kez öde.', 'Abonelik yok.'], 'Ücretsiz sürüm reklamlı. Pro reklamı kaldırır.'),
    ], ('Yükleme yok', 'Hesap yok', 'Filigran yok'), ('kes', 'kalsın')),
    'es-ES': ([
        (['Corta el silencio.', 'Conserva tu voz.'], 'Gratis, sin marca de agua ni registro.'),
        (['Tú apruebas', 'cada corte.'], 'Mantén cualquier pausa antes de guardar.'),
        (['Todo ocurre', 'en tu iPhone.'], 'Tus clips nunca se suben a la nube.'),
        (['Equilibrado, Ajustado', 'o Extremo.'], 'Elige cuánto quieres recortar.'),
        (['Ajuste fino', 'de cada pausa.'], 'Define la pausa mínima y el margen.'),
        (['Paga una vez.', 'Sin suscripción.'], 'Gratis con anuncios. Pro los quita para siempre.'),
    ], ('Sin subidas', 'Sin cuenta', 'Sin marca de agua'), ('cortar', 'mantener')),
    'pt-BR': ([
        (['Corte o silêncio.', 'Fique com a fala.'], 'Grátis, sem marca d’água e sem cadastro.'),
        (['Você aprova', 'cada corte.'], 'Mantenha qualquer pausa antes de salvar.'),
        (['Tudo acontece', 'no seu iPhone.'], 'Seu vídeo nunca é enviado a servidores.'),
        (['Equilibrado, Intenso', 'ou Extremo.'], 'Escolha o quanto quer cortar.'),
        (['Ajuste fino', 'em cada pausa.'], 'Defina a pausa mínima e o respiro.'),
        (['Pague uma vez.', 'Sem assinatura.'], 'Grátis com anúncios. O Pro remove de vez.'),
    ], ('Sem upload', 'Sem conta', 'Sem marca d’água'), ('cortar', 'manter')),
    'de-DE': ([
        (['Stille raus.', 'Gesagtes bleibt.'], 'Kostenlos, ohne Wasserzeichen und Konto.'),
        (['Du entscheidest', 'jeden Schnitt.'], 'Behalte jede Pause vor dem Speichern.'),
        (['Alles passiert', 'auf dem iPhone.'], 'Dein Video wird nie hochgeladen.'),
        (['Ausgewogen, Straff', 'oder Extrem.'], 'Wähle, wie straff geschnitten wird.'),
        (['Feinschliff', 'für jede Pause.'], 'Minimale Pause und Puffer einstellen.'),
        (['Einmal zahlen.', 'Kein Abo.'], 'Gratis mit Werbung. Pro entfernt sie für immer.'),
    ], ('Kein Upload', 'Kein Konto', 'Kein Wasserzeichen'), ('schneiden', 'behalten')),
    'fr-FR': ([
        (['Coupez les blancs.', 'Gardez la parole.'], 'Gratuit, sans filigrane ni inscription.'),
        (['Vous validez', 'chaque coupe.'], 'Gardez une pause avant d’enregistrer.'),
        (['Tout se passe', 'sur votre iPhone.'], 'Votre vidéo n’est jamais envoyée.'),
        (['Équilibré, Serré', 'ou Extrême.'], 'Choisissez l’intensité de la coupe.'),
        (['Ajustez', 'chaque pause.'], 'Réglez la pause minimale et la marge.'),
        (['Payez une fois.', 'Sans abonnement.'], 'Gratuit avec pubs. Pro les retire pour de bon.'),
    ], ('Aucun envoi', 'Aucun compte', 'Aucun filigrane'), ('couper', 'garder')),
    'it': ([
        (['Taglia i silenzi.', 'Tieni le parole.'], 'Gratis, senza filigrana né registrazione.'),
        (['Approvi tu', 'ogni taglio.'], 'Tieni qualsiasi pausa prima di salvare.'),
        (['Tutto avviene', 'sul tuo iPhone.'], 'Il tuo video non viene mai caricato.'),
        (['Bilanciato, Deciso', 'o Estremo.'], 'Scegli quanto deve essere netto il taglio.'),
        (['Regola', 'ogni pausa.'], 'Imposta la pausa minima e il margine.'),
        (['Paghi una volta.', 'Zero abbonamenti.'], 'Gratis con pubblicità. Pro la toglie per sempre.'),
    ], ('Nessun upload', 'Nessun account', 'Nessuna filigrana'), ('taglia', 'tieni')),
    'ja': ([
        (['無音はカット。', '話はそのまま。'], '無料。透かしなし、登録不要。'),
        (['どのカットも', 'あなたが決める。'], '保存する前に、残したい間を選べます。'),
        (['カットは', 'iPhoneの中で。'], '動画はどこにもアップロードされません。'),
        (['バランス、タイト、', '最大から選べる。'], 'カットの強さを3段階で。'),
        (['すべての間を', '微調整。'], '最短の間と余白を自分で設定。'),
        (['買い切り。', 'サブスクなし。'], '無料版は広告つき。Proで広告が消えます。'),
    ], ('アップロードなし', 'アカウント不要', '透かしなし'), ('カット', '残す')),
    'ko': ([
        (['무음은 자르고', '말은 남기고.'], '무료. 워터마크도, 가입도 없습니다.'),
        (['모든 컷을', '직접 승인하세요.'], '저장 전에 원하는 멈춤을 남길 수 있어요.'),
        (['컷은', 'iPhone 안에서.'], '동영상은 어디에도 업로드되지 않습니다.'),
        (['균형, 타이트,', '최대 중에서.'], '원하는 컷 강도를 고르세요.'),
        (['모든 멈춤을', '세부 조정.'], '최소 멈춤과 여유를 직접 설정하세요.'),
        (['한 번 구매.', '구독 없음.'], '무료 버전은 광고 포함. Pro는 광고를 없앱니다.'),
    ], ('업로드 없음', '계정 없음', '워터마크 없음'), ('자르기', '유지')),
}

SHEET_TOP = 1878              # top edge of the Fine-tune sheet (same in every language)


def dark(px, y, x0=60, x1=1260):
    return all(sum(px[x, y]) < 60 for x in range(x0, x1, 4))


def home_top(raw):
    """40 px above the "CutSense" overline: first text row after the gap under Home's own waveform.
    Measured per capture because the subtitle wraps to 1 or 2 lines depending on language."""
    px, y, gap = raw.load(), 1400, 0
    while gap < 40:
        gap = gap + 1 if dark(px, y) else 0
        y += 1
    while dark(px, y): y += 1
    return y - 40


def pay_crop(raw):
    """Paywall crop: 40 px above the "CutSense Pro" overline to 60 px under the white Pro column."""
    px = raw.load()
    top = next(y for y in range(200, 800) if not dark(px, y, 60, 1100))
    col = next(y for y in range(600, 1400) if sum(px[1075, y]) > 740)  # inside the white Pro column
    bottom = next(y for y in range(col, H) if sum(px[1075, y]) < 600)
    return top - 40, bottom + 60


def main():
    vals, cut = bars()
    OUT.mkdir(exist_ok=True)
    for old in OUT.glob('*.png'):
        old.unlink()
    outs = []
    shots, caps, notes = COPY[LOC]
    for k, ((name, rawname), (lines, sub)) in enumerate(zip(FILES, shots)):
        raw = Image.open(S / f'{rawname}.png').convert('RGB')
        assert raw.size == (W, H), f'{rawname}: {raw.size}'
        c = frame(k, vals, cut)
        d = ImageDraw.Draw(c)
        pro = k >= 4
        if pro: badge(d)
        title(d, lines, sub, 190 if pro else 170)

        if k == 2:
            HOME_TOP = home_top(raw)
            paste_ui(c, raw, HOME_TOP)
            f, y = label_font(50), 1100
            for label in caps:
                w = d.textlength(label, font=f) + 2 * 48
                assert y + 112 <= HOME_TOP, 'capsules overlap the Home crop'
                ov = Image.new('RGBA', (W, H), (0, 0, 0, 0))
                ImageDraw.Draw(ov).rounded_rectangle([X0, y, X0 + w, y + 112], 56, outline=(255, 255, 255, 56), width=2)
                c.paste(ov, (0, 0), ov)
                d = ImageDraw.Draw(c)
                d.text((X0 + 48, y + 56), label, font=f, fill=WHITE, anchor='lm')
                y += 112 + 28
        elif k == 5:
            top, bottom = pay_crop(raw)
            ui = raw.crop((0, top, W, bottom))
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
            f = label_font(30)
            first = next(i for i in range(30) if cut[i])
            end = next((i for i in range(first, 30) if not cut[i]), 30)
            d.text((((first + end) / 2) * 44, 1010), notes[0], font=f, fill=(128, 128, 128), anchor='mt')
            top = max(range(30), key=lambda i: -1 if cut[i] else vals[i])
            x = max(top * 44 + 22, d.textlength(notes[1], font=f) / 2 + 40)  # long words stay off the edge
            d.text((x, 1010), notes[1], font=f, fill=(128, 128, 128), anchor='mt')

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

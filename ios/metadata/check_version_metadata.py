"""Validate version-1.1.0.json against App Store limits and CutSense copy rules."""
import json, re, sys
from pathlib import Path

PATH = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).with_name("version-1.1.0.json"))
LOCALES = ["en-US", "en-GB", "en-AU", "en-CA", "es-MX", "es-ES", "pt-BR", "de-DE", "fr-FR", "it", "ja", "ko", "tr"]
LIMITS = {"description": 4000, "promotionalText": 170, "whatsNew": 4000, "keywords": 100}

EN_NS = "Silence Remover: CutSense Remove Pauses, Auto Jump Cut"
# Words of the localized name + subtitle (plus singular/unaccented forms) that keywords must not repeat.
# shortcut: de/fr/it/ja/ko names unknown, so ban English name words + native silence/remove/pause words.
NAME_WORDS = {
    **{l: EN_NS + " pause" for l in ["en-US", "en-GB", "en-AU", "en-CA"]},
    "tr": "Sessizlik Silme: CutSense Duraksamaları Sil, Jump Cut sessiz duraksama",
    "es-ES": "Eliminar Silencios: CutSense Quitar pausas, jump cut auto silencio pausa",
    "es-MX": "Quitar Silencios: CutSense Elimina pausas, jump cut auto silencio pausa eliminar",
    "pt-BR": "Remover Silêncio: CutSense Cortar pausas, jump cut auto silencio pausa",
    "de-DE": EN_NS + " stille entfernen pause pausen löschen jump cuts",
    "fr-FR": EN_NS + " silence silences supprimer enlever pause pauses coupe jump cut auto",
    "it": EN_NS + " silenzio silenzi rimuovi rimuovere eliminare togliere pausa pause taglia jump cut auto",
    "ja": EN_NS + " 無音 削除 カット 間 沈黙 部分 自動 ジャンプカット",
    "ko": EN_NS + " 무음 침묵 제거 삭제 컷 멈춤 공백 구간 자동 점프컷",
}
FORBIDDEN = [r"\bAI\b", r"\bIA\b", r"\bKI\b", r"yapay zeka", "人工知能", "인공지능", r"tik ?tok",
             r"one[- ]tap", r"single[- ]tap", "tek dokunuş", "un (solo )?toque", "um toque", "ワンタップ", "원탭",
             r"\b4K\b", "lossless", "no re-?encode", "jumpcut", "autocut", "capcut", r"\bcaptions\b",
             r"\$|€|£|₺|¥|₩"]
KW_BANNED = ["filler", "tiktok", "jumpcut", "autocut", "podcast", "audio"]

data = json.loads(PATH.read_text(encoding="utf-8"))
assert list(data) == LOCALES or set(data) == set(LOCALES), f"locales: {sorted(data)}"
assert len(data) == 13

errors = []
print(f"{'locale':7} {'desc':>5} {'promo':>5} {'new':>5} {'kw':>4} {'kwB':>4}")
for loc in LOCALES:
    m = data[loc]
    assert set(m) == set(LIMITS), (loc, set(m))
    for field, lim in LIMITS.items():
        v = m[field]
        if not v.strip():
            errors.append(f"{loc}.{field} empty")
        if len(v) > lim:
            errors.append(f"{loc}.{field} {len(v)} > {lim}")
        for pat in FORBIDDEN:
            if re.search(pat, v, re.IGNORECASE if pat.isascii() and "\\b" not in pat else 0):
                errors.append(f"{loc}.{field} forbidden /{pat}/")
    kw = m["keywords"]
    if ", " in kw or kw != kw.strip():
        errors.append(f"{loc} keywords: space after comma / padding")
    terms = kw.split(",")
    if len(terms) != len(set(t.lower() for t in terms)):
        errors.append(f"{loc} keywords: duplicate term")
    banned_tokens = {t.lower() for t in re.findall(r"[\w']+", NAME_WORDS[loc])}
    for t in terms:
        if any(b in t.lower() for b in KW_BANNED):
            errors.append(f"{loc} keyword banned: {t}")
        tokens = set(t.lower().split()) if t.isascii() or " " in t else {t.lower()}
        hit = tokens & banned_tokens or {b for b in banned_tokens if not b.isascii() and len(b) and b in t and not t.isascii()}
        if hit:
            errors.append(f"{loc} keyword '{t}' repeats name/subtitle word {hit}")
    print(f"{loc:7} {len(m['description']):5} {len(m['promotionalText']):5} {len(m['whatsNew']):5} {len(kw):4} {len(kw.encode()):4}")

if errors:
    print("FAIL"); print("\n".join(errors)); sys.exit(1)
print("OK: 13 locales, all limits and rules pass")

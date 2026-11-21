import json, re, sys
P = "/Users/jinx/Documents/projeler/CutSense/ios/metadata/version-1.1.0-global.json"
data = json.load(open(P, encoding="utf-8"))
LOC = ["zh-Hans","zh-Hant","hi","id","ar-SA","ru","vi","th","pl","nl-NL","sv","uk","ms","he","el","cs","ro","hu","da","fi","no","ca","hr","sk","fr-CA","pt-PT"]
assert list(data) == LOC and len(data) == 26
LIM = {"name": 30, "subtitle": 30, "keywords": 100, "description": 4000, "promotionalText": 170, "whatsNew": 4000}
CS = [r"\bAI\b", r"one[- ]tap", r"tik ?tok", r"capcut", r"youtube", r"\b4K\b", r"lossless", r"filler", r"[$€£₺¥₩₹฿₫]|\bUSD\b|\bEUR\b"]
CJK = {"zh-Hans", "zh-Hant"}
err = []
print(f"{'loc':8}{'name':>5}{'sub':>5}{'kw':>5}{'desc':>6}{'promo':>6}{'new':>6}")
for l in LOC:
    m = data[l]
    assert set(m) == set(LIM), l
    for f, lim in LIM.items():
        v = m[f]
        if not v.strip(): err.append(f"{l}.{f} empty")
        if len(v) > lim: err.append(f"{l}.{f} {len(v)}>{lim}")
        for p in CS:
            if re.search(p, v, 0 if p == r"\bAI\b" else re.I): err.append(f"{l}.{f} forbidden {p}")
    if not (m["name"].endswith(": CutSense") or m["name"].startswith("CutSense: ")): err.append(f"{l} name pattern")
    kw = m["keywords"]
    if ", " in kw or kw != kw.strip() or ",," in kw: err.append(f"{l} kw spacing")
    terms = kw.split(",")
    if len({t.lower() for t in terms}) != len(terms): err.append(f"{l} kw dup")
    ns = m["name"].replace(": CutSense", "") + " " + m["subtitle"]
    ntok = {t.lower() for t in re.findall(r"[^\s,:،.]+", ns)} - {"jump", "cut", "auto"} | {"jump", "cut", "auto"}
    for t in terms:
        if re.search(r"tiktok|capcut|youtube|filler|\bAI\b|cutsense", t, re.I): err.append(f"{l} kw banned {t}")
        for w in re.findall(r"[^\s,:،.]+", t.lower()):
            if w in ntok: err.append(f"{l} kw '{t}' repeats name/subtitle '{w}'")
        if l in CJK:
            grams = {ns[i:i+2] for i in range(len(ns) - 1) if ns[i].isalpha() and ns[i+1].isalpha()}
            hit = [g for g in grams if g in t]
            if hit: err.append(f"{l} kw '{t}' overlaps {hit}")
    for k in ("promotionalText",):
        pass
    print(f"{l:8}{len(m['name']):5}{len(m['subtitle']):5}{len(kw):5}{len(m['description']):6}{len(m['promotionalText']):6}{len(m['whatsNew']):6}")
if err:
    print("FAIL"); print("\n".join(err)); sys.exit(1)
print("OK: 26 locales, all limits and rules pass")

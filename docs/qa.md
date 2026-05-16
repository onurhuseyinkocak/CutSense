# CutSense QA Checklist

## Test Matrix

| Scenario | Status |
|----------|--------|
| 10s video | - |
| 30s video | - |
| No-audio video | - |
| Landscape video | - |
| Square video | - |
| Bright background | - |
| Dark background | - |
| Low storage | - |
| Export cancel | - |
| Photos permission denied | - |
| Transcription fail | - |

## Mandatory Test Transcript

```
"Bugun size DidntHappen'i anlaticam... olmadi bastan aliyorum...
DidntHappen kaygilarinizi takip eden bir uygulama... eee sey...
gerceklesmeyen kaygilarinizi gosteriyor... bunu kes...
en guclu tarafi su... bu strateji olmadi cunku kullanici tutmadi
dersek sistem bunu kesmemeli... dur demeyi ogrenmek bazen onemli...
dur dur tekrar alayim... asil olay su, kayginin gerceklikle
arasindaki farki goruyorsun."
```

### Expected Behavior
- CUT: failed intro
- CUT: "olmadi bastan aliyorum"
- CUT: filler damaging rhythm
- CUT: "bunu kes"
- KEEP: "bu strateji olmadi cunku kullanici tutmadi" (content)
- KEEP: "dur demeyi ogrenmek bazen onemli" (content)
- CUT: "dur dur tekrar alayim"
- KEEP: "asil olay su..." (reveal)

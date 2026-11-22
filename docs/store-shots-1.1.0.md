# App Store screenshots 1.1.0 (Fable plan)

**Karar:** Mevcut `en-US-110` seti çöpe gider: lime vurgulu, 1290x2796 ve eski arayüzden. Yeni set 6 kare, 1320x2868, saf siyah-beyaz-gri, cihaz çerçevesiz ve sıfır kırmızı (kırmızı yalnız teklif içindir, sette teklif yok).

- **Ortak fikir, "tek dalga, altı kare":** demo klibin gerçek ses verisinden çizilen tek bir dalga şeridi altı karenin hepsinden kesintisiz geçer; kesilen duraklamalar soluk noktalarla görünür. Arama sonucunda ilk 3 kare yan yana tek panorama gibi okunur ve uygulama ikonundaki çubuk motifini tekrarlar.
- **Çerçeve yok:** uygulama zemini #000 olduğu için ham simülatör görüntüsünün alt kısmı tuvale 1:1, aynı koordinata yapıştırılır. Üstteki 1060 px (durum çubuğu, araç çubuğu, oynatıcının çoğu) başlık ve dalga ile değişir.
- **Yüz yok:** setteki hiçbir karede tanınabilir kişi olmayacak. CC BY yalnız telifi kapsar, kişilik hakkını ve "bu kişi uygulamayı öneriyor" izlenimini kapsamaz; atıf da mağaza görseline sığmaz. Gözlüklü adam klibinin (`shots-110/fixture-silence.mp4`) kaynağı da bulunamadı, kullanılmaz.
- **Demo klip:** tek amaçlı bir klip üretilir. Ses `07_lecture.mov` 243–288 s aralığıdır (45 s'de 8 duraklama, yaklaşık 10,4 s sessizlik; `silencedetect -35dB d=0.85` ölçümü). Görüntü Pexels'ten kişisiz dikey bir mikrofon/masa klibidir.
- **Sıra:** arama sonucu 3 kare gösterdiği için güven 3. sıraya alındı; kanıt 1. karenin içindeki gerçek rakamlardır.

Tuzak: `CUTSENSE_FORCE_PRO` ücretsiz karelerde kullanılmaz; Fine-tune kilidini açar ve tutma sayacını gizler.

**Çekim listesi** (başlık satır 1 beyaz, satır 2 #A3A3A3)

| # | Rol | Başlık | Alt satır | Ekran / durum | Ham dosya |
|---|---|---|---|---|---|
| 1 | Kanca + kanıt | Cut the silence. / Keep the talk. | Free. No watermark. No sign-up. | Review, ücretsiz, Balanced | `raw_1_review.png` |
| 2 | Kontrol | You approve / every cut. | Keep any pause before you save. | Cut list sheet, 2 duraklama tutulmuş, "Kept 2 of 3. Unlimited with Pro." görünür | `raw_2_cuts.png` |
| 3 | Güven | Private / by design. | Your video never leaves your iPhone. | Home, ücretsiz | `raw_3_home.png` |
| 4 | Kanıt + kontrol | Balanced, Tight / or Hardcore. | Pick how tight the cut feels. | Review, ücretsiz, Tight seçili | `raw_4_tight.png` |
| 5 | Pro | Fine-tune / every pause. | Set minimum pause and breathing room. | Review + Fine-tune sheet, Pro | `raw_5_finetune.png` |
| 6 | Pro | Pay once. / No subscription. | Free with ads. Pro removes them for good. | Paywall, ücretsiz, CTA üstünden kırpılmış | `raw_6_paywall.png` |

İlk 3 öncelik: 1 sonucu ve rakamı, 2 rakiplerden ayıran kontrolü, 3 fiyat/gizlilik itirazını karşılar. Hepsi yalnız başlıktan okunmalı.

**Adımlar:**

1. **Demo klip.** Çalışma dizini `/private/tmp/claude-501/-Users-jinx/c6915351-0541-4085-8acb-38700776b4dc/scratchpad/store-110b/`.
   - Pexels'ten bir klip indir: dikey (9:16), en az 1080x1920, mikrofon ya da masa yakın çekimi. Hiçbir karede insan, el, yüz, marka logosu ya da yazı olmayacak.
   - 0, 15, 30 ve 44. saniye karelerini çıkarıp gözle bak; biri şartı bozuyorsa başka klip seç.
   - Pexels URL'sini `real-videos/SOURCES.md` dosyasına ekle.
   - Birleştir: `ffmpeg -stream_loop -1 -i pexels.mp4 -ss 243 -t 45 -i real-videos/07_lecture.mov -map 0:v -map 1:a -vf "scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,fps=30" -c:v libx264 -crf 18 -c:a aac -ar 48000 -t 45 -map_metadata -1 demo_en.mp4`

2. **Yakalama testi.** Geçici dosya: `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Tests/UI/StoreShotsUITests.swift`. `Tests/UI` zaten `project.yml` kaynağı; `xcodegen` gerekiyorsa çalıştır. `snapshot` yardımcısını `OfferFlowUITests.swift:712`'den kopyala.
   - Ortak launch argümanları: `-app_language en -AppleLanguages (en) -onboarding_done_v1 YES -ad_free_until <now+3600>`.
   - Ortak env: `CUTSENSE_DISABLE_ADS=1`, `CUTSENSE_SKIP_ONBOARDING=1`.
   - Kare 1, 2, 4: ek env `CUTSENSE_AUTORUN_VIDEO_URL=<demo_en.mp4 mutlak yolu>`. `saveButton` bekle, `Balanced` seçili değilse seç, 2 s bekle, `raw_1_review` al.
   - Kare 2: `reviewCutsButton`'a dokun, `keepLimitButton` bekle, `cutToggle_1` ve `cutToggle_2`'ye dokun, 1 s bekle, snapshot. Sheet orta detent'te kalır.
   - Kare 4: sheet'i `swipeDown` ile kapat, iki toggle'ı geri alma, `Tight`'a dokun, 3 s bekle, snapshot.
   - Kare 3: AUTORUN yok, ana ekran, 2 s bekle, snapshot.
   - Kare 5: AUTORUN + `CUTSENSE_FORCE_PRO=1`; `saveButton` bekle, `fineTuneButton`'a dokun, 1 s bekle, snapshot. Kaydırıcılara dokunma.
   - Kare 6: `CUTSENSE_SHOW_PAYWALL=1`, FORCE_PRO yok; 2 s bekle, snapshot. Karşılaştırma tablosu 6 satır olmalı.

3. **Çalıştır ve dışa aktar.** Simülatör yalnız `3C9044C5-36C3-4899-BAEB-6A9563BB790E` (iPhone 17 Pro Max, adı "Promtable ..."). Önce başka bir `xcodebuild test` süreci var mı bak; varsa bekle.
   - Önce: `xcrun simctl status_bar <udid> override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3`.
   - Test: `xcodebuild test -scheme CutSense -destination id=<udid> -only-testing:CutSenseUITests/StoreShotsUITests -resultBundlePath store-110b/shots.xcresult`.
   - Dışa aktar: `xcrun xcresulttool export attachments --path shots.xcresult --output-path store-110b/att`, dosyaları `raw_N_*.png` adlarına taşı.
   - Sonra: `xcrun simctl status_bar <udid> clear`.

4. **Ham görüntü kabulü.** Altı PNG'ye tek tek bak; her biri 1320x2868 olmalı.
   - Hiçbirinde "Test mode", reklam kartı, Türkçe metin ya da "PRO" kapsülü (kare 5 hariç) yok.
   - Kare 1'de kesim sayısı en az 5 ve "removed" %12–40 arasında. Değilse rakamla oynama: 1. adımdaki ses penceresini 242'ye kaydırıp yeniden üret.
   - Kare 2'de görünen toggle'lardan ikisi "Keep", sayaç "Kept 2 of 3".
   - Kare 6'da y=1060 altında fiyat içeren CTA'nın yeri ölç.

5. **`compose.py`'yi yeniden yaz.** Dosya: `/Users/jinx/Documents/projeler/CutSense/ios/metadata/screenshots/compose.py`. Yalnız PIL + stdlib; argümanlar `S` (ham dizin) ve klip yolu.
   - **Tuval:** `W,H=1320,2868`, zemin (0,0,0); gradyan, gölge, çerçeve yok.
   - **Font:** `/System/Library/Fonts/SFNS.ttf`, `set_variation_by_axes([width, opsz, grad, weight])`.
     - Başlık: `[100,96,400,700]`, 132 px, satır aralığı 146, sola hizalı x=88, ilk satır üstü y=170.
     - Alt satır: `[100,28,400,400]`, 54 px, #A3A3A3, x=88, başlık bloğunun altı + 36.
     - `textlength > 1144` ise boyutu 4'er px düşür; 112 px altına inerse `assert` ile dur.
   - **Dalga şeridi:** klip sesini `ffmpeg -i clip -ac 1 -ar 8000 -f s16le -` ile oku.
     - 180 kova (0,25 s), kova başına RMS; 95. yüzdeliğe böl, 1'e kırp, `pow(v,0.6)`, taban 0,06 (tasarım dokümanı §3 `MonoWave.bars` formülü).
     - Normalize değeri art arda en az 4 kova boyunca 0,12 altındaysa "kesik".
     - Kare k (0..5), `bars[k*30:(k+1)*30]` çizer: slot 44 px, çubuk genişliği 22, tam yuvarlak, merkez y=880, yükseklik `max(22, v*240)`, beyaz.
     - Kesik kova: 10 px çaplı nokta, #3A3A3A. Çubuklar slot ortasında olduğu için dikiş hiçbir çubuğu kesmez.
   - **Arayüz yapıştırma (kare 1–5):** `raw.crop((0,1060,1320,2868))` tuvalin (0,1060) noktasına. Üst kenarda 140 px'lik doğrusal alfa maskesi (0'dan 255'e), oynatıcı şeridi siyaha erisin.
   - **Kare 3 istisnası:** ana ekranın kendi dalga görseli şeritle çakışır. Kırpmanın üstünü uygulamadaki "CutSense" yazısının 40 px üstüne al (ölç), aynı y'ye yapıştır. Aradaki boşluğa x=88, y=1100'den üç kapsül alt alta: "No upload", "No account", "No watermark". Kapsül: yükseklik 112, aralık 28, 2 px çizgi (255,255,255,56), metin `/System/Library/Fonts/SFNSMono.ttf` 50 px beyaz. Kapsüller kırpmanın üstüne taşarsa aralığı azalt.
   - **Kare 5 rozeti:** başlığın üstüne (x=88, y=96) beyaz dolu kapsül, 60 px yüksek, siyah "PRO", SFNSMono 34 px. Bu karede başlık y=190'dan başlar.
   - **Kare 6:** kırpma üstü "CutSense Pro" üst yazısının 40 px üstü, altı beyaz Pro sütununun altı + 60 px (ikisini de ölç). y=1080'e yapıştır; yükseklik 1740'ı aşarsa LANCZOS ile küçült ve yatay ortala. Kırpma içinde "$" ya da "Unlock" geçmeyecek. Aynı "PRO" rozeti kullanılır.
   - **Kare 1 açıklaması:** şeritte ilk kesik bölgenin ortasının altına (y=1010) SFNSMono 30 px #808080 "cut"; en yüksek çubuğun altına "kept". Başka açıklama yok.
   - **Çıktı:** `/Users/jinx/Documents/projeler/CutSense/ios/metadata/screenshots/en-US-110/01_hook.png` … `06_pro.png` ve `contact.png` (altısı yan yana, her biri 300 px genişlikte). Dosya sonunda boyut `assert`'i.
   - Eski dört PNG silinir. `en-US/` klasörüne dokunma.

6. **Temizlik.** `StoreShotsUITests.swift` silinir, `shots.xcresult` ve `att` kaldırılır. `demo_en.mp4` kalır; sonraki dil setleri aynı klibi kullanır.

**Dokunma:**
- Uygulama kaynak kodu, `Translations.swift`, `Products.storekit`, `version-1.1.0.json`. Başlıklar mevcut açıklamayla zaten uyumlu.
- Onboarding ekranları sette kullanılmaz: sayfa 2 İngilizcesi "Keep a pause with one tap" içeriyor (`OnboardingView.swift:152`).
- History ekranı kullanılmaz: seed verisinin küçük resimleri boş gri kutu.
- Simülatörde Promtable uygulaması ve verisi; simülatörü silme ya da sıfırlama. Başka oturumun süreçlerini öldürme.
- Fiyat, indirim, "one tap", "100%", `#FF453A` ve lime `(182,243,92)` hiçbir karede yer almaz.

**Doğrulama:**
- `python3 ios/metadata/screenshots/compose.py <S> <demo_en.mp4>` hatasız biter; `sips -g pixelWidth -g pixelHeight en-US-110/0*.png` hepsinde 1320 ve 2868 verir.
- `contact.png` gözle: dalga dikişlerde kesintisiz, ilk 3 başlık 300 px genişlikte okunuyor.
- Tam boy altı PNG gözle: reklam yok, "$" yok, Türkçe yok, yüz yok, kare 2'de "Kept 2 of 3", kare 5 ve 6'da "PRO" rozeti, kare 6'da 6 satır.
- Hata yolu: `demo_en.mp4` yolu yanlışsa uygulama "failed" ekranına düşer ve `saveButton` beklemesi testi düşürür; bu durumda görüntü üretilmemeli.
- `python3 ios/metadata/check_version_metadata.py` ve `check_global.py` hâlâ hatasız.

**Risk:**
- UNVERIFIED: uygulamanın demo klipte vereceği gerçek yüzde ve kesim sayısı. Benim ölçüm ffmpeg `silencedetect` ile; uygulamada çalıştırmadım.
- UNVERIFIED: `CUTSENSE_DISABLE_ADS=1` ücretsiz Review'da "Ad break" kartını da kaldırıyor mu. `AdMobService.isEnabled` bunu kapatıyor görünüyor, ekranda denemedim; kart çıkarsa `skipAdButton`'a dokun.
- UNVERIFIED: simülatörün `/private/tmp` altındaki mutlak yolu okuyabildiği. Kod `/` ile başlayan yolu kabul ediyor; okuyamazsa klibi `simctl get_app_container ... data` altındaki `Documents/qa-run/` klasörüne kopyala ve göreli yol ver.
- UNVERIFIED: ders sesinin (CC BY) yalnız dalga biçimi olarak görünmesi atıf gerektirir mi. Ses dağıtılmıyor, risk düşük. Sıfır risk istenirse aynı klip sahibin kendi 45 saniyelik ses kaydıyla yeniden üretilir.
- UNVERIFIED: kare 3 ve 6'daki kırpma sınırları ile orta detent'te sayaç satırının görünür kalması. Reklamsız, klampsız güncel görüntüm yok; executor ölçecek.
- Yan bulgu: uygulama içi onboarding metni "one tap" diyor. Mağaza yasak listesi metadata içindir, ama owner aynı kuralı uygulama metnine de istiyorsa ayrı iş.

Atlanan: Pexels klibini ben seçmedim, yalnız ölçüt verdim. Diğer 12 dilin seti kapsam dışı.
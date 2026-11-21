**Karar:** 1.1.0'a 22 küçük detay düzeltmesi girsin (aşağıdaki tabloda "1.1.0"), ilk 15'i üç builder görevine bölündü. Kural: efor S/M, yeni izin yok, StoreKit/reklam zamanlaması/şema değişmez, 16e yükseklik bütçesine tek satır eklenmez. Motor (`QuickSilenceEngine`) iki yerde bilerek açılır: yalnız Görev C, #18 hata metni ve #22 ilerleme aralığı. Teklif akışı (onboarding sonunda welcome, 600 sn sonra flash) commit `cb4c050` ile sahibin kararı; dokunulmaz, yalnız işaretlendi.

Builder'lar için kritik uyarı: `QuickSilenceView.swift` ve `ReviewScreen.swift` denetim sırasında başka ajan tarafından değişti (918→931 ve 949→951 satır). Satır numarası kullanılmaz, yalnız fonksiyon ve metin çapası.

**Adımlar:**

## 1. Sıralı tablo

Efor S/M/L. Etki: T = tutunma, P = puan, G = gelir. Görev: A/B/C aşağıda.

| # | An | Kullanıcı ne görüyor, neden kaybediyor | Düzeltme | Efor | Etki | Sürüm | Görev |
|---|---|---|---|---|---|---|---|
| 1 | Import | Yerel video dahil her videoda "Downloading iCloud video" yazıyor: `VideoImportService.loadMovie` ilerlemeyi hep ≥0 yapıyor, `QuickSilenceView.importVideo` bunu iCloud sayıyor | Başlık "Preparing video"; iCloud metni yalnız 3 sn sonra hâlâ <1 ise | S | P | 1.1.0 | A |
| 2 | Save | Fotoğraflar izni export bittikten sonra isteniyor; red olursa çıktı siliniyor, tekrar tam export | İzin export'tan önce | S | P, T | 1.1.0 | A |
| 3 | Dönen kullanıcı | Sertlik her açılışta Balanced'a dönüyor (`@State`) | `@AppStorage("cut_intensity")` | S | T | 1.1.0 | A |
| 4 | Pro | İnce ayar her yeni videoda ve her seviye değişiminde siliniyor; özel ayar aktifken kontrol hâlâ "Balanced" gösteriyor | Değerleri sakla ve yeniden uygula; ipucu satırında "Custom fine-tune" | M | G, P | 1.1.0 | A+B |
| 5 | Save→Share | Kaydettikten sonra Paylaş videoyu baştan export ediyor; paylaşılan dosya adı `cutsense-<UUID>.mp4` | Çıktıyı plan değişene kadar tut; ad `cutsense-yyyyMMdd-HHmmss.mp4` | S | T | 1.1.0 | A |
| 6 | Kayıt sonrası | "Saved to Photos" yazıyor, gidecek yer yok | "Open Photos" düğmesi | S | T, P | 1.1.0 | A+B |
| 7 | Review | Seviyelerin KENDİ videosuna ne yaptığını görmek için tek tek basmak gerekiyor | Her segmentin altında o seviyenin yeni süresi | M | T | 1.1.0 | A+B |
| 8 | Review | Önizlemenin kesilmiş hâl olduğu yazmıyor; orijinalle karşılaştırma yalnız kesim listesinde | Video üstünde basılı tut: orijinal | M | T, P | 1.1.0 | B |
| 9 | Processing | Ne kadar süreceği, uygulamadan çıkılıp çıkılamayacağı yazmıyor; uzun analizde ekran kilitlenebiliyor (idle timer yalnız export'ta kapalı) | Alt satır + kalan süre + idle timer | S | T | 1.1.0 | A |
| 10 | Export | Uygulamadan çıkınca export ölüyor; overlay'de süre yok | `beginBackgroundTask` + kalan süre | S | P | 1.1.0 | A+B |
| 11 | Review | Kaydetmeden önce çözünürlük ve boyut bilinmiyor | "New Video" satırında "1080p · ≈48 MB" | S | T | 1.1.0 | A+B |
| 12 | Review | Sıfır kesimde ekran %0 gösterip susuyor | İpucu: "Try Tight" | S | P | 1.1.0 | B |
| 13 | Review | Seviye ya da ince ayar değişince önizleme başa dönüyor | Oynatma konumunu koru | S | T | 1.1.0 | B |
| 14 | Review | Elle tut/kes seçimi yapılmışken "New Video" tek dokunuşla hepsini siliyor (Save'in hemen altında) | Yalnız elle değişiklik varsa onay | S | P | 1.1.0 | B |
| 15 | Review | "0:12 silence" belirsiz; soluk çubukların "kesilecek" olduğu yazmıyor | Etiket "shorter"; zaman satırında lejant | S | T | 1.1.0 | B |
| 16 | Settings | Depolama satırı "Zero KB" yazıyor (`SettingsScreen` `ByteCountFormatter.string`) | "0 KB" | S | cila | 1.1.0 | C |
| 17 | Settings | Puan vermenin yolu yok | "Rate CutSense" satırı | S | P | 1.1.0 | C |
| 18 | Export hatası | "The iOS export engine did not produce an output…" ve "(%lld bytes)" mühendis dili | Sade metin | S | P | 1.1.0 | C |
| 19 | Import hatası | Disk doluyken import "could not be loaded" diyor | Boş alan <300 MB ise depolama mesajı | S | P | 1.1.0 | A |
| 20 | Kesim listesi (ek) | Uzun videoda 60+ satır; en çok kazandıran kesimler aranıyor | Sıralama: zaman / en uzun | S | T | 1.1.0 | B |
| 21 | Fine-tune sheet | Sıfırlama yok | "Reset" (tertiary) | S | G | 1.1.0 | B |
| 22 | Processing | Yüzde, yerel videoda %4'te bekleyip %40'a sıçrıyor | Analiz aralığını 0.1…1.0'a genişlet | S | cila | 1.1.0 | C |
| 23 | Failed | "Try Again" tekrar denemiyor, ana ekrana dönüyor | Düğme doğrudan picker açsın; `EdgeCaseUITests` etikete ve ana ekrana dönüşe bağlı, testle birlikte değişir | M | P | sonraki | n/a |
| 24 | Review girişi | Sonucun ilk saniyelerinde reklam kartı; sesli otomatik oynatma kart çözülene kadar bekliyor | Sahip kararı; ölçüp karar ver (kartı ilk oynatma bitince göster) | M | T, G | sonraki | n/a |
| 25 | Paywall | Kilitli "Fine-tune" ne yaptığını göstermeden paywall açıyor | Kilitliyken sheet'i demo modda aç (slider oynar, uygulama kilitli) | M | G | sonraki | n/a |
| 26 | Home | Video seçmeden önce sertlik soruluyor; ilk kullanıcı "Hardcore" nedir bilmiyor | #3 ve #7 girince home'daki kontrolü kaldırmayı dene | S | T | sonraki | n/a |
| 27 | Export | Uzun export'ta uygulamada beklemek zorunlu | Bildirimli arka plan export / Live Activity (yeni izin) | L | T | sonraki | n/a |
| 28 | Share | Hedef uygulamaya göre ipucu ya da hazır açıklama yok | Önerilen caption | M | T | sonraki | n/a |
| 29 | Kesim listesi | Kesimleri sırayla dinletme yok | "Play all cuts" | M | T | sonraki | n/a |
| 30 | Review | Kesim kenarı sürüklenemiyor, dalga formu yakınlaşmıyor | Tasarım dokümanındaki "Next" kalemi | L | T | sonraki | n/a |
| 31 | Review | Toggle'larda geri al yok | Undo | M | P | sonraki | n/a |
| 32 | Önizleme | Oynatırken kesim atlamasında haptik yok | Reddedildi: 60 kesimde titreşim gürültü olur | n/a | n/a | yok | n/a |
| 33 | Review | Sessiz moddayken ses açık otomatik oynuyor (`.playback`) | Sahip kararı; yalnız işaretlendi | n/a | P | yok | n/a |
| 34 | Onboarding | Değer görülmeden welcome teklifi | Sahip kararı (`cb4c050`); dokunma | n/a | G | yok | n/a |

## 2. Yeni metin anahtarları

EN ve TR çağrı yerinde; diğer 7 dili yalnız Görev A `Services/Translations.swift`'e ekler. Önce `grep` ile mevcut anahtar aranır ("Original", "Cancel" zaten var).

| # | EN | TR | Kullanan |
|---|---|---|---|
| K1 | Preparing video | Video hazırlanıyor | A |
| K2 | Keep CutSense open. Your video stays on this iPhone. | CutSense'i açık tut. Videon bu iPhone'dan çıkmaz. | A |
| K3 | About %@ left | Yaklaşık %@ kaldı | A, B |
| K4 | Open Photos | Fotoğraflar'ı Aç | B |
| K5 | Photos access is off. Allow it in Settings to save. | Fotoğraflar izni kapalı. Kaydetmek için Ayarlar'dan izin ver. | A |
| K6 | Hold for original | Orijinal için basılı tut | B |
| K7 | Dim bars are cut | Soluk çubuklar kesilir | B |
| K8 | No pauses long enough to cut. Try Tight. | Kesilecek kadar uzun duraklama yok. Sıkı'yı dene. | B |
| K9 | No pauses to cut in this video. | Bu videoda kesilecek duraklama yok. | B |
| K10 | Custom fine-tune. Pick a level to reset. | Özel ince ayar. Sıfırlamak için bir seviye seç. | B |
| K11 | Discard your changes? | Değişiklikler silinsin mi? | B |
| K12 | Your keep and cut choices will be lost. | Tut ve kes seçimlerin kaybolur. | B |
| K13 | Discard and start new | Sil ve yeni video seç | B |
| K14 | shorter | daha kısa | B |
| K15 | Rate CutSense | CutSense'i Değerlendir | C |
| K16 | Couldn't create the video. Try again, or switch to Balanced. | Video oluşturulamadı. Tekrar dene ya da Dengeli'ye geç. | C |
| K17 | Not enough free storage to import this video. Free up some space and try again. | Bu videoyu içe aktarmak için yeterli boş alan yok. Biraz yer açıp tekrar dene. | A |
| K18 | Longest first | Önce en uzun | B |
| K19 | Reset | Sıfırla | B |

## 3. Builder görevleri

Sıra: mevcut audition işi biter → A (seam dahil) → B. C, A ile paralel yazılır. Build'ler seri alınır (tek DerivedData).

### Görev A: akış ve durum
Dosyalar:
- `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/QuickSilence/QuickSilenceView.swift`
- `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/QuickSilence/MonoKit.swift`
- `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Video/PhotosSaveService.swift`
- `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Services/Translations.swift`
- `ReviewScreen.swift` içinde yalnız A0 seam satırları

**A0. Seam (ilk iş).** `ReviewScreen`'de `let fineTune: FineTuneAccess` satırından hemen sonra, bu sırayla:
```swift
let sourceInfo: ReviewSourceInfo?
let presetLengths: [QuickSilenceEngine.CutIntensity: Double]
let onOpenPhotos: () -> Void
```
`ReviewScreen.swift` sonuna: `struct ReviewSourceInfo: Equatable { let pixelSize: CGSize; let fileBytes: Int64 }`. `QuickSilenceView.review(...)` çağrısında aynı sırayla geçilir.

**A1 (#1).** `importVideo(_:jobID:)` içindeki tracker:
- Döngüden önce `let started = Date.now`.
- `download >= 0` dalı yalnız `download < 1 && Date.now.timeIntervalSince(started) > 3` iken mevcut iCloud başlığını kullanır.
- Diğer durumda K1 ile `applyProgress(0.04, …)`.
- `handlePick`'teki ilk "Importing video" de K1 olur.

**A2 (#2).**
- `PhotosSaveService`'e `static func ensureAddAccess() async -> Bool` eklenir; `saveVideo` içindeki mevcut status/request bloğu buraya taşınır ve `saveVideo` bunu çağırır.
- `startSave` başı: `guard exportTask == nil else { return }`, sonra `Task { guard await PhotosSaveService.ensureAddAccess() else { saveError = K5; saveNeedsSettings = true; return }; runExport { … } }`.

**A3 (#3).**
- `@State private var cutIntensity … = .balanced` → `@AppStorage("cut_intensity") private var cutIntensity: QuickSilenceEngine.CutIntensity = .balanced`.
- `cutSettings` başlangıcı `.task` içinde `cutSettings = CutSettings(cutIntensity)` ile eşitlenir.

**A4 (#4).**
- Yeni `@AppStorage`: `finetune_active` (Bool), `finetune_min_silence` (Double), `finetune_pad` (Double).
- `FineTuneSheet` `onCommit` closure'ında: üç değer yazılır, `finetune_active = true`.
- `onChange(of: cutIntensity)` içinde `finetune_active = false`.
- `analyzeAndReview`'da `cutSettings = CutSettings(cutIntensity)` satırından sonra: `if store.isPro, finetuneActive { cutSettings.minSilence = …; cutSettings.pad = … }`.

**A5 (#5).**
- `startSave` başarı dalından ve `startShare` `onFinish`'inden `session.discardOutput()` kaldırılır. Hata dalları ve `review` içindeki `onChange(of: plan)` silmesi kalır.
- `runExport` başına: `if let url = session.outputURL, FileManager.default.fileExists(atPath: url.path) { exportTask = Task { await finish(url); exportTask = nil }; return }`.
- Export sonucu `tmp/cutsense-<yyyyMMdd-HHmmss>.mp4` adına `moveItem` ile taşınır, sonra `session.setOutput(newURL)`. `cutsense-` öneki `WorkFiles.isManaged` için zorunlu.

**A6 (#6).** `onOpenPhotos: { if let url = URL(string: "photos-redirect://") { UIApplication.shared.open(url) } }`.

**A7 (#7).**
- `@State private var presetLengths: [QuickSilenceEngine.CutIntensity: Double] = [:]`.
- `analyzeAndReview`'da `analysis = result`'tan sonra her `CutIntensity.allCases` için `try? QuickSilenceEngine.plan(result, settings: .init(i)).outputDuration`. `endVideo`'da boşaltılır.
- `MonoIntensityControl`'e `var sublabels: [QuickSilenceEngine.CutIntensity: String] = [:]` eklenir (varsayılanlı, home çağrısı değişmez).
- Segment etiketi `VStack(spacing: 0)`: başlık 14 semibold, altında varsa 10 pt medium monospaced (seçiliyken siyah %60, değilken `Mono.C.text3`). Track 44 kalır.

**A8 (#9).**
- `.working` görünümünde `state.title` altına K2 (`caption`, `text3`, ortalı, 2 satır).
- Altına kalan süre: `@State private var analysisStarted: Date?`; `applyProgress`'te `fraction >= 0.4` ilk kez görülünce set, `endVideo`'da nil. Geçen > 3 sn ve kalan > 5 sn ise `String(format: K3, timeString(kalan))`; kalan = `geçen × (1 − p) / (p − 0.4)`.
- `onChange(of: phaseKey)`: `UIApplication.shared.isIdleTimerDisabled = key == 1 || exportTask != nil`.

**A9 (#10).** `runExport` Task'i içinde `let bg = UIApplication.shared.beginBackgroundTask { exportTask?.cancel() }`; mevcut `defer`'e `UIApplication.shared.endBackgroundTask(bg)`.

**A10 (#11).** `analyzeAndReview`'da `VideoMetadataService.extract(from: inputURL)` ile `sourceInfo = ReviewSourceInfo(pixelSize: meta.resolution, fileBytes: meta.fileSize)`; `endVideo`'da nil.

**A11 (#19).** `importVideo`'daki `importService.error` dalında: hata `.loadFailed` ve `WorkFiles.availableBytes()` 1…300 MB arasındaysa K17 fırlatılır.

**A12.** K1–K19 için 7 dil satırı.

### Görev B: review ekranı (audition görevine ek)
Dosya: `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/QuickSilence/ReviewScreen.swift`

**B1 (#8) Basılı tut: orijinal.**
- `CutAuditioner`'a `private(set) var isComparing = false` ve iki fonksiyon:
  - `beginCompare(at:preview:)`: `stop(preview:)`, `isComparing = true`, `original` sıfır toleransla `at`'e seek edip oynar.
  - `endCompare(preview:)`: `original.pause()`, `isComparing = false`, `preview.scrub(toOriginal: original.currentTime().seconds)`, `preview.player.play()`.
- `isShowingOriginal` → `isComparing || (activeID != nil && mode == .before)`.
- `ReviewScreen.onAppear`'a `auditioner.prepare(url: inputURL)` eklenir (sheet'teki kalır).
- `videoStage`'e `.overlay(alignment: .trailing)`, padding 10: kapsül, 13 medium, yükseklik 36, min 44 hit, `Color.black.opacity(0.7)` zemin, metin K6. Basılıyken beyaz zemin, siyah "Original".
- Jest: `DragGesture(minimumDistance: 0)`; `onChanged` ilk seferde `beginCompare(at: preview.originalTime, …)`, `onEnded`'de `endCompare`. Başlangıçta `.impact(flexibility: .soft)`.
- Şu durumlarda gizli: `isExporting`, `preview.isLoading`, `auditioner.activeID != nil`.
- VoiceOver: `.accessibilityAction` aç/kapa.

**B2 (#7).** `MonoIntensityControl(…, sublabels: presetLengths.mapValues(timeString))`.

**B3 (#4, #12) `hint`.** Öncelik sırası:
1. `!usesPresetSettings` → K10.
2. `plan.cuts.isEmpty` → `intensity == .hardcore ? K9 : K8`.
3. Mevcut iki kural.

**B4 (#13).** `.task(id: plan)` içinde `let seek = pendingSeek ?? (preview.originalTime > 0.5 ? preview.originalTime : nil)`.

**B5 (#6, #11) Alt satır.** "New Video" düğmesi 40 pt yüksek bir `HStack`'e alınır, yükseklik değişmez:
- Solda `saved` ise K4 tertiary düğme (beyaz, id `openPhotosButton`, `onOpenPhotos`).
- `saved` değilse `sourceInfo` varsa `overline`, `text3` metin: `"\(etiket) · ≈\(boyut)"`.
  - etiket = `min(w, h) >= 2160 ? "4K" : "\(Int(min(w, h)))p"`.
  - boyut = `ByteCountFormatter(fileBytes × plan.outputDuration / plan.duration)`.
- `Spacer`, sağda mevcut `newVideoButton`.

**B6 (#14).**
- `newVideoButton` aksiyonu: `(!saved && (plan.cuts.contains(where: \.isRestored) || !usesPresetSettings))` ise `confirmationDialog` (başlık K11, mesaj K12, destructive K13 → `onNewVideo`, Cancel). Değilse doğrudan `onNewVideo`.
- Değişiklik yokken diyalog çıkmaz; `testDoubleTapNewVideoAndChooseVideo` bozulmaz.

**B7 (#15).**
- `timeStat(silence, …)` etiketi "silence" → K14. Süre `Text`'i ayrı kalır.
- Zaman satırında iki süre arasına ortalı K7 (`overline`, `text3`); `compacted` iken gizli.

**B8 (#10).** `ExportOverlay`'de `@State private var started = Date.now`. Geçen > 2 sn ve `progress > 0.08` iken "Keep the app open." altına K3 satırı; kalan = `geçen × (1 − p) / p`.

**B9 (#20, #21).**
- `CutListSheet`: `@State private var longestFirst = false`. Keep all / Cut all satırının altına 36 pt yüksek tek tertiary düğme, başlık K18, seçiliyken beyaz. `ForEach` kaynağı `longestFirst` ise uzunluğa göre azalan sıralı indeksler.
- `FineTuneSheet`'e `let preset: QuickSilenceEngine.CutSettings` parametresi. Başlık satırının sağına K19 tertiary: `draft = preset; onCommit(preset)`.
- Detent `.height(300)` kalır. Bu imza değişikliği `QuickSilenceView`'daki tek çağrıyı kırar: B, A'dan sonra o satıra `preset: .init(cutIntensity)` ekler.

### Görev C: ayarlar ve hata metni
Dosyalar:
- `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/UI/SettingsScreen.swift`
- `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/QuickSilence/QuickSilenceEngine.swift` (yalnız metin ve ilerleme sabiti)

**C1 (#16).** Depolama değeri: `usage == 0 ? "0 KB" : ByteCountFormatter.string(…)`.

**C2 (#17).** "About" bölümünde Support'tan sonra `Link`, glif `star`, başlık K15, hedef `https://apps.apple.com/app/id6770024868?action=write-review`. Mevcut `link(…)` yardımcısı site yolu aldığı için aynı satır yapısı elle kurulur.

**C3 (#18).** `Failure.message`: `.exportFailed`, `.outputEmpty` ve `.timelineInsertFailed` üçü de K16 döndürür.

**C4 (#22).** `QuickSilenceView.analyzeAndReview`'daki eşleme sabiti A'nın dosyasında olduğu için bu kalemi A uygular: A1 sonrası import sabit 0.04'te kalacağından `0.4 + … * 0.6` → `0.1 + … * 0.9`; A8'deki `0.4` eşikleri `0.1` olur.

**Dokunma:**
- `ProStore`, `OfferCenter`, `OfferView`, `PaywallView`, `OnboardingView`: teklif ve fiyat mantığı, `pro_unlocked` entitlement.
- `AdMobService`, `AdFreePass`, `NativeAdCard`, `startResultAdBreakIfNeeded` gövdesi, rating prompt zamanlaması.
- `Info.plist`, `project.yml`, `WorkFiles.swift` (yeni dosya adı `cutsense-` önekiyle uyumlu, değişiklik gerekmez).
- `QuickSilenceEngine`: kesim planlama, export ve analiz mantığı. Yalnız C3 metni değişir.
- Erişilebilirlik kimlikleri ve test etiketleri: "Saved to Photos", "Try Again" (ana ekrana döner), `newVideoButton`, `saveButton`, `cutToggle_*`. Stat süreleri ayrı `Text` kalır.
- Review dikey bütçesi: hiçbir kalem yeni satır eklemez. Video min 220 pt korunur.

**Doğrulama:**
- **Build ve test:** `cd /Users/jinx/Documents/projeler/CutSense/ios && xcodegen generate && xcodebuild test -scheme CutSense -destination 'id=3C9044C5-36C3-4899-BAEB-6A9563BB790E'`. `TranslationsTests` (K1–K19 × 7 dil, tekrar yok), `OfferCenterTests`, `WorkFilesTests` yeşil olmalı.
- **Cihaz (iPhone 16e):** `CutSenseDevice` şemasında `DeviceFlowUITests` ve `EdgeCaseUITests`.
- **#1:** Yerel video seç → "Preparing video" görünür, "iCloud" görünmez. iCloud'da duran videoda 3 sn sonra iCloud başlığı çıkar.
- **#2:** Ayarlar'dan Fotoğraflar iznini kapat → Save: export overlay hiç açılmadan K5 + "Open Settings".
- **#3, #4:** Tight seç, uygulamayı öldür, aç → Tight. Pro'da ince ayar yap, New Video, yeni video → ipucu K10 ve aynı değerler.
- **#5:** Save sonra Share → overlay açılmadan paylaşım sayfası; AirDrop adında tarih var. New Video → Settings "Temporary files" 0 KB.
- **#8:** Kapsüle basılı tut → orijinal ve sessizlikler oynar; bırak → kesilmiş hâl aynı noktadan sürer. `CUTSENSE_CLAMP_16E=1` ekran görüntüsünde sistem oynatıcı kontrolleriyle çakışma yok.
- **#12:** `qa-fixtures/07` (sürekli müzik) → K8.
- **#14:** Bir toggle kapat, New Video → diyalog. Hiç değişiklik yokken → doğrudan ana ekran.
- **#10:** Export sırasında ana ekrana çık, 10 sn sonra dön → tamamlanmış ya da review'da temiz hata.
- **Ekranlar:** review free/pro ve Almanca, hem tam boy hem `CUTSENSE_CLAMP_16E=1`. Segment alt etiketleri kırpılmamalı.

**Risk:**
- UNVERIFIED: `photos-redirect://` belgelenmemiş şema; App Review riski düşük ama sıfır değil. Reddedilirse yalnız #6 çıkar.
- UNVERIFIED: #1 kodu okuyarak kanıtlandı, cihazda izlenmedi. Yerel büyük dosyada kopya 3 sn'yi aşarsa yine iCloud başlığı çıkar.
- UNVERIFIED: #8 kapsülünün iOS 26 satır içi oynatıcı kontrolleriyle çakışması. Çakışırsa konum `.leading` olur.
- UNVERIFIED: `beginBackgroundTask` süresinde `AVAssetExportSession`'ın bitmesi; uzun fallback export'ta yetmez (#27 bunun asıl çözümü).
- UNVERIFIED: #11 boyut tahmini yalnız passthrough yolunda doğru; uyumluluk modunda sapar, bu yüzden "≈".
- UNVERIFIED: replan sonrası oynatıcının çalma durumunu koruması (#13 yalnız konumu garanti eder).
- RISK: `dev9att` paywall (lime) ve `dev11att` Settings (mavi linkler) görüntüleri güncel kodla uyuşmuyor; eski build. Mono tasarımın 16e cihazında güncel yakalaması yok.
- RISK: `shots-mono/C/cut-sheet.png` audition işinden önce çekilmiş; kesim listesi koddan denetlendi.
- RISK: #5 sonrası kayıtlı çıktı review boyunca diskte kalır; uzun videoda geçici kullanım iki katına çıkar.
- Bakılmayanlar: `docs/offer-policy-owner.md` yok (politika commit `cb4c050`'den okundu). `Video/VideoCompressor`, `VideoFrameRenderer`, `VideoPreviewEngine` ve `AdMobService` iç yerleşimi okunmadı. Hiçbir build ya da test çalıştırılmadı; bu yalnız spesifikasyon.
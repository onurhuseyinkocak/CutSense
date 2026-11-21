A0 tamam: build ve testler yeşil, yeni uyarı yok. Tasarım spec'indeki tüm token'lar ve bileşenler yazıldı, 7 yeni çeviri anahtarı ve ReviewScreen'e waveform bağlantısı eklendi. Hiçbir bileşen ekranda görülmedi; Preview derleniyor ama render edilmedi. Commit atılmadı, branch `release/1.1.0`.

### Yapılan
- **Yeni:** `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/QuickSilence/MonoKit.swift`. Token'lar, butonlar, kontroller, göstergeler, `SignalField` ve yalnız DEBUG'da çalışan `#Preview("Mono components")` burada.
- **Yeni:** `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/QuickSilence/MonoWave.swift`. `MonoWave.bars` ve `WaveformTimeline` burada.
- **Yeni:** `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Tests/Release/MonoWaveTests.swift`, 5 test: boş girdi, hep sıfır, adet ve aralık (bar sayısından az örnek dahil), ramp'te değerlerin azalmaması, kesim maskesi.
- **Çeviri:** `Translations.swift` dosyasına 7 anahtar × 7 dil eklendi. Önce grep ile kontrol ettim, hiçbiri dosyada yoktu.
- **Bağlantı:** `ReviewScreen` içinde `plan`'dan hemen sonra `let waveform: [Float]` var. `QuickSilenceView.review(...)` bunu `waveform: analysis?.windowRMS ?? []` olarak geçiyor. İki dosyada da başka değişiklik yok.
- `xcodegen generate` çalıştırıldı. pbxproj farkı +12 satır, yani yalnız 3 yeni dosya.

### Doğrulanan
- `xcodebuild test` sonucu **TEST SUCCEEDED**: 34 test, 0 hata, 1 test zaten atlanan bir test. `MonoWaveTests` ve `TranslationsTests` geçti.
- Kendi dosyalarımda uyarı yok. Log'da kalan tek uyarı appintents metadata uyarısı, benimle ilgisi yok.
- Yasaklı kelime grep'i iki yeni dosyada boş döndü: renk temizliği (`orange`, `.blue`, `red: 182`, `LinearGradient`, `design: .rounded`) ve entegrasyon (`accent`, `QSPrimary`, `QSSecondary`, `CutIntensityPicker`).

### B, C ve D için public API
```swift
// Token'lar
Mono.C.bg / raised / elevated / hairline / strong / text / text2 / text3 / disabled / waveCut / onWhite2 / pressedWhite(#E6E6E6) / scrim(siyah %90)
Mono.Style: .display .title .numeralXL .numeralL .numeralM .headline .body .label .overline .caption
view.monoText(_ style: Mono.Style, size: CGFloat? = nil)   // ör. .monoText(.title, size: 22)
Mono.Space.xxs 4, xs 8, s 12, m 16, l 24, xl 32, xxl 48
Mono.Radius.chip 10, nativeAd 12, card 24, sheet 28
Mono.Motion.snappy / smooth / bouncy / fade ; Mono.Motion.pick(_ a: Animation, reduce: Bool) -> Animation
view.monoSheet() ; view.monoEntrance(_ index: Int)

// Butonlar
MonoPrimaryButtonStyle(outlined: Bool = false)        // tam genişlik, 56 yükseklik
MonoActionLabel(_ title: String, systemImage: String) // chip rengi stilden gelir
MonoSecondaryButtonStyle(height: CGFloat = 48)        // tam genişlik
MonoTertiaryButtonStyle(color: Color = Mono.C.text2)  // beyaz için color: Mono.C.text

// Kontroller ve göstergeler
MonoIntensityControl(selection: Binding<QuickSilenceEngine.CutIntensity>, language: AppLanguage, hint: String?)
MonoToggleStyle()
MonoBadge(_ text: String, filled: Bool = false)
MonoNotice(text: String, systemImage: String, actionTitle: String? = nil, action: (() -> Void)? = nil)
MonoProgressRing(progress: Double, size: CGFloat = 132)
MonoCheckSeal(size: CGFloat = 72)

// Sinyal ve dalga
SignalField(mode: SignalField.Mode)   // ayrıca SignalField(.demo); Mode: .demo, .scanning(progress:), .flat
WaveformTimeline(bars: [Float], plan: QuickSilenceEngine.CutPlan, playhead: Double? = nil, compacted: Bool = false, onScrub: ((Double) -> Void)? = nil)
WaveformTimeline.cutMask(count: Int, plan:) -> [Bool]   // nonisolated
MonoWave.bars(from rms: [Float], count: Int = 84) -> [Float]
```

### Builder'ların bilmesi gerekenler
- **Haptic:** `MonoIntensityControl` `.selection` haptic'ini kendisi veriyor; B ve C tekrar eklemesin. Haptic helper yazmadım, diğer haptic'ler `.sensoryFeedback` ile ekranlarda eklenir.
- **Buton genişliği:**
  - Share yuvarlağı: `MonoSecondaryButtonStyle(height: 56)` ve `.frame(width: 56)`.
  - Skip: `height: 36`, `.fixedSize()` ve 44 pt dokunma alanını B kendisi verir.
- **`WaveformTimeline`:**
  - Tek erişilebilirlik öğesi, ±5 sn ayarlanabilir aksiyonu var, değeri yüzde (`m:ss` değil).
  - "Timeline" etiketini C dışarıdan vermeli: `.accessibilityLabel(appText(language, "Zaman çizelgesi", "Timeline"))`.
  - Cut sheet'teki küçük kopya `.accessibilityHidden(true)` olmalı.
  - Bar'lar ekrana gelince kendiliğinden büyüyor. `compacted` olunca kalan bar'lar ortalanıyor, genişlemiyor.
- **`ReviewScreen.waveform` ham RMS:** C `MonoWave.bars(from:)` çağrısını bir kez yapmalı, `body` içinde değil.
- **`MonoCheckSeal` yalnız giriş animasyonu yapıyor:** 0.7 sn bekleme ve çıkış C'de.
- **`MonoProgressRing` içinde içerik yeri yok:** yüzde `overlay` ile konur; halka erişilebilirlikte gizli.
- **`SignalField`:** B tek instance'ı phase `switch`'inin dışında tutmalı, böylece `progress` ve amplitude modlar arasında animasyonlu değişir. Reduce Motion açıkken statik kare çiziyor.

### Risk / Eksik
- **UNVERIFIED (görsel):** `#Preview` hiç render edilmedi. Hiçbir bileşen ekranda görülmedi; hero döngüsünün zamanlaması ve Reduce Motion davranışı da bu kapsamda.
- **UNVERIFIED:** `MonoToggleStyle` içindeki `accessibilityRepresentation` Toggle'ına `.toggleStyle(.switch)` ekledim; yoksa stil kendini tekrar tekrar çağırabilirdi. `cutToggle_0`'ın Switch olarak görünüp görünmediği C'nin sheet'inde kontrol edilmeli. Görünmezse spec'teki geri dönüş planı geçerli.
- **D için:** "Banner ads paused until" çevirisinde fr/it ("jusqu'au", "fino al") yalnız takvim tarihine uyuyor; Türkçe kaynak saat gibi okunuyor. D tarih biçimini seçerken bunu göz önünde bulundursun.

### Sonraki doğru adım
B, C ve D paralel başlayabilir; build'ler sırayla alınmalı, aynı `dd` DerivedData kullanılıyor. Atladıklarım: haptic helper'lar ve ekran görüntüsüyle kontrol.
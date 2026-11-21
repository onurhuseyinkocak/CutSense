**Karar:** Tek kırmızı `Mono.C.offer = #FF453A` eklenir ve yalnız `kind == .flash` yüzeylerinde, yalnız `Mono.C.bg` (#000) üstünde kullanılır. Welcome teklifi tamamen siyah-beyaz kalır: kırmızı "süreli" demek olur, welcome zaman iddiası taşımaz (`docs/offer-policy-owner.md`). Hesaplanan kontrast: siyah üstünde 6.16, kırmızı dolgu üstünde siyah metin 6.16. Beyaz üstünde kırmızı ve kırmızı üstünde beyaz 3.41 ile AA altında kalır, bu yüzden pill beyaz kapsülden siyah kapsüle çevrilir. Hareket gradient'siz, düz 1 px çizgidir (`docs/design-1.1.0.md` gradient/shadow/blur yasağı sürer). Hiçbir şey build edilmedi veya render edilmedi; plan kod okuması ve mevcut ekran görüntülerine dayanıyor.

Kodda bulunan iki gerçek kusur da bu işte düzelir:
- `OfferView.swift:241` paydayı `900` sabit almış; `CUTSENSE_OFFER_SECONDS` ile çizgi yanlış dolar.
- `OfferView.swift:233` `numericText` için sürücü animasyon yok; rakamlar büyük olasılıkla animasyonsuz değişiyor (UNVERIFIED, çalıştırıp bakılmadı).

**Adımlar:**

1. **`/Users/jinx/Documents/projeler/CutSense/ios/CutSense/QuickSilence/MonoKit.swift`, tokenlar.** `enum C` içine `scrim`'den sonra:
   - `static let offer = Color(red: 1, green: 69 / 255, blue: 58 / 255)` ve üstüne yorum: `/// Flash offer only, on bg only. Never on raised/white, never as a fill under white text.`
   - `static let offerDim = offer.opacity(0.35)` (yalnız dekoratif hairline; metin için yasak).
   - Dosya başı yorumu (satır 3): "black, white and grays only; one red accent (`offer`) reserved for the timed flash offer."

2. **Aynı dosya, `MonoBadge`.** Yeni defaulted parametre: `init(_ text: String, filled: Bool = false, tint: Color = Mono.C.text)`. Yalnız `filled` dalında `Capsule().fill(tint)` olur; metin siyah kalır, boyut değişmez. Varsayılan bugünkü görünümü korur (`OnboardingView.swift:170` ve preview'a dokunulmaz).

3. **Aynı dosya, `MonoBadge`'den sonra yeni `OfferSweep`.** Kapsül kenarında dolaşan 1 px düz kırmızı segment: tur 2.4 sn `easeInOut`, 6 sn'de bir, segment uzunluğu çevrenin %15'i. Hazır `.trim(from:to:)` kullanılmaz: iki ucu ayrı ayrı lineer interpole edilir ve segment sıfır uzunlukta kalır. Animatable shape şart:
   ```swift
   /// One red hairline lap around a capsule border: 2.4 s every 6 s. Nothing under Reduce Motion.
   struct OfferSweep: View {
       @Environment(\.accessibilityReduceMotion) private var reduceMotion
       @State private var head: CGFloat = 0

       var body: some View {
           if !reduceMotion {
               Segment(head: head)
                   .stroke(Mono.C.offer, style: StrokeStyle(lineWidth: 1, lineCap: .round))
                   .allowsHitTesting(false)
                   .accessibilityHidden(true)
                   .task {
                       while !Task.isCancelled {
                           var reset = Transaction(); reset.disablesAnimations = true
                           withTransaction(reset) { head = 0 }
                           try? await Task.sleep(for: .milliseconds(50))
                           withAnimation(.easeInOut(duration: 2.4)) { head = 1 }
                           try? await Task.sleep(for: .seconds(6))
                       }
                   }
           }
       }

       private struct Segment: Shape {
           var head: CGFloat
           var animatableData: CGFloat { get { head } set { head = newValue } }
           func path(in rect: CGRect) -> Path {
               Capsule().path(in: rect.insetBy(dx: 0.5, dy: 0.5))
                   .trimmedPath(from: max(0, head * 1.15 - 0.15), to: min(1, head * 1.15))
           }
       }
   }
   ```
   `head` 0 ve 1'de segment görünmez, yani reset ve bekleme görünmez. Tempo son dakikada da değişmez. `MonoKitPreview`'daki badge satırına `MonoBadge("−50%", filled: true, tint: Mono.C.offer)` eklenir.

4. **`/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Pro/OfferView.swift`, `OfferPanel` fiyat bloğu.**
   - Yeni yardımcı: `private var isFlash: Bool { kind == .flash }`.
   - Satır 190: `MonoBadge("\u{2212}\(prices.percent)%", filled: true, tint: isFlash ? Mono.C.offer : Mono.C.text)`.
   - Satır 216 stroke rengi: `isFlash ? Mono.C.offer : (phase < 2 ? Mono.C.text : Mono.C.text2)`. Kalınlık 3 / 1.5 ve `reveal()` zamanlamaları (0.35 bekle, 0.3 çizim, 0.3, `smooth`) aynen kalır. Fiyat metni rengi değişmez.
   - Satır 102: `priceBlock` üst boşluğu `Mono.Space.l` → `Mono.Space.xl`.
   - Satır 105: `timeRow` üst boşluğu `Mono.Space.m` → `Mono.Space.l`.

5. **Aynı dosya, `timeRow` (224–256) yeniden düzen.** Bugün 34 pt saat fiyatın hemen altında üçüncü bir fiyat gibi okunuyor. Yeni string yok. `TimelineView(.periodic(from: .now, by: 1))` kalır; içinde `let total = OfferCenter.duration(OfferCenter.flashSeconds)`, `let secs = Int(remaining.rounded(.up))`, `let final = remaining <= 60`. Yukarıdan aşağı:
   - **Satır:** `HStack(alignment: .firstTextBaseline)` içinde solda mevcut "Ends at %@" (`caption`, `text2`), `Spacer`, sağda `Text(clock(remaining))`.
   - **Saat:** `.monoText(.numeralM)`, renk `final ? Mono.C.offer : Mono.C.text`, `.contentTransition(.numericText(countsDown: true))`, `.animation(reduceMotion ? nil : Mono.Motion.snappy, value: secs)`.
   - **Çizgi:** 8 pt boşluktan sonra `GeometryReader` yüksekliği 2. Ray `Mono.C.offerDim`, dolgu `Mono.C.offer`, genişlik `w * min(1, remaining / total)`.
   - **Tik:** dolgunun ucunda 1.5 × 10 pt `Mono.C.offer` dikey çizgi, çizgiye dikey ortalı, `.offset(x:)` ile (SignalField playhead motifi).
   - **Akıcılık:** dolgu ve tik üzerinde `.animation(reduceMotion ? nil : .linear(duration: 1), value: secs)`. Ek 30/60 fps timeline eklenmez.
   - **Son 60 sn:** tik opaklığı `final && !reduceMotion && secs % 2 == 1 ? 0.4 : 1`, `.animation(.easeInOut(duration: 1), value: secs)`. Bu 0.5 Hz eder; başka hiçbir şey yanıp sönmez, haptic yok. Reduce Motion'da yalnız kırmızı rakam ve statik tik.
   - **Alt satır:** "After that, the regular price applies." (`caption`, `text3`).
   - `accessibilityElement(children: .ignore)` ve `accessibilityLabel(clock(remaining))` saat+çizgi grubunda korunur.

6. **Aynı dosya, `OfferPill`.** Yalnız `label(_:percent:)` flash dalı ve yeni bir flash kapsülü değişir. `Button`, `.accessibilityIdentifier("offerPill")`, `accessibilityLabel`, `visible`, `.task`, transition ve haptic aynen kalır. `else` dalındaki beyaz `capsule(base)` de kalır.
   - **Kapsül:** yükseklik 32, yatay padding 12, `Capsule().fill(Mono.C.bg)` ve `Capsule().strokeBorder(Mono.C.offerDim, lineWidth: 1)`.
   - **İçerik:** `HStack(spacing: 6)`, hepsi 12 pt, `.lineLimit(1).fixedSize()`:
     - "Pro": bold, `Mono.C.text`.
     - "−N%": bold, `Mono.C.offer`.
     - Ayraç: 1 × 12 pt `Mono.C.strong`.
     - Saat: semibold `.monospacedDigit()`, `remaining <= 60 ? Mono.C.offer : Mono.C.text`, `numericText(countsDown: true)` ve adım 5'teki `secs` animasyonu.
   - **Erişilebilirlik:** `.accessibilityValue("Pro −N% · mm:ss")` korunur.
   - **Sweep:** `.overlay { OfferSweep() }` `TimelineView` kapanışının DIŞINDA, `Group`'a eklenir; içeride olursa her saniye yeniden kurulabilir. 44 pt `frame(minHeight:)` hit alanı sweep'i kapsamamalı: overlay 32 pt kapsüle uygulanır, dış çerçeveye değil. Bunun için `TimelineView` yalnız içerik `HStack`'ini sarar, kapsül arka planı ve sweep dışarıda kalır.
   - **Disabled (export sırasında, `QuickSilenceView.swift:117`):** `@Environment(\.isEnabled)` okunur, kapsül `.opacity(isEnabled ? 1 : 0.4)`, sweep yalnız `isEnabled` iken render edilir.

7. **Dokümanlar.**
   - `/Users/jinx/Documents/projeler/CutSense/docs/design-1.1.0.md`: renk tablosuna `offer #FF453A` (6.16 on #000, yalnız flash, yalnız bg üstünde) ve `offerDim` (%35, dekoratif) satırları; Motion'a "Offer sweep 2.4 s / 6 s, countdown linear 1 s, final-minute tick 0.5 Hz" satırı.
   - `/Users/jinx/Documents/projeler/CutSense/docs/mono-api.md`: API bloğuna `Mono.C.offer / offerDim`, `MonoBadge(_:filled:tint:)`, `OfferSweep()`.

8. **Sıra:** 1 → 2 → 3 → 4 → 5 → 6 → 7. Yeni dosya yok, `xcodegen` gerekmez.

**Dokunma:**
- `OfferCenter.swift` ve `ProStore.swift` (zamanlama, anahtarlar, SKU'lar): yalnız `OfferCenter.duration` / `flashSeconds` okunur.
- `OfferPanel` içinde `buy()`, `restore()`, `expireIfIdle()`, `.task(id: endsAt)`, `onExpired`, `ProSheet` latch mantığı.
- Kimlikler `offerPill`, `offerBuyButton`, `offerNotNow`.
- `MonoPrimaryButtonStyle`: CTA beyaz kalır.
- `PaywallView.swift`, `OnboardingView.swift`, reklam ve düzenleme ekranları: kırmızı girmez.
- `Translations.swift`: yeni anahtar yok.
- `Tests/UI/OfferFlowUITests.swift`: commit'lenmemiş değişiklik var, dokunulmaz.
- Eski `UI/*.swift` ekranlarındaki `Color.red` kullanımları kapsam dışı.

**Doğrulama:**
- **Build ve test:** xcodebuildmcp ile simülatör `3C9044C5-36C3-4899-BAEB-6A9563BB790E` (iPhone 17 Pro Max olduğu doğrulandı, şu an Shutdown). `OfferFlowUITests` yeşil kalmalı.
- **Sızıntı grep'i:** `grep -rn "Mono.C.offer\|OfferSweep" ios/CutSense` yalnız `MonoKit.swift` ve `Pro/OfferView.swift` döndürmeli. `grep -n "LinearGradient\|AngularGradient\|shadow\|blur(" ios/CutSense/Pro/OfferView.swift ios/CutSense/QuickSilence/MonoKit.swift` yeni satır döndürmemeli (`blurReplace` mevcut, sayılmaz).
- **Ekran görüntüleri** (env: `CUTSENSE_SKIP_ONBOARDING=1 CUTSENSE_FORCE_FLASH_OFFER=1 CUTSENSE_FAKE_PRICES=1`):
  1. **Ana ekran:** siyah pill, kırmızı "−50%", beyaz saat; 6 sn içinde iki kare alınıp sweep segmentinin göründüğü doğrulanır.
  2. **Flash panel:** kırmızı badge üstünde siyah metin, kırmızı üstü çizgi, kırmızı çizgi ve tik, beyaz saat sağda.
  3. **Son dakika:** `CUTSENSE_OFFER_SECONDS=75` eklenir (zorlanmış flash bu env'i okur, `OfferCenter.swift:161`). İlk 15 sn beyaz rakam, sonra panelde ve pill'de kırmızı rakam; çizgi tam dolu başlayıp akıcı azalmalı (payda düzeltmesinin kanıtı).
  4. **Süre bitimi:** panel `PaywallView`'a döner, pill kaybolur, ekranda kırmızı kalmaz.
  5. **Reduce Motion açık:** sweep yok, pulse yok, çizgi adımlı, kırmızı öğeler statik.
  6. **Welcome:** `CUTSENSE_RESET_ONBOARDING=1 CUTSENSE_FAKE_PRICES=1` ile onboarding sonunda $5.99, −25% beyaz badge, beyaz üstü çizgi, hiç kırmızı yok. Eski `welcome-panel-s.png` bayat ($3.99 ve "until" satırı gösteriyor); yenisi çekilmeli.
  7. **Normal paywall** (Settings → Pro, flash yokken): hiç kırmızı yok.
  8. **Dynamic Type xxLarge:** flash panelde saat satırı taşmıyor.

**Risk:**
- UNVERIFIED: `Capsule().path(in:)` başlangıç noktası, yani sweep'in nereden doğduğu. Görsel kusursa `Segment`'e `.rotation` yerine `head` ofseti eklenir.
- UNVERIFIED: nav bar `principal` toolbar öğesinde sürekli `.task` animasyonunun davranışı (yeniden kurulma, kırpılma). Sorun çıkarsa sweep `QuickSilenceView`'a taşınmaz; `OfferSweep` içinde `.task(id:)` anahtarı pill'in `visible` değerine bağlanır.
- UNVERIFIED: `numeralM` (monospaced design) ile `numericText` geçişinin 20 pt'te titremesi. Titrerse geçiş kaldırılır, renk kalır.
- UNVERIFIED: 5.6 açısından App Review yorumu. Savunma: sayaç gerçek mutlak zaman, kurulum başına bir kez, hız/tempo artışı yok, tek pulse 0.5 Hz.
- RISK: siyah pill beyaz kapsüle göre daha az göze çarpar. Bilinçli tercih; dönüşüm etkisi ölçülmedi.

Atlananlar: badge boyut büyütme, welcome'a kırmızı, yeni çeviri anahtarı, son dakika haptic'i.
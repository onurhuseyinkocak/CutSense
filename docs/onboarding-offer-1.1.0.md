**Karar:** Koordinatörün beş itirazını tarttım ve ilk spesifikasyonu üç yerde değiştirdim; bu sürüm öncekinin yerine geçer.

- **Teklifin yeri:** Gerçek indirim onboarding sonundan ilk başarılı kayda taşındı. Onboarding 3 sahnedir ve satın alma ekranı içermez; yalnız tek satırlık bir Pro bilgisi taşır.
- **Mekanizma:** Tek ikinci non-consumable, `com.cutsense.app.pro.lifetime.offer`, $3.99, aynı entitlement. İki pencerede satılır:
  - "Welcome offer": ilk kayıttan itibaren 24 saat, tarihli, geri sayımsız.
  - "15-minute offer": kurulum başına tam bir kez, gerçek geri sayımlı.
- **Çapa:** Bu iki pencere dışında fiyat her zaman $7.99'dur.
- **Sahip koruması:** Pro sahibine hiçbir ürün satılmaz; satın alma öncesi entitlement tazelenir.
- **UMP:** Onboarding bitince başlar. ATT eklenmez.
- **Reddedilenler:** abonelik, global fiyat indirimi, offer code, kişiselleştirme çipleri, flash'a özel üçüncü ürün.

**Pushback (sahibin sözünden sapmalar):**

| Sahibin isteği | Karar | Neden |
|---|---|---|
| İndirim onboarding sonunda | İlk başarılı kayıttan sonra | Ücretsiz bir araçta değer görülmeden teklif "salesy" hissin ta kendisi. Herkese ilk dakikada $3.99 göstermek $7.99 çapasını da öldürür. Onboarding'de yalnız "Free with ads. One-time Pro removes them." satırı kalır; reklam beklentisini de dürüstçe kurar. |
| Reddedince "bir süre sonra" tekrar eden flash | Kurulum başına 1 flash; welcome bitiminden ≥ 7 gün sonra ve ≥ 3 kayıtta | Tekrarlayan flash kullanıcıyı beklemeye alıştırır ve 5.6 açısından sahte aciliyet gibi okunur. Tek seferlik olunca aciliyet gerçektir. |
| Welcome'da "iyi indirim" vurgusu | Geri sayım yok, yalnız bitiş tarihi | Sayaç yalnız gerçekten 15 dakikalık teklifte kullanılır. |
| Teklif ekranı | Yalnız bir kez kendiliğinden açılır (ilk kayıttan sonra "New Video"ya basınca); flash hiç modal açmaz | Kayıttan 1.2 sn sonraki rating prompt ve ödüllü reklam kartıyla çakışmaz; flash nav bar'daki haptan "doğrudan erişilebilir". |
| "was $7.99" | "Regular price" + üstü çizili | Pro hiç $7.99'a satılmadı; "was" yanıltıcı olurdu. |
| Kişiselleştirme çipleri | Yok | Seçim sonradan hiçbir yerde kullanılmıyor. |
| İki fiyat noktası ($4.99 / $3.99) | Tek nokta, $3.99 | Aşağıda. |

- **Fiyat:** Tek seferlik rakipler $4.99–$5.99, 5cut lifetime $6.99. Pro'nun değeri (reklamsız + Fine-tune) zayıf olduğu için $3.99 hepsinin altında ve "−50%" dilden bağımsız.
- **Tek SKU'nun yan etkisi:** Derinleşen indirim olmaz (pazarlık öğretmez) ve review yükü tek üründür.
- **Review ekranı (madde 4):** Sesli otomatik oynatma, reklam akışı çözüldükten sonra, video başına bir kez. Sessiz autoplay tuzak: kullanıcı play'e basıp ses duymaz.
- **Home boşluğu (madde 5):** Hero uzun ekranda büyür, alt boşluk sabitlenir.

**Adımlar:**

## 0. Token yeniden kullanımı
- Yeni token yok: `Mono.C.*`, `Mono.Style`, `Mono.Space`, `Mono.Motion.*` + `pick(_:reduce:)`, `monoEntrance`.
- Bileşenler: `MonoPrimaryButtonStyle`, `MonoActionLabel`, `MonoTertiaryButtonStyle`, `MonoBadge`, `MonoToggleStyle`, `MonoCheckSeal`.
- `SignalField` kullanılmaz (sabit döngü, private iç yapı); `MonoKit.swift` değişmez.
- Uppercase, gradient, blur, renk yok.

## 1. Onboarding (3 sayfa; 390×844, güvenli alan 763; yatay padding 24)

**Yerleşim:**

| Öğe | Yükseklik |
|---|---|
| Üst bar: solda 3 ilerleme kapsülü (24×3, aralık 6; aktif beyaz, diğerleri `strong`), sağda "Skip" (tertiary, 44 hit) | 44 |
| boşluk | 8 |
| `OnboardingStage` (genişlik 342) | `min(300, ekran yüksekliği × 0.36)` |
| boşluk | 28 |
| overline "CutSense" (`text3`) | 14 |
| başlık (`display`, 2 satır) | ≤ 96 |
| gövde (`body`, `text2`, 3 satır) | ≤ 60 |
| rozet satırı (yalnız sayfa 3) | 12 + 22 |
| `Spacer` | esnek |
| Pro satırı (yalnız sayfa 3; `caption`, `text3`, ortalı) | 16 + 8 |
| CTA: `MonoActionLabel("Continue", "arrow.right")`; sayfa 3'te "Start cutting" | 56 |
| alt padding | 16 |

**Gezinme:**
- Continue ya da yatay sürükleme (eşik 50 pt); otomatik ilerleme yok.
- Skip ve sayfa 3 CTA'sı doğrudan uygulamaya gider.
- Metin bloğu `.id(page)` + `.transition(.blurReplace)` + `smooth`; satırlar `monoEntrance(0…2)`.
- Sayfa değişiminde `.impact(flexibility: .soft)`.

**Sahne altyapısı (`OnboardingStage`):**
- `Canvas`, `TimelineView(.animation(minimumInterval: 1/60, paused: scenePhase != .active))` içinde, `accessibilityHidden`.
- 48 slot, `slot = W/48`, bar genişliği `slot*0.5`, tam yuvarlak.
- Sessizlik aralıkları: A = 8–13, B = 20–26, C = 34–40 (20 slot = %41.7; 32 sn → 19 sn).
- Konuşma zarfı: `0.28 + 0.72*abs(sin(i*1.31)*0.6 + sin(i*0.47+1.3)*0.4)`; nefes `×(0.85 + 0.15*sin(t*2.4 + i*0.55))`.
- Sessizlik zarfı 0.05; B aralığı 0.16.
- Her sahne `pose(page, τ) -> [BarPose(x, w, h, white, alpha)]` üretir.
- Sayfa geçişi: donmuş eski pozdan yenisine 0.55 sn easeInOut lerp; overlay'ler çapraz solar.
- Sayaç ve satırlar SwiftUI overlay'dir (`.contentTransition(.numericText())`).

**Sayfa 1, "Collapse"** (bar merkezi y = 150, en yüksek bar 132):

| τ (sn) | Olay |
|---|---|
| 0–0.6 | Bar'lar 0'dan büyür: 0.35 easeOut, gecikme `i*0.012`. Sol üstte `numeralM` "0:32", sağ üstte overline "Original". |
| 0.6–2.2 | 1.5 pt playhead soldan sağa lineer. Geçilen konuşma 0.45→1.0, sessizlik 0.22. |
| 2.2–2.5 | Playhead söner. Sessizlik aralıklarına 1 pt `strong` çerçeve (radius 6) trim 0→1. |
| 2.5–3.4 | `c` 0→1 easeInOut: sessizlik slot genişliği `slot*(1−c)`, satır ortalanır, birleşimlerde 1 pt çizgi (beyaz `0.5*c`). Sayaç `32 − 13c` ile 0:19'a iner, etiket "Without silence", `MonoBadge("−41%", filled: true)` `bouncy`. τ = 2.5'te `.impact(weight: .light)`, yalnız ilk turda. |
| 3.4–6.0 | Bekleme. |
| 6.0–6.8 | `c` → 0, sayaç 0:32. Döngü τ = 0.6'dan. |

Reduce Motion: statik `c = 1`, "0:19", rozet görünür.

**Sayfa 2, "Review"** (bant y = 44, en yüksek bar 64; `c = 0`; kesilen bar'lar `waveCut`, ×0.35, arkada `raised` dolgu + hairline):
- y = 100'den 3 satır, her biri 52 yüksek: "01" overline + mono 15 aralık + etkileşimsiz `Toggle` (`MonoToggleStyle`, `.allowsHitTesting(false)`).
- Aralıklar: "0:05 – 0:09", "0:13 – 0:18", "0:23 – 0:27".
- y = 268'de solda "New length", sağda `numeralM`.

| τ (sn) | Olay |
|---|---|
| 0–0.55 | Morph. |
| 0.3–0.9 | Satırlar `monoEntrance`. Sayı "0:19". |
| 1.4 | Satır 02 toggle'ında dokunma noktası (28 pt beyaz %30, scale 0.6→1, 0.25 sn). |
| 1.7 | Toggle "Keep", `.selection`. B çerçevesi söner, bar'lar beyaz ve tam yükseklik (`smooth`). Sayı 0:19 → 0:24. |
| 3.2–3.5 | Geri: "Cut", 0:19. |
| 5.0 | Döngü τ = 1.0'dan. |

Reduce Motion: statik, satır 02 "Keep", "0:24".

**Sayfa 3, "On-device"** (`c = 1`):
- Telefon çerçevesi 140×280, radius 30, 1.5 pt beyaz, trim 0→1 (0–0.7 sn).
- Bar'lar 108 pt genişliğe ölçeklenir (en yüksek 72, y = 150).
- 0.9–2.1: 1 pt beyaz %60 tarama çizgisi yukarıdan aşağı; 4 sn'de bir tekrar.
- 2.1: `MonoCheckSeal(size: 44)` y = 236'da, kalır.
- Rozetler 0.8 / 0.95 / 1.1 sn'de: "No upload", "No account", "No watermark".

Reduce Motion: statik.

**Kopya:**

| EN | TR |
|---|---|
| Cut the silence. Keep the talk. | Sessizliği kes. Konuşma kalsın. |
| CutSense finds every pause in your video and closes the gap in seconds. | CutSense videondaki her duraklamayı bulur, boşluğu saniyeler içinde kapatır. |
| You approve every cut. | Her kesim senin onayında. |
| See each cut before saving. Keep a pause with one tap. | Kaydetmeden önce her kesimi gör. Tek dokunuşla duraklamayı geri al. |
| Your video never leaves your iPhone. | Videon iPhone'undan hiç çıkmaz. |
| Everything runs on-device. No upload, no account, no watermark. | Her şey cihazda çalışır. Yükleme yok, hesap yok, filigran yok. |
| Free with ads. One-time Pro removes them. | Reklamlı ve ücretsiz. Tek seferlik Pro reklamları kaldırır. |
| Continue / Skip / Start cutting | Devam / Geç / Kesmeye başla |
| Original / Without silence / New length | Orijinal / Sessizlik olmadan / Yeni süre |
| No upload / No account | Yükleme yok / Hesap yok |

## 2. Teklif ekranı (`OfferPanel`, sheet içinde; welcome ve flash)

Orta kısım `ScrollView` (`.scrollBounceBehavior(.basedOnSize)`), footer sabit; yapı `PaywallView` ile aynı.

1. **Kapat:** `xmark`, 44 pt, sağ üst, `text2`, label "Close".
2. **Overline:** "Welcome offer" ya da "15-minute offer".
3. **Başlık:** mevcut "No ads. Finer control. Pay once.", 34 semibold, tracking −0.8.
4. **Fiyat bloğu:**
   - Teklif fiyatı `numeralXL` + `MonoBadge("−\(percent)%", filled: true)` (kodda kurulur).
   - Altında "Regular price" caption `text3` + üstü çizili `numeralM` normal fiyat.
   - Tek erişilebilirlik öğesi.
5. **Zaman satırı:**
   - Welcome: caption `text2` "Welcome price until %@" (`endsAt.formatted(date: .abbreviated, time: .shortened)`). Sayaç yok.
   - Flash:
     - `numeralL` "14:59"; `TimelineView(.periodic(from: .now, by: 1))` içinde her karede `endsAt − date`, yerel azaltma yok.
     - 2 pt hairline iz üstünde beyaz çizgi, genişlik `remaining/900`.
     - Caption "Ends at %@" + "After that, the regular price applies."
     - Nabız, titreşim, renk yok.
6. **3 fayda satırı** (48 yüksek, hairline; mevcut anahtarlar, önce grep): "No ads, ever", "Fine-tune: minimum pause and breathing room", "One-time purchase. No subscription."
7. **Footer:** mesaj; CTA `MonoActionLabel(String(format: "Unlock for %@", offerPrices.offer), "arrow.right")`; 44 yüksek tek satırda "Restore Purchases" · "Terms" · "Privacy".

**Fiyat açılışı:**

| t (sn) | Olay |
|---|---|
| 0 | Normal fiyat büyük konumda. |
| 0.35–0.65 | Üstüne çizgi trim 0→1. |
| 0.65 | Normal fiyat `matchedGeometryEffect` + `smooth` ile küçülür; teklif fiyatı `.blurReplace`, rozet `bouncy`, `.impact(weight: .medium)`. |

Reduce Motion: son durum, fade.

**Davranış:**
- Başarı: `.success`, `MonoCheckSeal(72)` 0.9 sn, sonra `onClose()`.
- Hata, pending, unavailable: `PaywallView.buy()` içindeki mevcut anahtarlar; `.warning`.
- Süre dolunca: `remaining <= 0 && !isWorking` ise `onExpired()`. Pencere içinde başlayan satın alma tamamlanır.

**Kopya:**

| EN | TR |
|---|---|
| Welcome offer | Hoş geldin teklifi |
| 15-minute offer | 15 dakikalık teklif |
| Regular price | Normal fiyat |
| Welcome price until %@ | Hoş geldin fiyatı %@ tarihine kadar |
| Ends at %@ | %@ itibarıyla biter |
| After that, the regular price applies. | Sonrasında normal fiyat geçerli. |
| Pro offer | Pro teklifi |

## 3. Durum makinesi (`OfferCenter`)

**Anahtarlar (`UserDefaults`):**

| Anahtar | Tip | Anlam |
|---|---|---|
| `onboarding_done_v1` | Bool | Onboarding bitti |
| `offer_kind` | String | Aktif teklif: "welcome" ya da "flash" |
| `offer_ends_at` | Double | Aktif teklifin mutlak bitişi |
| `offer_welcome_done` | Bool | Welcome kullanıldı |
| `offer_flash_done` | Bool | Flash kullanıldı |
| `offer_auto_shown` | Bool | Welcome sheet'i bir kez kendiliğinden açıldı |
| `offer_last_ended_at` | Double | Son teklifin bitişi |
| `offer_clock_high` | Double | Görülen en büyük saat |
| `stat_saves` | Int | Başarılı kayıt sayısı |

**`refresh()`** (launch, `scenePhase == .active`, hap süre dolunca):
- `now < high − 120` ise saat geri alınmış: aktif teklif hemen biter, `last_ended = high`.
- Aksi halde `high = max(high, now)`.
- `now >= ends` ya da `isPro` ise teklif biter, `last_ended = min(now, ends)`.

**`noteSave()`:** `refresh()`, `stat_saves += 1`. `canOffer()` doğruysa ve aktif teklif yoksa:
- `!welcome_done` ise welcome başlar: `ends = now + 86400`, `welcome_done = true`.
- Değilse `!flash_done && stat_saves >= 3 && max(now, high) >= last_ended + 7*86400` ise flash başlar: `ends = now + 900`, `flash_done = true`.

**`takeAutoPresent() -> Bool`:** Welcome aktif, `!auto_shown` ve `canOffer()` ise bir kez `true` döner.

`canOffer()` = iki ürün yüklü, teklif fiyatı < normal fiyat, yüzde ≥ 10, Pro değil.

**Kenar durumlar:**

| Durum | Davranış |
|---|---|
| Relaunch / kill | Bitiş mutlak; süre sıfırlanmaz |
| Tetik anında offline ya da ürün yok | Teklif başlamaz, hak yanmaz; sonraki kayıtta denenir |
| Teklif sırasında offline | Sistem hatası; süre uzamaz |
| Ask to Buy pending | Mesaj; süre akar; sonradan onay Pro verir |
| Saat ileri | Erken biter |
| Saat geri (> 120 sn) | Hemen biter |
| Reinstall | Sıfırlanır; welcome ve flash birer kez daha mümkün. Kabul edildi, Keychain yok; teklif gerçek |
| İade | `isPro` false; kullanılmış teklifler geri gelmez |
| 1.0.x'ten yükselten | Onboarding'i bir kez görür; 1.1.0'daki ilk kaydı welcome'ı başlatır |
| Pro sahibi (başka cihaz, restore) | `canOffer` false; hap ve panel yok; satın alma öncesi `refresh()` çift ödemeyi engeller |

**Yaşam döngüsü:**

| An | Yüzey | Fiyat | Sıklık |
|---|---|---|---|
| Onboarding sayfa 3 | Tek satır Pro bilgisi | yok | 1 |
| İlk kayıttan önce | PRO kapsülü, reklam kartı, Fine-tune, Ayarlar | $7.99 | kullanıcı dokununca |
| İlk kayıt → 24 saat | Nav'da "Pro −50%" hapı; tüm girişler; "New Video" sonrası tek otomatik sheet | $3.99 | kurulum başına 1 |
| Sonrası | Aynı girişler | $7.99 | her zaman |
| Welcome bitiminden ≥ 7 gün sonra, ≥ 3. kayıtta | Nav'da "Pro −50% · 14:59" hapı, 15 dk | $3.99 | kurulum başına 1 |
| Hiçbir zaman | Export önünde paywall, reklam üstüne bindirme, ikinci otomatik modal | n/a | n/a |

**Metrik:**
- Analytics backend yok, eklenmiyor.
- Cihaz sayaçları yalnız karar mantığıdır; cihazdan çıkmaz.
- İzlenecekler: ASC Sales & Trends'te SKU başına adet, App Analytics dönüşüm, AdMob gösterim/eCPM.
- Tek SKU welcome ile flash satışını ayıramaz.

## 4. Builder görevleri (çakışma yok; build almazlar; `Translations.swift`'e dokunmazlar)

**E — StoreKit + durum:**

Dosyalar:
- `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Pro/ProStore.swift`
- `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Pro/Products.storekit`
- yeni `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Pro/OfferCenter.swift`
- yeni `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Tests/Release/OfferCenterTests.swift`
- `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Tests/Release/ProStoreTests.swift` (yalnız ekleme)

```swift
// ProStore additions; existing signatures stay
static let offerID = "com.cutsense.app.pro.lifetime.offer"
struct OfferPrices: Equatable, Sendable { let offer: String; let regular: String; let percent: Int }
private(set) var offerProduct: Product?
var offerPrices: OfferPrices?          // nil unless both loaded, offer.price < product.price, floor percent >= 10
init(productID: String = ProStore.lifetimeID, offerID: String = ProStore.offerID)
func purchaseOffer() async -> Outcome

// OfferCenter
@MainActor @Observable final class OfferCenter {
    enum Kind: String { case welcome, flash }
    struct Active: Equatable { let kind: Kind; let endsAt: Date }
    static let shared: OfferCenter
    private(set) var active: Active?
    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         canOffer: @escaping @MainActor () -> Bool = { ProStore.shared.offerPrices != nil && !ProStore.shared.isPro })
    func refresh()
    func noteSave()
    func takeAutoPresent() -> Bool
}
enum OnboardingGate {
    static let key = "onboarding_done_v1"
    static var bypass: Bool
    static func applyDebugHooks()
}
```
- `loadProduct()` iki id'yi tek çağrıda yükler.
- `refresh()` iki id'den biri eşleşirse `owned = true` yapar. Bu olmazsa indirimli alıcı bir sonraki refresh'te Pro'yu kaybeder.
- `purchase()` ve `purchaseOffer()` şu satırlarla başlar: `await refresh(); guard !isPro else { return .purchased }`. StoreKit aynı ürünü ikinci kez sattırmaz ama diğer SKU'yu sattırır; bu guard çift ödemeyi keser.
- `Products.storekit`: ikinci ürün; `displayPrice` "3.99", `internalID` "6770030002", `referenceName` "CutSense Pro Offer", `NonConsumable`.
- `OnboardingGate.bypass`: `XCTestConfigurationFilePath` set; DEBUG'da `CUTSENSE_SKIP_ONBOARDING=1`, `CUTSENSE_AUTORUN_VIDEO_URL` ya da `CUTSENSE_SHOW_PAYWALL` set.
- DEBUG kancaları:
  - `CUTSENSE_RESET_ONBOARDING=1`: onboarding + tüm `offer_*` + `stat_saves` silinir; bypass'ı ezer.
  - `CUTSENSE_FORCE_WELCOME_OFFER=1`, `CUTSENSE_FORCE_FLASH_OFFER=1`: kurallar atlanır, teklif başlar.
  - `CUTSENSE_OFFER_SECONDS=<n>`: teklif süresi.
  - `CUTSENSE_FAKE_PRICES=1`: ürünler nil ise `offerPrices` = ("$3.99", "$7.99", 50).
- Testler (enjekte defaults ve saat):
  - İlk kayıt welcome başlatır.
  - Aynı defaults ile yeni instance aynı bitişi görür.
  - Welcome 24 saatte biter.
  - Flash 7 günden ve 3. kayıttan önce başlamaz.
  - Flash 900 sn sürer ve ikinci kez başlamaz.
  - Saat geri alınınca biter.
  - `canOffer == false` iken hak yanmaz.
  - `takeAutoPresent` yalnız bir kez `true` döner.
  - `ProStoreTests`: `offerPrices?.percent == 50`.

**F — Onboarding:**

Dosyalar (yeni):
- `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/QuickSilence/OnboardingView.swift`
- `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/QuickSilence/OnboardingStage.swift`

- `struct OnboardingView: View { init(onFinish: @escaping () -> Void) }`; dil `@AppStorage(AppLanguage.storageKey)`.
- Bölüm 1 birebir. `OfferPanel`'a bağımlılık yok.
- DEBUG: `CUTSENSE_ONBOARDING_PAGE=0…2`, `CUTSENSE_ONBOARDING_FREEZE=<sn>`.
- Kimlikler: `onboardingContinue`, `onboardingSkip`.

**G — Teklif UI:**

Dosya (yeni): `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Pro/OfferView.swift`

```swift
struct OfferPanel: View {
    init(kind: OfferCenter.Kind, endsAt: Date, language: AppLanguage,
         onClose: @escaping () -> Void, onExpired: @escaping () -> Void)
}
struct ProSheet: View { init(language: AppLanguage) }
struct OfferPill: View { init(language: AppLanguage, action: @escaping () -> Void) }
```
- `ProSheet`:
  - `@State showsOffer: Bool?`.
  - `showsOffer ?? (OfferCenter.shared.active != nil && ProStore.shared.offerPrices != nil)` doğruysa `OfferPanel`, değilse `PaywallView(language:)`.
  - `onExpired: { showsOffer = false }`; değişim `Mono.Motion.fade`.
- `OfferPill`:
  - Yalnız `active != nil && !isPro && offerPrices != nil` iken görünür.
  - Beyaz kapsül, 30 yüksek, 44 hit; siyah 12 bold `monospacedDigit`.
  - Metin: welcome'da "Pro −50%", flash'ta "Pro −50% · 14:59".
  - `TimelineView(.periodic(by: 1))`; süre dolunca `OfferCenter.shared.refresh()`.
  - Giriş scale 0.9→1 + opaklık (`bouncy`), `.impact(weight: .light)`. Reduce Motion: fade.
  - Kimlikler: `offerPill`, `offerBuyButton`.

**Entegrasyon (yürütücü; B ve D bittikten sonra):**

1. `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/QuickSilence/QuickSilenceApp.swift`
   - `init`'e `OnboardingGate.applyDebugHooks()`.
   - `@AppStorage(OnboardingGate.key) private var onboardingDone = false`; `showsMain = onboardingDone || OnboardingGate.bypass`.
   - `DebugScreenClamp` içinde `ZStack`: `showsMain` ise mevcut `NavigationStack`, değilse `OnboardingView { withAnimation(.easeInOut(duration: 0.45)) { onboardingDone = true } }`; ikisi de `.transition(.opacity)`.
   - `.task` → `.task(id: showsMain)`. Sıra: audio session → `await ProStore.shared.refresh()` → `ProStore.shared.start()` → `OfferCenter.shared.refresh()` → `if showsMain { AdMobService.start() }`.
     - `QuickSilenceView` render edilmediği için kendi `.task`'ı da UMP'yi onboarding'den sonra tetikler.
   - `onChange(of: scenePhase)`: `OfferCenter.shared.refresh()`; yeniden yükleme koşulu `product == nil || offerProduct == nil`.
2. `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/QuickSilence/QuickSilenceView.swift` (metin çapalarıyla)
   - `@State private var offers = OfferCenter.shared`.
   - `if isIdle && store.canOfferPro` → `&& offers.active == nil` eklenir.
   - `.toolbar`'a `ToolbarItem(placement: .principal) { OfferPill(language: appLanguage) { showsPaywall = true }.disabled(exportTask != nil) }`.
   - `.sheet(isPresented: $showsPaywall)` içinde `PaywallView(language: appLanguage)` → `ProSheet(language: appLanguage)`.
   - `startSave` içinde `saved = true`'dan hemen sonra `OfferCenter.shared.noteSave()`.
   - `.onChange(of: phaseKey) { _, key in if key == 0, !AdMobService.hasPresentedContent, offers.takeAutoPresent() { showsPaywall = true } }`.
3. `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/UI/SettingsScreen.swift`: sheet içinde `PaywallView(language: language)` → `ProSheet(language: language)`.
4. `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Tests/UI/DeviceFlowUITests.swift` `setUp`: `app.launchArguments += ["-onboarding_done_v1", "YES"]`.
5. `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Services/Translations.swift`: bölüm 1 ve 2'deki yeni anahtarlar × 7 dil. Her biri önce grep'lenir; mevcut olanlar eklenmez.
6. **Home boşluğu** (`QuickSilenceView.swift`):
   - `SignalField` satırında `.frame(height: isIdle ? 96 : 64)` → `.frame(minHeight: isIdle ? 96 : 64, maxHeight: isIdle ? 220 : 64)`.
   - `home` içindeki `Spacer(minLength: 24)` → `Color.clear.frame(height: 24)`.
   - Sonuç: 6.9" ekranda boş yükseklik hero'ya gider, alt yazı kontrollerin hemen üstünde durur; 16e'de hero 96 kalır.
7. **Review autoplay** (`/Users/jinx/Documents/projeler/CutSense/ios/CutSense/QuickSilence/ReviewScreen.swift`, `PreviewPlayer`):
   - `private var didAutoplay = false`.
   - `func autoplayOnce() { guard !didAutoplay, player.currentItem != nil else { return }; didAutoplay = true; player.play() }`.
   - `stop()` içinde `didAutoplay = false`.
   - `QuickSilenceView.startResultAdBreakIfNeeded` içinde:
     - `guard AdMobService.isEnabled else { preview.autoplayOnce(); return }`.
     - Task gövdesinin ilk satırı: `defer { if !Task.isCancelled, isActive(jobID), isReview, !AdMobService.hasPresentedContent { preview.autoplayOnce() } }`.
   - Sesli oynar, video başına bir kez; replan yeniden yüklemelerinde tekrar etmez.
8. `cd /Users/jinx/Documents/projeler/CutSense/ios && xcodegen generate`.

**ASC (sahibi):**
```
asc iap setup --app 6770024868 --type NON_CONSUMABLE --reference-name "Pro Lifetime Offer" --product-id "com.cutsense.app.pro.lifetime.offer" --locale "en-US" --display-name "CutSense Pro Offer" --description "Remove all ads and unlock fine-tune controls." --price "3.99" --base-territory "United States"
```
- Family Sharing kapalı; review görüntüsü welcome `OfferPanel`.

**Review notu (iki ürüne):**
> "CutSense Pro is a one-time non-consumable; no subscription. Two product IDs unlock the identical entitlement (no ads + Fine-tune): `…pro.lifetime` (regular price) and `…pro.lifetime.offer` (reduced price). Regular product: tap 'PRO' at the top right of the home screen, or Settings > CutSense Pro. Reduced product: save any video once; a 'Pro −50%' pill appears at the top for 24 hours, and tapping 'New Video' opens the offer once. The reduced price is offered one more time per install, for 15 minutes, at least 7 days later. End times are stored and are not reset by relaunch; afterwards only the regular product is shown. Owners of either product are never shown a purchase button. Restore is on every purchase screen."

**Dokunma:**
- Kod: `MonoKit.swift`, `MonoWave.swift`, `PaywallView.swift`, `AdMobService.swift` (ATT yok, UMP aynen), `AdMobIDs`, `NativeAdCard.swift`, `QuickSilenceEngine`, `project.yml`, `Info.plist`.
- Entitlement: `pro_unlocked` anahtarı, `ProStore.lifetimeID`, `init(productID:)`, `restore()`.
- UI sözleşmesi: mevcut erişilebilirlik kimlikleri; "Restore Purchases" ve "Unlock for %@" etiketleri.
- Akış: rating prompt, ödüllü reklam zamanlaması ve metni, `AdFreePass`.
- ASC: abonelik grubu 22125338.
- B ve D bitmeden `QuickSilenceView.swift` ve `SettingsScreen.swift`'e yazılmaz. `ReviewScreen.swift` (e8023a7) yalnız madde 7'deki üç ekleme için açılır.
- Hardcode fiyat ya da yüzde (DEBUG fixture hariç), sahte kıtlık cümlesi, nabız/titreşim, ikinci otomatik modal yok.

**Doğrulama:**

Build ve test:
- `cd /Users/jinx/Documents/projeler/CutSense/ios && xcodegen generate && xcodebuild test -scheme CutSense -destination 'id=3C9044C5-36C3-4899-BAEB-6A9563BB790E' -derivedDataPath <dd>`
- `OfferCenterTests`, `ProStoreTests`, `TranslationsTests` yeşil olmalı.

Simülatör:
- Kalıp: `SIMCTL_CHILD_<VAR>=… xcrun simctl launch 3C9044C5-36C3-4899-BAEB-6A9563BB790E com.cutsense.app`, sonra `xcrun simctl io <id> screenshot`.
- Her görüntü tam boy ve `CUTSENSE_CLAMP_16E=1` ile alınır.

| Akış | Ortam | Beklenen |
|---|---|---|
| Sayfa 1 | `CUTSENSE_RESET_ONBOARDING=1`, `CUTSENSE_ONBOARDING_PAGE=0`, `CUTSENSE_ONBOARDING_FREEZE=1.5` ve `=4` | Playhead karesi; çökmüş kare, "0:19", "−41%" |
| Sayfa 2 | `PAGE=1`, `FREEZE=2.5` | Satır 02 "Keep", "0:24" |
| Sayfa 3 | `PAGE=2`, `FREEZE=3`; EN ve DE | Çerçeve, seal, rozetler, Pro satırı, "Start cutting"; satın alma butonu yok |
| UMP sırası | Temiz kurulum | Onay formu onboarding'de çıkmaz, ana ekranda çıkar |
| Welcome hapı + paneli | `CUTSENSE_SKIP_ONBOARDING=1`, `CUTSENSE_FORCE_WELCOME_OFFER=1`, `CUTSENSE_FAKE_PRICES=1` | Hap "Pro −50%" (sayaçsız); PRO kapsülü gizli; panelde üstü çizili $7.99, $3.99, bitiş tarihi, Restore, Terms, Privacy |
| Gerçek tetik | `CUTSENSE_SKIP_ONBOARDING=1`, `CUTSENSE_FAKE_PRICES=1`, `CUTSENSE_AUTORUN_VIDEO_URL=…` olmadan elle bir video kaydet | Kayıtta hap belirir; "New Video"da panel bir kez açılır, ikinci kez açılmaz |
| Flash | `CUTSENSE_FORCE_FLASH_OFFER=1`, `CUTSENSE_FAKE_PRICES=1` | Hap sayaçlı; panelde sayaç ve azalan çizgi |
| Relaunch | Aynı, `FORCE` olmadan | Kalan süre devam eder |
| Bitiş | `CUTSENSE_OFFER_SECONDS=20`, panel açık | 0:00'da `PaywallView`'a döner; hap kaybolur; PRO kapsülü geri gelir |
| Pro sahibi | `CUTSENSE_FORCE_PRO=1` + `FORCE_FLASH_OFFER=1` | Hap ve panel yok |
| Satın alma hatası | Fixture ile CTA | "The product could not be loaded right now…" mesajı + `.warning` |
| Bypass | `CUTSENSE_AUTORUN_VIDEO_URL=…` ya da `CUTSENSE_SHOW_PAYWALL=1` | Onboarding çıkmaz |
| Home 6.9" | Tam boy, clamp'siz | Alt yazı ile kontroller arasında 24 pt; hero büyümüş. Clamp'te hero 96 |
| Autoplay | `CUTSENSE_FORCE_PRO=1` ile review | Video kendiliğinden sesli başlar; yoğunluk değişince yeniden başlamaz |
| Autoplay (reklamlı) | Reklamlar açık, review | Reklam kartı ve reklam sırasında oynatma yok; reklam kapanınca başlar |
| Reduce Motion | Ayarlar'dan açık | Statik kareler, fade |

Xcode Run (StoreKit config ile):
- Welcome'dan satın al → Pro açılır; uygulama kapatılıp açılınca Pro kalır.
- Normal ürünü alan kullanıcıda teklif CTA'sı hiç görünmez.

**Risk:**
- RISK (review): İndirimli ürünü görmek için reviewer'ın bir video kaydetmesi gerekir. Not adımları veriyor ama cihazında video yoksa "IAP bulunamadı" reddi gelebilir. Geri dönüş: `.offer` ürünü gönderimden çekilir; `offerPrices` nil kalır ve tüm teklif yüzeyleri kendiliğinden kaybolur.
- UNVERIFIED: Aynı entitlement'ı veren iki non-consumable'ın Apple tarafından kabulü; ASC'de display name benzersizliği ("CutSense Pro Offer" bu yüzden seçildi).
- UNVERIFIED (hukuk): Üstü çizili "Regular price" AB Omnibus ve FTC açısından; $7.99 eşzamanlı ve sürekli satışta. Hukuki görüş alınmadı.
- UNVERIFIED: İlk kayıt teklifinin onboarding sonu teklifinden daha iyi dönüştüreceği; veri ve A/B altyapısı yok. Gerekçe erişim (herkes) ile niyet (değer görmüş kullanıcı) takasıdır. Tek ölçüm ASC'deki SKU adetleridir.
- UNVERIFIED: $3.99'un $4.99'a göre net geliri.
- UNVERIFIED: `simctl launch` ile StoreKit config bağlanmıyor varsayıldı; görüntüler fixture'a dayanır. `SKTestSession` satın alması bu hostta atlanıyor.
- UNVERIFIED: iOS 26'da `.principal` öğesinin camsız çizilmesi ve 16e'de gear + privacy glifleriyle sığması.
- UNVERIFIED (autoplay): Skip'in `processingAdTask`'ı iptal edip etmediği okunmadı. İptal ediyorsa `defer` içindeki `!Task.isCancelled` autoplay'i atlar; o durumda Skip işleyicisine de `preview.autoplayOnce()` eklenir. "Soluk, duraklatılmış" görüntünün kaynağı (sistem kontrol katmanı) ekran görüntüsünde doğrulanmadı.
- UNVERIFIED (home): `SignalField` bar yüksekliğinin çerçeve yüksekliğiyle ölçeklendiği ve 220 pt'de iyi göründüğü. Kötü görünürse `maxHeight` 160'a iner.
- RISK: Sesli autoplay sessiz ortamda rahatsız edebilir; oturum `.playback` olduğu için sessiz anahtarı dinlenmez. Şikâyet gelirse autoplay yalnız Pro yoluna daraltılır.
- RISK: F ve G derlemeden yazar; entegrasyonda bir derleme turu beklenir.
- Bakılmayanlar: B'nin son `QuickSilenceView` hali, `SettingsScreen` Pro kartı gövdesi, JA/KO fiyat genişliği, 7 dilin çevirileri. Kod yazılmadı, build alınmadı.
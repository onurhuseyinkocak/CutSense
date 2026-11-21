## Karar

**1.1.0 = "güven + gelir" sürümü.** Uygulama ücretsiz, filigransız ve reklamlı kalır. Eklenenler: dışa aktarmadan önce önizleme ve kesim-başına geri alma, tek seferlik `CutSense Pro` ($7.99, StoreKit 2, abonelik yok), sıkı geçici dosya temizliği, 9 dilli UI. ASO değişikliği 1.1.0'ı beklemez: 1.0.4 incelemeden çekilir, yeni isim/anahtar kelimelerle aynı build 30 hemen yeniden gönderilir.

**Gerçekçilik (2. madde):** 1M kullanıcı/30 gün fiilen imkânsız; $2500/ay 30 günde çok düşük olasılık (tahminim <%2, UNVERIFIED).
- Taban (VERIFIED): 16 indirme/5 hafta, AdMob ~₺38/ay, 7 günde 54 gösterim.
- 1M/30 gün = günde ~33.000 indirme. Nişin en büyük doğrudan rakibi 30 puanlı; ivmesi olan tek komşu uygulama CutAI 2.2K puanlı.
- $2500 için Pro $7.99 → net $6.79 (%15 komisyon) veya $5.59 (%30) → ayda 368–447 satın alma. %2 dönüşümle (UNVERIFIED) ayda 18–22 bin indirme gerekir; bu bugünkü hızın ~1.100–1.400 katı.
- Yalnız reklamla $2500, bugünkü eCPM'de ayda ~1.3M gösterim ister.
- Gerçekçi 30 gün hedefi (UNVERIFIED): 300–2.000 indirme, $20–200. Üst kuyruk yalnız viral kısa videoyla açılır; bu da sahibin sosyal hesabını gerektirir.

**Mevcut uygulamanın eleştirisi (1. madde), önem sırasıyla — hepsi VERIFIED:**
1. **Kör kesim.** Önizleme ve geri alma yok; sertlik değişince tüm analiz ve export baştan koşuyor (`rerunCurrentInput`, `QuickSilenceView.swift:402`). Pazardaki 1 numaralı şikâyet olan aşırı kesmeye karşı savunma yok; varsayılan da `.tight`.
2. **Sevinç anında reklam.** Sonuç ekranı açıldıktan 0.85 sn sonra 3 sn geri sayım başlıyor ve kullanıcı Atla'ya basmazsa tam ekran reklam açılıyor (`:557`). Reklamdan kurtulmanın ücretli yolu yok.
3. **Sonuç ekranı dağınık.** Oynatıcı, 3 istatistik, picker ve 4 alt alta buton scroll içinde; "Aynı Videoyu Tekrar Kes" bir mimari eksiğin UI'a sızması.
4. **İşleme ekranı mühendis ekranı.** Olay günlüğü (`WorkTimeline`), aşama destesi, "Uyumluluk modu", banner ve native reklam aynı anda.
5. **Depolama sızıntısı.**
   - İçe aktarma tam kopya alıyor (`VideoImportService.swift:116`) ve `reset()` bunu silmiyor.
   - Her yeniden kesim yeni bir MP4 bırakıyor; bilinçli olarak silinmiyor (`:438` yorumu), yalnız açılış süpürmesi temizliyor.
   - Ölü `QuickMovie` (`:956`) `input-*.mov` yazıyor; süpürmenin `cutsense-` öneki bunu yakalamaz.
6. **Dil.** 13 mağaza dili var, UI yalnız TR/EN. `VideoImportService.ImportError` yalnız Türkçe (`:26-28`), yani İngilizce kullanıcı Türkçe hata görüyor. `CFBundleLocalizations` olmadığı için sistem bileşenleri (PhotosPicker, paylaşım) İngilizce kalıyor.
7. **Ana ekran boş.** Makas ikonu ve tek buton; "ücretsiz / filigransız / cihazda" kanıtı yok. En görünür ikincil öğe TR/EN anahtarı.
8. **Hata mesajı çıkmaz sokak** ("daha kısa video seç"), boş alan kontrolü yok, puan isteği yok.
9. **Yan bulgu:** `ios/scripts/verify.sh` `iPhone 17 Pro` hedefliyor; simülatör kuralını ihlal ediyor.

**Gelir modeli (3. madde):**
- **Ürün:** tek non-consumable, `com.cutsense.app.pro.lifetime`, $7.99 (US taban, diğer bölgeler Apple eşitlemesi). Deneme yok; ücretsiz katman denemenin kendisi.
- **Ücretsiz:** sınırsız kesim, önizleme, kesim-başına geri alma, 3 ön ayar, filigransız, orijinal çözünürlük, reklamlı (24 saatlik ödül yolu aynen kalır).
- **Pro:** tüm reklamlar kalıcı kapalı + "Fine-tune" (iki kaydırıcı: en kısa duraklama, nefes payı) + gelecekteki Pro özellikleri.
- **Paywall yerleri:** ana ekran toolbar'ında "PRO" kapsülü, reklam-arası kartında "Remove ads forever", kilitli Fine-tune satırı, Ayarlar satırı. Açılışta veya export önünde paywall yok.
- **Altyapı:** StoreKit 2 doğrudan. RevenueCat reddedildi: bağımlılık ve ağ çağrısı ekler, tek ürün için gereksiz.
- **Reddedilen tuzak:** haftalık abonelik. Yorumlardaki en yüksek sesli şikâyet abonelik; 3.1.2 inceleme riski ve yasal metin yükü de getirir. "No subscription" mağaza satırı olarak kullanılacak.
- ASC'deki boş `CutSense Pro` abonelik grubuna (22125338) dokunulmaz.

**1.1.0 kapsamı (4. madde):**

| Durum | Özellik |
|---|---|
| IN | Önizleme + kesim listesi/geri alma + anlık sertlik değişimi (export yalnız Kaydet/Paylaş'ta) |
| IN | Pro + paywall |
| IN | Depolama temizliği + Ayarlar'da kullanım/temizle + boş alan kontrolü |
| IN | Kaydetme sonrası puan isteği |
| IN | Sadeleşmiş işleme ekranı, ana ekranda güven satırı |
| IN | 9 dil: en, tr, es, pt, de, fr, it, ja, ko (seri son geçiş, tek commit, kesilebilir) |
| OUT (1.2) | Dolgu kelime silme, otomatik altyazı (Speech izni, dil-başına cihaz-içi kullanılabilirlik ve doğrulama süresi yüzünden) |
| OUT | WhisperKit (boyut bütçesi), 9:16, toplu işlem, Files'tan içe aktarma, onboarding, filigran, TikTok'a doğrudan paylaşım, izin metni çevirisi (`InfoPlist.xcstrings`) |

"Orijinal kalite" zaten var (passthrough önce); yeni kod değil, mağaza metni.

**ASO (5. madde).** Karakter sayıları programla sayıldı (VERIFIED):

| Locale | Name | Subtitle | Keywords |
|---|---|---|---|
| en-US | `Silence Remover: CutSense` (25) | `Remove Pauses, Auto Jump Cut` (28, aynı) | `video,cutter,dead air,trim,editor,talking head,filler,podcast,reels,shorts,tiktok,ugc,vlog,audio` (96) |
| en-GB | aynı isim | mevcut | `video,cutter,dead air,remove,editor,talking head,podcast,reels,shorts,tiktok,vlog,audio,gaps,speech` (99) |
| en-AU / en-CA | aynı isim | mevcut | `video,cutter,dead air,remove,trim,editor,talking head,podcast,reels,shorts,tiktok,vlog,audio,gaps` (97) |
| tr | `Sessizlik Silme: CutSense` (25) | `Duraksamaları Sil, Jump Cut` (27, aynı) | `sessizlik kaldırıcı,silici,video kesme,boşluk,kırpma,düzenleme,reels,shorts,tiktok,podcast,vlog,ses` (99) |
| es-ES | `Eliminar Silencios: CutSense` (28) | `Quitar pausas, jump cut auto` (28) | `cortar,vídeo,video,editor,recortar,silencio,pausa,reels,tiktok,podcast,vlog,youtube,shorts,audio` (96) |
| es-MX | `Quitar Silencios: CutSense` (26) | `Elimina pausas, jump cut auto` (29) | `jumpcut,autocut,trimmer,shorten,clip,speech,lecture,cortar,recortar,editor,reels,tiktok,podcast,vlog` (100) |
| pt-BR | `Remover Silêncio: CutSense` (26) | `Cortar pausas, jump cut auto` (28) | `vídeo,video,editor,aparar,encurtar,silencio,pausa,tirar,reels,tiktok,podcast,vlog,youtube,shorts` (96) |

- de/fr/it/ja/ko değişmez.
- es-MX'in ABD mağazasında da indekslendiği varsayımı UNVERIFIED.
- "silence cutter" #2 sırası `cutter` anahtar kelimesiyle korunmaya çalışılır; kayıp riski kabul edildi.
- **Ekran görüntüleri (1.1.0):** boş ana ekran ilk sıradan çıkar (mevcut `01_home.png` TR/EN anahtarlı boş bir ekran). `compose.py` satırları:
  1. `('Remove silence',False),('in one tap',True)` / `Free. No watermark. No sign-up.` — ham görüntü: review ekranı
  2. `('Review',False),('every cut',True)` / `Restore any pause before you save.` — kesim listesi sheet'i
  3. `('32s video,',False),('19s cut',True)` / `Dead air gone. Original untouched.` — mevcut
  4. `('Runs on',False),('your iPhone',True)` / `Your video is never uploaded.`
  5. `('No',False),('subscription',True)` / `Free with ads. One-time Pro removes them.` — paywall

**Yayın mekaniği (6. madde):** 1.0.4 incelemeden çekilir, ASO uygulanır, build 30 aynı gün yeniden gönderilir (kuyruk kaybı < 1 gün; ASO 2–3 gün erken canlıya çıkar). 1.1.0 = `MARKETING_VERSION 1.1.0`, `CURRENT_PROJECT_VERSION 31`. 1.1.0 hazır olduğunda 1.0.4 hâlâ incelemedeyse o da iptal edilir ve yerine 1.1.0 gönderilir.

**Büyüme, $0 (7. madde):**
- **Ajan yapabilir:** ASO (yukarıdaki), puan isteği, yeni ekran görüntüleri, `asc` ile yorum yanıtları, `cutsense.onarika.net` üzerinde "remove silence from video iphone" ve TR/ES/PT karşılıkları için açılış sayfaları (CF Worker, ücretsiz), ffmpeg + simülatör kaydıyla önce/sonra demo videoları üretmek.
- **Sahibi olmadan imkânsız:** TikTok/Reels/Shorts/Reddit paylaşımı (kişisel hesap ve yüz), Paid Apps sözleşmesi + banka/vergi, Small Business Program başvurusu, ASC web 2FA, reklam ağı hesapları (mediation).
- Product Hunt atlanır: araştırmadaki örnek 4 puan aldı.

## Adımlar

`ROOT = /Users/jinx/Documents/projeler/CutSense/ios`. Branch: `release/1.1.0` (main'den). Tüm builder'lar aynı çalışma ağacında, yalnız kendi dosyalarında çalışır. `xcodebuild` aynı anda tek tane koşar (16 GB RAM, tek simülatör); sırayı yürütücü verir. DerivedData: `-derivedDataPath /private/tmp/claude-501/-Users-jinx/c6915351-0541-4085-8acb-38700776b4dc/scratchpad/dd`, iş bitince silinir.

**Adım 0 — yürütücü, seri, dalga 1'den önce**

0a. Boyut tabanı: `f8c08bd`'de Release build al, `du -sk <dd>/Build/Products/Release-iphoneos/CutSense.app` değerini kaydet.

0b. `ROOT/project.yml`:
- `MARKETING_VERSION: "1.1.0"`, `CURRENT_PROJECT_VERSION: 31`.
- `sources`'a ekle: `- path: CutSense/Pro` ve `- path: CutSense/Storage`, ikisi de `optional: true` (XcodeGen 2.45.3'te scratch ile VERIFIED).
- `- path: CutSense/Services/AppLanguage.swift` satırını `- path: CutSense/Services` + `includes: ["AppLanguage.swift", "Translations.swift"]` yap.
- `info.properties`'e `CFBundleLocalizations: [en, tr, es, pt-BR, de, fr, it, ja, ko]`.
- `schemes.CutSense.run.storeKitConfiguration: CutSense/Pro/Products.storekit` (VERIFIED).
- `CutSenseTests.sources`'a `- path: CutSense/Pro/Products.storekit` (`optional: true`).
- `UI/LanguageSwitcher.swift` satırını sil.

0c. `ROOT/scripts/verify.sh`: `name=iPhone 17 Pro` → `name=iPhone 17 Pro Max`.

0d. ASO + 1.0.4 (koddan bağımsız, hemen):
1. `asc submit cancel --version-id f46a1272-2f28-4e96-93f6-88007cec37f0 --app 6770024868 --confirm`
2. `asc apps info list --app 6770024868` ile düzenlenebilir app-info ID'sini al (şu an `ceec6ec5-0aa0-4293-b099-57b88e067b34`).
3. Her locale için: `asc localizations update --app 6770024868 --type app-info --app-info <ID> --locale <L> --name "…" --subtitle "…"`
4. Her locale için: `asc localizations update --version f46a1272-2f28-4e96-93f6-88007cec37f0 --locale <L> --keywords "…"`
5. `asc review doctor --app 6770024868`, ardından `asc review submit --app 6770024868 --version "1.0.4" --build <build 30 ID> --confirm`. Bayrakları önce `--help` ile doğrula.

0e. IAP: `asc iap setup --app 6770024868 --type NON_CONSUMABLE --reference-name "Pro Lifetime" --product-id "com.cutsense.app.pro.lifetime" --locale "en-US" --display-name "CutSense Pro" --description "Remove all ads and unlock fine-tune controls." --price "7.99" --base-territory "United States"`. TR/es/pt yerelleştirmeleri `asc iap localizations` ile eklenir.

**Dalga 1 — paralel, dosya çakışması sıfır**

**Görev A — Motor bölme.** Sahiplik: `ROOT/CutSense/QuickSilence/QuickSilenceEngine.swift`, yeni `ROOT/CutSense/Tests/Release/QuickSilencePlanTests.swift`.

`QuickSilenceEngine`'e eklenecek API:
```swift
struct CutSettings: Sendable, Equatable {
    var minSilence: Double; var pad: Double; var minCutLength: Double; var thresholdFallbackDB: Float
    init(_ intensity: CutIntensity)
}
struct Analysis: Sendable { let windowRMS: [Float]; let duration: Double }
struct Cut: Identifiable, Sendable, Equatable { let id: Int; let range: ClosedRange<Double>; var isRestored: Bool }
struct CutPlan: Sendable, Equatable {
    let duration: Double; var cuts: [Cut]
    var keepRanges: [ClosedRange<Double>]; var outputDuration: Double; var removedPercent: Int
    func outputTime(forOriginal t: Double) -> Double
}
static func analyze(url: URL, language: AppLanguage, progress: @escaping @MainActor (ProgressUpdate) -> Void) async throws -> Analysis
static func plan(_ analysis: Analysis, settings: CutSettings) throws -> CutPlan
@MainActor static func makePreviewItem(url: URL, plan: CutPlan) async throws -> AVPlayerItem
static func export(url: URL, plan: CutPlan, language: AppLanguage, progress: @escaping @MainActor (ProgressUpdate) -> Void) async throws -> Result
```

Kurallar:
- `CutSettings.init(intensity)`: `minCutLength = max(finalMinimumRemovedGap, mergeGap)`. Bu, `merged(gap:)` ile eşdeğerdir (kısa kesimleri düşürür); böylece `cuts` listesi gerçekten silinenlerle birebir olur.
- `Analysis.windowRMS = AudioAnalysisService.analyze(...).segments.map(\.energy)`. `AudioAnalysisService.swift` değişmez.
- `plan` saf ve senkron: `silenceThreshold` → `classify(minSilence:)` → `protectedCutRanges` → `minCutLength` altını at. Hiç konuşma yoksa `Failure.nothingToKeep`.
- `keepRanges`, `isRestored == false` kesimlerin tümleyenidir.
- Kompozisyon kurma tek özel yardımcıda toplanır; `makePreviewItem` ve `export` onu kullanır. Swift 6 non-Sendable dönüş hatası çıkarsa yardımcının dönüşü `sending` işaretlenir.
- Mevcut `cut(url:intensity:language:progress:)` imzası korunur; gövdesi `analyze → plan → export` olur.
- `sweepTemporaryFiles` bu görevde yerinde kalır.

Kabul:
- Mevcut 7 test değişmeden geçer.
- `plan` her intensity için fixture'da 4 kesim verir.
- Bir kesim `isRestored = true` yapılınca `outputDuration` o kesimin uzunluğu kadar artar.
- `outputTime(forOriginal:)` kesim öncesi, içi ve sonrası için doğru.
- `export` sonrası tmp'de tam 1 yeni `cutsense-*` dosyası kalır (passthrough/fallback artığı yok).
- Geri alınmış planla export süresi `plan.outputDuration` ± 0.2 sn.

**Görev B — Depolama.** Sahiplik: yeni `ROOT/CutSense/Storage/WorkFiles.swift`, `ROOT/CutSense/Video/VideoImportService.swift`, yeni `ROOT/CutSense/Tests/Release/WorkFilesTests.swift`.

```swift
enum WorkFiles {                       // nonisolated, yalnız FileManager
    static let importsDirectory: URL   // Caches/CutSense/imports
    static func isManaged(_ url: URL) -> Bool   // importsDirectory içi VEYA tmp + "cutsense-" öneki
    static func delete(_ url: URL?)             // isManaged değilse no-op
    static func sweepAtLaunch()                 // tüm managed dosyalar + eski "input-*.mov"
    static func usageBytes() -> Int64
    static func clearUnused(keeping: Set<URL>) -> Int64
    static func availableBytes() -> Int64       // volumeAvailableCapacityForImportantUsage
}
@MainActor final class WorkSession {
    private(set) var inputURL: URL?; private(set) var outputURL: URL?
    var urlsInUse: Set<URL>
    func begin(input: URL)     // önceki oturumu end() eder
    func setOutput(_ url: URL) // önceki çıktıyı siler: aynı anda en fazla 1 çıktı
    func discardOutput()
    func end()                 // girdi (managed ise) + çıktı silinir
}
```

`VideoImportService` değişiklikleri:
- `importing` kapanışında önce `moveItem`, hata verirse `copyItem` (çift kopya zirvesini önler); hedef `WorkFiles.importsDirectory`.
- `errorMessage: String?` kaldırılır; yerine `private(set) var error: ImportError?` ve `ImportError.message(for: AppLanguage)` (tr/en `appText` ile).
- `func discardImport()` eklenir (dosyayı siler, URL'yi nil yapar).

Kabul testleri:
- (a) Managed olmayan yol (ör. tmp altında `fixture-x.mp4`) `delete`/`end` sonrası durur. DEBUG autorun fixture'ını korur.
- (b) `sweepAtLaunch` imports + `cutsense-*` + `input-*.mov` siler.
- (c) `begin → setOutput → discardOutput`: çıktı yok, girdi var.
- (d) `setOutput` iki kez: ilki silinmiş (kaydet-sonra-paylaş senaryosu).
- (e) `end`: ikisi de yok.
- (f) `clearUnused(keeping:)` kullanımdakini korur, dönen bayt doğru.
- (g) `usageBytes` yazılan baytla eşleşir.

**Görev D — Pro.** Sahiplik: yeni `ROOT/CutSense/Pro/ProStore.swift`, `ROOT/CutSense/Pro/PaywallView.swift`, `ROOT/CutSense/Pro/Products.storekit`, `ROOT/CutSense/Ads/AdMobService.swift` (yalnız `isEnabled`), yeni `ROOT/CutSense/Tests/Release/ProStoreTests.swift`.

```swift
enum ProEntitlement {                  // nonisolated; AdMobService.isEnabled okur
    static let key = "pro_unlocked"
    static var isPro: Bool             // UserDefaults; DEBUG'da env CUTSENSE_FORCE_PRO=1 → true
}
@MainActor @Observable final class ProStore {
    static let shared: ProStore
    static let lifetimeID = "com.cutsense.app.pro.lifetime"
    private(set) var product: Product?; private(set) var isPro: Bool
    var canOfferPro: Bool { product != nil && !isPro }
    func start()                       // ürün yükle, Transaction.currentEntitlements ile tazele, Transaction.updates dinle
    func purchase() async -> Outcome   // .purchased / .cancelled / .pending / .failed(String)
    func restore() async               // AppStore.sync() + tazele
}
struct PaywallView: View { init(language: AppLanguage) }
```

Kurallar:
- `AdMobService.isEnabled` koşuluna `&& !ProEntitlement.isPro` eklenir. Bu tek kapı banner, native, ödüllü reklam, UMP onayı ve gizlilik düğmesini birlikte kapatır; hepsi `isEnabled` kontrol ediyor (VERIFIED).
- `ProStore` her tazelemede `ProEntitlement.key`'i yazar; iade olursa false'a döner.
- `PaywallView` içeriği: başlık `CutSense Pro`; maddeler `No ads, ever` / `Fine-tune: minimum pause and breathing room` / `One-time purchase. No subscription.`; buton `Unlock for \(product.displayPrice)`; `Restore Purchases`; Terms + Privacy linkleri (`https://cutsense.onarika.net/terms`, `/privacy`). Emoji yok; mevcut koyu tema ve `ACC=(182,243,92)` vurgusu.
- `ROOT/CutSense/Store/*` (eski abonelik kodu) kullanılmaz.

Kabul:
- `SKTestSession(configurationFileNamed: "Products")` ile satın alma sonrası `isPro == true`, `ProEntitlement.isPro == true`, `canOfferPro == false`.
- İşlem temizlenip tazelenince false.
- Ürün yüklenemezse `canOfferPro == false`.
- `SKTestSession` test hedefinde çalışmazsa: test atlanmaz; simülatörde scheme'deki StoreKit config ile elle satın alma ekran görüntüsü kanıt sayılır ve durum UNVERIFIED raporlanır.

**Dalga 2 — Görev C, UI entegrasyonu (A, B, D birleşip yeşil olduktan sonra)**

Sahiplik: `ROOT/CutSense/QuickSilence/QuickSilenceView.swift`, `QuickSilenceApp.swift`, yeni `QuickSilence/ReviewScreen.swift`, yeni `QuickSilence/ShareSheet.swift`, `ROOT/CutSense/UI/SettingsScreen.swift`. `UI/LanguageSwitcher.swift` silinir.

**G0 kapısı (ilk iş, iPhone 16e):** 4K HEVC, 40+ kesimli klipte `makePreviewItem` oynatılır.
- `AVPlayerItem.status == .failed` veya kesimlerde > 1 sn donma varsa yedek kullanılır: orijinal dosyayı oynatan `AVPlayer` + 0.05 sn periyodik gözlemci, aktif kesime girince kesim sonuna seek eder.
- Yedekte de ek dosya yazılmaz; UI aynı kalır.

Akış ve kurallar:
1. `Phase`: `.idle / .working / .review / .failed`. Seç → içe aktar → `analyze` → `plan` → `.review`. Bu aşamada export yok, çıktı dosyası yok.
2. **Review ekranı** (16e'de scroll'suz): oynatıcı, 3 istatistik, `CutIntensityPicker` (değişince `plan` anında yeniden hesaplanır, geri almalar sıfırlanır), pasif zaman çubuğu (tutulan açık, kesilen koyu), `Review cuts (N)` butonu, `Save to Photos` (birincil), `Share`, `New Video`. `removedPercent > 60` ise ipucu: `Too much cut? Try Balanced.`
3. **Kesim sheet'i** (`.presentationDetents([.medium, .large])`): her satır `0:12 – 0:14 · 1.8s` + Cut/Keep anahtarı. Satıra dokununca önizleme `plan.outputTime(forOriginal: cut.range.lowerBound) - 1` konumuna gider. Anahtar değişince önizleme öğesi yeniden kurulur.
4. **Fine-tune:** `ProStore.shared.isPro` ise iki kaydırıcı (`minSilence` 0.15–1.5, `pad` 0.03–0.40). `canOfferPro` ise kilitli satır `PaywallView` açar. İkisi de değilse satır gizli.
5. **Kaydet:** `WorkFiles.availableBytes() < girdi boyutu × 1.1` ise `.failed("Not enough free storage…")`. Değilse `export` → `session.setOutput` → `PhotosSaveService.saveVideo` → başarıda `session.discardOutput()`.
6. **Paylaş:** `export` → `ShareSheet` (`UIActivityViewController`, `completionWithItemsHandler`) → kapanınca `session.discardOutput()`.
7. Plan değişimi, `New Video`, iptal, hata ve yeni seçim: `session.end()` + `importService.discardImport()`. Plan değişiminde yalnız `discardOutput()`.
8. Export sırasında `UIApplication.shared.isIdleTimerDisabled = true`. **Hiçbir reklam gösterilmez** (banner, native, ödüllü): reklama dokunmak uygulamayı arka plana atar ve export'u öldürür.
9. **Ödüllü reklam arası:** videoda bir kez, `.review`'a ilk girişte (bugünkü `startResultAdBreakIfNeeded` mantığı). Karta ikinci buton eklenir: `Remove ads forever` → paywall (yalnız `canOfferPro` iken).
10. **İşleme ekranı:** `WorkTimeline`, `workEvents`, `ProcessingStageDeck`, `ProcessingStageRow` silinir. Kalan: ilerleme, başlık, yüzde, İptal; yalnız içe aktarma/analizde native reklam.
11. **Ana ekran:** `LanguageSwitcher` kalkar. Butonun altına tek satır: `Free · No watermark · On-device`. Toolbar'da `canOfferPro` iken `PRO` kapsülü.
12. **Puan isteği:** `@Environment(\.requestReview)`; başarılı kayıttan 1.2 sn sonra; `UserDefaults "review_prompt_version"` ≠ güncel sürüm ve `!AdMobService.hasPresentedContent` ise.
13. `QuickMovie` silinir. Import hatası `importService.error?.message(for: appLanguage)` ile gösterilir.
14. `QuickSilenceApp.init`: `WorkFiles.sweepAtLaunch()` (eski çağrının yerine). `.task` içinde `ProStore.shared.start()`, `AdMobService.start()`'tan önce.
15. **`SettingsScreen`:**
    - "Storage" bölümü: `Temporary files: <ByteCountFormatter>` + `Clear` (`WorkFiles.clearUnused(keeping:)`), dipnot `CutSense keeps no copies of your videos.`
    - "CutSense Pro" bölümü: durum, `Unlock` (yalnız `canOfferPro` iken), `Restore Purchases`.

Kabul:
- Simülatörde `SIMCTL_CHILD_CUTSENSE_AUTORUN_VIDEO_URL` ile review ekranına ulaşılır; sertlik değişimi < 0.5 sn.
- Bir kesim geri alınınca "new length" artar ve kaydedilen dosyanın süresi eşleşir.
- Kaydet sonrası tmp'de `cutsense-*` yok.
- `CUTSENSE_FORCE_PRO=1` ile hiçbir reklam yüzeyi yok.

**Dalga 3 — Görev E, 9 dil (seri, tek başına, tek commit)**

Sahiplik: `ROOT/CutSense/Services/AppLanguage.swift`, yeni `ROOT/CutSense/Services/Translations.swift`, yeni `ROOT/CutSense/Tests/Release/TranslationsTests.swift`; ayrıca diğer dosyalarda yalnız interpolasyonlu `appText` çağrıları.

- `AppLanguage`: `tr, en, es, pt, de, fr, it, ja, ko`. `systemDefault` dil kodunu eşler, bilinmeyen `.en`.
- `appText(language, tr, en)`: tr → `tr`; en → `en`; diğer → `Translations.table[en]?[language] ?? en`. Çağrı yerleri değişmez; eksik çeviri İngilizce'ye düşer.
- Interpolasyonlu çağrılar `String(format: appText(language, "… %@", "… %@"), …)` biçimine çevrilir; anahtar format dizgisidir.
- Görev A'dan kalan `QuickSilenceEngine.sweepTemporaryFiles` burada silinir (artık çağıranı yok).
- Kabul: testte her tablo girdisinde 7 dil dolu ve `%` yer tutucu sayısı İngilizce ile eşit. de ve ja için ana, review, paywall, ayarlar ekran görüntülerinde kırpılma/taşma yok.
- **Kesme kuralı:** kabul geçmezse bu commit geri alınır ve 1.1.0 TR/EN ile çıkar.

**Dalga 4 — yürütücü**

`fable-reviewer` kapısı → Doğrulama → `compose.py` ile 5 ekran görüntüsü → `asc iap review-screenshots` ile paywall görüntüsü → `asc publish appstore --app 6770024868 … --version 1.1.0 --submit --confirm`. IAP'yi sürüme iliştirme yolu `asc iap submit --help` ile doğrulanır.

## Dokunma

- `ROOT/CutSense/RoughCut/AudioAnalysisService.swift`: eşikler ve sınıflandırma değişmez; mevcut kullanıcıların kesim davranışı aynı kalır.
- `AdMobIDs.swift`, `SKAdNetworkItems`, UMP onay akışı, ödüllü reklam intro + Skip, `AdFreePass` (24s/72s): inceleme uyumu buna bağlı.
- `PrivacyInfo.xcprivacy`, `PhotosSaveService.swift`, bundle ID, `DEVELOPMENT_TEAM`.
- `project.ugc-full.yml` ve hedefte olmayan eski dizinler (`Store/`, `Captions/`, `AI/` vb.): silme, kullanma.
- Yeni SPM paketi, gömülü model/medya, ağ çağrısı, backend, analitik SDK yok.
- ASC: abonelik grubu 22125338, yaş derecelendirmesi, fiyat/bölge, de/fr/it/ja/ko metadatası.
- Kullanıcının Fotoğraflar'ındaki orijinal video asla silinmez veya değiştirilmez. Temizlik yalnız `WorkFiles.isManaged` yollarında çalışır.
- Kodda kadın ismi yok, UI'da emoji yok.

## Doğrulama

1. **Birim testleri:** `cd ROOT && xcodegen generate && xcodebuild test -scheme CutSense -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath <dd>`. Beklenen: mevcut 7 + `QuickSilencePlanTests` + `WorkFilesTests` + `ProStoreTests` + `TranslationsTests` yeşil.
2. `ROOT/scripts/verify.sh` exit 0 (0c düzeltmesinden sonra).
3. **Boyut bütçesi:** Release `.app` `du -sk` değeri, 0a tabanı + 1.500 KB'ı geçmez. `project.yml`'de yeni `packages` girdisi yok.
4. **Simülatör (iPhone 17 Pro Max), ekran görüntüleriyle.** Test videosu `say` + `ffmpeg` ile scratchpad'de üretilir.
   - Ana ekran, analiz, review, kesim sheet'i (bir kesim geri alınmış), paywall, ayarlar (Storage satırı).
   - `CUTSENSE_FORCE_PRO=1` ile reklamsız review.
   - de ve ja ekranları.
5. **iPhone 16e (`00008140-0011694C2629401C`):**
   - G0 kapısı.
   - 4K klipte kaydet → Fotoğraflar'da çözünürlük ve süre doğru.
   - Kaydet → paylaş → New Video sonrası Ayarlar > Storage "0" (ya da `Zero KB`).
   - Uygulamayı export ortasında öldür → yeniden aç → Storage 0.
   - Ürün yükleniyorsa sandbox satın alma + Restore.
6. **Hata yolları:**
   - Sessiz video → "no audio" mesajı, cihaz dilinde.
   - Fotoğraflar izni reddi → Ayarları Aç.
   - Export sırasında İptal → tmp temiz.
   - Boş alan yetersiz dalı, testte `availableBytes` eşiği enjekte edilerek.
   - Ürün yüklenmezse hiçbir Pro girişi görünmez.
7. **ASO:** `asc localizations list --app 6770024868 --type app-info --app-info <ID>` ve `--version f46a1272-…` çıktıları tablodaki dizgilerle birebir. `asc review status --app 6770024868` → WAITING_FOR_REVIEW.

## Risk

- **UNVERIFIED — Paid Apps sözleşmesi.** Aktif değilse ürün sandbox'ta bile yüklenmez. Plan buna bağımlı değil (`canOfferPro == false` → uygulama aynen ücretsiz + reklamlı çıkar), ama gelir sıfır kalır. Açacak tek kişi sahibi (ASC > Business).
- **UNVERIFIED — kompozisyon önizlemesi.** 4K HEVC ve çok kesimde cihazda akıcılığı kanıtlanmadı; G0 kapısı ve yedek tanımlı.
- **UNVERIFIED — metadata kilidi.** İsim/alt başlık/anahtar kelimelerin WAITING_FOR_REVIEW'da kilitli olduğu ve iptalden sonra app-info ID'sinin aynı kaldığı varsayım. 0d-2 yeniden listeler.
- **UNVERIFIED — `asc` yolları.** IAP'yi sürüme iliştirme ve `asc review submit` bayrakları yalnız `--help` düzeyinde görüldü. Olmazsa ASC web gerekir (2FA = sahibi).
- **UNVERIFIED — gelir tahminleri.** %2 dönüşüm, 30 günlük indirme aralığı ve Small Business Program üyeliği (%15 ya da %30).
- **UNVERIFIED — sıralama etkisi.** İsim değişikliğinin "silence remover" sırasına etkisi ve "silence cutter" #2'nin korunması.
- **RISK — çeviriler.** 7 dil model çevirisi; ana dili konuşan biri kontrol etmedi.
- **RISK — yeniden export.** Kaydet sonrası Paylaş yeniden export eder. Passthrough'da saniyeler; uzun videoda fallback re-encode dakikalar sürebilir. Depolama kuralı lehine kabul edildi.
- **RISK — kalite iddiası.** Fallback ön ayarları 4K'yı 1080p'ye düşürebilir; mağaza metninde mutlak "no re-encode" iddiası kullanılmadı.
- **RISK — rakip.** Instagram First Draft tek-özellik kullanımını yapısal olarak tehdit ediyor; 1.2'de altyazı/dolgu kelime olmadan farklılaşma zayıf.
- **Repo kuralı uyumsuzluğu.** `ROOT/CLAUDE.md` içindeki `Tests/CutSenseQualityTests`, golden senaryolar ve ExportVerificationReport kapıları eski UGC hedefine ait; o hedef derlenmiyor. Yayın hedefi için geçerli kapı `CutSenseTests`'tir. O dosyanın tamamlanma dili ve kanıt kuralları geçerli kalır.
- **Atlananlar / bakılmayanlar:** `NativeAdCard.swift` okunmadı; `02_processing.png` açılmadı; rakip ekran görüntüleri ve ES/PT arama hacimleri bilinmiyor; 1.0.4'ün incelemede ne kadar beklediği ölçülmedi; mevcut IPA boyutu ölçülmedi (0a ölçer).
# Monetization gap audit + 14-day plan (Fable)

**Karar:** Darboğaz dönüşüm hunisi değil, trafik: 5 haftada 16 indirme, ABD'de 0 puan. Bugün yalnız, satın almaya hazır kullanıcının teklifi hiç görmediği iki deliği kapat (2 küçük kod değişikliği), fiyatı 16 düşük gelirli ülkede elle indir, sonra 14 günü Türkçe kısa videoya ve puan toplamaya harca. AdMob'a, Product Hunt'a, CPP/PPO testlerine bu hacimde dokunma. 14 günde gerçekçi gelir $0–40, 30 günde $20–200; $2.500/ay organik olarak bu sürede gerçekçi değil.

## 0. Para kazanma politikasının zayıf noktaları (gelir etkisine göre)

| # | Açık | Kanıt | Etki | Çözüm | Ne zaman |
|---|---|---|---|---|---|
| 1 | Trafik yok; huni ayarı sıfırla çarpılıyor | 16 indirme/5 hafta (`docs/plan-1.1.0.md`), iTunes lookup: ABD 0 puan | Gelirin tamamı | Adım 5–8 | Bugün + R+0..14 |
| 2 | "Geç" karşılama teklifini tamamen atlıyor | `OnboardingView.swift:102` `finish` çağırıyor, teklif yalnız `advance()` :199-203'te | Yeni kurulumların teklif görme oranı tahminen yarı → tamamı (UNVERIFIED) | Geç → teklif adımı | **1.1.0 bugün** |
| 3 | Flash teklif yalnız kurulumdan +10..+25 dk arasında uygulama açıksa görünür, sonra kalıcı ölür | `OfferCenter.swift:28-29`, `:58` (`t >= end` → `cancel()`) | İlk oturum 3–5 dk sürer; çoğu kullanıcı $3.99'u hiç görmez, 1. günden sonra yalnız $7.99 kalır | Pencere, +10 dk sonrası ilk ön plana gelişte başlasın | **1.1.0 bugün** |
| 4 | Fiyat yerel alım gücüne göre değil | ASC: tüm ülkeler otomatik eşitleme; TR bugün ₺399,99, 3 Aralık'ta ₺499,99 | Senin kitlen TR; ₺500 tek özellikli araç için satmaz | Adım 3 tablosu | Bugün, kodsuz |
| 5 | Kaydetme anında (değerin zirvesi) Pro hiç görünmüyor | `showsPaywall = true` yalnız `QuickSilenceView.swift:133,144,438,442,457,921`; `:677-678` kaydetmede yalnız puan istemi | Tekrar kullanan en değerli kitle teklif görmüyor | Kayıt sonrası Pro satırı + 3. kayıtta paywall | 1.1.1 |
| 6 | Kurulum başına tek teklif; geri dönen kullanıcıya indirim yok | `OfferCenter.swift:71` `armed` bir kez | 7. gün dönen kullanıcı yalnız tam fiyat görür | Sürüm güncellemesinde tek seferlik yeniden kurma (politika kararı) | 1.1.1 |
| 7 | Mağaza sayfasında IAP tanıtımı yok | `asc iap promoted-purchases list` boş; kodda `PurchaseIntent` yok | Bu hacimde küçük | `PurchaseIntent` dinleyicisi + promoted IAP | 1.1.1 |
| 8 | Reklam geliri ihmal edilebilir | 7 günde 54 gösterim, ayda ~₺38 | DAU 200'ü geçmeden sıfıra yakın | Mediation adaptör ister, kodsuz değil | DAU > 200 olunca |

Sağlam olanlar, dokunma: puan istemi ilk başarılı kayıttan 1,2 sn sonra (`:795-808`), reklam arasında "Reklamları kaldır" (`:454-457`), 3 tutma sınırı, üç ayrı SKU (ASC'de yüzey başına ücretsiz ölçüm verir). Abonelik ekleme: "abonelik yok" pazardaki en yüksek sesli talep ve tek farkın. "Made with CutSense" bitiş kartı da reddedildi; "filigransız" vaadi 39 dilde yazılı.

## Adımlar

**Bugün, gönderimden önce (sıra bağlayıcı)**

1. **Geç → teklif.** `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/QuickSilence/OnboardingView.swift`
   - `advance()` içindeki `:201-202` satırlarını `private func offerOrFinish()` olarak ayır; `advance()` son sayfada onu çağırsın.
   - `:102` `Button(t("Geç","Skip"), action: finish)` → `action: offerOrFinish`.
   - `Tests/UI/OfferFlowUITests.swift:64` `testOnboardingSkipAndSwipe`: Geç'ten sonra `offerNotNow`'a dokunmayı ekle.
   - Bu, `docs/offer-policy-owner.md` Flow madde 2'yi geçersiz kılar; dosyaya tek satır not düş.

2. **Flash penceresi görülebildiği anda başlasın.** `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Pro/OfferCenter.swift`
   - `Key`'e `static let opened = "offer_flash_opened"` ekle, `Key.all`'a da.
   - `init`'e `isForeground: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active }` ekle (`import UIKit`).
   - `refresh()` içinde `start`/`end` okunduktan sonra, `if t >= end` satırından önce: `t >= start` ve `opened` false ise:
     - ön planda değilse `publish(nil, nil)` ve `return` (iptal etme);
     - ön plandaysa `opened = true`, `startsAt = t`, `endsAt = t + duration(flashSeconds)` yaz, yerel `start`/`end`'i güncelle.
   - Süre gerçek kalır (ilk gösterimden 15 dk), kurulum başına bir kez kalır.
   - `Tests/Release/OfferCenterTests.swift`: "pencere uygulama kapalıyken geçti → iptal" bekleyen testi "ilk ön planda açılır, 15 dk sonra biter" olarak güncelle; testlerde `isForeground: { true }` ver.
   - 30 dk içinde cihazda geçmezse bu adımı at, 1.1.1'e taşı. Adım 1 tek başına gider.

3. **Fiyatlar (asc, kodsuz).** IAP kimlikleri: regular `6837688999`, welcome `6837794688`, flash `6837787623`. ABD $7.99/$5.99/$3.99 aynı kalır.

   | Ülke | Regular | Welcome | Flash | Regular price point |
   |---|---|---|---|---|
   | TUR | ₺199,99 | 149,99 | 99,99 | 10200 |
   | IND | ₹299 | 229 | 149 | 10088 |
   | BRA | R$24,90 | 19,90 | 12,90 | 10097 |
   | IDN | Rp59.000 | 45.000 | 29.000 | 10095 |
   | MEX | $99 | 79 | 49 | 10095 |
   | PHL | ₱249 | 199 | 129 | 10074 |
   | VNM | ₫99.000 | 79.000 | 49.000 | 10095 |
   | EGY | E£199,99 | 149,99 | 99,99 | 10200 |
   | PAK | Rs900 | 700 | 450 | 10143 |
   | NGA | ₦4.900 | 3.900 | 2.500 | 10143 |
   | COL | $14.900 | 11.900 | 7.900 | 10043 |
   | THA | ฿149 | 119 | 79 | 10044 |
   | MYS | RM19,90 | 14,90 | 9,90 | 10073 |
   | ZAF | R79,99 | 59,99 | 39,99 | 10100 |
   | ARG, UKR | $3.99 | 2.99 | 1.99 | 10049 |

   - Her SKU için tam price point kimliğini al: `asc iap pricing price-points list --iap-id <IAP> --territory <T> --paginate --price "<fiyat>"`.
   - Uygula: `asc iap pricing schedules create --iap-id <IAP> --base-territory USA --prices "<USA_PP>,<TUR_PP>,..."`. Bu komut takvimi değiştirir, ABD taban noktası listede olmalı.
   - Önce yalnız flash SKU'da dene, `asc iap pricing summary --iap-id 6837787623` ile doğrula, sonra diğer ikisi.
   - Her ülkede welcome ve flash, regular'dan en az %10 ucuz olmalı; yoksa `ProStore.offerPrices` nil döner ve teklif o ülkede kaybolur. Tablodaki en düşük fark %20.

4. **Meta veri (asc, 1.1.0 ile birlikte).**
   - İnceleme notunda "Tapping Skip on the intro bypasses it." → "Skip also leads to the welcome offer."
   - Aynı notta flash cümlesi → "starts the first time the app is in the foreground at least 10 minutes after the intro".
   - en-US/GB/AU/CA anahtar kelimeler: `pauses,jump cut,auto,dead air,cutter,trim,editor,talking head,reels,shorts,podcast,gaps,vlog,ugc` (96 karakter). Önce alt başlığı oku; "video" orada yoksa `ugc,gaps` yerine `video` koy.
   - Build'i yükle, üç IAP'yi 1.1.0 ile birlikte incelemeye ekle (hepsi `READY_TO_SUBMIT`, inceleme görselleri `COMPLETE`), manuel yayın.

**İncelemede beklerken (ajan yapar)**

5. Gerçek simülatör kaydından 6 adet önce/sonra kısa video (3 TR, 3 EN): ham konuşma → kesilmiş hali, ekranda "2:10 → 1:24". SVG çizim yok.
6. `cutsense.onarika.net`'e TR/ES/PT açılış sayfaları: "sessizlik silme", "quitar silencios", "remover silêncio". Yerelde doğrula, `gerekceli-red` kapısından geçir, deploy et.

**Yayından sonra (R = yayın günü)**

7. R+0: tanıtım metnini TR/EN güncelle (incelemesiz). Sahip 5 kişiden gerçek puan ister; ABD'de 0 puan, rakiplerin hepsi 31'in altında. **Sahibin eli gerekir.**
8. R+0..R+13: günde 1 video, TikTok + Reels + Shorts. Onarika hesapları için ajan planlar; kişisel hesaplar **sahibin eli**. R+3'te r/NewTubers gönderisi (ajan taslak yazar, sub kurallarını kontrol eder, **sahip atar**).
9. R+7 ve R+14: ASC satış raporunu SKU bazında oku, aşağıdaki eşiklere göre 1.1.1 kapsamını kes.

**1.1.1 listesi (sıralı):** kayıt sonrası Pro satırı + 3. kayıtta paywall; sürüm güncellemesinde tek seferlik geri kazanma flash'ı; `PurchaseIntent` + promoted IAP; flash başlarken yerel bildirim (yalnız kayıt sonrası izin isteyerek); DAU > 200 ise AdMob mediation.

## Dokunma

- `ProStore.swift`, ürün kimlikleri, `ProEntitlement`: satın alma ve geri yükleme yolu değişmez.
- 3 tutma sınırı, Hardcore'un ücretsiz olması, `AdMobService.swift`, reklam sıklığı.
- Çalışma ağacındaki commit edilmemiş 5 dosya (`QuickSilenceView.swift`, `Translations.swift`, 3 UI testi): üzerine yaz, `stash`/`checkout` yok.
- ABD ve Avrupa fiyatları. Creem ve diğer projeler.
- Canlı siteye tarama yok; yalnız değişen URL'lere `curl -I`.

## Doğrulama

- **Adım 1:** `CUTSENSE_RESET_ONBOARDING=1 CUTSENSE_FAKE_PRICES=1` ile iPhone 17 Pro Max'te 1. sayfada Geç → teklif paneli açılır; "Şimdi değil" → ana ekran. Fiyat yüklenmezse (fake kapalı, StoreKit yok) Geç doğrudan ana ekrana gider.
- **Adım 2:** `CUTSENSE_FLASH_DELAY_SECONDS=20 CUTSENSE_OFFER_SECONDS=60` ile onboarding'i bitir, uygulamayı arka plana al, 90 sn bekle, aç → flash şimdi açılır ve 60 sn sürer. Tekrar kapat-aç → bir daha açılmaz. Pro satın alınmışsa hiç açılmaz.
- **Testler:** `OfferCenterTests` ve `OfferFlowUITests` yeşil; iPhone 16e'de bir tam akış.
- **Adım 3:** `asc iap pricing summary --app 6770024868` üç SKU'da TUR satırı 199,99/149,99/99,99. Sandbox'ta TR mağaza hesabıyla paywall'da "%25" ve "%50" görünür.
- **Eşikler (R+7, R+14; ASC Sales, SKU bazında birim):**

  | Gözlem | Karar |
  |---|---|
  | İlk indirme < 100 | Huniye dokunma, yalnız içerik ve ASO |
  | İndirme ≥ 200, toplam satın alma/indirme < %1 | 1.1.1 madde 1 |
  | Welcome birimi 0, diğerleri > 0 | Teklif ekranı metni |
  | Flash birimi 0 | Madde 2 + bildirim |
  | Puan < 10 | Puan istemini 2. kayda da ekle |
  | AdMob eşleşme < %40 veya DAU < 200 | Reklama iş harcama |

## Risk

- UNVERIFIED: `schedules create` çoklu `--prices` sözdizimi (virgül mü, tekrar mı) ve başlangıç tarihi vermeden hemen geçerli olması. Bu yüzden önce tek SKU.
- UNVERIFIED: price point numaraları üç SKU'da aynı görünüyor (flash TUR 10200 = ₺199,99 ile tutarlı), ama welcome ve flash için tablo çekmedim; kimlikleri SKU başına `--price` ile çöz.
- UNVERIFIED: Geç yolunun ve flash'ın dönüşüme etkisi; uygulamada analitik yok, tek ölçüm ASC SKU birimleri.
- UNVERIFIED: alt başlık metni okunamadı (`app-info/*.json` bozuk: "RECON GAP"); anahtar kelime değişikliğinden önce ASC'den oku.
- RISK: temel SKU yüklenmezse `canOfferPro` false olur ve tüm Pro hunisi ile tutma sınırı sessizce kapanır. IAP'ler ilk kez inceleniyor; reddedilirse gelir sıfır.
- RISK: 3 Aralık'ta Apple'ın otomatik eşitlemesi elle fiyat girilmeyen ülkelerde fiyatı yükseltecek (TUR, EGY, COL, BWA, RWA görüldü).
- **Gelir beklentisi:** $2.500/ay için ayda 370–450 satın alma, yani %2 dönüşümle 18–22 bin indirme gerekir; bugünkü hızın ~1.000 katı. 1M kullanıcı günde ~33 bin indirme demek. Üst kuyruğu yalnız tutan bir kısa video açar; bu da sahibin hesaplarından düzenli paylaşım ister.

Bakmadıklarım: AdMob konsolu (Chrome), `asc review doctor` zaman aşımına uğradı (`ASC_TIMEOUT=90s` ile yeniden koş), `PaywallView` metni, KAZ fiyat tablosu boş döndü. Hiçbir dosya ya da ASC kaydı değiştirilmedi.
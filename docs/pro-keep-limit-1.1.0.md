# Pro packaging decision 1.1.0 (Fable)

**Karar:** Review cuts'ın inceleme kısmı (liste, dinleme, Önce/Sonra, tek tek kes/tut) ücretsiz kalsın; ücretsiz kullanıcı video başına en fazla 3 duraklamayı tutabilsin, 4. tutma ve "Keep all" Pro olsun. Fine-tune Pro'da, Hardcore ücretsiz kalsın. Bu 1.1.0'a girmeli, 1.2'ye bırakılmamalı.

- **Brief'teki iki varsayım git ile çelişiyor.** `recover/build28` hedefi (`ios/project.yml`) yalnız `CutSense/QuickSilence` ve birkaç dosyayı derliyor; orada `ReviewScreen`/`CutListSheet` yok. Yani Review 1.1.0'da ilk kez çıkıyor, 1.0.x kullanıcısı bir şey kaybetmez. Hardcore ise 1.0.3'te ücretsizdi (varsayılan `.tight` idi), kilitlemek yayınlanmış özelliği geri almak olur.
- **Hardcore kilidi neden reddedildi.** `ReviewScreen.swift:737` ücretsiz kullanıcıya "Try Hardcore" diyor, 39 dildeki açıklamanın 2. adımı da Hardcore'u sayıyor; ikisi de kilide çıkardı.
- **Review'un tamamını kilitlemek neden reddedildi.** Onboarding 2. sayfa ("Keep a pause with one tap" ve animasyonlu tutulan satır), `02_cuts.png` başlığı ve açıklamanın 4. adımı yanlış kalırdı. Pazar araştırmasında en sık 1 yıldız sebebi aşırı kesim; çaresini tamamen paraya bağlamak bunu tetikler.
- **3'lük sınır neden doğru.** Yukarıdaki üç vaat doğru kalır ve Pro'ya "reklamsız + 2 kaydırıcı"dan güçlü bir üçüncü sebep ekler. Ücretsiz kullanıcının çaresi sürer: 3 tutma ve daha yumuşak seviye.
- **Neden şimdi.** Review ücretsiz yayınlandıktan sonra kısıtlamak geri alma olur; sınırı sonradan gevşetmek bedelsizdir.
- **Fine-tune'u ücretsiz yapmak** gelir getirmez; `OfferFlowUITests` 221-340 ve tüm Pro metinlerini yeniden yazdırır. Reddedildi.

**Adımlar:** (sıra bağlayıcı; çalışma ağacının üstüne yaz, `git stash`/`checkout` yok)

1. `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/QuickSilence/ReviewScreen.swift` — `CutListSheet` yakınına saf bir kapı ekle:
   - `enum KeepGate { static let freeLimit = 3; static func canKeepAnother(_ plan: QuickSilenceEngine.CutPlan, limited: Bool) -> Bool { !limited || plan.cuts.filter(\.isRestored).count < freeLimit } }`
   - Sayım her zaman `plan.cuts`'tan türetilir. UserDefaults sayacı ekleme.

2. Aynı dosya, `CutListSheet`: yeni parametreler `keepsLimited: Bool` ve `onLocked: () -> Void`.
   - **Toggle setter'ının başına:** `if !$0 && !KeepGate.canKeepAnother(plan, limited: keepsLimited) { onLocked(); return }`. Reddedilen dokunuş `plan`'ı değiştirmemeli; kök `.onChange(of: plan)` export'u siliyor.
   - **Keep all:** `keepsLimited` ise `setAll` yerine `onLocked()`; etiket `Label(..., systemImage: "lock.fill")`. Cut all serbest.
   - **Sayaç satırı:** rehber metninin altına, yalnız `keepsLimited && !plan.cuts.isEmpty` iken, `MonoTertiaryButtonStyle` ile dokunulabilir satır; `accessibilityIdentifier("keepLimitButton")`, eylem `onLocked()`. Metin: `String(format: appText(language, "%d/%d tutuldu. Pro ile sınırsız.", "Kept %d of %d. Unlimited with Pro."), min(kept, KeepGate.freeLimit), KeepGate.freeLimit)`.
   - Seviye değişimi tutulanları taşıdığı için sayı 3'ü aşabilir (`QuickSilenceEngine.swift` 183-189). Yalnız yeni tutma engellenir, mevcutlar geri alınmaz.

3. Aynı dosya, `ReviewScreen`: yeni parametreler `var keepsLimited: Bool = false`, `var onUpgrade: () -> Void = {}`; `@State private var upgradeAfterCuts = false`.
   - `CutListSheet`'e `keepsLimited: keepsLimited, onLocked: { upgradeAfterCuts = true; showsCuts = false }` geçir.
   - Mevcut `.sheet(... onDismiss:)` içinde `auditioner.stop`'tan sonra: `if upgradeAfterCuts { upgradeAfterCuts = false; onUpgrade() }`.
   - `CutListSheet` içine iç içe paywall sheet'i koyma; `QuickSilenceView.swift:181` (dinlemeyi durdurma) ve 916/923 (flash/reklam korumaları) atlanır.

4. `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/QuickSilence/QuickSilenceView.swift` (~418, `ReviewScreen(` çağrısı): `keepsLimited: store.canOfferPro, onUpgrade: { showsPaywall = true }`.
   - Ürün yüklenemediyse sınır yoktur; Fine-tune'un `.hidden` deseniyle aynı mantık, satın alınamayan kilit gösterilmez.
   - Kod yorumu: `// shortcut: no limit while the product is not loaded, revisit if offline abuse shows up`.

5. `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Pro/PaywallView.swift`:
   - **Alt başlık:** `t("İstediğin kadar duraklamayı tut, gerisine ince ayar yap.", "Keep as many pauses as you want, and fine-tune the rest.")`. Ana başlık aynı kalır.
   - **`compareRow` imzası:** `freeText: String? = nil, proSymbol: String = "checkmark"`. `freeText` varsa ücretsiz sütunda ikon yerine o metin (`.monoText(.label)`, `Mono.C.text2`).
   - **Satır sırası:** 0 Unlimited cuts (free), 1 Review every cut (free), 2 No watermark (free), 3 Ad-free (Pro), 4 yeni satır, 5 Fine-tune (Pro).
   - **Yeni satır:** `compareRow(4, t("Video başına tutulan duraklama", "Kept pauses per video"), free: false, freeText: "3", proSymbol: "infinity")`; a11y etiketi `"\(title): \(t("Ücretsiz", "Free")) 3, Pro \(t("sınırsız", "unlimited"))"`.

6. `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Pro/OfferView.swift:110`: `benefit(1, t("Sınırsız tutma ve İnce ayar", "Unlimited keeps and Fine-tune"))`. Satır sayısı 3 kalır.
   - Eski "Fine-tune: minimum pause and breathing room" anahtarı başka yerde kullanılmıyorsa (`grep`, testler dahil) `Translations.swift` satırını sil.

7. `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Services/Translations.swift` — dört yeni EN anahtarına 7 dil satırı. Yalnız düz `%d`, aynı sırada (test regex'i konumsal biçimi görmüyor). Fiiller mevcut "Keep"/"Keep all" satırlarıyla hizalanır.
   - **"Kept %d of %d. Unlimited with Pro."**
     - es: `%d de %d conservadas. Ilimitado con Pro.`
     - pt: `%d de %d mantidas. Ilimitado com o Pro.`
     - de: `%d von %d behalten. Unbegrenzt mit Pro.`
     - fr: `%d sur %d gardées. Illimité avec Pro.`
     - it: `%d di %d mantenute. Illimitato con Pro.`
     - ja: `%d/%d 件を保持。Proなら無制限。`
     - ko: `%d/%d개 유지됨. Pro는 무제한.`
   - **"Keep as many pauses as you want, and fine-tune the rest."**
     - es: `Conserva todas las pausas que quieras y ajusta el resto.`
     - pt: `Mantenha quantas pausas quiser e ajuste o resto.`
     - de: `Behalte so viele Pausen, wie du willst, und stimme den Rest fein ab.`
     - fr: `Gardez autant de pauses que vous voulez et affinez le reste.`
     - it: `Mantieni tutte le pause che vuoi e regola il resto.`
     - ja: `好きなだけ間を残して、残りは微調整。`
     - ko: `원하는 만큼 멈춤을 유지하고 나머지는 미세 조정하세요.`
   - **"Kept pauses per video"**
     - es: `Pausas conservadas por video`
     - pt: `Pausas mantidas por vídeo`
     - de: `Behaltene Pausen pro Video`
     - fr: `Pauses gardées par vidéo`
     - it: `Pause mantenute per video`
     - ja: `動画ごとに残せる間`
     - ko: `동영상당 유지 가능한 멈춤`
   - **"Unlimited keeps and Fine-tune"** — "Fine-tune" kelimesi her dilde mevcut Fine-tune satırındaki karşılıkla yazılır.
     - es: `Pausas ilimitadas y Ajuste fino`
     - pt: `Pausas ilimitadas e Ajuste fino`
     - de: `Unbegrenzt behalten und Feinabstimmung`
     - fr: `Pauses illimitées et Réglage fin`
     - it: `Pause illimitate e Regolazione fine`
     - ja: `無制限に保持＋微調整`
     - ko: `무제한 유지 및 미세 조정`
   - **"unlimited"** (a11y) için de satır ekle.

8. Testler:
   - **`ios/CutSense/Tests/Release/QuickSilencePlanTests.swift`** — `KeepGate` testi: 0-2 tutulan → true; 3 → false; `limited: false` → her zaman true; biri geri kesilince tekrar true.
   - **`ios/CutSense/Tests/Release/TranslationsTests.swift`** — her yeni anahtar için açık assertion (`Translations.table[key] != nil`). Eksik anahtar bugün sessizce İngilizceye düşüyor.
   - **`ios/CutSense/Tests/UI/EdgeCaseUITests.swift`** — Keep all kullanan test (139-146) için `app.launchEnvironment["CUTSENSE_FORCE_PRO"] = "1"`. Ad `ProStore.swift:11`'deki gibi olmalı, `CUTSENSE_DEBUG_FORCE_PRO` değil. Satır 164'teki rehber metni assertion'ı aynı kalır.
   - **`ios/CutSense/Tests/UI/OfferFlowUITests.swift`** — yeni `testFreeKeepLimitOpensPaywallAndProUnlocks`, 221. satırdaki testi model al:
     1. `reviewCutsButton` etiketinden kesim sayısını oku; 4'ten azsa Tight'a geç.
     2. `cutToggle_0..2`'yi tut, `keepLimitButton` etiketi "Kept 3 of 3…" olsun.
     3. `cutToggle_3`'e dokun: paywall açılır, kapatınca `reviewCutsButton` etiketi ve yeni süre değişmemiş olur.
     4. Satın al, listeyi aç: `cutToggle_3` tutulur, `keepLimitButton` yok, Keep all çalışır.

9. Arşivden önce (blokaj): commit edilmemiş diff'teki `print("XXWATCH …")` satırlarını ve `XX_NOFAIL` env kancasını `ReviewScreen.swift`'ten sil. Fallback mantığı (`watchComposition`, `compositionFailed`, `installFallback`) kalır.

10. Mağaza metni, 39 dil, üç cümle değişir:
    - **(a) REVIEW EVERY CUT paragrafı.** "Change cuts one by one, or use Keep all and Cut all." yerine: "Change cuts one by one. The free version keeps up to 3 pauses per video. Pro keeps as many as you want and adds Keep all."
      TR: "Kesimleri tek tek değiştir. Ücretsiz sürüm video başına 3 duraklamaya kadar tutar. Pro'da istediğin kadarını tutarsın, ayrıca Tümünü tut açılır."
    - **(b) CUTSENSE PRO paragrafı.** "Pro removes all ads for good, lets you keep as many pauses as you want, and unlocks Fine-tune, where you set …" (devamı aynı).
      TR: "Pro tüm reklamları kalıcı olarak kaldırır, istediğin kadar duraklamayı tutmanı sağlar ve İnce ayar'ı açar; …"
    - **(c) whatsNew Pro maddesi.** "It removes ads, keeps unlimited pauses and unlocks Fine-tune."
      TR: "Reklamları kaldırır, sınırsız duraklama tutar ve İnce ayar'ı açar."
    - **13 dil:** `/Users/jinx/Documents/projeler/CutSense/ios/metadata/gen_meta.py` düzenlenir ve çalıştırılır; `version-1.1.0.json` üretilir. en-GB/AU/CA = en-US.
    - **26 dil:** `/Users/jinx/Documents/projeler/CutSense/ios/metadata/version-1.1.0-global.json` doğrudan düzenlenir, üreteci yok.
    - **Çeviri kuralı:** kalan diller bu üç EN cümlesinden çevrilir; o dosyada arayüz etiketi nasıl yazıldıysa (ör. tırnak içinde "Keep all") öyle kalır. Para simgesi, "one-tap"/"tek dokunuş" yok (FORBIDDEN listesi).

11. `/Users/jinx/Documents/projeler/CutSense/web/app/terms/terms-content.tsx:106-107` (TR+EN): "It removes ads, keeps unlimited pauses per video and unlocks fine-tune controls (…)" / "Reklamları kaldırır, video başına sınırsız duraklama tutmayı ve ince ayar kontrollerini açar". Support ve privacy dosyaları Pro özelliklerini saymıyor, dokunma.

12. Ekran görüntüsü: yalnız `ios/metadata/screenshots/en-US-110/04_pro.png` yeniden üretilir. iPhone 17 Pro Max simülatörü, `CUTSENSE_SHOW_PAYWALL=1 CUTSENSE_FAKE_PRICES=1`, sonra `compose.py`'deki ilgili `shot(...)` satırı. `02_cuts.png` aynı kalır.

13. Dokümanlar: `docs/plan-1.1.0.md:29` ve `docs/onboarding-offer-1.1.0.md:368` (IAP review notu) "no ads + unlimited keeps (free: 3 per video) + Fine-tune" olarak güncellenir. Aynı not App Store Connect'teki review notuna da yazılır.

Zaman yetmezse kesilebilecek tek adım 12'dir. 10 ve 11 kesilemez; ücretli sınır açıklamada yazmalı.

**Dokunma:**
- `ProStore`/`ProEntitlement`, üç SKU, `OfferCenter` zamanlaması, fiyatlar.
- Fine-tune kilidi (`QuickSilenceView.swift:430/438`) ve `MonoIntensityControl`; seviyeler ücretsiz kalır.
- Dinleme, Önce/Sonra, satıra dokunma, Cut all, "Longest first" ücretsiz kalır.
- Onboarding 2. sayfa metni ve animasyonu, `02_cuts.png`, açıklamanın 4. adımı.
- Yeni UserDefaults anahtarı yok; `privacy-content.tsx:57-58`'deki cihazda saklananlar listesi değişmesin.
- Tutulan kesimlerin seviye değişiminde taşınması (`QuickSilenceEngine.swift` 183-189).
- Commit edilmemiş önizleme fallback çalışması geri alınmaz.

**Doğrulama:**
- **Birim testleri:** `xcodebuild test` ile Release test hedefi, iPhone 17 Pro Max. `KeepGate` ve `TranslationsTests` yeşil olmalı.
- **UI testleri:** `OfferFlowUITests/testFreeKeepLimitOpensPaywallAndProUnlocks`, `testProPurchaseRemovesAdsLiveAndUnlocksFineTune`, `EdgeCaseUITests` (Keep all, audition, kept-pause-survives) yeşil olmalı.
- **Başarısızlık yolları, elle:**
  - Ürün yüklenmemişken (StoreKit config'siz çalıştırma): sayaç satırı ve kilit görünmez, 4. tutma çalışır.
  - Sınırda 4. toggle: konum değişmez, yeni süre ve "Saved" durumu bozulmaz, paywall liste kapandıktan sonra açılır.
  - Paywall X ile kapanınca liste yeniden açılabilir ve 3 tutulan durur.
  - Flash teklif etkinken aynı yol `OfferPanel(.flash)` gösterir.
  - 3 tutulanla Tight'a geçince sayı 3'ü aşsa da tutulanlar durur, sayaç "3 of 3" gösterir.
- **Görsel:** iPhone 17 Pro Max'te paywall 6 satır, TR ve DE'de taşma yok; fiziksel 16e'de kesim listesi `.fraction(0.55)` detent'inde sayaç satırı ve video görünür.
- **Metadata:** `python3 ios/metadata/check_version_metadata.py` ve `python3 ios/metadata/check_global.py` hatasız.
- **Debug kalıntısı:** `grep -rn "XXWATCH\|XX_NOFAIL" ios/CutSense` boş dönmeli.

**Risk:**
- UNVERIFIED: liste `onDismiss`'inden kök `showsPaywall = true` ile sunumun her seferinde açıldığı. Kanıtı yeni UI testi; açılmazsa `onUpgrade()` çağrısını `Task { @MainActor in … }` ile bir runloop ertele.
- UNVERIFIED: 3'lük sınırın dönüşüme ve puanlara etkisi; ölçüm yok. Sınırı gevşetmek tek sabit (`KeepGate.freeLimit`), sıkılaştırmak geri alma olur.
- UNVERIFIED: App Store Connect'teki mevcut durum (yüklü build, metadata, IAP review notu) ve canlı 1.0.1 listesi; `ios/metadata/version/1.0.1` dosyası kurtarma parçası, okunamadı.
- UNVERIFIED: App Review kural numaraları. Yönerge sayfasını açmadım; "ücretli sınır açıklamada yazmalı" gerekçesi numarasız verildi.
- RISK: 37 dildeki üç cümle makine çevirisi olacak; ana dili konuşan kontrolü yok.
- RISK: uçak modunda açan kullanıcı sınırsız tutar; bilinçli tercih (adım 4).
- Bakmadıklarım: `OfferFlowUITests` fixture'ının Balanced'ta kaç kesim verdiği (test sayıyı etiketten okuyacak), `compose.py`'deki 04 ham dosya adı, web deploy durumu (web değişikliği canlıya çıkış kapısından geçmeli).
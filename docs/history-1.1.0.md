- **Karar:** Geçmiş, ana ekran toolbar'ında dişlinin soluna konan bir saat glifinden açılan, `List` tabanlı tek bir ekran olacak; kayıt yalnız başarılı Photos kaydından sonra yapılır.
  - **Giriş noktası:** `clock.arrow.circlepath` glifi. Home satırı değil, çünkü idle ekran 16e'de zaten dolu. 390 pt'de en kötü durum (privacy 44 + ortalanmış pill + 2 glif) pill'e yaklaşık 180 pt bırakıyor.
  - **Ekran:** Swipe-to-delete istendiği için grid değil `List`. Üstte iki sayaçlı özet ve her kaydın kesim yüzdesinden oluşan bar şeridi var.
  - **Özet metni:** Tek cümle yerine iki ayrı numeral ("Silence cut" süre, "Videos" adet). Böylece 9 dilde çoğul ve placeholder sırası sorunu çıkmaz. Toplamlar kayıtlardan hesaplanır; silme ve 200 sınırı toplamı düşürür.
  - **Kayıt:** `saveToPhotos` `.success` dalında, `saved = true`'dan önce ve `await` ile. Export overlay'i `finish` dönene kadar dosyayı kilitliyor (`QuickSilenceView.swift:731`); detached iş, New Video dosyayı silince boş thumbnail üretirdi. Share sayılmaz: tamamlandığı bilinemez ve Photos'ta karşılığı yoktur.
  - **`localIdentifier` saklanmayacak:** `.addOnly` altında okunamıyor ve `photos-redirect://` belirli bir asset'e gidemiyor. Bu, `PhotosSaveService` imzasını da değiştirmemek demek.
  - **Depolama:** Application Support'ta JSON + thumbnail klasörü, iCloud yedeğinden hariç ("videolar cihazda kalır" sözüyle tutarlı).
  - **Paywall/offer'da özet kullanımı:** Şimdi yok.

- **Adımlar:**

  1. **Yeni dosya `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Storage/HistoryStore.swift`**
     - `struct HistoryEntry: Codable, Identifiable, Equatable` alanları: `id: UUID`, `date: Date`, `originalDuration: Double`, `outputDuration: Double`, `removedPercent: Int`, `intensity: String` (`CutIntensity.rawValue`), `isCustom: Bool`, `resolution: String?`, `hasThumbnail: Bool`.
     - Dosya zarfı: `private struct File: Codable { var version: Int; var entries: [HistoryEntry] }`, `version = 1`.
     - `@MainActor @Observable final class HistoryStore`:
       - `static let shared`, `init(directory: URL)` (testler için enjekte edilir), `static let cap = 200`, `static let maxThumbnailBytes = 24_000`.
       - `private(set) var entries: [HistoryEntry]`, en yeni başta.
       - `var removedSeconds: Double` = Σ(`originalDuration − outputDuration`).
       - `func add(_ entry: HistoryEntry, thumbnail: Data?)`: thumbnail `maxThumbnailBytes`'ı aşarsa yazılmaz ve `hasThumbnail = false` olur; başa eklenir; `cap` aşılırsa en eskiler thumbnail dosyalarıyla silinir.
       - `func delete(id: UUID)`, `func clear()`, `func thumbnailURL(for id: UUID) -> URL`.
     - Disk düzeni:
       - Varsayılan dizin `URL.applicationSupportDirectory.appending(path: "CutSense/History")`; içinde `history.json` ve `thumbs/<uuid>.jpg`.
       - Dizin oluşturulunca `isExcludedFromBackup = true` verilir.
       - Yazımlar `Data.write(options: .atomic)`; hata `#if DEBUG print` ile loglanır, kullanıcıya gösterilmez.
     - Yükleme: decode başarısızsa veya `version != 1` ise `entries = []`, çökme yok, sonraki yazım dosyayı ezer. Yüklemede `thumbs/` içindeki referanssız dosyalar silinir.
     - `nonisolated static func thumbnail(of url: URL, outputDuration: Double) async -> Data?`:
       - `AVAssetImageGenerator` ile `appliesPreferredTrackTransform = true` (yoksa dikey video yan çıkar) ve `maximumSize = CGSize(width: 160, height: 160)`.
       - `try? await generator.image(at: CMTime(seconds: outputDuration * 0.25, preferredTimescale: 600))`.
       - `UIImage(cgImage:).jpegData(compressionQuality: 0.7)`.
     - `#if DEBUG`: `shared` oluşturulurken `CUTSENSE_SEED_HISTORY=N` okunur. Store içeriği **değiştirilir**, eklenmez; N=0 temizler. N adet sahte kayıt farklı tarih, süre ve seviyelerle üretilir, biri `isCustom`, biri thumbnail'siz. Sahte thumbnail `UIGraphicsImageRenderer` ile 160 px gri gradyan.

  2. **`/Users/jinx/Documents/projeler/CutSense/ios/CutSense/QuickSilence/ReviewScreen.swift`**
     - `ReviewSourceInfo`'ya (satır 1154) `var resolutionLabel: String?` eklenir. Gövdesi 576–578'deki mantığın aynısı: kısa kenar ≤ 0 ise nil, ≥ 2160 ise "4K", değilse "\(Int(short))p".
     - `sourceSummary` bu property'yi kullanır. Başka değişiklik yok.

  3. **Yeni dosya `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/QuickSilence/HistoryView.swift`**
     - `struct HistoryView: View { let language: AppLanguage }`, `@State private var store = HistoryStore.shared`.
     - Kabuk `SettingsScreen` ile aynı: `.listStyle(.insetGrouped)`, `.scrollContentBackground(.hidden)`, `Mono.C.bg`, `.preferredColorScheme(.dark)`, `.dynamicTypeSize(...DynamicTypeSize.xxLarge)`, `.navigationTitle("History")`. Satırlar `listRowBackground(Mono.C.raised)` ve `listRowSeparatorTint(Mono.C.hairline)` kullanır.
     - **Özet (ilk section, şeffaf arka plan):**
       - İki sütun: `timeString(removedSeconds)` + overline "Silence cut"; `entries.count` + overline "Videos". Stil `.numeralXL`, 16e'de `minimumScaleFactor(0.7)`.
       - Count-up: `@State shown` değerleri `onAppear`'da `withAnimation(Mono.Motion.smooth)` ile 0'dan hedefe gider, `.contentTransition(.numericText(value:))` ile. Reduce Motion'da animasyonsuz atanır.
       - Tek erişilebilirlik öğesi olarak birleştirilir.
       - Altında private `HistoryBars`: 32 sabit slot, son 32 kaydın `removedPercent/100` yüksekliği (taban 0.08), boş slotlar `Mono.C.hairline`, dolular `Mono.C.text`, yükseklik 44. Girişte 12 ms kademeli `scaleEffect(y:, anchor: .bottom)`; Reduce Motion'da statik. `.accessibilityHidden(true)`.
     - **Satır (`Button`, min yükseklik 72):**
       - Thumbnail 56×56, `Mono.Radius.chip`, `UIImage(contentsOfFile:)` ile. Yoksa `Mono.C.elevated` üstünde `film` glifi.
       - 1. satır `"\(timeString(original)) → \(timeString(output))"`, `.numeralM`.
       - 2. satır tarih · seviye · çözünürlük, `.caption`, `Mono.C.text2`, `lineLimit(1)`. Tarih biçimi `SettingsScreen.swift:91-92` ile aynı locale kalıbı. Seviye `isCustom` ise "Custom", değilse `CutIntensity(rawValue:)?.title(for: language)`.
       - Sağda `MonoBadge("−\(removedPercent)%")`.
       - Dokununca `photos-redirect://` açılır (`QuickSilenceView.swift:425` ile aynı).
       - VoiceOver: label = tarih + `String(format: "From %@ to %@, %@ removed", ...)` + seviye; hint "Opens Photos".
       - `.monoEntrance(index)` yalnız ilk 8 satıra.
     - **Silme:** `.swipeActions(edge: .trailing, allowsFullSwipe: true)` içinde `trash` ikonlu, label'ı "Delete" olan Button. Role verilmez, `.tint(Mono.C.elevated)` (mono kuralı: kırmızı yok). `withAnimation { store.delete(id:) }`, onay yok. `.sensoryFeedback(.impact(weight: .light), trigger: store.entries.count)`.
     - **Alt bilgi (section footer):** "Only a small preview and the numbers are kept. Your videos stay in Photos."
     - **Boş durum (`entries.isEmpty`, List yerine):** ortalanmış `VStack` — `HistoryBars` (hepsi taban), "No edits yet" `.title`, "Videos you save to Photos appear here." `.body`, `Mono.C.text2`. CTA yok.

  4. **`/Users/jinx/Documents/projeler/CutSense/ios/CutSense/QuickSilence/QuickSilenceView.swift`**
     - `@State private var showsHistory = false` eklenir.
     - `toolbarContent` trailing grubunda, Settings `NavigationLink`'inden hemen önce:
       - `Button { showsHistory = true } label: { toolbarGlyph("clock.arrow.circlepath") }`.
       - `.disabled(isWorking || exportTask != nil)`, `.accessibilityLabel(t("Geçmiş", "History"))`, `.accessibilityIdentifier("historyButton")`.
     - `body` içinde `.sheet`'in yanına `.navigationDestination(isPresented: $showsHistory) { HistoryView(language: appLanguage) }`. `screen` zincirine eklenmez: type-checker limiti notu satır 79'da.
     - `saveToPhotos` `.success` dalının ilk satırları, `saved = true`'dan önce:
       - `if let plan { let thumb = await HistoryStore.thumbnail(of: url, outputDuration: plan.outputDuration); HistoryStore.shared.add(HistoryEntry(...), thumbnail: thumb) }`.
       - Alan eşlemesi: `originalDuration: plan.duration`, `outputDuration: plan.outputDuration`, `removedPercent: plan.removedPercent`, `intensity: cutIntensity.rawValue`, `isCustom: cutSettings != QuickSilenceEngine.CutSettings(cutIntensity)`, `resolution: sourceInfo?.resolutionLabel`, `hasThumbnail: thumb != nil`.
       - Thumbnail nil olsa da kayıt eklenir.
     - `startAutorunIfRequested` DEBUG bloğuna: `if env["CUTSENSE_SHOW_HISTORY"] == "1" { showsHistory = true }`.

  5. **`/Users/jinx/Documents/projeler/CutSense/ios/CutSense/UI/SettingsScreen.swift`**
     - `@State private var history = HistoryStore.shared` ve `@State private var confirmsClearHistory = false`.
     - Storage section'da "Clear" butonundan sonra: `row(t("Geçmişi temizle", "Clear history"), "clock.arrow.circlepath")` butonu, `.disabled(history.entries.isEmpty)`.
     - `.confirmationDialog(t("Geçmiş temizlensin mi?", "Clear history?"), isPresented:, titleVisibility: .visible)`:
       - Mesaj: "Your videos in Photos are not affected."
       - Destructive "Clear history" → `history.clear()`; "Cancel".

  6. **`/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Services/Translations.swift`**
     - Yeni `// MARK: History` bloğu. Önce her anahtar grep'lenir: `testNoDuplicateKeys` tekrarı yakalar ama eksik satır sessizce İngilizceye düşer.
     - TR/EN `appText` çağrısında inline, tabloya 7 dil yazılır:

     | EN anahtar | TR | es | pt | de | fr | it | ja | ko |
     |---|---|---|---|---|---|---|---|---|
     | History | Geçmiş | Historial | Histórico | Verlauf | Historique | Cronologia | 履歴 | 기록 |
     | Silence cut | Kesilen sessizlik | Silencio cortado | Silêncio cortado | Stille entfernt | Silence coupé | Silenzio tagliato | カットした無音 | 잘라낸 무음 |
     | Videos | Video | Videos | Vídeos | Videos | Vidéos | Video | 動画 | 동영상 |
     | No edits yet | Henüz düzenleme yok | Aún no hay ediciones | Nenhuma edição ainda | Noch keine Bearbeitungen | Aucun montage pour l'instant | Ancora nessuna modifica | まだ編集がありません | 아직 편집이 없습니다 |
     | Videos you save to Photos appear here. | Galeriye kaydettiğin videolar burada görünür. | Los videos que guardes en Fotos aparecerán aquí. | Os vídeos que você salvar no Fotos aparecem aqui. | Videos, die du in Fotos sicherst, erscheinen hier. | Les vidéos enregistrées dans Photos apparaissent ici. | I video salvati in Foto appaiono qui. | 写真に保存した動画がここに表示されます。 | 사진에 저장한 동영상이 여기에 표시됩니다. |
     | Custom | Özel | Personalizado | Personalizado | Eigene | Personnalisé | Personalizzato | カスタム | 사용자 설정 |
     | Delete | Sil | Eliminar | Apagar | Löschen | Supprimer | Elimina | 削除 | 삭제 |
     | Opens Photos | Galeriyi açar | Abre Fotos | Abre o Fotos | Öffnet Fotos | Ouvre Photos | Apre Foto | 写真を開きます | 사진을 엽니다 |
     | Clear history | Geçmişi temizle | Borrar historial | Limpar histórico | Verlauf löschen | Effacer l'historique | Cancella cronologia | 履歴を消去 | 기록 지우기 |
     | Clear history? | Geçmiş temizlensin mi? | ¿Borrar historial? | Limpar histórico? | Verlauf löschen? | Effacer l'historique ? | Cancellare la cronologia? | 履歴を消去しますか？ | 기록을 지울까요? |
     | Your videos in Photos are not affected. | Galerideki videoların etkilenmez. | Tus videos en Fotos no se ven afectados. | Seus vídeos no Fotos não são afetados. | Deine Videos in Fotos bleiben unberührt. | Vos vidéos dans Photos ne sont pas concernées. | I tuoi video in Foto non vengono toccati. | 写真内の動画には影響しません。 | 사진의 동영상에는 영향이 없습니다. |
     | From %@ to %@, %@ removed | %@ → %@, %@ kesildi | De %@ a %@, %@ eliminado | De %@ para %@, %@ removido | Von %@ auf %@, %@ entfernt | De %@ à %@, %@ supprimé | Da %@ a %@, %@ rimosso | %@から%@へ、%@カット | %@에서 %@로, %@ 제거 |
     | Only a small preview and the numbers are kept. Your videos stay in Photos. | Yalnızca küçük bir önizleme ve sayılar saklanır. Videoların galeride kalır. | Solo se guardan una vista previa pequeña y las cifras. Tus videos siguen en Fotos. | Só uma prévia pequena e os números são guardados. Seus vídeos ficam no Fotos. | Gespeichert werden nur eine kleine Vorschau und die Zahlen. Deine Videos bleiben in Fotos. | Seuls un petit aperçu et les chiffres sont conservés. Vos vidéos restent dans Photos. | Vengono salvati solo una piccola anteprima e i numeri. I tuoi video restano in Foto. | 保存されるのは小さなプレビューと数値だけです。動画は写真に残ります。 | 작은 미리보기와 수치만 저장됩니다. 동영상은 사진에 그대로 있습니다. |

  7. **Yeni dosya `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Tests/Release/HistoryStoreTests.swift`**
     - Test target yalnız bu klasörü derler. `@MainActor`, her test tmp altında UUID'li dizin kullanır ve `tearDown`'da siler.
     - Testler:
       - add: en yeni başta, `removedSeconds` doğru.
       - cap: 205 ekle → 200 kalır, düşenlerin thumbnail dosyası yok.
       - delete: kayıt ve dosyası gider.
       - clear: json'da boş liste, `thumbs/` boş.
       - persist: aynı dizinle yeni instance aynı `entries`'i okur.
       - bozuk dosya: `history.json`'a çöp yaz → init boş döner, sonraki add çalışır.
       - yetim thumbnail: yüklemede silinir.
       - bütçe: 24_001 baytlık thumbnail reddedilir (`hasThumbnail == false`, dosya yok); 200 kayıtlık `history.json` < 64 KB.

  8. **Proje üretimi:** `cd /Users/jinx/Documents/projeler/CutSense/ios && xcodegen generate`. `project.yml`'e dokunmaya gerek yok: `CutSense/Storage`, `CutSense/QuickSilence` ve `Tests/Release` zaten kaynak yolu. pbxproj farkı yalnız 3 yeni dosya olmalı.

- **Dokunma:**
  - `PhotosSaveService.swift` ve `Info.plist` izinleri: yeni Photos izni yok, `.addOnly` kalır.
  - `WorkFiles` / `WorkSession`: geçmiş managed dosya değildir; `sweepAtLaunch` ve Settings "Clear" onu silmemeli.
  - `runExport`, `startShare`, `OfferCenter.noteSave`, `scheduleReviewPrompt`: sıra ve davranış aynı kalır.
  - `OfferPill`, `proCapsule`, `AdBannerSlot`, `isScreenVisible` mantığı: `onDisappear` her push'ta reklamı zaten kapatıyor (satır 180).
  - `MonoKit.swift` / `MonoWave.swift`'e yeni token veya bileşen eklenmez.
  - `ReviewScreen`'de adım 2 dışında değişiklik yok.
  - Migration yok; mevcut kullanıcı boş geçmişle başlar.

- **Doğrulama:**
  - **Build ve test:**
    - `xcodebuild test -scheme CutSense -destination 'platform=iOS Simulator,id=3C9044C5-36C3-4899-BAEB-6A9563BB790E' -only-testing:CutSenseTests` → `HistoryStoreTests` ve `TranslationsTests` yeşil.
    - `scripts/verify.sh` exit 0.
  - **Ekran görüntüleri:** `xcrun simctl launch` + `SIMCTL_CHILD_` env ile; onboarding bypass için `OnboardingGate` hook'u grep'lenir.
    1. `CUTSENSE_SEED_HISTORY=0 CUTSENSE_SHOW_HISTORY=1` → boş durum.
    2. `CUTSENSE_SEED_HISTORY=3 CUTSENSE_SHOW_HISTORY=1` → 3 kayıt. İkinci kez başlatınca yine 3 olmalı (6 değil).
    3. Aynısı + launch arg `-app_language de` → DE; rozet ve ikinci satır taşmıyor.
    4. Aynısı + `CUTSENSE_CLAMP_16E=1` → 390×763 içinde kırpılma yok.
    5. Ana ekran toolbar'ı: PRO + saat + dişli; offer pill aktifken pill + saat + dişli.
    6. Settings'te "Clear history" satırı ve onay diyaloğu.
  - **Elle akış:** gerçek video → Save to Photos → Geçmiş'te 1 kayıt, thumbnail dik duruyor (dikey videoyla dene).
    - Share → kayıt eklenmez.
    - Swipe sil → sayaçlar düşer.
    - Settings > Clear history → boş durum.
  - **Hata yolları:**
    - Photos izni reddi → kayıt eklenmez.
    - `history.json`'u bozup aç → boş liste, çökme yok.
    - Reduce Motion açık → count-up ve bar animasyonu yok.
    - VoiceOver satır label'ı ve hint okunur.
  - **Boyut:** `du -sh "$(xcrun simctl get_app_container 3C9044C5-36C3-4899-BAEB-6A9563BB790E <bundle-id> data)/Library/Application Support/CutSense/History"` → kayıt başına 12 KB civarı veya altı.

- **Risk:**
  - **UNVERIFIED:** Hiçbir şey derlenmedi veya ekranda görülmedi; bu plan yalnız kod okumasına dayanıyor.
  - **UNVERIFIED:** iOS 26'da toolbar'ın üç trailing öğeyi (PRO + saat + dişli) 390 pt'de nasıl grupladığı. Sıkışırsa saat glifi yalnız `isIdle` iken gösterilir.
  - **UNVERIFIED:** 160 px / q 0.7 JPEG'in gerçek videoda 8–12 KB tutması. 24 KB üst sınırı store'da zorlanıyor; aşan kare thumbnail'siz kaydedilir.
  - **UNVERIFIED:** Simülatör `3C9044C5…` adı "Promtable iPhone 17 Pro Max"; model yalnız adından doğrulandı.
  - **UNVERIFIED:** 7 dil çevirisi ana dili konuşan biri tarafından okunmadı.
  - **RISK (gizlilik metni, builder kapsamı dışı):** `/Users/jinx/Documents/projeler/CutSense/web/app/privacy/privacy-content.tsx` satır 51–52 ("cihazda saklanan ayarlar") ve 134–135 (saklama) artık eksik. Kalıcı bir video karesi ve düzenleme geçmişi cihazda tutuluyor. Sürümden önce "yalnız cihazda, yedeklenmez, Settings > Clear history ile silinir" cümlesi ayrı bir web adımıyla eklenmeli. App Store gizlilik etiketi değişmez, veri toplanmıyor.
  - **RISK:** Yedekten hariç tutulduğu için geçmiş yeni telefona taşınmaz; bilinçli tercih.
  - **RISK:** Satıra dokunmak belirli videoyu değil Photos uygulamasını açar; `.addOnly` altında başka yol yok.

Atlananlar: `localIdentifier` saklama, paywall/offer'da özet metni, grid görünümü, ömür boyu ayrı toplam sayaç, History içinde ikinci bir "Clear" butonu. `docs/design-1.1.0.md` baştan sona okunmadı (yalnız toolbar bölümü) ve `OnboardingGate` bypass env adı bulunamadı; builder grep'lemeli.
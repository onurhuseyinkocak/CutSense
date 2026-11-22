"use client";

import { useLanguage } from "../language-context";
import { SiteFooter, SiteNav } from "../site-chrome";

const contact = "info@vibecodingturkey.com";
// Seller name exactly as Apple publishes it on the App Store listing.
const seller = "Onur Hseyin Kocak";

export function TermsContent() {
  const { t } = useLanguage();

  const sections: { title: string; body: string[] }[] = [
    {
      title: t("Yürürlük tarihi", "Effective date"),
      body: [t("22 Kasım 2026", "November 22, 2026")],
    },
    {
      title: t("Biz kimiz", "Who we are"),
      body: [
        t(
          `CutSense, App Store'da satıcı olarak görünen ${seller} tarafından Türkiye'den sunulur ("biz"). E-posta: ${contact}.`,
          `CutSense is provided from Türkiye by ${seller}, the seller listed on the App Store ("we", "us"). Email: ${contact}.`,
        ),
      ],
    },
    {
      title: t("Bu şartlar ve Apple EULA", "These terms and Apple's EULA"),
      body: [
        t(
          "CutSense'i indirmen veya kullanman, bu şartları ve Apple'ın Standart Lisanslı Uygulama Son Kullanıcı Lisans Sözleşmesi'ni (apple.com/legal/internet-services/itunes/dev/stdeula) kabul ettiğin anlamına gelir. Bu şartlar Apple EULA'yı tamamlar; uygulama lisansı konusunda çelişki olursa Apple EULA geçerlidir. Gizlilik Politikamız da geçerlidir.",
          "By downloading or using CutSense you agree to these terms and to Apple's Standard Licensed Application End User License Agreement (apple.com/legal/internet-services/itunes/dev/stdeula). These terms supplement Apple's EULA; if they conflict on the app license, Apple's EULA governs. Our Privacy Policy also applies.",
        ),
        t(
          "Bu şartlar seninle bizim aramızdadır, Apple ile değil. Uygulamanın bakımı, desteği ve içeriğinden Apple değil biz sorumluyuz. Apple ve bağlı şirketleri bu şartların üçüncü taraf lehtarıdır ve bunları sana karşı uygulayabilir.",
          "These terms are between you and us, not Apple. We, not Apple, are responsible for the app, its maintenance, support, and content. Apple and its subsidiaries are third-party beneficiaries of these terms and may enforce them against you.",
        ),
      ],
    },
    {
      title: t("Yaş ve ehliyet", "Age and capacity"),
      body: [
        t(
          "CutSense'i kullanmak için en az 13 yaşında (ülkende dijital rıza yaşı daha yüksekse o yaşta) olmalısın. Reşit değilsen CutSense'i ve satın alımları yalnızca ebeveyninin veya vasinin izniyle kullanabilirsin.",
          "You must be at least 13 years old (or the higher digital-consent age in your country) to use CutSense. If you are a minor, you may use CutSense and make purchases only with the consent of your parent or guardian.",
        ),
      ],
    },
    {
      title: t("Lisans", "License"),
      body: [
        t(
          "CutSense sana satılmaz, lisanslanır. Bu şartlara ve App Store kurallarına tabi olarak, sahip olduğun veya kontrol ettiğin Apple cihazlarında CutSense'i kullanman için, kendi videolarını düzenleyip yayınlamak dahil, sınırlı, münhasır olmayan, devredilemez ve geri alınabilir bir lisans veririz. Uygulama, kodu, tasarımı ve CutSense adı bize aittir; burada açıkça verilmeyen tüm haklar saklıdır.",
          "CutSense is licensed, not sold, to you. Subject to these terms and App Store rules, we grant you a limited, non-exclusive, non-transferable, revocable license to use CutSense on Apple devices you own or control, including to edit and publish your own videos. The app, its code, its design, and the CutSense name belong to us; all rights not expressly granted are reserved.",
        ),
      ],
    },
    {
      title: t("İçeriğin ve sorumluluğun", "Your content and your responsibility"),
      body: [
        t(
          "Seçtiğin, düzenlediğin, dışa aktardığın, kaydettiğin veya paylaştığın videoların mülkiyeti sende kalır. Videolar iPhone'unda işlenir; biz onları hiçbir zaman almayız, görmeyiz veya saklamayız ve üzerlerinde hak iddia etmeyiz.",
          "You keep ownership of the videos you select, edit, export, save, or share. Videos are processed on your iPhone; we never receive, see, or store them, and we claim no rights over them.",
        ),
        t(
          "İşlediğin her video için gerekli haklara ve izinlere sahip olmalısın: telif hakkı, müzik lisansı, videodaki kişilerin rızası, gizlilik ve tanıtım hakları dahil. İçeriğinden, onu nerede yayınladığından ve platform kurallarına uymaktan yalnızca sen sorumlusun. İçeriğin veya bu şartları ihlal etmen nedeniyle üçüncü kişiler bize karşı talepte bulunursa, yasanın izin verdiği ölçüde bu taleplerden doğan zararımızı karşılarsın.",
          "You must have all rights and permissions needed for every video you process, including copyright, music licenses, the consent of people who appear in it, and privacy and publicity rights. You alone are responsible for your content, where you publish it, and following each platform's rules. If third parties bring claims against us arising from your content or your breach of these terms, you will, to the extent the law allows, cover our losses from those claims.",
        ),
      ],
    },
    {
      title: t("Yasak kullanım", "Prohibited use"),
      body: [
        t(
          "CutSense'i şunlar için kullanamazsın: yasaları çiğnemek; telif hakkı veya diğer üçüncü taraf haklarını ihlal etmek; yasa dışı, taciz edici, nefret içeren veya rızasız mahrem içerik ya da çocukları istismar eden içerik üretmek veya dağıtmak; uygulamayı tersine mühendislik yapmak, kopyalamak, değiştirmek veya yeniden satmak (yasanın buna izin verdiği hâller hariç); reklam, rıza, teklif veya satın alma sistemlerini aşmak ya da kandırmak; otomatik araçlarla reklamlarla etkileşime girmek; uygulamanın veya cihazların güvenliğine müdahale etmek.",
          "You may not use CutSense to: break the law; infringe copyright or other third-party rights; create or distribute content that is illegal, harassing, hateful, non-consensual intimate content, or that exploits children; reverse engineer, copy, modify, or resell the app (except where the law allows this); bypass or manipulate advertising, consent, offer, or purchase systems; interact with ads through automated means; or interfere with the security of the app or devices.",
        ),
      ],
    },
    {
      title: t("Markalar ve bağımsızlık", "Trademarks and no affiliation"),
      body: [
        t(
          "Instagram ve Reels Meta Platforms, Inc.'in; YouTube ve Shorts Google LLC'nin; TikTok ByteDance Ltd.'nin; Apple, iPhone, App Store ve Fotoğraflar Apple Inc.'in markalarıdır. Diğer adlar sahiplerine aittir. Bu adlar yalnızca CutSense ile hazırladığın videoların nerede kullanılabileceğini anlatmak için geçer. CutSense bu şirketlerle bağlantılı değildir, onlar tarafından onaylanmamış veya desteklenmemiştir.",
          "Instagram and Reels are trademarks of Meta Platforms, Inc.; YouTube and Shorts of Google LLC; TikTok of ByteDance Ltd.; Apple, iPhone, App Store, and Photos of Apple Inc. Other names belong to their owners. They are mentioned only to describe where videos made with CutSense can be used. CutSense is not affiliated with, endorsed by, or sponsored by any of these companies.",
        ),
      ],
    },
    {
      title: t("Ücretsiz sürüm, reklamlar ve ödüllü reklamlar", "Free version, ads, and rewarded ads"),
      body: [
        t(
          "CutSense'i indirmek ve kullanmak ücretsizdir; hesap ve abonelik yoktur. Ücretsiz sürüm Google tarafından sağlanan banner reklamlar, işlem sırasında native reklamlar ve atlanabilir ödüllü reklamlar gösterir. Reklamların içeriğinden reklam verenler sorumludur.",
          "CutSense is free to download and use, with no account and no subscription. The free version shows banner ads, native ads while a video is processing, and skippable rewarded ads, all provided by Google. Advertisers are responsible for the content of their ads.",
        ),
        t(
          "Ödüllü reklam geçişi (1.1 ve sonrası): ödüllü bir reklamı sonuna kadar izlersen banner ve native reklamlar 24 saat kapalı kalır. Ödüller birikir, ancak banner ve native reklamların kapalı kaldığı toplam süre hiçbir zaman 72 saati geçmez. Bu süre içinde de ödüllü reklam teklifi çıkabilir; 3 saniyelik geri sayımla gösterilir ve atlanabilir. Reklam mevcut değilse ödül verilmeyebilir. Ödülün nakdi değeri yoktur, devredilemez ve cihazda saklanır; uygulamayı silmek kalan süreyi siler.",
          "Rewarded pass (version 1.1 and later): if you watch a rewarded ad to the end, banner and native ads stay off for 24 hours. Rewards stack, but the total time banner and native ads stay off never exceeds 72 hours. The rewarded ad offer can still appear during that time; it shows with a 3-second countdown and can be skipped. If no ad is available, no reward may be given. The reward has no cash value, is not transferable, and is stored on your device; deleting the app removes any remaining time.",
        ),
      ],
    },
    {
      title: t("CutSense Pro", "CutSense Pro"),
      body: [
        t(
          "Uygulamada sunulduğu yerde CutSense Pro, App Store üzerinden alınan tek seferlik bir uygulama içi satın alımdır (tüketilmeyen ürün). Abonelik değildir ve yenilenmez. Reklamları kaldırır ve ince ayar kontrollerini (en kısa duraklama ve nefes payı) açar; reklam SDK'sı satın almadan sonraki açılıştan itibaren hiç başlatılmaz. Normal fiyat ABD'de 7,99 $'dır. Geçerli olan fiyat, satın almadan önce App Store'un ülken için gösterdiği fiyat ve vergilerdir.",
          "Where available in the app, CutSense Pro is a one-time in-app purchase (non-consumable) made through the App Store. It is not a subscription and never renews. It removes ads and unlocks fine-tune controls (minimum pause and breathing room); the ad SDK is not started from the next launch after purchase. The regular price is US$7.99 in the United States. The price that applies is the one, with taxes, the App Store shows for your country before you confirm.",
        ),
        t(
          "Pro, satın aldığın Apple Kimliğine bağlıdır. Yeni bir cihazda veya yeniden kurulumdan sonra Ayarlar > Satın Alımları Geri Yükle ile ücretsiz geri yükleyebilirsin; her satın alma ekranında da Geri Yükle vardır. Pro'yu yeniden satın almak yerine her zaman önce geri yükle.",
          "Pro is tied to the Apple ID you buy it with. On a new device or after reinstalling, restore it for free in Settings > Restore Purchases; every purchase screen also has Restore. Always restore instead of buying Pro again.",
        ),
      ],
    },
    {
      title: t("Sınırlı süreli teklifler", "Limited-time offers"),
      body: [
        t(
          "Uygulamada sunulduğu yerlerde CutSense Pro'yu iki tek seferlik indirimle alabilirsin. Geçerli olan fiyat her zaman satın alma anında uygulamada ve App Store onay ekranında gösterilen fiyattır; aşağıdaki ABD fiyatları örnektir. Normal fiyat (ABD'de 7,99 $) her teklif ekranında üstü çizili olarak gösterilir.",
          "Where offered in the app, you can buy CutSense Pro with one of two one-time discounts. The price that applies is always the one shown in the app and on the App Store confirmation sheet at the time of purchase; the US prices below are examples. The regular price (US$7.99 in the United States) is shown struck through on every offer screen.",
        ),
        t(
          "Hoş geldin teklifi (ABD'de 5,99 $): ilk açılıştaki tanıtımın sonunda bir kez gösterilebilir. Geri sayımı yoktur. Tanıtımı Geç ile atlarsan gösterilmez. “Şimdi değil” veya kapat dersen tekrar çıkmaz.",
          "Welcome offer (US$5.99 in the United States): may be shown once, at the end of the first-run intro. It has no countdown. It is not shown if you skip the intro. If you tap Not now or close it, it does not come back.",
        ),
        t(
          "Flaş teklif (ABD'de 3,99 $): Pro almadıysan, tanıtım bittikten (atlansa bile) 10 dakika sonra başlar ve 15 dakika sürer. Kurulum başına yalnızca bir kez olur ve tekrar başlamaz. Zamanlayıcı gerçek saattir: uygulama kapalıyken de işler, uzatılmaz ve süre bitince teklif sona erer. Uygulamada kalan süre gösterilir. Cihaz saatini geri almak teklifi sonlandırır.",
          "Flash offer (US$3.99 in the United States): if you have not bought Pro, it starts 10 minutes after the intro ends (even if skipped) and lasts 15 minutes. It happens only once per installation and never restarts. The timer is real time: it keeps running while the app is closed, is not extended, and the offer ends when time runs out. The app shows the time left. Setting the device clock back ends the offer.",
        ),
        t(
          "İndirimli ürünler normal Pro ile aynı özellikleri açar, abonelik değildir ve tek seferlik ödenir. Teklifler birleştirilemez: tek bir Pro satın alımı yeterlidir. Pro sahiplerine teklif gösterilmez; Pro'n varsa satın almak yerine Geri Yükle'yi kullan. Teklifler devredilemez, nakde çevrilemez ve süresi geçen teklif geri getirilmez. Teklifleri değiştirebilir veya sonlandırabiliriz; bu, önceden yaptığın satın alımı etkilemez. Süre bitince normal fiyat geçerlidir.",
          "Discounted products unlock the same Pro features, are not subscriptions, and are paid once. Offers cannot be combined: one Pro purchase is all you need. Pro owners are not shown offers; if you already have Pro, use Restore instead of buying. Offers are not transferable, have no cash value, and an expired offer is not brought back. We may change or end offers; that does not affect a purchase you already made. When an offer ends, the regular price applies.",
        ),
      ],
    },
    {
      title: t("Ödeme ve iadeler", "Payment and refunds"),
      body: [
        t(
          "Tüm ödemeleri Apple işler; kart bilgilerini almayız. İadeler Apple'ın politikalarına ve bulunduğun yerin zorunlu tüketici yasalarına tabidir ve reportaproblem.apple.com üzerinden Apple'dan istenir; biz doğrudan iade yapamayız. Bir satın alma iade edilirse Pro kapanır.",
          "All payments are processed by Apple; we never receive card details. Refunds follow Apple's policies and the mandatory consumer law where you live, and are requested from Apple at reportaproblem.apple.com; we cannot issue refunds directly. If a purchase is refunded, Pro is turned off.",
        ),
      ],
    },
    {
      title: t("Çıktı kalitesi ve yedekler", "Output quality and backups"),
      body: [
        t(
          "CutSense sessizlikleri otomatik keser ve otomatik düzenleme kusursuz değildir. Sonuç; kaynak videonun ses kalitesine, arka plan gürültüsüne, müziğe, konuşma hızına ve seçtiğin ayarlara bağlıdır. Bazen istediğin bir bölüm kesilebilir veya bir sessizlik kalabilir. Dışa aktarılan videoyu yayınlamadan, göndermeden veya ona güvenmeden önce izlemek senin sorumluluğundadır.",
          "CutSense cuts silence automatically, and automatic editing is not perfect. Results depend on the source video's audio quality, background noise, music, speaking pace, and the settings you choose. Sometimes a part you wanted may be cut or a pause may remain. You are responsible for watching the exported video before publishing, sending, or relying on it.",
        ),
        t(
          "CutSense orijinal videonu değiştirmez ve yeni bir kopya kaydeder. Yine de orijinallerini sakla ve önemli videolarının yedeğini al; cihazındaki veri kaybından biz sorumlu değiliz.",
          "CutSense does not change your original video and saves a new copy. Still, keep your originals and back up important videos; we are not responsible for loss of data on your device.",
        ),
      ],
    },
    {
      title: t("Üçüncü taraf servisler", "Third-party services"),
      body: [
        t(
          "Reklam ve rıza özelliklerini Google, satın alımları Apple sağlar. Bu servisler kendi şartlarına tabidir; değişebilir, kesintiye uğrayabilir veya doğrudan kontrolümüz dışında içerik gösterebilir.",
          "Advertising and consent features are provided by Google, and purchases by Apple. These services follow their own terms and may change, be interrupted, or display content outside our direct control.",
        ),
      ],
    },
    {
      title: t("Garanti yok", "No warranty"),
      body: [
        t(
          "CutSense olduğu gibi ve mevcut haliyle sunulur. Yasaların izin verdiği azami ölçüde kesintisiz çalışma, hatasız sonuç, belirli bir amaca uygunluk, satılabilirlik ve ihlal etmeme dahil tüm açık ve örtülü garantileri reddederiz. Özellikleri değiştirebilir, güncelleyebilir veya uygulamayı yayından kaldırabiliriz. Yasanın sana tanıdığı zorunlu garantiler bundan etkilenmez.",
          "CutSense is provided as is and as available. To the maximum extent permitted by law, we disclaim all express and implied warranties, including uninterrupted operation, error-free results, fitness for a particular purpose, merchantability, and non-infringement. We may change, update, or withdraw features or the app. Mandatory warranties the law gives you are not affected.",
        ),
      ],
    },
    {
      title: t("Sorumluluğun sınırlandırılması", "Limitation of liability"),
      body: [
        t(
          "Yasaların izin verdiği azami ölçüde CutSense kullanımından doğan dolaylı, arızi, özel, sonuçsal veya cezai zararlardan ya da veri, içerik, gelir, kâr, takipçi veya itibar kaybından sorumlu değiliz. Toplam sorumluluğumuz, son 12 ayda CutSense için ödediğin tutarla sınırlıdır.",
          "To the maximum extent permitted by law, we are not liable for indirect, incidental, special, consequential, or punitive damages, or for loss of data, content, revenue, profits, followers, or goodwill arising from use of CutSense. Our total liability is limited to the amount you paid for CutSense in the last 12 months.",
        ),
        t(
          "Bu sınırlamalar; kasıt veya ağır kusurdan, ölüm veya yaralanmadan doğan sorumluluğu ve bulunduğun yerin zorunlu tüketici yasalarından doğan hakları (Türkiye'de 6502 sayılı Tüketicinin Korunması Hakkında Kanun dahil) kısıtlamaz. Bazı ülkeler bu sınırlamalara izin vermez; o durumda yalnızca izin verilen ölçüde uygulanır.",
          "These limits do not restrict liability for intent or gross negligence, for death or personal injury, or rights you have under mandatory consumer law where you live (including Türkiye's Consumer Protection Law No. 6502). Some countries do not allow these limits; in that case they apply only as far as allowed.",
        ),
      ],
    },
    {
      title: t("Uygulanacak hukuk ve uyuşmazlıklar", "Governing law and disputes"),
      body: [
        t(
          "Bu şartlar Türkiye Cumhuriyeti hukukuna tabidir ve uyuşmazlıklarda Türkiye mahkemeleri yetkilidir. Tüketiciysen, yaşadığın ülkenin zorunlu tüketici koruma kuralları ve oradaki mahkemelere veya tüketici hakem heyetlerine başvurma hakkın saklıdır. Bir sorun olursa önce bize yaz; çoğu konuyu doğrudan çözebiliriz.",
          "These terms are governed by the laws of the Republic of Türkiye, and the courts of Türkiye have jurisdiction over disputes. If you are a consumer, the mandatory consumer protection rules of your country of residence, and your right to go to the courts or consumer dispute bodies there, are preserved. If something goes wrong, email us first; we can resolve most issues directly.",
        ),
      ],
    },
    {
      title: t("Değişiklikler", "Changes"),
      body: [
        t(
          "Bu şartları güncelleyebiliriz. Güncel sürüm her zaman bu sayfadadır ve yürürlük tarihi yukarıda yazar. Değişiklikler yayımlandıktan sonra geçerli olur ve önceden yaptığın satın alımları geriye dönük olarak etkilemez. Güncellemelerden sonra CutSense'i kullanmaya devam etmen, güncellenmiş şartları kabul ettiğin anlamına gelir; kabul etmiyorsan uygulamayı kullanmayı bırakabilirsin.",
          "We may update these terms. The current version is always on this page, with the effective date above. Changes apply once published and do not retroactively affect purchases you already made. Continued use of CutSense after an update means you accept the updated terms; if you do not agree, you can stop using the app.",
        ),
      ],
    },
    {
      title: t("Bölünebilirlik ve diğer hükümler", "Severability and other terms"),
      body: [
        t(
          "Bu şartların bir hükmü geçersiz veya uygulanamaz sayılırsa, o hüküm gereken en az ölçüde sınırlanır ve diğer hükümler geçerli kalır. Bir hakkı kullanmamamız o haktan vazgeçtiğimiz anlamına gelmez. Bu şartlar, Apple EULA ve Gizlilik Politikası ile birlikte CutSense konusunda aramızdaki anlaşmanın tamamıdır. Türkçe ve İngilizce sürümler arasında fark olursa, zorunlu yasa aksini gerektirmedikçe Türkiye'deki kullanıcılar için Türkçe, diğerleri için İngilizce sürüm esas alınır.",
          "If any part of these terms is found invalid or unenforceable, it is limited to the minimum extent necessary and the rest remains in effect. Not enforcing a right does not waive it. These terms, Apple's EULA, and the Privacy Policy are the entire agreement between us about CutSense. If the Turkish and English versions differ, the Turkish version applies to users in Türkiye and the English version to everyone else, unless mandatory law requires otherwise.",
        ),
      ],
    },
    {
      title: t("İletişim", "Contact"),
      body: [
        t(
          `${seller}, Türkiye. Yasal veya destek soruları için ${contact} adresine yaz.`,
          `${seller}, Türkiye. For legal or support questions, email ${contact}.`,
        ),
      ],
    },
  ];

  return (
    <main>
      <SiteNav />
      <article className="legal-shell">
        <p className="eyebrow">CutSense</p>
        <h1>{t("Kullanım Şartları", "Terms of Service")}</h1>
        <p className="legal-intro">
          {t(
            "Bu şartlar CutSense iPhone uygulamasının ve web sitesinin kullanımını düzenler.",
            "These terms govern your use of the CutSense iPhone app and website.",
          )}
        </p>
        <div className="legal-sections">
          {sections.map((section) => (
            <section key={section.title}>
              <h2>{section.title}</h2>
              {section.body.map((paragraph) => (
                <p key={paragraph}>{paragraph}</p>
              ))}
            </section>
          ))}
        </div>
      </article>
      <SiteFooter />
    </main>
  );
}

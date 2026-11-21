"use client";

import { useLanguage } from "../language-context";
import { SiteFooter, SiteNav } from "../site-chrome";

export function TermsContent() {
  const { t } = useLanguage();

  const sections: { title: string; body: string[] }[] = [
    {
      title: t("Yürürlük tarihi", "Effective date"),
      body: [t("22 Kasım 2026", "November 22, 2026")],
    },
    {
      title: t("Bu şartlar ve Apple EULA", "These terms and Apple's EULA"),
      body: [
        t(
          "CutSense'i indirmen veya kullanman, bu şartları ve Apple'ın Standart Lisanslı Uygulama Son Kullanıcı Lisans Sözleşmesi'ni (apple.com/legal/internet-services/itunes/dev/stdeula) kabul ettiğin anlamına gelir. Bu şartlar Apple EULA'yı tamamlar; çelişki olursa uygulama lisansı konusunda Apple EULA geçerlidir. Gizlilik Politikamız da bu şartların parçasıdır.",
          "By downloading or using CutSense you agree to these terms and to Apple's Standard Licensed Application End User License Agreement (apple.com/legal/internet-services/itunes/dev/stdeula). These terms supplement Apple's EULA; if they conflict, Apple's EULA governs the app license. Our Privacy Policy is also part of these terms.",
        ),
      ],
    },
    {
      title: t("Lisans", "License"),
      body: [
        t(
          "Bu şartlara ve App Store kurallarına tabi olarak, sahip olduğun veya kontrol ettiğin Apple cihazlarında CutSense'i kişisel kullanımın için sınırlı, devredilemez ve geri alınabilir bir lisans veririz.",
          "Subject to these terms and App Store rules, we grant you a limited, non-transferable, revocable license to use CutSense for your own use on Apple devices you own or control.",
        ),
      ],
    },
    {
      title: t("Ücretsiz sürüm ve reklamlar", "Free version and ads"),
      body: [
        t(
          "CutSense'i indirmek ve kullanmak ücretsizdir; hesap ve abonelik yoktur. Ücretsiz sürüm banner reklamlar, işlem sırasında native reklamlar ve isteğe bağlı ödüllü reklamlar gösterir. Ödüllü bir reklamı sonuna kadar izlersen banner ve native reklamlar 24 saat durur; bu süre en fazla 72 saate kadar birikir. Reklamları Google sağlar.",
          "CutSense is free to download and use, with no account and no subscription. The free version shows banner ads, native ads while a video is processing, and optional rewarded ads. If you watch a rewarded ad to the end, banner and native ads pause for 24 hours; this time stacks up to a maximum of 72 hours. Ads are provided by Google.",
        ),
      ],
    },
    {
      title: t("CutSense Pro", "CutSense Pro"),
      body: [
        t(
          "Uygulamada sunulduğu yerde CutSense Pro, App Store üzerinden alınan tek seferlik bir uygulama içi satın alımdır (tüketilmeyen ürün). Abonelik değildir ve yenilenmez. Reklamları kaldırır ve ince ayar kontrollerini (en kısa duraklama ve nefes payı) açar. Normal fiyat ABD'de 7,99 $'dır; ülkendeki fiyat ve vergiler satın almadan önce App Store'da gösterilir.",
          "Where available in the app, CutSense Pro is a one-time in-app purchase (non-consumable) made through the App Store. It is not a subscription and never renews. It removes ads and unlocks fine-tune controls (minimum pause and breathing room). The regular price is US$7.99 in the United States; the price and taxes for your country are shown by the App Store before you confirm.",
        ),
        t(
          "Pro, satın aldığın Apple Kimliğine bağlıdır. Yeni bir cihazda veya yeniden kurulumdan sonra Ayarlar > Satın Alımları Geri Yükle ile ücretsiz geri yükleyebilirsin.",
          "Pro is tied to the Apple ID you buy it with. On a new device or after reinstalling, restore it for free in Settings > Restore Purchases.",
        ),
      ],
    },
    {
      title: t("Sınırlı süreli teklifler", "Limited-time offers"),
      body: [
        t(
          "Uygulamada sunulduğu yerlerde CutSense Pro'yu indirimli bir fiyata (ABD'de 3,99 $; normal fiyat 7,99 $) alabilirsin. Hoş geldin teklifi ilk videonu kaydettikten sonra 24 saat sürer. Daha sonra, en az 7 gün geçmiş ve en az 3 video kaydetmişsen tek bir 15 dakikalık teklif çıkabilir. Her teklif bir kurulumda en fazla bir kez görünür, kalan süre uygulamada gösterilir ve süre bitince normal fiyat geçerli olur.",
          "Where offered in the app, you can buy CutSense Pro at a reduced price (US$3.99 in the United States; regular price US$7.99). The welcome offer lasts 24 hours after you save your first video. Later, once at least 7 days have passed and you have saved at least 3 videos, a single 15-minute offer may appear. Each offer appears at most once per installation, the time left is shown in the app, and the regular price applies when it ends.",
        ),
        t(
          "İndirimli ürün normal Pro ile aynı özellikleri açar, abonelik değildir ve tek seferlik ödenir. Pro'ya zaten sahipsen tekrar ücretlendirilmezsin. Teklifler devredilemez ve nakde çevrilemez; teklifleri değiştirebilir veya sonlandırabiliriz, ancak bu, önceden yaptığın satın alımı etkilemez.",
          "The discounted product unlocks the same Pro features, is not a subscription, and is paid once. If you already own Pro you are not charged again. Offers are not transferable and have no cash value; we may change or end offers, but that does not affect a purchase you already made.",
        ),
      ],
    },
    {
      title: t("Ödeme ve iadeler", "Payment and refunds"),
      body: [
        t(
          "Tüm ödemeleri Apple işler; kart bilgilerini almayız. İadeler Apple'ın politikalarına tabidir ve reportaproblem.apple.com üzerinden Apple'dan istenir; biz doğrudan iade yapamayız. Bir satın alma iade edilirse Pro kapanır.",
          "All payments are processed by Apple; we never receive card details. Refunds follow Apple's policies and are requested from Apple at reportaproblem.apple.com; we cannot issue refunds directly. If a purchase is refunded, Pro is turned off.",
        ),
      ],
    },
    {
      title: t("İçeriğin", "Your content"),
      body: [
        t(
          "Seçtiğin, düzenlediğin, dışa aktardığın, kaydettiğin veya paylaştığın videoların mülkiyeti sende kalır. CutSense içeriğin üzerinde hak iddia etmez ve videolarını cihazından göndermez. İçeriğinin ve kullanımının telif hakkı, gizlilik, tanıtım hakkı ve diğer üçüncü taraf haklarına uygun olmasından sen sorumlusun.",
          "You keep ownership of the videos you select, edit, export, save, or share. CutSense claims no rights over your content and does not send your videos off your device. You are responsible for making sure your content and use comply with copyright, privacy, publicity, and other third-party rights.",
        ),
      ],
    },
    {
      title: t("Çıktıyı kontrol etme", "Output review"),
      body: [
        t(
          "CutSense sessizlikleri otomatik keser, ancak otomatik düzenleme kusursuz değildir. Dışa aktarılan videoları yayınlamadan, göndermeden veya onlara güvenmeden önce kontrol etmekten sen sorumlusun. Orijinal videon değiştirilmez.",
          "CutSense cuts silence automatically, but automatic editing is not perfect. You are responsible for reviewing exported videos before publishing, sending, or relying on them. Your original video is not changed.",
        ),
      ],
    },
    {
      title: t("Yasak davranışlar", "Restricted conduct"),
      body: [
        t(
          "CutSense'i yasaları çiğnemek, üçüncü taraf haklarını ihlal etmek, zararlı içerik dağıtmak, uygulamayı tersine mühendislik yapmak, reklam, rıza veya satın alma sistemlerini aşmak, uygulamayı yeniden satmak ya da uygulama güvenliğine müdahale etmek için kullanamazsın.",
          "You may not use CutSense to break the law, violate third-party rights, distribute harmful content, reverse engineer the app, bypass advertising, consent, or purchase systems, resell the app, or interfere with app security.",
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
          "CutSense olduğu gibi ve mevcut haliyle sunulur. Yasaların izin verdiği azami ölçüde kesintisiz çalışma, hatasız sonuç, belirli bir amaca uygunluk ve ihlal etmeme dahil tüm garantileri reddederiz.",
          "CutSense is provided as is and as available. To the maximum extent permitted by law, we disclaim warranties of uninterrupted operation, error-free results, fitness for a particular purpose, and non-infringement.",
        ),
      ],
    },
    {
      title: t("Sorumluluğun sınırlandırılması", "Limitation of liability"),
      body: [
        t(
          "Yasaların izin verdiği azami ölçüde CutSense kullanımından doğan dolaylı, arızi, özel, sonuçsal veya cezai zararlardan ya da veri, gelir, kâr veya itibar kaybından sorumlu değiliz. Toplam sorumluluğumuz, son 12 ayda CutSense için ödediğin tutarla sınırlıdır. Bu şartlardaki hiçbir şey, bulunduğun yerin zorunlu tüketici yasalarından doğan haklarını kısıtlamaz.",
          "To the maximum extent permitted by law, we are not liable for indirect, incidental, special, consequential, or punitive damages, or for loss of data, revenue, profits, or goodwill arising from use of CutSense. Our total liability is limited to the amount you paid for CutSense in the last 12 months. Nothing in these terms limits rights you have under mandatory consumer law where you live.",
        ),
      ],
    },
    {
      title: t("Değişiklikler", "Changes"),
      body: [
        t(
          "Bu şartları güncelleyebiliriz. Güncel sürüm her zaman bu sayfadadır ve yürürlük tarihi yukarıda yazar. Güncellemelerden sonra CutSense'i kullanmaya devam etmen, güncellenmiş şartları kabul ettiğin anlamına gelir.",
          "We may update these terms. The current version is always on this page, with the effective date above. Continued use of CutSense after an update means you accept the updated terms.",
        ),
      ],
    },
    {
      title: t("İletişim", "Contact"),
      body: [
        t(
          "Yasal veya destek soruları için info@vibecodingturkey.com adresine yaz.",
          "For legal or support questions, email info@vibecodingturkey.com.",
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
            "Bu şartlar CutSense iPhone uygulamasını ve web sitesini kullanımını düzenler.",
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

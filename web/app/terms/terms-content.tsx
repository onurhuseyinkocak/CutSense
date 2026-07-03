"use client";

import { useLanguage } from "../language-context";
import { SiteFooter, SiteNav } from "../site-chrome";

export function TermsContent() {
  const { t } = useLanguage();

  const sections = [
    {
      title: t("Yürürlük tarihi", "Effective date"),
      body: "June 29, 2026",
    },
    {
      title: t("Lisans", "License"),
      body: t(
        "Bu şartlara ve App Store kurallarına tabi olarak, sahip olduğun veya kontrol ettiğin kişisel cihazlarda CutSense'i kullanman için sınırlı, devredilemez ve geri alınabilir bir lisans veririz.",
        "We grant you a limited, non-transferable, revocable license to use CutSense on personal devices you own or control, subject to these terms and App Store rules.",
      ),
    },
    {
      title: t("Ücretsiz ve reklam destekli", "Free and ad-supported"),
      body: t(
        "CutSense ücretsizdir. Hesap sistemi, abonelik veya ödeme duvarı yoktur. Ürünün çalışmasını desteklemek için uygulama banner reklamlar, native reklamlar ve isteğe bağlı reklam araları gösterebilir.",
        "CutSense is free to use. It has no account system, subscription, or paywall. The app may show banner ads, native ads, and optional ad breaks to support operation of the product.",
      ),
    },
    {
      title: t("İçeriğin", "Your content"),
      body: t(
        "Seçtiğin, düzenlediğin, dışa aktardığın, kaydettiğin veya paylaştığın videoların mülkiyeti sende kalır. CutSense içeriğin üzerinde mülkiyet iddia etmez. İçeriğinin ve uygulamayı kullanımının telif hakkı, gizlilik, tanıtım hakkı ve diğer üçüncü taraf haklarına uygun olmasından sen sorumlusun.",
        "You keep ownership of the videos you select, edit, export, save, or share. CutSense does not claim ownership over your content. You are responsible for making sure your content and use of the app comply with copyright, privacy, publicity, and other third-party rights.",
      ),
    },
    {
      title: t("Çıktıyı kontrol etme", "Output review"),
      body: t(
        "CutSense sessizlikleri otomatik keser, ancak otomatik düzenleme kusursuz değildir. Dışa aktarılan videoları yayınlamadan, göndermeden veya onlara güvenmeden önce kontrol etmekten sen sorumlusun.",
        "CutSense cuts silence automatically, but automatic editing is not perfect. You are responsible for reviewing exported videos before publishing, sending, or relying on them.",
      ),
    },
    {
      title: t("Yasak davranışlar", "Restricted conduct"),
      body: t(
        "CutSense'i yasaları çiğnemek, üçüncü taraf haklarını ihlal etmek, zararlı içerik dağıtmak, uygulamayı tersine mühendislik yapmak, reklam veya rıza sistemlerini aşmak, uygulamayı yeniden satmak ya da uygulama güvenliğine müdahale etmek için kullanamazsın.",
        "You may not use CutSense to break the law, violate third-party rights, distribute harmful content, reverse engineer the app, bypass advertising or consent systems, resell the app, or interfere with app security.",
      ),
    },
    {
      title: t("Üçüncü taraf servisler", "Third-party services"),
      body: t(
        "Reklam ve rıza özellikleri Google tarafından sağlanır. Üçüncü taraf servisler değişebilir, başarısız olabilir veya doğrudan kontrolümüz dışında içerik gösterebilir.",
        "Advertising and consent features are provided by Google. Third-party services may change, fail, or display content outside our direct control.",
      ),
    },
    {
      title: t("Garanti yok", "No warranty"),
      body: t(
        "CutSense olduğu gibi ve mevcut haliyle sunulur. Yasaların izin verdiği azami ölçüde kesintisiz çalışma, hatasız sonuç, belirli bir amaca uygunluk ve ihlal etmeme dahil olmak üzere tüm garantileri reddederiz.",
        "CutSense is provided as is and as available. To the maximum extent permitted by law, we disclaim warranties of uninterrupted operation, error-free results, fitness for a particular purpose, and non-infringement.",
      ),
    },
    {
      title: t("Sorumluluğun sınırlandırılması", "Limitation of liability"),
      body: t(
        "Yasaların izin verdiği azami ölçüde CutSense kullanımından doğan dolaylı, arızi, özel, sonuçsal, örnek niteliğinde veya cezai zararlardan ya da veri, gelir, kar, itibar veya iş fırsatı kaybından sorumlu değiliz.",
        "To the maximum extent permitted by law, we are not liable for indirect, incidental, special, consequential, exemplary, or punitive damages, or for loss of data, revenue, profits, goodwill, or business opportunities arising from use of CutSense.",
      ),
    },
    {
      title: t("Değişiklikler", "Changes"),
      body: t(
        "Bu şartları zaman zaman güncelleyebiliriz. Güncellemelerden sonra CutSense'i kullanmaya devam etmen, güncellenmiş şartları kabul ettiğin anlamına gelir.",
        "We may update these terms from time to time. Continued use of CutSense after updates means you accept the updated terms.",
      ),
    },
    {
      title: t("İletişim", "Contact"),
      body: t(
        "Yasal veya destek soruları için info@vibecodingturkey.com adresine yazabilirsin.",
        "For legal or support questions, contact info@vibecodingturkey.com.",
      ),
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
              <p>{section.body}</p>
            </section>
          ))}
        </div>
      </article>
      <SiteFooter />
    </main>
  );
}

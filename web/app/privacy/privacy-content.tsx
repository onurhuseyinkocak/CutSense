"use client";

import { useLanguage } from "../language-context";
import { SiteFooter, SiteNav } from "../site-chrome";

export function PrivacyContent() {
  const { t } = useLanguage();

  const sections = [
    {
      title: t("Yürürlük tarihi", "Effective date"),
      body: "June 29, 2026",
    },
    {
      title: t("Hesap veya kayıt yok", "No account or signup"),
      body: t(
        "CutSense hesap, kayıt, giriş, abonelik veya ödeme duvarı gerektirmez. Uygulama için kullanıcı profili oluşturmayız.",
        "CutSense does not require an account, signup, login, subscription, or paywall. We do not create user profiles for the app.",
      ),
    },
    {
      title: t("Seçtiğin videolar", "Videos you select"),
      body: t(
        "CutSense yalnızca Fotoğraflar'dan açıkça seçtiğin videoları okur. Uygulama, kendi sunucularımız için tüm arşivini taramaz ve seçtiğin videoları CutSense sunucusuna yüklemez. Sessizlik analizi ve kesme işlemi cihazında çalışır. İşlem sırasında cihazında geçici çalışma dosyaları oluşturulabilir; bunlar iOS tarafından veya uygulamayı sildiğinde kaldırılabilir.",
        "CutSense only reads videos you explicitly choose from Photos. The app does not enumerate your full library for our own servers and does not upload your selected videos to a CutSense server. Silence analysis and cutting run on your device. Temporary working files may be created on your device during processing and can be removed by iOS or when you delete the app.",
      ),
    },
    {
      title: t("Fotoğraf arşivi izinleri", "Photo library permissions"),
      body: t(
        "CutSense seçtiğin videoyu içe aktarmak için fotoğraf arşivi erişimi ister. Bir dışa aktarımı Fotoğraflar'a kaydettiğinde uygulama yalnızca ekleme izni isteyebilir. Bu izinleri iOS Ayarları'ndan değiştirebilirsin.",
        "CutSense asks for photo library access to import a video you select. If you save an export to Photos, the app may ask for add-only photo library permission. You can change these permissions in iOS Settings.",
      ),
    },
    {
      title: t("Reklamlar ve rıza", "Ads and consent"),
      body: t(
        "CutSense ücretsiz ve reklam desteklidir. Reklam göstermek, reklam performansını ölçmek, kötüye kullanımı önlemek, rıza tercihlerini yönetmek ve reklam teslimini teşhis etmek için Google Mobile Ads ve Google User Messaging Platform kullanırız. Google; IP adresi, cihaz tanımlayıcıları, uygulama ve reklam etkileşimleri, ağ bilgisinden türetilen yaklaşık konum, çökme verileri, performans verileri ve tanılama bilgileri gibi verileri işleyebilir. CutSense seçtiğin videoları Google'a yüklemez.",
        "CutSense is free and ad-supported. We use Google Mobile Ads and Google User Messaging Platform to show ads, measure ad performance, prevent abuse, manage consent choices, and diagnose ad delivery. Google may process data such as IP address, device identifiers, app and ad interactions, approximate location inferred from network information, crash data, performance data, and diagnostic information. Your selected videos are not uploaded to Google by CutSense.",
      ),
    },
    {
      title: t("Takip ve IDFA", "Tracking and IDFA"),
      body: t(
        "CutSense App Tracking Transparency izni istemez ve IDFA'ya erişmez. Bölgen ve rıza tercihlerine bağlı olarak Google reklam teknolojisi yine de App Store gizlilik ayrıntılarında açıklanması gereken verileri işleyebilir.",
        "CutSense does not request App Tracking Transparency permission and does not access IDFA. Depending on your region and consent choices, Google advertising technology may still process data that must be disclosed in App Store privacy details.",
      ),
    },
    {
      title: t("Çocuklar", "Children"),
      body: t(
        "CutSense 13 yaş altındaki çocuklara yönelik değildir. 13 yaş altındaki çocuklardan bilerek kişisel veri toplamaya çalışmayız.",
        "CutSense is not directed to children under 13. We do not knowingly seek personal data from children under 13.",
      ),
    },
    {
      title: t("Üçüncü taraf servisler", "Third-party services"),
      body: t(
        "Reklam ve rıza teknolojisi Google tarafından sağlanır. Google'ın veri uygulamaları Google'ın kendi politikalarına ve gerektiği yerlerde uygulamadaki rıza tercihlerine tabidir.",
        "Google provides advertising and consent technology. Google's data practices are governed by Google's own policies and by the consent choices available in the app where required.",
      ),
    },
    {
      title: t("Tercihlerin", "Your choices"),
      body: t(
        "Fotoğraflar iznini iOS Ayarları'ndan değiştirebilir, yerel uygulama verilerini kaldırmak için uygulamayı silebilir ve bölgen için gerekli olduğunda uygulama içindeki Google gizlilik seçeneklerini kullanabilirsin.",
        "You can change Photos permission in iOS Settings, delete the app to remove local app data, and use the in-app Google privacy options when they are required for your region.",
      ),
    },
    {
      title: t("İletişim", "Contact"),
      body: t(
        "Gizlilik soruları için info@vibecodingturkey.com adresine yazabilirsin.",
        "For privacy questions, contact info@vibecodingturkey.com.",
      ),
    },
  ];

  return (
    <main>
      <SiteNav />
      <article className="legal-shell">
        <p className="eyebrow">CutSense</p>
        <h1>{t("Gizlilik Politikası", "Privacy Policy")}</h1>
        <p className="legal-intro">
          {t(
            "Bu politika CutSense'in videoları, izinleri, reklamları, rıza yönetimini ve tanılama verilerini nasıl ele aldığını açıklar.",
            "This policy explains how CutSense handles videos, permissions, ads, consent, and diagnostics.",
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

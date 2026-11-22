"use client";

import Link from "next/link";
import { useLanguage } from "../language-context";
import { SiteFooter, SiteNav } from "../site-chrome";

export function SupportContent() {
  const { t } = useLanguage();

  const issues: { title: string; body: string; link?: { href: string; label: string } }[] = [
    {
      title: t("Video uzun sürüyor", "The video takes a long time"),
      body: t(
        "Büyük videolar daha fazla zaman ister; çünkü CutSense sesi analiz eder ve iPhone'unda yeni bir dosya dışa aktarır. Sonuç ekranı görünene kadar uygulamayı açık tut.",
        "Large videos need more time because CutSense analyzes audio and exports a new file on your iPhone. Keep the app open until the result screen appears.",
      ),
    },
    {
      title: t("Kesim fazla sert", "The cut is too aggressive"),
      body: t(
        "Hardcore yerine Dengeli veya Sıkı modu dene, sonra sonuç ekranından aynı videoyu tekrar çalıştır.",
        "Try Balanced or Tight instead of Hardcore, then run the same video again from the result screen.",
      ),
    },
    {
      title: t("Fotoğraflar'a kaydetme başarısız", "Saving to Photos fails"),
      body: t(
        "iOS Ayarları'nı aç ve CutSense'in Fotoğraflar'a ekleme izni olduğunu doğrula. Dışa aktarılan dosyayı başka yere göndermek için Paylaş'ı da kullanabilirsin.",
        "Open iOS Settings and confirm CutSense has permission to add to Photos. You can also use Share to send the exported file elsewhere.",
      ),
    },
    {
      title: t("Reklam gizlilik tercihleri", "Ad privacy choices"),
      body: t(
        "Gerekli olduğu bölgelerde (ör. AEA, Birleşik Krallık, İsviçre) rızanı Ayarlar > Reklam gizliliği > Gizlilik tercihlerini yönet bölümünden (CutSense 1.1 ve sonrası) istediğin an değiştirebilir veya geri çekebilirsin. Ayrıntılar Gizlilik Politikası'nda.",
        "Where required (for example in the EEA, UK, and Switzerland), you can change or withdraw consent any time in Settings > Ad privacy > Manage privacy choices (CutSense 1.1 and later). Details are in the Privacy Policy.",
      ),
    },
    {
      title: t("Pro'yu geri yükleme", "Restoring Pro"),
      body: t(
        "Yeni bir iPhone'da veya yeniden kurduktan sonra, satın aldığın Apple Kimliğiyle oturum açıp Ayarlar > Satın Alımları Geri Yükle'ye dokun. Tekrar ücret alınmaz.",
        "On a new iPhone or after reinstalling, sign in with the Apple ID you bought Pro with and tap Settings > Restore Purchases. You are not charged again.",
      ),
    },
    {
      title: t("İade", "Refunds"),
      body: t(
        "Ödemeleri Apple işlediği için iadeleri de Apple yapar; biz doğrudan iade yapamayız. Talebini Apple'ın sorun bildirme sayfasından ilet. İade edilen satın alımda Pro kapanır.",
        "Apple processes payments, so refunds are handled by Apple; we cannot issue them directly. Request one on Apple's report-a-problem page. If a purchase is refunded, Pro turns off.",
      ),
      link: { href: "https://reportaproblem.apple.com", label: "reportaproblem.apple.com" },
    },
    {
      title: t("Teklifler hakkında sorular", "Questions about offers"),
      body: t(
        "Hoş geldin teklifi ilk tanıtımın sonunda bir kez gösterilebilir. Flaş teklif, Pro almadıysan tanıtımdan 10 dakika sonra başlar, 15 dakika sürer ve kurulum başına bir kez olur; süresi geçen teklif geri getirilemez. Ödenecek fiyat her zaman satın alma anında App Store'da gösterilendir. Pro'n zaten varsa yeniden satın alma, Geri Yükle'yi kullan. Ayrıntılar Kullanım Şartları'nda.",
        "The welcome offer may be shown once at the end of the first-run intro. If you have not bought Pro, the flash offer starts 10 minutes after the intro, lasts 15 minutes, and happens once per installation; an expired offer cannot be brought back. The price you pay is always the one the App Store shows at purchase. If you already have Pro, do not buy again; use Restore. Details are in the Terms of Service.",
      ),
    },
    {
      title: t("Gizlilik talepleri", "Privacy requests"),
      body: t(
        "Verilerine erişim, düzeltme veya silme talebin (KVKK, GDPR veya ABD eyalet yasaları kapsamında) için kim olduğunu ve ne istediğini yazarak e-posta gönder; 30 gün içinde ücretsiz yanıt veririz. Videoların cihazından çıkmadığı için bizde video bulunmaz. Geçmiş'i Ayarlar > Geçmişi temizle ile, reklam verilerini Google'ın araçlarıyla yönetebilirsin.",
        "To access, correct, or delete your data (under KVKK, GDPR, or US state laws), email us saying who you are and what you need; we reply within 30 days, free of charge. Your videos never leave your device, so we hold none of them. You can clear History in Settings > Clear history and manage advertising data with Google's tools.",
      ),
    },
  ];

  return (
    <main>
      <SiteNav />
      <article className="legal-shell">
        <p className="eyebrow">{t("Yardım", "Help")}</p>
        <h1>{t("CutSense Destek", "CutSense Support")}</h1>
        <p className="legal-intro">
          {t(
            "İçe aktarma, kesme, kaydetme, reklamlar veya gizlilik tercihleriyle ilgili yardıma mı ihtiyacın var?",
            "Need help with importing, cutting, saving, ads, or privacy choices?",
          )}{" "}
          {t("E-posta:", "Email")}{" "}
          <a href="mailto:info@vibecodingturkey.com">
            info@vibecodingturkey.com
          </a>
          .
        </p>
        <div className="legal-sections">
          {issues.map((issue) => (
            <section key={issue.title}>
              <h2>{issue.title}</h2>
              <p>
                {issue.body}
                {issue.link ? (
                  <>
                    {" "}
                    <a
                      href={issue.link.href}
                      rel="noopener noreferrer"
                      style={{ color: "var(--text)", textDecoration: "underline" }}
                      target="_blank"
                    >
                      {issue.link.label}
                    </a>
                  </>
                ) : null}
              </p>
            </section>
          ))}
        </div>
        <div className="support-links">
          <Link className="button secondary" href="/privacy">
            {t("Gizlilik Politikası", "Privacy Policy")}
          </Link>
          <Link className="button secondary" href="/terms">
            {t("Kullanım Şartları", "Terms of Service")}
          </Link>
        </div>
      </article>
      <SiteFooter />
    </main>
  );
}

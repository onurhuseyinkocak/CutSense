"use client";

import Link from "next/link";
import { useLanguage } from "../language-context";
import { SiteFooter, SiteNav } from "../site-chrome";

export function SupportContent() {
  const { t } = useLanguage();

  const issues = [
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
        "Gerekli olduğu bölgelerde CutSense, uygulama ayarlarında Google gizlilik seçeneklerini gösterir. Bu tercihler bölgen için uygun Google reklam ve rıza davranışını kontrol eder.",
        "Where required, CutSense shows Google privacy options in the app settings. Those choices control eligible Google ad and consent behavior for your region.",
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
              <p>{issue.body}</p>
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

"use client";

import Image from "next/image";
import Link from "next/link";
import { useLanguage } from "./language-context";
import { SiteFooter, SiteNav } from "./site-chrome";

export default function Home() {
  const { t } = useLanguage();

  const workflow = [
    {
      label: t("Video seç", "Pick a video"),
      detail: t("Fotoğraflar'dan bir klip seç.", "Choose a clip from Photos."),
    },
    {
      label: t("Sesi tara", "Scan audio"),
      detail: t(
        "Ses analizi cihaz üzerinde çalışır.",
        "Audio analysis runs on device.",
      ),
    },
    {
      label: t("Sessizlikleri kes", "Cut pauses"),
      detail: t(
        "Dengeli, Sıkı veya Sert modu kullan.",
        "Balanced, Tight, or Hardcore.",
      ),
    },
    {
      label: t("MP4 dışa aktar", "Export MP4"),
      detail: t(
        "Kısaltılmış sonucu kaydet veya paylaş.",
        "Save or share the shorter result.",
      ),
    },
  ];

  const facts = [
    t("Hesap yok", "No account"),
    t("Onboarding duvarı yok", "No onboarding wall"),
    t("Abonelik yok", "No subscription"),
    t("Reklam destekli", "Ad-supported"),
    t("Orijinal dosya değişmez", "Original file untouched"),
    t("Seçilen videolar cihazda kalır", "Selected videos stay on device"),
  ];

  return (
    <main>
      <SiteNav />

      <section className="hero">
        <div className="hero-copy">
          <p className="eyebrow">
            {t("Ücretsiz iPhone sessizlik kesici", "Free iPhone silence cutter")}
          </p>
          <h1>CutSense</h1>
          <p className="hero-text">
            {t(
              "Bir video seç, kesim yoğunluğunu belirle ve orijinal dosyan değişmeden daha kısa bir MP4 dışa aktar.",
              "Pick a video, choose how aggressive the cuts should be, and export a shorter MP4 while your original stays untouched.",
            )}
          </p>
          <div className="hero-actions" aria-label="Primary actions">
            <Link className="button primary" href="/privacy">
              {t("Gizlilik Politikası", "Privacy Policy")}
            </Link>
            <Link className="button secondary" href="/support">
              {t("Destek", "Support")}
            </Link>
          </div>
        </div>

        <div className="product-visual" aria-label="CutSense product summary">
          <div className="phone-shell">
            <div className="phone-top">
              <Image
                src="/app-icon.png"
                width={72}
                height={72}
                alt="CutSense app icon"
                className="phone-icon"
                priority
              />
              <div>
                <p className="phone-title">
                  {t("Sessizlik Kes", "Cut Silence")}
                </p>
                <p className="phone-subtitle">
                  {t("Video seçildi", "Video selected")}
                </p>
              </div>
            </div>
            <div className="timeline" aria-hidden="true">
              <span className="speech" />
              <span className="silence" />
              <span className="speech short" />
              <span className="silence" />
              <span className="speech" />
            </div>
            <div className="cut-result">
              <span>{t("Sessizlik kaldırıldı", "Silence removed")}</span>
              <strong>38%</strong>
            </div>
          </div>
        </div>
      </section>

      <section className="fact-band" aria-label="Release model">
        {facts.map((fact) => (
          <span key={fact}>{fact}</span>
        ))}
      </section>

      <section className="content-grid">
        {workflow.map((item, index) => (
          <article className="workflow-card" key={item.label}>
            <span className="step-number">{index + 1}</span>
            <h2>{item.label}</h2>
            <p>{item.detail}</p>
          </article>
        ))}
      </section>

      <section className="privacy-strip">
        <div>
          <p className="eyebrow">{t("Gizlilik modeli", "Privacy model")}</p>
          <h2>
            {t(
              "Seçtiğin videolar iPhone'unda işlenir.",
              "Selected videos are processed on your iPhone.",
            )}
          </h2>
        </div>
        <p>
          {t(
            "CutSense kayıt gerektirmez ve seçtiğin videoları CutSense sunucusuna yüklemez. Uygulama Google Mobile Ads ile finanse edilir; bu nedenle reklam gösterimi, ölçüm, rıza yönetimi ve tanılama bilgileri gizlilik politikasında açıklanır.",
            "CutSense does not require signup and does not upload your selected videos to a CutSense server. The app is funded by Google Mobile Ads, so ad delivery, measurement, consent, and diagnostics are disclosed in the privacy policy.",
          )}
        </p>
      </section>

      <SiteFooter />
    </main>
  );
}

import type { Metadata } from "next";
import { SiteFooter, SiteNav } from "./site-chrome";
import {
  appStoreUrl,
  hreflangMap,
  landingJsonLd,
  type LandingPage,
} from "./landing-data";
import { siteUrl } from "./site";

export function landingMetadata(p: LandingPage): Metadata {
  return {
    title: { absolute: `${p.metaTitle} | CutSense` },
    description: p.description,
    alternates: { canonical: p.path, languages: hreflangMap },
    openGraph: {
      type: "website",
      url: `${siteUrl}${p.path}`,
      siteName: "CutSense",
      locale: p.locale.replace("-", "_"),
      title: p.metaTitle,
      description: p.description,
      images: [{ url: "/app-icon.png", width: 1024, height: 1024, alt: "CutSense app icon" }],
    },
    twitter: { card: "summary", title: p.metaTitle, description: p.description, images: ["/app-icon.png"] },
  };
}

export function LandingView({ page: p }: { page: LandingPage }) {
  return (
    <main>
      <SiteNav />
      <article className="legal-shell landing" lang={p.locale}>
        <p className="eyebrow">{p.eyebrow}</p>
        <h1>{p.h1}</h1>
        <p className="legal-intro">{p.intro}</p>
        <div className="support-links">
          <a className="button primary" href={appStoreUrl} rel="noopener">
            {p.cta}
          </a>
        </div>
        <p className="landing-note">{p.ctaNote}</p>

        <h2 className="landing-h2">{p.stepsTitle}</h2>
        <div className="landing-steps">
          {p.steps.map((s, i) => (
            <div className="workflow-card" key={s.title}>
              <span className="step-number">{i + 1}</span>
              <h3>{s.title}</h3>
              <p>{s.body}</p>
            </div>
          ))}
        </div>

        <h2 className="landing-h2">{p.whyTitle}</h2>
        <div className="legal-sections">
          {p.why.map((w) => (
            <section key={w.title}>
              <h3>{w.title}</h3>
              <p>{w.body}</p>
            </section>
          ))}
        </div>

        <h2 className="landing-h2">{p.faqTitle}</h2>
        <div className="legal-sections">
          {p.faq.map((f) => (
            <section key={f.q}>
              <h3>{f.q}</h3>
              <p>{f.a}</p>
            </section>
          ))}
        </div>

        <div className="support-links">
          <a className="button primary" href={appStoreUrl} rel="noopener">
            {p.cta}
          </a>
        </div>
      </article>
      <SiteFooter />
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(landingJsonLd(p)) }}
      />
    </main>
  );
}

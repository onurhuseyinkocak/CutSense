"use client";

import Image from "next/image";
import Link from "next/link";
import { LanguageToggle, useLanguage } from "./language-context";

export function SiteNav() {
  const { t } = useLanguage();

  return (
    <header className="site-nav" aria-label="Site navigation">
      <Link className="brand" href="/">
        <Image
          src="/app-icon.png"
          width={40}
          height={40}
          alt=""
          className="brand-icon"
          priority
        />
        <span>CutSense</span>
      </Link>
      <nav className="nav-links" aria-label="Primary">
        <Link href="/privacy">{t("Gizlilik", "Privacy")}</Link>
        <Link href="/terms">{t("Şartlar", "Terms")}</Link>
        <Link href="/support">{t("Destek", "Support")}</Link>
      </nav>
    </header>
  );
}

export function SiteFooter() {
  const { t } = useLanguage();

  return (
    <footer className="site-footer">
      <div className="footer-copy">
        <p>
          {t(
            "CutSense ücretsizdir, reklam desteklidir ve iPhone'da doğrudan kullanım için tasarlanmıştır.",
            "CutSense is free, ad-supported, and built for direct use on iPhone.",
          )}
        </p>
        <LanguageToggle />
      </div>
      <div className="footer-links">
        <Link href="/privacy">{t("Gizlilik Politikası", "Privacy Policy")}</Link>
        <Link href="/terms">{t("Kullanım Şartları", "Terms of Service")}</Link>
        <Link href="/support">{t("Destek", "Support")}</Link>
        <a href="mailto:info@vibecodingturkey.com">{t("İletişim", "Contact")}</a>
      </div>
    </footer>
  );
}

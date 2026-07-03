import type { Metadata, Viewport } from "next";
import "./globals.css";
import { LanguageProvider } from "./language-context";
import { siteUrl } from "./site";

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  applicationName: "CutSense",
  title: {
    default: "CutSense | Free Silence Cutter for iPhone",
    template: "%s | CutSense",
  },
  description:
    "CutSense is a free, ad-supported iPhone app that cuts silent pauses from selected videos on device. No account, no onboarding, no paywall.",
  alternates: {
    canonical: "/",
  },
  icons: {
    icon: "/app-icon.png",
    apple: "/app-icon.png",
  },
  openGraph: {
    type: "website",
    url: siteUrl,
    siteName: "CutSense",
    title: "CutSense | Free Silence Cutter for iPhone",
    description:
      "Pick a video, choose the cut intensity, and export a shorter MP4 while the original stays untouched.",
    images: [
      {
        url: "/app-icon.png",
        width: 1024,
        height: 1024,
        alt: "CutSense app icon",
      },
    ],
  },
  twitter: {
    card: "summary",
    title: "CutSense | Free Silence Cutter for iPhone",
    description:
      "Free, ad-supported on-device silence cutting for selected iPhone videos.",
    images: ["/app-icon.png"],
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  colorScheme: "dark",
  themeColor: "#050608",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>
        <LanguageProvider>{children}</LanguageProvider>
      </body>
    </html>
  );
}

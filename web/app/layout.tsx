import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "CutSense — Messy recording in. Polished video out.",
  description:
    "AI-powered video editing that turns messy talking-head recordings into clean, polished short-form content.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}

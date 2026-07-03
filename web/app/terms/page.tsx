import type { Metadata } from "next";
import { TermsContent } from "./terms-content";

export const metadata: Metadata = {
  title: "Terms of Service",
  description:
    "Terms of Service for CutSense, a free ad-supported iPhone silence cutter.",
  alternates: {
    canonical: "/terms",
  },
};

export default function TermsPage() {
  return <TermsContent />;
}

import type { Metadata } from "next";
import { SupportContent } from "./support-content";

export const metadata: Metadata = {
  title: "Support",
  description: "Support and troubleshooting for CutSense.",
  alternates: {
    canonical: "/support",
  },
};

export default function SupportPage() {
  return <SupportContent />;
}

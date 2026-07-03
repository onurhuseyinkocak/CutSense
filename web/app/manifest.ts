import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "CutSense",
    short_name: "CutSense",
    description: "Free ad-supported silence cutter for iPhone videos.",
    start_url: "/",
    display: "standalone",
    background_color: "#050608",
    theme_color: "#050608",
    icons: [
      {
        src: "/app-icon.png",
        sizes: "1024x1024",
        type: "image/png",
      },
    ],
  };
}

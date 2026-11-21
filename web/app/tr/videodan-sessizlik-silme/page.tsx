import { landingByLocale } from "../../landing-data";
import { LandingView, landingMetadata } from "../../landing-view";

const page = landingByLocale["tr"];

export const metadata = landingMetadata(page);

export default function Page() {
  return <LandingView page={page} />;
}

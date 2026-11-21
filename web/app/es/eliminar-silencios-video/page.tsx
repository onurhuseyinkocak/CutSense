import { landingByLocale } from "../../landing-data";
import { LandingView, landingMetadata } from "../../landing-view";

const page = landingByLocale["es"];

export const metadata = landingMetadata(page);

export default function Page() {
  return <LandingView page={page} />;
}

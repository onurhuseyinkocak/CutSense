import { landingByLocale } from "../../landing-data";
import { LandingView, landingMetadata } from "../../landing-view";

const page = landingByLocale["pt-BR"];

export const metadata = landingMetadata(page);

export default function Page() {
  return <LandingView page={page} />;
}

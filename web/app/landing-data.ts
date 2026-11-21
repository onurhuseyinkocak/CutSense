import { siteUrl } from "./site";

export const appStoreUrl = "https://apps.apple.com/app/id6770024868";

export type LandingLocale = "en" | "tr" | "es" | "pt-BR";

export type LandingPage = {
  locale: LandingLocale;
  path: string;
  metaTitle: string;
  description: string;
  eyebrow: string;
  h1: string;
  intro: string;
  stepsTitle: string;
  steps: { title: string; body: string }[];
  whyTitle: string;
  why: { title: string; body: string }[];
  faqTitle: string;
  faq: { q: string; a: string }[];
  cta: string;
  ctaNote: string;
  appDescription: string;
};

export const landingPages: LandingPage[] = [
  {
    locale: "en",
    path: "/remove-silence-from-video-iphone",
    metaTitle: "Remove Silence from Video on iPhone, Free",
    description:
      "Remove silence from video on iPhone with CutSense. Free, no watermark, processed on device. Pick a video, choose a cut level, review every cut, save.",
    eyebrow: "Free iPhone silence remover",
    h1: "Remove silence from video on iPhone",
    intro:
      "CutSense finds the pauses in your video and cuts them out, so talking-head clips, lectures and voiceovers get tighter in minutes. It is free, adds no watermark, and your video is processed on your iPhone.",
    stepsTitle: "How it works",
    steps: [
      {
        title: "Pick a video",
        body: "Choose any clip from your Photos library. Nothing is uploaded; the audio is analyzed on your iPhone.",
      },
      {
        title: "Choose a cut level",
        body: "Balanced keeps natural breathing room. Tight trims harder. Hardcore removes almost every gap.",
      },
      {
        title: "Review and save",
        body: "Go through every cut, restore any pause you want back, then save to Photos or share the new video.",
      },
    ],
    whyTitle: "Why people use it",
    why: [
      {
        title: "You stay in control",
        body: "Automatic cutting is never perfect. CutSense shows each cut so you can put back a dramatic pause or a breath before a punchline.",
      },
      {
        title: "Free and watermark-free",
        body: "The app is free and ad-supported. Exports carry no watermark. An optional one-time CutSense Pro purchase removes ads and adds fine-tune controls.",
      },
      {
        title: "Private by design",
        body: "No account and no upload of your video to a CutSense server. Your original file is left untouched.",
      },
    ],
    faqTitle: "Questions",
    faq: [
      {
        q: "Is it really free?",
        a: "Yes. CutSense is free to download and use, with no watermark on exports. The free version shows ads. CutSense Pro is an optional one-time purchase that removes ads and adds fine-tune controls.",
      },
      {
        q: "Is my video uploaded anywhere?",
        a: "No. Analysis and cutting run on your iPhone, and the video is not uploaded to a CutSense server. The ad SDK has its own data practices, described in the privacy policy.",
      },
      {
        q: "Does it change my original video?",
        a: "No. CutSense exports a new, shorter video and leaves the original in your library.",
      },
      {
        q: "Will it cut words by mistake?",
        a: "It can misjudge a quiet moment, which is why every cut is reviewable. Restore any pause with a tap before you save.",
      },
      {
        q: "What about video quality?",
        a: "CutSense keeps the original quality when possible. Very long or high-resolution clips take longer to export.",
      },
      {
        q: "Does it work on Android or Mac?",
        a: "Not today. CutSense is an iPhone app.",
      },
    ],
    cta: "Download on the App Store",
    ctaNote: "Free for iPhone. No account needed.",
    appDescription:
      "Free iPhone app that removes silent pauses from videos on device, with a review step for every cut.",
  },
  {
    locale: "tr",
    path: "/tr/videodan-sessizlik-silme",
    metaTitle: "Videodan Sessizlik Silme: iPhone, Ücretsiz",
    description:
      "iPhone'da videodan sessizlikleri sil. CutSense ücretsiz, filigransız ve cihazda çalışır. Videoyu seç, kesim seviyesini belirle, her kesimi gözden geçir, kaydet.",
    eyebrow: "Ücretsiz iPhone sessizlik silici",
    h1: "iPhone'da videodan sessizlik silme",
    intro:
      "CutSense videondaki duraksamaları bulup keser. Konuşma videoları, ders kayıtları ve seslendirmeler dakikalar içinde sıkılaşır. Ücretsizdir, filigran eklemez ve videon iPhone'unda işlenir.",
    stepsTitle: "Nasıl çalışır",
    steps: [
      {
        title: "Video seç",
        body: "Fotoğraflar'dan istediğin klibi seç. Hiçbir şey yüklenmez; ses analizi iPhone'unda yapılır.",
      },
      {
        title: "Kesim seviyesini seç",
        body: "Dengeli doğal nefes boşluklarını korur. Sıkı daha çok keser. Sert neredeyse tüm boşlukları siler.",
      },
      {
        title: "Gözden geçir ve kaydet",
        body: "Her kesime bak, geri istediğin duraksamayı geri getir, sonra Fotoğraflar'a kaydet ya da paylaş.",
      },
    ],
    whyTitle: "Neden CutSense",
    why: [
      {
        title: "Kontrol sende",
        body: "Otomatik kesim hiçbir zaman kusursuz olmaz. CutSense her kesimi gösterir; vurgulu bir duraksamayı ya da espriden önceki nefesi geri koyabilirsin.",
      },
      {
        title: "Ücretsiz ve filigransız",
        body: "Uygulama ücretsiz ve reklam destekli. Dışa aktarılan videoda filigran yok. İsteğe bağlı tek seferlik CutSense Pro satın alımı reklamları kaldırır ve ince ayar ekler.",
      },
      {
        title: "Tasarımdan gizli",
        body: "Hesap yok, videon bir CutSense sunucusuna yüklenmez. Orijinal dosyana dokunulmaz.",
      },
    ],
    faqTitle: "Sık sorulanlar",
    faq: [
      {
        q: "Gerçekten ücretsiz mi?",
        a: "Evet. CutSense'i indirmek ve kullanmak ücretsizdir, dışa aktarımda filigran yoktur. Ücretsiz sürümde reklam görünür. CutSense Pro, reklamları kaldıran ve ince ayar ekleyen isteğe bağlı tek seferlik bir satın alımdır.",
      },
      {
        q: "Videom bir yere yükleniyor mu?",
        a: "Hayır. Analiz ve kesim iPhone'unda çalışır, video bir CutSense sunucusuna yüklenmez. Reklam SDK'sının kendi veri uygulamaları gizlilik politikasında anlatılır.",
      },
      {
        q: "Orijinal videom değişiyor mu?",
        a: "Hayır. CutSense yeni, daha kısa bir video dışa aktarır; orijinal kitaplığında kalır.",
      },
      {
        q: "Yanlışlıkla kelime keser mi?",
        a: "Sessiz bir anı yanlış değerlendirebilir. Bu yüzden her kesim gözden geçirilebilir. Kaydetmeden önce istediğin duraksamayı tek dokunuşla geri getir.",
      },
      {
        q: "Video kalitesi ne olur?",
        a: "CutSense mümkün olduğunda orijinal kaliteyi korur. Çok uzun ya da yüksek çözünürlüklü videoların dışa aktarımı daha uzun sürer.",
      },
      {
        q: "Android veya Mac'te çalışır mı?",
        a: "Şimdilik hayır. CutSense bir iPhone uygulamasıdır.",
      },
    ],
    cta: "App Store'dan indir",
    ctaNote: "iPhone için ücretsiz. Hesap gerekmez.",
    appDescription:
      "Videolardaki sessiz duraksamaları cihazda silen, her kesimi gözden geçirmeye izin veren ücretsiz iPhone uygulaması.",
  },
  {
    locale: "es",
    path: "/es/eliminar-silencios-video",
    metaTitle: "Eliminar silencios de un video en iPhone, gratis",
    description:
      "Elimina los silencios de un video en iPhone con CutSense. Gratis, sin marca de agua y en tu dispositivo. Elige el video, el nivel de corte, revisa cada corte y guarda.",
    eyebrow: "Eliminador de silencios gratis para iPhone",
    h1: "Eliminar silencios de un video en iPhone",
    intro:
      "CutSense detecta las pausas de tu video y las corta, así que los videos hablados, las clases y las locuciones quedan más ágiles en minutos. Es gratis, no pone marca de agua y tu video se procesa en tu iPhone.",
    stepsTitle: "Cómo funciona",
    steps: [
      {
        title: "Elige un video",
        body: "Selecciona cualquier clip de tu biblioteca de Fotos. No se sube nada; el audio se analiza en tu iPhone.",
      },
      {
        title: "Elige el nivel de corte",
        body: "Equilibrado conserva un respiro natural. Ajustado corta más. Extremo elimina casi todas las pausas.",
      },
      {
        title: "Revisa y guarda",
        body: "Recorre cada corte, restaura la pausa que quieras recuperar y guarda en Fotos o comparte el video nuevo.",
      },
    ],
    whyTitle: "Por qué usarlo",
    why: [
      {
        title: "Tú tienes el control",
        body: "El corte automático nunca es perfecto. CutSense muestra cada corte para que puedas devolver una pausa dramática o el respiro antes de un remate.",
      },
      {
        title: "Gratis y sin marca de agua",
        body: "La app es gratuita y con anuncios. Las exportaciones no llevan marca de agua. Una compra única opcional, CutSense Pro, quita los anuncios y añade ajuste fino.",
      },
      {
        title: "Privada por diseño",
        body: "Sin cuenta y sin subir tu video a un servidor de CutSense. Tu archivo original no se toca.",
      },
    ],
    faqTitle: "Preguntas frecuentes",
    faq: [
      {
        q: "¿De verdad es gratis?",
        a: "Sí. CutSense es gratis para descargar y usar, y las exportaciones no llevan marca de agua. La versión gratuita muestra anuncios. CutSense Pro es una compra única opcional que quita los anuncios y añade ajuste fino.",
      },
      {
        q: "¿Mi video se sube a algún sitio?",
        a: "No. El análisis y el corte ocurren en tu iPhone y el video no se sube a un servidor de CutSense. El SDK de anuncios tiene sus propias prácticas de datos, descritas en la política de privacidad.",
      },
      {
        q: "¿Cambia mi video original?",
        a: "No. CutSense exporta un video nuevo y más corto, y deja el original en tu biblioteca.",
      },
      {
        q: "¿Puede cortar palabras por error?",
        a: "Puede interpretar mal un momento tranquilo, por eso cada corte se puede revisar. Restaura cualquier pausa con un toque antes de guardar.",
      },
      {
        q: "¿Y la calidad del video?",
        a: "CutSense conserva la calidad original cuando es posible. Los clips muy largos o de alta resolución tardan más en exportarse.",
      },
      {
        q: "¿Funciona en Android o Mac?",
        a: "Por ahora no. CutSense es una app para iPhone.",
      },
    ],
    cta: "Descargar en el App Store",
    ctaNote: "Gratis para iPhone. Sin cuenta.",
    appDescription:
      "App gratuita para iPhone que elimina las pausas en silencio de los videos en el dispositivo, con revisión de cada corte.",
  },
  {
    locale: "pt-BR",
    path: "/pt/remover-silencio-video",
    metaTitle: "Remover silêncio de vídeo no iPhone, grátis",
    description:
      "Remova o silêncio de vídeos no iPhone com o CutSense. Grátis, sem marca d'água e no próprio aparelho. Escolha o vídeo e o nível de corte, revise cada corte e salve.",
    eyebrow: "Removedor de silêncio grátis para iPhone",
    h1: "Remover silêncio de vídeo no iPhone",
    intro:
      "O CutSense encontra as pausas do seu vídeo e as corta, então vídeos falados, aulas e narrações ficam mais enxutos em minutos. É grátis, não coloca marca d'água e seu vídeo é processado no iPhone.",
    stepsTitle: "Como funciona",
    steps: [
      {
        title: "Escolha um vídeo",
        body: "Selecione qualquer clipe da sua biblioteca de Fotos. Nada é enviado; o áudio é analisado no seu iPhone.",
      },
      {
        title: "Escolha o nível de corte",
        body: "Equilibrado mantém uma respiração natural. Apertado corta mais. Extremo remove quase todas as pausas.",
      },
      {
        title: "Revise e salve",
        body: "Passe por cada corte, restaure a pausa que quiser de volta e salve em Fotos ou compartilhe o vídeo novo.",
      },
    ],
    whyTitle: "Por que usar",
    why: [
      {
        title: "Você no controle",
        body: "O corte automático nunca é perfeito. O CutSense mostra cada corte para você devolver uma pausa dramática ou a respiração antes de uma piada.",
      },
      {
        title: "Grátis e sem marca d'água",
        body: "O app é gratuito e com anúncios. As exportações não têm marca d'água. Uma compra única opcional, o CutSense Pro, remove os anúncios e adiciona ajuste fino.",
      },
      {
        title: "Privado por padrão",
        body: "Sem conta e sem enviar seu vídeo a um servidor do CutSense. Seu arquivo original não é alterado.",
      },
    ],
    faqTitle: "Perguntas frequentes",
    faq: [
      {
        q: "É grátis mesmo?",
        a: "Sim. O CutSense é grátis para baixar e usar, e as exportações não têm marca d'água. A versão gratuita exibe anúncios. O CutSense Pro é uma compra única opcional que remove os anúncios e adiciona ajuste fino.",
      },
      {
        q: "Meu vídeo é enviado para algum lugar?",
        a: "Não. A análise e o corte acontecem no seu iPhone, e o vídeo não é enviado a um servidor do CutSense. O SDK de anúncios tem suas próprias práticas de dados, descritas na política de privacidade.",
      },
      {
        q: "Ele altera meu vídeo original?",
        a: "Não. O CutSense exporta um vídeo novo e mais curto e deixa o original na sua biblioteca.",
      },
      {
        q: "Ele pode cortar palavras por engano?",
        a: "Pode interpretar mal um momento calmo, por isso cada corte pode ser revisado. Restaure qualquer pausa com um toque antes de salvar.",
      },
      {
        q: "E a qualidade do vídeo?",
        a: "O CutSense mantém a qualidade original quando possível. Clipes muito longos ou de alta resolução demoram mais para exportar.",
      },
      {
        q: "Funciona no Android ou no Mac?",
        a: "Por enquanto não. O CutSense é um app para iPhone.",
      },
    ],
    cta: "Baixar na App Store",
    ctaNote: "Grátis para iPhone. Sem conta.",
    appDescription:
      "App gratuito para iPhone que remove pausas em silêncio de vídeos no aparelho, com revisão de cada corte.",
  },
];

export const landingByLocale = Object.fromEntries(
  landingPages.map((p) => [p.locale, p]),
) as Record<LandingLocale, LandingPage>;

export const hreflangMap: Record<string, string> = {
  en: landingByLocale.en.path,
  tr: landingByLocale.tr.path,
  es: landingByLocale.es.path,
  "pt-BR": landingByLocale["pt-BR"].path,
  "x-default": landingByLocale.en.path,
};

export function landingJsonLd(p: LandingPage) {
  const url = `${siteUrl}${p.path}`;
  return [
    {
      "@context": "https://schema.org",
      "@type": "SoftwareApplication",
      name: "Silence Remover: CutSense",
      applicationCategory: "MultimediaApplication",
      operatingSystem: "iOS",
      description: p.appDescription,
      url,
      inLanguage: p.locale,
      downloadUrl: appStoreUrl,
      offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
    },
    {
      "@context": "https://schema.org",
      "@type": "FAQPage",
      inLanguage: p.locale,
      mainEntity: p.faq.map((f) => ({
        "@type": "Question",
        name: f.q,
        acceptedAnswer: { "@type": "Answer", text: f.a },
      })),
    },
  ];
}

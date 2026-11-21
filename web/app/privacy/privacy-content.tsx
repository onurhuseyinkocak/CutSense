"use client";

import { useLanguage } from "../language-context";
import { SiteFooter, SiteNav } from "../site-chrome";

const contact = "info@vibecodingturkey.com";

export function PrivacyContent() {
  const { t } = useLanguage();

  const sections: { title: string; body: string[] }[] = [
    {
      title: t("Yürürlük tarihi", "Effective date"),
      body: [t("22 Kasım 2026", "November 22, 2026")],
    },
    {
      title: t("Kısaca", "Summary"),
      body: [
        t(
          "CutSense videolarını iPhone'unda işler ve onları bize ya da başka birine göndermez. Hesap, kendi sunucumuz veya analiz aracımız yok. Ücretsiz sürüm Google AdMob reklamları gösterir; Google reklam göstermek ve ölçmek için cihaz ve kullanım verilerini işler. Bu sayfa hangi verilerin, neden ve kimin tarafından işlendiğini ve bunları nasıl kontrol edeceğini anlatır.",
          "CutSense processes your videos on your iPhone and does not send them to us or anyone else. There is no account, no server of our own, and no analytics tool. The free version shows Google AdMob ads, and Google processes device and usage data to show and measure them. This page explains what data is handled, why, by whom, and how you control it.",
        ),
      ],
    },
    {
      title: t("Biz kimiz", "Who we are"),
      body: [
        t(
          `CutSense, App Store'da satıcı olarak görünen bağımsız geliştirici tarafından yayınlanır ("biz"). Gizlilikle ilgili tüm sorular ve talepler için: ${contact}.`,
          `CutSense is published by the independent developer listed as the seller on the App Store ("we", "us"). For any privacy question or request, contact ${contact}.`,
        ),
      ],
    },
    {
      title: t("Videoların cihazında kalır", "Your videos stay on your device"),
      body: [
        t(
          "Videoları iOS'un kendi Fotoğraflar seçicisiyle seçersin. CutSense yalnızca seçtiğin videoyu alır, arşivinin geri kalanını görmez. Sessizlik analizi, kesim ve dışa aktarma tamamen iPhone'unda çalışır. Videolar, ses ve kesim sonuçları bize, Google'a veya başka bir sunucuya yüklenmez.",
          "You pick videos with the iOS Photos picker. CutSense receives only the video you pick and does not see the rest of your library. Silence analysis, cutting, and export run entirely on your iPhone. Videos, audio, and cut results are not uploaded to us, to Google, or to any other server.",
        ),
        t(
          "İşlem sırasında uygulama, cihazında geçici çalışma kopyaları oluşturur. Bunlar iş bittiğinde ve uygulamanın bir sonraki açılışında silinir; CutSense 1.1 ve sonrasında Ayarlar > Depolama > Temizle ile istediğin an silebilirsin. Fotoğraflar'a kaydettiğinde uygulama yalnızca ekleme izni ister; mevcut fotoğraflarını okuyamaz veya değiştiremez. İzinleri iOS Ayarları'ndan değiştirebilirsin.",
          "While processing, the app creates temporary working copies on your device. They are deleted when the job ends and the next time the app starts, and in CutSense 1.1 and later you can delete them any time in Settings > Storage > Clear. When you save to Photos, the app asks only for add-only permission, so it cannot read or change your existing photos. You can change permissions in iOS Settings.",
        ),
      ],
    },
    {
      title: t("Cihazında saklanan ayarlar", "Settings stored on your device"),
      body: [
        t(
          "CutSense birkaç küçük ayarı yalnızca cihazında saklar: seçtiğin dil, Pro'nun açık olup olmadığı, reklamsız süre bitiş zamanı, teklif zamanlayıcıları ve kaydettiğin video sayısı, tanıtım ve değerlendirme isteğinin gösterilip gösterilmediği. Bunlar bize gönderilmez. Uygulamayı silince hepsi silinir.",
          "CutSense keeps a few small settings only on your device: your chosen language, whether Pro is unlocked, when an ad-free period ends, offer timers and how many videos you have saved, and whether the intro and the rating prompt were shown. They are not sent to us. Deleting the app deletes them.",
        ),
      ],
    },
    {
      title: t("Bizim topladığımız veriler", "Data we collect"),
      body: [
        t(
          "Uygulama üzerinden kişisel veri almıyoruz: hesap, kendi sunucumuz, analiz, çökme raporlama veya pazarlama aracı kullanmıyoruz. Apple, App Store Connect'te bize toplu indirme, satış ve (paylaşmayı seçtiysen) çökme istatistikleri gösterebilir; bunlar seni tanımlamaz.",
          "We do not receive personal data through the app: we use no account, no server of our own, and no analytics, crash-reporting, or marketing tool. Apple may show us aggregated download, sales, and (if you chose to share them) crash statistics in App Store Connect; these do not identify you.",
        ),
        t(
          "Bize e-posta yazarsan e-posta adresini ve mesajını yalnızca sana yanıt vermek için kullanırız. Talebin çözülünce, yasal bir zorunluluk yoksa silinir; daha önce silmemizi istersen sileriz.",
          "If you email us, we use your email address and message only to reply. It is deleted once your request is resolved unless the law requires us to keep it, and we delete it sooner if you ask.",
        ),
      ],
    },
    {
      title: t("Reklamlar: Google AdMob", "Advertising: Google AdMob"),
      body: [
        t(
          "Ücretsiz sürüm Google Mobile Ads SDK (AdMob) ile banner reklamlar, işlem sırasında native reklamlar ve isteğe bağlı ödüllü reklamlar gösterir. Google'ın açıklamasına göre SDK şunları toplayabilir: IP adresi, cihaz tanımlayıcıları (uygulamaya veya geliştiriciye özel kimlikler), gördüğün reklamlar gibi reklam verileri, uygulama açılışı ve reklam etkileşimleri gibi ürün etkileşimleri, IP adresinden çıkarılan yaklaşık konum, çökme ve performans verileri.",
          "The free version uses the Google Mobile Ads SDK (AdMob) to show banner ads, native ads while a video is processing, and optional rewarded ads. According to Google, the SDK may collect: IP address, device identifiers (app- or developer-scoped IDs), advertising data such as ads you have seen, product interactions such as app launches and ad taps, approximate location derived from your IP address, and crash and performance data.",
        ),
        t(
          "Google bu verileri reklam göstermek ve seçmek, reklam performansını ölçmek, reklam sıklığını sınırlamak, dolandırıcılığı ve kötüye kullanımı önlemek ve hizmetini iyileştirmek için kullanır. Kişiselleştirilmiş reklam yalnızca yasa gerektirdiğinde verdiğin izinle gösterilir. Google bu verileri kendi gizlilik politikasına göre bağımsız olarak işler: policies.google.com/privacy ve policies.google.com/technologies/partner-sites.",
          "Google uses this data to serve and select ads, measure ad performance, limit how often you see an ad, prevent fraud and abuse, and improve its service. Personalized ads are shown only with your consent where the law requires it. Google processes this data independently under its own privacy policy: policies.google.com/privacy and policies.google.com/technologies/partner-sites.",
        ),
        t(
          "Yalnızca bu politikadakilere eşit koruma sağlayan üçüncü taraflarla çalışırız; Google bu veriyi AdMob şartları ve Google'ın AB Kullanıcı Rızası Politikası kapsamında korumakla yükümlüdür. Google dışında hiçbir üçüncü tarafla veri paylaşmıyoruz. Pro sahiplerinde reklam SDK'sı başlatılmaz ve reklam gösterilmez.",
          "We only work with third parties that provide protection equal to what this policy describes; Google is bound to protect this data under the AdMob terms and Google's EU User Consent Policy. We share no data with any third party other than Google. For Pro owners the ad SDK is not started and no ads are shown.",
        ),
      ],
    },
    {
      title: t("Takip ve IDFA", "Tracking and IDFA"),
      body: [
        t(
          "CutSense App Tracking Transparency izni istemez, bu yüzden reklam kimliğine (IDFA) erişilmez ve verilerin başka şirketlerin uygulama veya sitelerindeki verilerle eşleştirilerek seni takip etmek için kullanılmaz. Google yine de yukarıdaki verileri, App Store gizlilik ayrıntılarında açıklanan biçimde işleyebilir.",
          "CutSense does not ask for App Tracking Transparency permission, so the advertising identifier (IDFA) is not accessed and your data is not linked with data from other companies' apps or websites to track you. Google may still process the data above, as disclosed in the App Store privacy details.",
        ),
      ],
    },
    {
      title: t("AEA, Birleşik Krallık ve İsviçre: rıza ve hukuki dayanak", "EEA, UK, and Switzerland: consent and legal bases"),
      body: [
        t(
          "Bu bölgelerde CutSense ilk açılışta Google'ın rıza formunu (User Messaging Platform) gösterir. Cihazında bilgi saklanması veya okunması ve kişiselleştirilmiş reklam için hukuki dayanak rızandır (GDPR / UK GDPR md. 6(1)(a)). Rıza vermezsen Google, yasanın izin verdiği ölçüde sınırlı veya kişiselleştirilmemiş reklam gösterebilir; dolandırıcılık önleme ve güvenlik gibi amaçlar için meşru menfaate dayanabilir. Satın alımlar sözleşmenin ifasına, destek yazışmaları meşru menfaatimize dayanır.",
          "In these regions CutSense shows Google's consent form (User Messaging Platform) on first launch. The legal basis for storing or reading information on your device and for personalized ads is your consent (GDPR / UK GDPR Art. 6(1)(a)). If you do not consent, Google may show limited or non-personalized ads where the law allows and may rely on legitimate interests for purposes such as fraud prevention and security. Purchases rely on performance of a contract, and support emails on our legitimate interest in answering you.",
        ),
        t(
          "Rızanı istediğin an geri çekebilir veya değiştirebilirsin: uygulamada Ayarlar > Reklam gizliliği > Gizlilik tercihlerini yönet (CutSense 1.1 ve sonrası). Bu satır, bölgende gerekli olduğunda ve reklamlar açıkken görünür. Geri çekmek, önceki işlemenin hukuka uygunluğunu etkilemez.",
          "You can withdraw or change consent at any time in the app: Settings > Ad privacy > Manage privacy choices (CutSense 1.1 and later). This row appears where it is required in your region and while ads are on. Withdrawing does not affect processing that happened before.",
        ),
      ],
    },
    {
      title: t("ABD eyalet gizlilik hakları", "US state privacy rights"),
      body: [
        t(
          "CutSense kişisel bilgileri para karşılığı satmaz. Ancak Google'ın ücretsiz sürümde reklamları kişiselleştirmesi, California (CCPA/CPRA) ve benzeri eyalet yasalarında kişisel bilgilerin \"satışı\" veya hedefli reklam için \"paylaşılması\" sayılabilir. İlgili kategoriler: tanımlayıcılar, internet veya ağ etkinliği (reklam etkileşimleri) ve yaklaşık konum.",
          "CutSense does not sell personal information for money. However, Google personalizing ads in the free version may count as a \"sale\" or \"sharing\" of personal information for targeted advertising under California law (CCPA/CPRA) and similar state laws. The categories involved are identifiers, internet or network activity (ad interactions), and approximate location.",
        ),
        t(
          "Hedefli reklamdan çıkmak için: uygulama bir gizlilik seçeneği gösteriyorsa Ayarlar > Reklam gizliliği'ni kullan; Google reklam ayarlarını myadcenter.google.com adresinden yönet ya da sunulduğu yerde CutSense Pro ile reklamları tamamen kapat. Seninle ilişkilendirilmiş bir veri tutmadığımız için talebi senin yerine Google'a uygulayamayız; ancak her soru için bize yazabilirsin ve hakkını kullandığın için sana farklı davranmayız.",
          "To opt out of targeted ads: use Settings > Ad privacy in the app if it shows a privacy option; manage Google's ad settings at myadcenter.google.com; or, where available, turn ads off completely with CutSense Pro. Because we hold no data linked to you, we cannot apply an opt-out at Google on your behalf, but you can contact us with any question and we will not treat you differently for using your rights.",
        ),
      ],
    },
    {
      title: t("Satın alımlar", "Purchases"),
      body: [
        t(
          "Uygulamada sunulduğu yerde CutSense Pro, Apple'ın App Store'u üzerinden satılan tek seferlik bir uygulama içi satın alımdır. Ödemeyi Apple işler. Kart bilgilerini, adını, e-postanı veya Apple Kimliğini almayız. Uygulama, Pro'nun açık olup olmadığını iPhone'undaki Apple işlem kaydından kontrol eder. İadeler Apple tarafından reportaproblem.apple.com üzerinden yapılır.",
          "Where available in the app, CutSense Pro is a one-time in-app purchase sold through Apple's App Store. Apple processes the payment. We do not receive your card details, name, email, or Apple ID. The app checks whether Pro is unlocked from Apple's transaction record on your iPhone. Refunds are handled by Apple at reportaproblem.apple.com.",
        ),
      ],
    },
    {
      title: t("Saklama ve silme", "Retention and deletion"),
      body: [
        t(
          "Geçici video kopyaları iş bitince ve bir sonraki açılışta silinir. Cihazdaki ayarlar uygulamayı silene kadar kalır. E-postalar talebin çözülene kadar saklanır. Google reklam verilerini kendi saklama politikasına göre tutar: policies.google.com/technologies/retention.",
          "Temporary video copies are deleted when the job ends and at the next launch. On-device settings remain until you delete the app. Emails are kept until your request is resolved. Google keeps advertising data according to its own retention policy: policies.google.com/technologies/retention.",
        ),
      ],
    },
    {
      title: t("Hakların", "Your rights"),
      body: [
        t(
          "Bulunduğun yere bağlı olarak verilerine erişme, düzeltme, silme, işlemeyi kısıtlama veya itiraz etme, taşınabilirlik ve rızanı geri çekme hakların olabilir; ayrıca yerel veri koruma otoritesine şikâyet edebilirsin. Talepler için bize yaz; 30 gün içinde yanıt veririz. Google'ın tuttuğu reklam verileri için Google'ın araçlarını kullanman gerekir, çünkü bu verilere biz erişemeyiz.",
          "Depending on where you live, you may have the right to access, correct, delete, restrict or object to processing of, and port your data, and to withdraw consent; you can also complain to your local data protection authority. Email us with any request and we will reply within 30 days. For advertising data held by Google, use Google's tools, because we cannot access that data.",
        ),
      ],
    },
    {
      title: t("Uluslararası aktarımlar ve güvenlik", "International transfers and security"),
      body: [
        t(
          "Google verileri kendi ülkenin dışında, ABD dahil, işleyebilir ve bu aktarımlar için Standart Sözleşme Maddeleri gibi yasal mekanizmalar kullanır. Videoların cihazından çıkmadığı için en büyük koruma budur; iPhone'unun kendi güvenliği de geçerlidir.",
          "Google may process data outside your country, including in the United States, and uses legal mechanisms such as Standard Contractual Clauses for those transfers. Your videos never leave your device, which is the strongest protection we can offer; your iPhone's own security also applies.",
        ),
      ],
    },
    {
      title: t("Çocuklar", "Children"),
      body: [
        t(
          "CutSense 13 yaş altındaki çocuklara yönelik değildir ve bilerek çocuklardan kişisel veri toplamayız. Bir çocuğun bize veri gönderdiğini düşünüyorsan bize yaz, sileriz.",
          "CutSense is not directed to children under 13, and we do not knowingly collect personal data from children. If you believe a child has sent us personal data, contact us and we will delete it.",
        ),
      ],
    },
    {
      title: t("Değişiklikler", "Changes"),
      body: [
        t(
          "Bu politikayı güncelleyebiliriz. Güncel sürüm her zaman bu sayfadadır ve yürürlük tarihi yukarıda yazar.",
          "We may update this policy. The current version is always on this page, with the effective date above.",
        ),
      ],
    },
    {
      title: t("İletişim", "Contact"),
      body: [
        t(
          `Gizlilik soruları ve talepleri için ${contact} adresine yaz.`,
          `For privacy questions and requests, email ${contact}.`,
        ),
      ],
    },
  ];

  return (
    <main>
      <SiteNav />
      <article className="legal-shell">
        <p className="eyebrow">CutSense</p>
        <h1>{t("Gizlilik Politikası", "Privacy Policy")}</h1>
        <p className="legal-intro">
          {t(
            "Bu politika CutSense iPhone uygulamasının ve bu web sitesinin verileri nasıl ele aldığını açıklar.",
            "This policy explains how the CutSense iPhone app and this website handle data.",
          )}
        </p>
        <div className="legal-sections">
          {sections.map((section) => (
            <section key={section.title}>
              <h2>{section.title}</h2>
              {section.body.map((paragraph) => (
                <p key={paragraph}>{paragraph}</p>
              ))}
            </section>
          ))}
        </div>
      </article>
      <SiteFooter />
    </main>
  );
}
